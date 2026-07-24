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

import os
import re
import subprocess
import time
from pathlib import Path

import typer

from . import freedos, paths

_PROFILE = os.environ.get("BAK_PROFILE")


def _prof(label: str, dt: float) -> None:
    if _PROFILE:
        typer.secho(f"⏱  {label}: {dt:.2f}s", fg="yellow", err=True)

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
    _run_img(paths.IMG, bat, accel, mem, rtc=rtc)


def _run_img(img: Path, bat: str, accel: str, mem: int | None, *, rtc: bool = False) -> None:
    """Boot ``img`` in qemu with ``bat`` as ``/FDAUTO.BAT`` and wait for it to exit.

    Image-parameterized so the two accel islands can run against separate reflink
    copies concurrently (see ``run_islands_parallel``)."""
    freedos.write_in(img, "/FDAUTO.BAT", bat, paths.WORK)
    argv = freedos.command(img, accel=accel, mem_mb=mem, rtc_base=(paths.RTC if rtc else None))
    t0 = time.monotonic()
    subprocess.run(argv, check=False, capture_output=True, timeout=1800)
    _prof(f"qemu run [{accel}] {img.name}", time.monotonic() - t0)


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


def _check_log(log: str, text: str, invalidate_manifest: bool = True) -> None:
    """Hard-fail on any compiler/assembler/linker error found in a build log.

    Also invalidates the incremental manifest: the abort leaves the image in an
    unknown state (new sources synced in, MAKE may have deleted objects), and the
    manifest must not claim otherwise — e.g. reverting the broken edit would
    otherwise read as "no source changes" and re-verify old artifacts while the
    image still holds the broken source. Next ``bak build`` rebuilds clean.

    ``invalidate_manifest=False`` for the v1.02 pass: a 102 compile/link error must
    NOT poison the base 1.00 manifest — the 102 pass only writes OUT102\\ and never
    touches the OUT\\ objects the base manifest tracks, so the base build state stays
    valid regardless of the 102 outcome. It still hard-fails (exit 1)."""
    bad = [ln for ln in (raw.rstrip("\r") for raw in text.splitlines()) if _DIAG_RE.search(ln)]
    if not bad:
        return
    if invalidate_manifest:
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


def _read_log(img: Path, log: str, *, invalidate_manifest: bool = True) -> str:
    dst = paths.WORK / log
    dst.unlink(missing_ok=True)
    freedos.mcopy_out(img, f"/{log}", paths.WORK)
    text = dst.read_text(errors="replace") if dst.exists() else "<no log>"
    _check_log(log, text, invalidate_manifest=invalidate_manifest)
    return text


def _tcgobj_names() -> list[str]:
    """The TCG island's object basenames (``FOO.OBJ``), parsed from the MAKEFILE's
    ``TCGOBJ`` macro — the exact set to merge back from a whole-island TCG clone."""
    from . import incremental
    return [f"{b}.OBJ" for b in sorted(incremental._tcg_basenames())]


def _all_kvm_names() -> list[str]:
    """The KVM island's object basenames — the merge-back set for a whole-island KVM
    clone (only reached when the KVM set can't be enumerated for sharding)."""
    from . import incremental
    return [f"{b}.OBJ" for b in sorted(incremental._all_kvm_stems())]


def _merge_objs(src_img: Path, names: list[str], tag: str) -> int:
    """Copy the named ``OUT\\*.OBJ`` from ``src_img`` back into the canonical IMG.

    mtools preserves each object's (VM-clock) mtime across the copy, so merged objects
    keep the same freshness semantics as if built in IMG directly — a later dep-scan
    still sees them newer than their sources. Only the named objects move; everything
    else in IMG's OUT\\ is untouched."""
    stage = paths.WORK / f"merge_{tag}"
    stage.mkdir(parents=True, exist_ok=True)
    for f in stage.glob("*.OBJ"):
        f.unlink()
    for name in names:
        freedos.mcopy_out(src_img, f"/OUT/{name}", stage)
    objs = sorted(stage.glob("*.OBJ"))
    if objs:
        freedos.mcopy_in(paths.IMG, "OUT", *objs, text=False)
    return len(objs)


# Compile sharding: a broad header edit recompiles dozens of objects in one
# single-threaded Borland MAKE — the build's long pole. Splitting an island's stale
# object set across several concurrent VMs (each a reflink clone driven by a generated
# SHARD_<isl><i>.MAK target) cuts it to ~1/N. Below MIN objects the per-shard boot +
# merge overhead isn't worth it, so the island builds whole in one VM. MAX caps the
# concurrent VM count per island (host has KVM + cores to spare).
_SHARD_MIN = {"kvm": 12, "tcg": 4}
_SHARD_MAX = {"kvm": 4, "tcg": 3}


def _shard_makefile(stems: list[str]) -> str:
    """A generated MAKE fragment: include the real MAKEFILE, add a ``shard`` target
    depending on just these objects. Written into the image (never a tracked file), so
    it changes no build rule and can't perturb byte-identity — the compiler emits each
    object identically regardless of which VM drives it."""
    objs = " ".join(f"OUT\\{s}.OBJ" for s in stems)
    return "!include MAKEFILE\r\nshard : " + objs + "\r\n"


def _plan_shards(accel: str, stems: list[str] | None) -> list[list[str]]:
    """Split an island's stale object stems into shards (round-robin, even load).
    ``[[]]`` means "one VM builds the whole island target" — used when the set is
    small, empty (rebuild-all), or unknowable (unresolved include graph)."""
    lo, hi = _SHARD_MIN[accel], _SHARD_MAX[accel]
    if stems is None or len(stems) < lo:
        return [[]]
    n = min(hi, (len(stems) + lo - 1) // lo)
    shards: list[list[str]] = [[] for _ in range(n)]
    for i, s in enumerate(stems):
        shards[i % n].append(s)
    return shards


# One compile job: which accel, its image, its console log, the FDAUTO batch to run,
# and the object stems to merge back (empty ⇒ whole-island: merge the island's whole
# object set). Shard 0 of an island runs a whole-island make on the master IMG when
# unsharded; sharded jobs run a generated `shard` target on reflink clones.
class _Job:
    def __init__(self, accel: str, img: Path, log: str, bat: str, merge: list[str]):
        self.accel, self.img, self.log, self.bat, self.merge = accel, img, log, bat, merge


def _island_jobs(accel: str, make_exe: str, whole_target: str,
                 stems: list[str] | None, on_master: bool) -> list[_Job]:
    """Plan an island's concurrent jobs. ``on_master`` lets its first shard build into
    IMG directly (no copy-back); every other job gets a fresh reflink clone. ``.merge``
    holds the objects to copy back: a stem list for a shard, ``None`` for a whole-island
    clone (merge the whole island), ``[]`` when built into IMG (merge nothing)."""
    tag = accel.upper()
    jobs: list[_Job] = []
    for i, sh in enumerate(_plan_shards(accel, stems)):
        on_img = on_master and i == 0
        img = paths.IMG if on_img else paths.WORK / f"build_{accel}{i}.img"
        if not on_img:
            freedos._reflink(paths.IMG, img)
        log = f"{tag}{i}.LOG" if i else f"{tag}.LOG"
        if sh:  # sharded: inject a generated shard target (8.3-safe name SH<K|T><i>.MAK)
            dos_mak = f"SH{tag[0]}{i}.MAK"
            (paths.WORK / dos_mak).write_text(_shard_makefile(sh))
            freedos._mtool("mcopy", "-o", "-i", freedos._img(img),
                           str(paths.WORK / dos_mak), f"::/{dos_mak}")
            cmd = f"{make_exe} -f{dos_mak} shard"
            merge: list[str] | None = [] if on_img else [f"{s}.OBJ" for s in sh]
        else:  # one VM builds the whole island target
            cmd = f"{make_exe} {whole_target}"
            merge = [] if on_img else None
        jobs.append(_Job(accel, img, log,
                         _DOS_HEAD + f"{cmd} > C:\\{log}\r\n" + "c:\\EXIT.COM\r\n", merge))
    return jobs


def run_islands_parallel(compile_kvm: bool, kvm_stems: list[str] | None = None,
                         tcg_stems: list[str] | None = None) -> str:
    """Build both accel islands CONCURRENTLY (each possibly sharded across several VMs),
    then merge every built object into IMG. The caller links IMG in a final KVM boot.

    Every VM runs on its own reflink clone of IMG except one KVM shard, which builds
    into IMG directly (its objects need no copy-back). Object sets are disjoint across
    all VMs (KVMOBJ vs TCGOBJ, and disjoint shard subsets within an island), so no two
    qemu processes ever write the same bytes. After they exit, each clone's objects are
    copied back into IMG.

    ``compile_kvm`` gates the KVM island. ``kvm_stems``/``tcg_stems`` are the exact
    object sets to (re)build, enabling sharding; None → build the whole island target in
    one VM (small edit or an unresolved include graph)."""
    # TCG island always runs entirely on clones (a KVM shard owns IMG).
    jobs = _island_jobs("tcg", "maker", "tcgobjs", tcg_stems, on_master=False)
    if compile_kvm:
        jobs += _island_jobs("kvm", "make", "kvmobjs", kvm_stems, on_master=True)

    procs: list[tuple[_Job, subprocess.Popen]] = []
    for j in jobs:
        freedos.write_in(j.img, "/FDAUTO.BAT", j.bat, paths.WORK)
        mem = 96 if j.accel == "tcg" else 200
        argv = freedos.command(j.img, accel=j.accel, mem_mb=mem, rtc_base=None)
        procs.append((j, subprocess.Popen(
            argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)))

    t0 = time.monotonic()
    pending = {p: j for j, p in procs}
    while pending:
        for p in list(pending):
            if p.poll() is not None:
                j = pending.pop(p)
                _prof(f"  job [{j.accel} {j.log}] finished", time.monotonic() - t0)
        if pending:
            time.sleep(0.2)
    _prof(f"parallel islands ({len(procs)} qemu)", time.monotonic() - t0)

    # Read/scan every log only after all VMs have flushed and exited.
    out = [_read_log(j.img, j.log) for j, p in procs]

    t1 = time.monotonic()
    merged = 0
    for j, p in procs:
        if j.img == paths.IMG:
            continue  # built into IMG directly
        names = j.merge if j.merge is not None else (
            _tcgobj_names() if j.accel == "tcg" else _all_kvm_names())
        merged += _merge_objs(j.img, names, f"{j.accel}_{j.log}")
    _prof(f"merge objs ({merged})", time.monotonic() - t1)
    return "\n".join(out)


def run_kvm_link_102() -> str:
    """One KVM boot for the v1.02 CD pass: ``make kvmobjs102`` (the 30 -DV102CD C
    recompiles + the new CDAUDIO TASM module, at the real clock), then pin the DOS
    clock to 1994-03-21 and ``make link102`` (``tlink @KRN102.RSP`` → OUT102\\KRONDOR.EXE).

    The base 1.00 objects in OUT\\ (link inputs for every unchanged unit, plus the
    whole TCG island) must already exist — the caller runs a green base build first.
    Folds compile + link into a single boot exactly like ``run_kvm_link``; the 1994
    OVRINFO date comes from a mid-session DATE/TIME (the output is named KRONDOR.EXE
    so the OVRINFO self-name is authentic — only the directory differs from 1.00)."""
    day, tod = paths.RTC_102.split("T")  # 1994-03-21 , 12:00:00
    y, mo, dd = day.split("-")
    bat = _DOS_HEAD
    bat += "make kvmobjs102 > C:\\KVM102.LOG\r\n"
    bat += f"DATE {mo}-{dd}-{y}\r\nTIME {tod}\r\n"
    bat += "make link102 > C:\\LINK102.LOG\r\n"
    bat += "c:\\EXIT.COM\r\n"
    _run(bat, "kvm", 200, rtc=False)  # real clock at boot; DATE cmd pins 1994 for the link
    out = []
    for log in ("KVM102.LOG", "LINK102.LOG"):
        dst = paths.WORK / log
        dst.unlink(missing_ok=True)
        freedos.mcopy_out(paths.IMG, f"/{log}", paths.WORK)
        text = dst.read_text(errors="replace") if dst.exists() else "<no log>"
        _check_log(log, text, invalidate_manifest=False)
        out.append(text)
    return "\n".join(out)


def pull_exe_102() -> Path:
    """Copy OUT102\\KRONDOR.EXE out of the image to the host as work/KRONDOR102.EXE
    (a distinct name so it never clobbers the 1.00 work/KRONDOR.EXE). Staged through a
    scratch subdir because the in-image basename is KRONDOR.EXE (mcopy preserves it)."""
    stage = paths.WORK / "out102"
    stage.mkdir(parents=True, exist_ok=True)
    freedos.mcopy_out(paths.IMG, "/OUT102/KRONDOR.EXE", stage)
    dst = paths.WORK / "KRONDOR102.EXE"
    dst.unlink(missing_ok=True)
    (stage / "KRONDOR.EXE").replace(dst)
    return dst


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
