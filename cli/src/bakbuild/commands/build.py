"""``bak build`` — the 1993-authentic MAKE build of KRONDOR.EXE.

By default the build is **incremental**: it reuses the persistent ``build.img`` and
recompiles only what changed since the last verified build (see ``incremental`` for
the mechanics and why it's safe). Pass ``--clean`` to force the hermetic
from-scratch build; run a single stage by name to drive one pass for debugging.

Stages (run in order for a clean ``all``, or individually):

    kvmobjs   KVM pass: ``make kvmobjs`` — bc31 + TASM objects (213)
    tcgobjs   TCG pass: ``maker tcgobjs`` — the bc20 BCCX + bc30 island (18)
    link      KVM pass: ``make all`` — links KRONDOR.EXE (tlink @KRONDOR.RSP), builds
              the PACKOVL tool + driver chunks, packs VMCODE.OVL/SX.OVL, then
              fingerprints all three artifacts against the shipped 1993 files

No host-side object post-processing: the shipped binary's word-alignment pads come
from the four data-only TASM anchor modules (``D_2A81``/``D_320A``/``D_3508``/
``D_3657``) whose empty ``'CODE'`` SEGDEFs are ``segment word`` in source — TLINK
aligns those zero-length segments, and every C ``_TEXT`` stays at bcc's byte default.
"""

from __future__ import annotations

import hashlib
from enum import Enum

import typer

from .. import incremental, paths, vm


class Stage(str, Enum):
    all = "all"
    kvmobjs = "kvmobjs"
    tcgobjs = "tcgobjs"
    link = "link"


def _kvmobjs() -> None:
    """Explicit ``bak build kvmobjs`` debug driver: fresh image, KVM compile pass only."""
    vm.fresh_image()
    typer.echo("── KVM pass: make kvmobjs ──")
    typer.echo(vm.run_make("kvmobjs", "kvm", 64, "KVM.LOG")[-3000:])


def _tcgobjs() -> None:
    typer.echo("── TCG pass: maker tcgobjs (real-mode MAKER — DPMI MAKE can't spawn under TCG) ──")
    before = vm.count_objs()
    typer.echo(vm.run_make("tcgobjs", "tcg", 96, "TCG.LOG", make_exe="maker")[-3000:])
    typer.echo(f"TCG objs added: {vm.count_objs() - before} (expected 18)")


def _verify_one(name: str, want_size: int, want_sha: str) -> bool:
    """Fingerprint one pulled artifact against the shipped 1993 file; one ✅/❌ line."""
    path = paths.WORK / name
    if not path.exists():
        typer.secho(f"❌ {name}: not produced", fg="red")
        return False
    data = path.read_bytes()
    got_size, got_sha = len(data), hashlib.sha256(data).hexdigest()
    if got_size == want_size and got_sha == want_sha:
        typer.secho(f"✅ {name}: BYTE-IDENTICAL ({got_size} bytes, sha256 {got_sha})", fg="green")
        return True
    if got_size != want_size:
        typer.secho(f"❌ {name}: size differs: {got_size} vs {want_size}", fg="red")
    else:
        typer.secho(f"❌ {name}: sha256 differs: {got_sha}\n   expected {' ' * len(name)}{want_sha}", fg="red")
    return False


def _verify() -> bool:
    ok = True
    for name, size, sha in paths.ARTIFACTS:
        ok = _verify_one(name, size, sha) and ok
    return ok


def _link() -> bool:
    typer.echo("── KVM link+pack: make all (tlink KRONDOR.EXE → PACKOVL → VMCODE.OVL/SX.OVL) ──")
    typer.echo(vm.run_make("all", "kvm", 200, "LINK.LOG")[-3000:])
    vm.pull_artifacts()
    return _verify()


def _kvm_link(compile_kvm: bool, full_link: bool = True) -> bool:
    """One KVM boot: (optionally compile the KVM objects, then) link + verify.

    Folds what used to be a separate kvmobjs boot and link boot into a single FreeDOS
    boot (the link's 1993 date now comes from a mid-session DATE/TIME instead of a
    second boot's RTC pin). ``full_link`` chooses ``make all`` (authentic tlink /m +
    OVL repack) vs the dev fast relink (drops the unused /m map, ~0.77s)."""
    link_desc = "make all (tlink /m + pack)" if full_link else "relink (tlink, no map)"
    typer.echo(f"── KVM boot: {'make kvmobjs → ' if compile_kvm else ''}"
               f"set 1993 clock → {link_desc} ──")
    typer.echo(vm.run_kvm_link(compile_kvm, full_link)[-3000:])
    vm.pull_artifacts()
    return _verify()


def _clean_build() -> bool:
    """The hermetic from-scratch build: fresh image, the TCG pass, then one KVM boot
    that compiles the bulk and links (2 boots total: TCG island + KVM).

    The manifest is invalidated first: this wipes the image, so an interrupted run
    must read as "no prior build state" next time, not as whatever the manifest
    claimed the (now gone) image contained."""
    incremental.MANIFEST.unlink(missing_ok=True)
    vm.fresh_image()
    _tcgobjs()
    return _kvm_link(compile_kvm=True, full_link=True)


def _incremental_build() -> bool:
    """Reuse build.img; recompile only what changed since the last build.

    Falls back to a clean build when there's no prior state, when files were
    added/removed, or when the build rules (MAKEFILE/*.MAK) changed.

    The manifest is saved after every sync+build — green or red — because it
    tracks what the IMAGE contains, not what last verified: a divergent build
    followed by a source revert must register as a change (resync + rebuild),
    or the image would keep its stale objects while the tree matches the old
    manifest and the build short-circuits to a failing re-verify forever."""
    new = incremental.source_hashes()
    loaded = incremental.load_manifest()
    if loaded is None or not paths.IMG.exists():
        typer.echo("── no prior build state — full clean build ──")
        ok = _clean_build()
        incremental.save_manifest(new, ok)
        return ok
    old, old_verified = loaded

    changed, structural = incremental.diff(old, new)
    if structural:
        typer.echo("── source files added/removed — full clean build ──")
        ok = _clean_build()
        incremental.save_manifest(new, ok)
        return ok

    if not changed:
        typer.echo("── no source changes — re-verifying existing artifacts ──")
        ok = _verify()
        if ok or not old_verified:
            # green, or red-but-expected: this exact tree already built red
            # (an intentionally divergent edit) — rebuilding can't change it
            if ok != old_verified:
                incremental.save_manifest(new, ok)
            if not ok:
                typer.echo("── tree unchanged since its last (divergent) build ──")
            return ok
        # this tree last verified green but is red now: the image/artifacts
        # were disturbed outside the build — rebuild from scratch
        typer.echo("── artifacts stale — full clean build ──")
        ok = _clean_build()
        incremental.save_manifest(new, ok)
        return ok

    kvm_needed, tcg_needed, must_full = incremental.classify(changed)
    typer.echo(f"── incremental: {len(changed)} changed file(s) ──")
    for rel in changed:
        typer.echo(f"    ~ {rel}")

    if must_full:
        typer.echo("── build rules changed (MAKEFILE/*.MAK) — full clean build ──")
        ok = _clean_build()
        incremental.save_manifest(new, ok)
        return ok

    full_link = incremental.needs_full_link(changed)
    vm.sync_files(changed)
    if tcg_needed:
        _tcgobjs()  # separate TCG boot (only when the island changed)
    else:
        typer.echo("── TCG pass: skipped (island unchanged) ──")
    if not kvm_needed:
        typer.echo("── KVM compile: skipped (no KVM-side source changed) — relink only ──")
    # single KVM boot: compile the changed KVM objects (if any) + link + verify
    ok = _kvm_link(compile_kvm=kvm_needed, full_link=full_link)
    incremental.save_manifest(new, ok)
    return ok


def build(
    stage: Stage = typer.Argument(Stage.all, help="which stage to run (default: all)"),
    clean: bool = typer.Option(False, "--clean", "-c", help="force a hermetic from-scratch build"),
) -> None:
    """Compile (KVM + TCG passes) → link, then cmp vs the shipped KRONDOR.EXE.

    ``bak build`` is incremental by default; ``--clean`` forces a full rebuild."""
    s = stage.value
    if s == "all":
        if clean:
            typer.echo("── clean build requested ──")
            ok = _clean_build()
            incremental.save_manifest(incremental.source_hashes(), ok)
        else:
            ok = _incremental_build()
        if not ok:
            raise typer.Exit(1)
        # the image now provably holds 1993 codegen — refresh `bak diff`'s store
        typer.echo(f"reference store refreshed ({vm.pull_refs()} objs → work/ref/)")
        return

    # Explicit single-stage runs stay as low-level debugging drivers.
    if s == "kvmobjs":
        _kvmobjs()
    if s == "tcgobjs":
        _tcgobjs()
    if s == "link" and not _link():
        raise typer.Exit(1)


def register(app: typer.Typer) -> None:
    app.command()(build)
