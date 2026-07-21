"""The FreeDOS qemu build machinery.

Stage the ``bak/`` tree + Borland toolchain into a fresh disk image, run Borland
MAKE under the two accel passes the toolchain forces, and shuttle objects/artifacts
in and out. Thin orchestration over the vendored ``freedos`` primitives.

Two accel passes are inherent (empirically verified). The bc20 BCCX island runs on
the A.I. Architects 286 extender, which enters protected mode via a 286 hardware
task switch that qemu-KVM can't virtualize (GP fault) — so that island builds under
qemu-TCG; the bulk (bc31 + TASM) builds under KVM for speed. Both passes are
makefile-driven, but the TCG pass runs the real-mode ``MAKER`` instead of the DPMI
``MAKE`` — the DPMI MAKE corrupts a child's mode switch when it spawns a compiler
under qemu-TCG, whereas real-mode MAKER never enters protected mode.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import typer

from . import freedos, paths

_DOS_PATH = "path c:\\BC\\BIN;c:\\BC30;c:\\BC20;\\FREEDOS\\BIN\r\n"
_DOS_HEAD = "@echo off\r\nc:\r\ncd \\\r\n" + _DOS_PATH


def _img() -> str:
    return freedos._img(paths.IMG)


# Source-text file kinds (by extension, plus bare makefile-style names): these are
# copied with mtools' CRLF translation (-t), which bcc/tasm/make tolerate and BCCX
# requires. EVERYTHING ELSE (notably the .BIN driver-data blobs) is copied byte-raw:
# -t rewrites 0x0A→0x0D0A and appends a 0x1A EOF, which corrupts binary data.
_TEXT_EXTS = {".C", ".H", ".INC", ".ASM", ".MAK", ".RSP", ".PAK", ".TXT"}
_TEXT_NAMES = {"MAKEFILE"}


def _is_text(path: Path) -> bool:
    return path.suffix.upper() in _TEXT_EXTS or path.name.upper() in _TEXT_NAMES


def mirror() -> None:
    """Replicate ``bak/`` into the image root — dirs first, then files. Text sources
    are CRLF-translated; binary files (the .BIN data blobs) are copied byte-raw so
    the text translation can't corrupt them."""
    root = paths.BAK
    for d in sorted(p for p in root.rglob("*") if p.is_dir()):
        freedos.mmd(paths.IMG, "::/" + d.relative_to(root).as_posix())
    for f in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = f.relative_to(root).parent.as_posix()
        freedos.mcopy_in(paths.IMG, "" if rel == "." else rel, f, text=_is_text(f))


def sync_files(rels: list[str]) -> None:
    """Copy just these ``bak/``-relative files into the existing image, in place.

    Used by the incremental build: re-copying a changed source bumps its in-image
    mtime past the objects built last run, so MAKE (+ ``.autodepend``) rebuilds it
    and its dependents while leaving every untouched source — and its object —
    alone. Same text/binary handling as ``mirror``."""
    for rel in rels:
        f = paths.BAK / rel
        reldir = Path(rel).parent.as_posix()
        freedos.mcopy_in(paths.IMG, "" if reldir == "." else reldir, f, text=_is_text(f))


def fresh_image() -> None:
    """A clean build image: FreeDOS base (+ toolchain incl. MAKE) + the bak/ tree.
    OUT\\ ships in the bak/ tree (a `-md OUT` makefile target wedges Borland
    MAKE 3.6 under FreeDOS — see bak/OUT/README.TXT), so mirroring creates it."""
    paths.WORK.mkdir(parents=True, exist_ok=True)
    freedos._reflink(freedos.build_base(), paths.IMG)
    mirror()


def _run(bat: str, accel: str, mem: int | None, *, rtc: bool = False) -> None:
    freedos.write_in(paths.IMG, "/FDAUTO.BAT", bat, paths.WORK)
    argv = freedos.command(paths.IMG, accel=accel, mem_mb=mem, rtc_base=(paths.RTC if rtc else None))
    subprocess.run(argv, check=False, capture_output=True, timeout=1800)


# Tool-error markers in the captured DOS console. The DOS tools' exit codes never
# leave the VM (qemu exits 0 regardless), and Borland MAKE leaves the previous
# object in OUT\ when a compile fails — so an unscanned error means the link and
# every byte-match gate silently run on STALE objects and report a false PASS
# (the dialog_play_record incident, 2026-07-10). Warnings stay non-fatal: the
# 1993 source compiles with known benign ones.
_DIAG_RE = re.compile(
    r"^(?:Error|Fatal) \S+ \d+:"  # bcc/bccx file diagnostics: Error src\x.c 55: ...
    r"|^(?:Error|Fatal): "        # tlink (and non-file bcc) fatals
    r"|\*\*Error\*\*"             # TASM per-error marker
    r"|^\*\* error"               # Borland MAKE child-failure abort
)


def _check_log(log: str, text: str) -> None:
    """Hard-fail on any compiler/assembler/linker error found in a build log.

    Also invalidates the incremental manifest: the abort leaves the image in an
    unknown state (new sources synced in, MAKE may have deleted objects), and the
    manifest must not claim otherwise — e.g. reverting the broken edit would
    otherwise read as "no source changes" and re-verify old artifacts while the
    image still holds the broken source. Next ``bak build`` rebuilds clean."""
    bad = [ln for ln in (raw.rstrip("\r") for raw in text.splitlines()) if _DIAG_RE.search(ln)]
    if not bad:
        return
    from . import incremental  # late: avoid widening vm's import surface at module load
    incremental.MANIFEST.unlink(missing_ok=True)
    typer.secho(f"❌ {log}: tool errors — objects may be stale, nothing downstream "
                "can be trusted (build state invalidated; next build is clean):", fg="red", err=True)
    for ln in bad:
        typer.secho(f"   {ln}", fg="red", err=True)
    typer.secho(f"   (full log: {paths.WORK / log})", fg="red", err=True)
    raise typer.Exit(1)


def run_make(
    target: str, accel: str, mem: int | None, log: str, make_exe: str = "make"
) -> str:
    """Run ``<make_exe> <target>`` in the VM, capturing its DOS console into ``log``.
    ``make_exe`` is ``make`` (DPMI, the KVM passes) or ``maker`` (real-mode, the TCG
    pass — the DPMI MAKE can't spawn a child compiler under qemu-TCG). The link/all
    targets pin the RTC so TLINK stamps the original OVRINFO date."""
    _run(_DOS_HEAD + f"{make_exe} {target} > C:\\{log}\r\n" + "c:\\EXIT.COM\r\n",
         accel, mem, rtc=(target in ("link", "all")))
    dst = paths.WORK / log
    dst.unlink(missing_ok=True)
    freedos.mcopy_out(paths.IMG, f"/{log}", paths.WORK)
    text = dst.read_text(errors="replace") if dst.exists() else "<no log>"
    _check_log(log, text)
    return text


def run_kvm_link(compile_kvm: bool, full_link: bool = True) -> str:
    """One KVM boot: optionally ``make kvmobjs`` at the real clock, then pin the DOS
    clock to 1993 and link. Folds the former separate kvmobjs and link boots into a
    single FreeDOS boot — the split only existed to give the link its 1993 RTC (so
    TLINK stamps the original OVRINFO date), which the DOS ``DATE``/``TIME`` commands
    now supply mid-session. Verified byte-identical to the ``-rtc base=`` pin. The
    compile runs first, at the real clock, so freshly built objects keep an mtime
    newer than their (host-mtime) sources for the next build.

    ``full_link`` picks the link recipe:
      * True  — the authentic ``make all``: ``tlink /m`` (map with publics) + repack
        both OVLs. Used by ``--clean`` and whenever a driver/OVL/header input changed.
      * False — the dev fast path: a plain ``tlink @KRONDOR.RSP`` relink that drops the
        unused ``/m`` public-symbol map (~0.77s) and leaves the unchanged OVLs in
        place. Byte-identical KRONDOR.EXE; the segment-only map it writes is not a
        verified artifact."""
    day, tod = paths.RTC.split("T")  # 1993-06-16 , 12:00:00
    y, mo, dd = day.split("-")
    bat = _DOS_HEAD
    logs = []
    if compile_kvm:
        bat += "make kvmobjs > C:\\KVM.LOG\r\n"
        logs.append("KVM.LOG")
    bat += f"DATE {mo}-{dd}-{y}\r\nTIME {tod}\r\n"
    bat += ("make all" if full_link else "tlink @KRONDOR.RSP") + " > C:\\LINK.LOG\r\n"
    logs.append("LINK.LOG")
    bat += "c:\\EXIT.COM\r\n"
    _run(bat, "kvm", 200, rtc=False)  # real clock at boot; DATE cmd pins 1993 for the link
    out = []
    for log in logs:
        dst = paths.WORK / log
        dst.unlink(missing_ok=True)
        freedos.mcopy_out(paths.IMG, f"/{log}", paths.WORK)
        text = dst.read_text(errors="replace") if dst.exists() else "<no log>"
        _check_log(log, text)
        out.append(text)
    return "\n".join(out)


def count_objs() -> int:
    r = subprocess.run(["mdir", "-i", _img(), "::/OUT"], env=freedos._MENV,
                       capture_output=True, text=True)
    return r.stdout.upper().count(" OBJ ")


def pull_out(name: str) -> Path:
    """Copy ``OUT\\<name>`` out of the image to the host; returns its host path."""
    freedos.mcopy_out(paths.IMG, f"/OUT/{name}", paths.WORK)
    return paths.WORK / name


def pull_artifacts() -> None:
    """Copy the built binary set (KRONDOR.EXE + MAP, and both .OVL archives) out to
    the host for fingerprint verification."""
    for name in ("KRONDOR.EXE", "KRONDOR.MAP", "VMCODE.OVL", "SX.OVL"):
        freedos.mcopy_out(paths.IMG, f"/OUT/{name}", paths.WORK)


def pull_refs() -> int:
    """Snapshot every ``OUT\\*.OBJ`` into ``work/ref/`` — the reference store
    ``bak diff`` compares against. Only called after a build whose artifacts
    fingerprinted byte-identical, so the snapshot is provably the 1993 codegen."""
    ref = paths.WORK / "ref"
    ref.mkdir(parents=True, exist_ok=True)
    freedos.mcopy_out(paths.IMG, "/OUT/*.OBJ", ref)
    return len(list(ref.glob("*.OBJ")))
