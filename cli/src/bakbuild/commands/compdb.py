"""``bak compdb`` — emit a clang compilation database for IDE indexing.

Writes a ``compile_commands.json`` at the repo root describing every
``bak/SRC/**/*.C`` translation unit as a *clang* invocation, so a clangd-based
indexer (the engine behind CLion's code intelligence, and clangd in VS Code /
Neovim) can resolve includes, types, and symbols across the reconstructed
source tree.

This is an INDEXING aid, not a build. The real build (`bak build`) compiles
these sources with the period Borland toolchain (bcc/bccx) inside a FreeDOS
qemu VM; clang never runs them. The 16-bit codegen flags are therefore
irrelevant here and deliberately dropped — they don't affect a parse. What the
indexer needs is the include path plus a way to swallow the Borland dialect
(``far``/``near``/``huge``/``cdecl``/``interrupt``, the ``_AX`` pseudo-registers)
and the case-mismatched DOS system headers; that is supplied by the
force-included ``bakbuild/ide/include/clion_shim.h`` and the lowercase header
stubs beside it. See that header for the full rationale.

The generated file holds absolute, machine-local paths (the source tree and the
probed compiler, e.g. a nix-store gcc) so it is git-ignored and regenerated,
never committed. Re-run it whenever sources are added or removed to keep the
index in step with the tree.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Annotated

import typer

from .. import paths

# Candidate compiler DRIVERS, in preference order. CLion (unlike a raw clangd)
# probes the binary named in ``arguments[0]`` to learn its built-in include
# paths + predefined macros, so it must be a real, resolvable driver — not
# clangd/clang-check (which are not drivers). Whichever is found is written as an
# ABSOLUTE path. The chosen driver only matters for that probe; CLion's own
# clangd engine does the actual analysis, and the flags below are clang/gcc
# agnostic.
_CC_CANDIDATES = ("clang", "gcc", "cc")

# The force-included dialect shim + lowercase DOS-header stubs (dos.h/conio.h/…)
# ship inside the package, next to this code — anchored off the module so they
# resolve no matter where the repo lives or how ``bak`` is invoked.
IDE_INCLUDE_DIR = Path(__file__).resolve().parents[1] / "ide" / "include"
SHIM_HEADER = IDE_INCLUDE_DIR / "clion_shim.h"


def _detect_cc(override: str | None = None) -> str:
    """Resolve the indexing compiler driver to an absolute path. ``override`` (a
    name or path) wins; otherwise the first of ``clang``/``gcc``/``cc`` found on
    PATH. Raises with a clear message if none resolves — CLion needs a real
    driver to probe."""
    if override:
        found = shutil.which(override)
        if found is None and Path(override).is_file():
            found = str(Path(override).resolve())
        if found is None:
            raise typer.BadParameter(f"--cc compiler {override!r} not found on PATH or disk")
        return found
    for cand in _CC_CANDIDATES:
        found = shutil.which(cand)
        if found:
            return found
    raise typer.BadParameter(
        "no C compiler driver (clang/gcc/cc) found on PATH — CLion needs one to probe its "
        "built-in headers/macros. Install clang or gcc, or pass `--cc <path>`."
    )


def _sources() -> list[Path]:
    """Every C translation unit under ``bak/SRC`` — the per-unit files carry
    uppercase DOS names (``IO.C``), so match case-insensitively. Sorted for a
    stable, diff-friendly database. (Headers are not TUs; the indexer reaches
    them through the ``#include`` graph of these files.)"""
    src_root = paths.BAK / "SRC"
    if not src_root.exists():
        return []
    return sorted(p for p in src_root.rglob("*") if p.suffix.lower() == ".c")


def _clang_args(cc: str, src: Path, version: str) -> list[str]:
    """The compiler command for one TU. ``-std=gnu89`` matches Borland-era C
    (with lenient GNU extensions); ``-ffreestanding`` drops hosted-libc
    assumptions; the two ``-I`` give the game's own headers and the IDE
    shim/stub dir; ``-include`` force-loads the dialect shim ahead of the file;
    ``-D__BAK_CLION__`` arms it. The ``-Wno-*`` set is accepted by both clang and
    gcc (an unknown ``-Wno-foo`` is ignored by both unless it actually fires)."""
    return [
        cc,
        "-xc",
        "-std=gnu89",
        "-ffreestanding",
        # Borland/K&R-era C that modern clang/gcc promote to hard errors by
        # default. Downgraded so the indexer recovers a full AST instead of
        # bailing: implicit `int`, a non-void function that returns its value in
        # AX with no `return`, and the loose int<->pointer mixing this codebase
        # relies on. (Indexing only — never a real build.)
        "-Wno-return-mismatch",
        "-Wno-return-type",
        "-Wno-implicit-int",
        "-Wno-implicit-function-declaration",
        "-Wno-int-conversion",
        "-D__BAK_CLION__=1",
        # clangd parses each TU under ONE macro set, so the database presents a
        # single version view: 102 arms the #ifdef V102CD blocks (the 1.00-only
        # #ifndef blocks grey out), 100 the reverse.
        *(["-DV102CD=1"] if version == "102" else []),
        f"-I{paths.BAK / 'INCLUDE'}",
        # per-module headers are included root-relatively (#include "SRC/.../MOD.H");
        # bcc resolves them against its CWD (bak/), clang needs the explicit -I
        f"-I{paths.BAK}",
        f"-I{IDE_INCLUDE_DIR}",
        "-include",
        str(SHIM_HEADER),
        str(src),
    ]


def _generate(output: Path, cc: str, version: str) -> tuple[Path, int]:
    """Write the compilation database. Returns the output path and the number of
    translation units recorded."""
    directory = str(paths.PROJECT_ROOT)
    entries = [
        {"directory": directory, "file": str(src), "arguments": _clang_args(cc, src, version)}
        for src in _sources()
    ]
    output.write_text(json.dumps(entries, indent=2) + "\n")
    return output, len(entries)


def compdb(
    output: Annotated[
        Path | None,
        typer.Option(
            "--output",
            "-o",
            help="Where to write the database (default: <repo>/compile_commands.json).",
        ),
    ] = None,
    cc: Annotated[
        str | None,
        typer.Option(
            "--cc",
            help="Compiler driver for the entries (name or path). Default: first of "
            "clang/gcc/cc on PATH, written as an absolute path so CLion can probe it.",
        ),
    ] = None,
    version: Annotated[
        str,
        typer.Option(
            "--version",
            help="Which release view to index: 102 arms the #ifdef V102CD blocks "
            "(default), 100 the 1.00-only ones. One view per database — clangd "
            "cannot parse a file under two macro sets.",
        ),
    ] = "102",
) -> None:
    """Generate compile_commands.json so CLion / clangd can index the bak/ C tree.

    Indexing only — never a build. Re-run after adding/removing sources to
    refresh the file list. Open the repo in CLion (it auto-detects the database)
    or point clangd at it.
    """
    if version not in ("100", "102"):
        raise typer.BadParameter("--version must be 100 or 102")
    out = output or paths.PROJECT_ROOT / "compile_commands.json"
    driver = _detect_cc(cc)
    out, count = _generate(out, driver, version)
    typer.echo(f"wrote {out} ({count} translation units, version view: {version}, "
               f"compiler: {driver})")


def register(app: typer.Typer) -> None:
    app.command(name="compdb")(compdb)
