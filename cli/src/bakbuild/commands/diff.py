"""``bak diff`` — disassembly diff of one source's object vs the last green build.

Compares the OBJ your working tree produces for SOURCE against the reference
OBJ captured from the last verified byte-identical build (``work/ref/``, kept
fresh automatically by ``bak build``). Both sides are disassembled with the
same normalizer (capstone CS_MODE_16 over the OMF LEDATA bytes), so the diff
localizes exactly what a source edit did to codegen.

By default the diff is *loose*: relocated bytes and local-branch displacement
bytes are masked during alignment, so an insertion doesn't cascade a byte-shift
report through every jump that spans it — those rows render demoted (dim ``~``)
inside shown hunks instead. ``--strict`` promotes them to real diffs for
byte-level forensics. Verdicts stay honest either way: the exit code and the
summary line count shifts separately, and the byte-exact truth is always
``bak build``'s artifact fingerprint.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from .. import paths, vm

_SRC_EXTS = {".c", ".asm"}


def _resolve_source(source: str) -> Path:
    """Accept SRC/GAME/X.C, bak/SRC/GAME/X.C, or an absolute/cwd-relative path;
    the file must exist under ``bak/``."""
    for cand in (Path(source), paths.PROJECT_ROOT / source, paths.BAK / source):
        cand = cand.expanduser()
        if cand.is_file():
            cand = cand.resolve()
            if not cand.is_relative_to(paths.BAK):
                raise typer.BadParameter(f"{source}: not under {paths.BAK}")
            if cand.suffix.lower() not in _SRC_EXTS:
                raise typer.BadParameter(f"{source}: not a .C/.ASM source")
            return cand
    raise typer.BadParameter(f"{source}: no such source (looked in ., repo root, bak/)")


def _tail_log(name: str) -> str:
    p = paths.WORK / name
    return p.read_text(errors="replace")[-1500:] if p.exists() else "<no log>"


def diff(
    source: Annotated[str, typer.Argument(help="source under bak/ (e.g. SRC/GAME/TIMERPL.C)")],
    strict: Annotated[
        bool, typer.Option("--strict", help="report branch-displacement shifts as real diffs")
    ] = False,
    context: Annotated[int, typer.Option("--context", "-C", help="context rows per hunk")] = 3,
    build: Annotated[
        bool, typer.Option(help="run the incremental build first so the OBJ is current")
    ] = True,
) -> None:
    """Diff SOURCE's object against the last verified build's reference OBJ."""
    from .. import disasm  # defer: pulls in capstone
    from . import build as build_cmd

    src = _resolve_source(source)
    obj_name = src.stem.upper() + ".OBJ"
    ref_path = paths.WORK / "ref" / obj_name
    if not ref_path.exists():
        typer.secho(
            f"no reference for {obj_name} — the store (work/ref/) is populated by a "
            "verified `bak build`; run one from a green tree first.",
            fg="red",
        )
        raise typer.Exit(2)

    if build:
        build_cmd._incremental_build()  # verify-fail is expected mid-edit; keep going

    cand_path = paths.WORK / obj_name
    cand_path.unlink(missing_ok=True)
    vm.pull_out(obj_name)
    if not cand_path.exists():
        typer.secho(f"{obj_name} missing from the build image — compile failed?", fg="red")
        typer.echo(_tail_log("KVM.LOG"))
        raise typer.Exit(2)

    ref_rows, ref_obj = disasm.render_rows(ref_path)
    cand_rows, cand_obj = disasm.render_rows(cand_path)
    if ref_obj.has_lidata or cand_obj.has_lidata:
        typer.secho("warning: LIDATA records present — those bytes compare as zero-fill",
                    fg="yellow")

    lines, changed, shifted = disasm.diff_rows(ref_rows, cand_rows, loose=not strict)

    if not changed and not shifted:
        typer.secho(f"✅ {obj_name}: no codegen divergence vs last green build", fg="green")
        return

    _print_hunks(lines, context)
    mode = "strict" if strict else "loose"
    typer.echo()
    typer.secho(
        f"❌ {obj_name}: {changed} changed line(s)"
        + (f", {shifted} displacement shift(s) demoted (~)" if shifted else "")
        + f"  [{mode}]",
        fg="red",
    )
    raise typer.Exit(1)


def _print_hunks(lines: list, context: int) -> None:
    """unified-style hunks: ``-``/``+`` rows anchor windows; ``~`` shifts render
    dim inside windows but do not anchor (that's their demotion)."""
    n = len(lines)
    show = [False] * n
    for i, ln in enumerate(lines):
        if ln.tag in "-+":
            for k in range(max(0, i - context), min(n, i + context + 1)):
                show[k] = True

    color = {"-": "red", "+": "green", "~": "bright_black"}
    func = None
    i = 0
    while i < n:
        if not show[i]:
            j = i
            while j < n and not show[j]:
                j += 1
            typer.secho(f"     ⋯ {j - i} unchanged", fg="bright_black")
            i = j
            continue
        if lines[i].func != func:
            func = lines[i].func
            typer.secho(f"── {func or '(module)'}", fg="cyan")
        typer.secho(f"  {lines[i].tag} {lines[i].text}", fg=color.get(lines[i].tag))
        i += 1


def register(app: typer.Typer) -> None:
    app.command()(diff)
