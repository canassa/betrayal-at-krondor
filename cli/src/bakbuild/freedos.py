"""FreeDOS-on-qemu primitives for the build (self-contained).

The build VM: a copy of a cached *base* disk image (FreeDOS 1.3 LiteUSB + the
Borland toolchain baked at ``C:\\BC`` / ``C:\\BC20`` / ``C:\\BC30``) with the
``bak/`` tree + ``FDAUTO.BAT`` injected. The VM boots, ``FDAUTO.BAT`` builds,
then ``C:\\EXIT.COM`` flushes DOS's dirty buffers (INT 21h AH=0Dh) and writes
qemu's ``isa-debug-exit`` port for an instant shutdown. Files cross via
``mtools`` (offline FAT edits), never a live mount. All assets live in this
repo's ``toolchain/`` tree, so nothing outside the repo is read.

Two accel backends are inherent (empirically verified): the bc20 BCCX island runs
on the 1991 A.I. Architects 286 extender, whose 286-task-switch mode entry qemu-KVM
can't virtualize (GP fault), so it builds under qemu-TCG (``-cpu 486``); bc31 + TASM
build under KVM for speed. The TCG pass drives MAKE via the real-mode ``MAKER`` (the
DPMI ``MAKE`` corrupts a spawned child's mode switch under qemu-TCG).
"""

from __future__ import annotations

import fcntl
import hashlib
import logging
import os
import shutil
import subprocess
from pathlib import Path

from . import paths

log = logging.getLogger("bakbuild.freedos")

# FreeDOS 1.3 LiteUSB: partition 1 starts at sector 63 (x512 = 32256). mtools
# addresses the FAT inside the partition with ``<img>@@<offset>``.
PART_OFFSET = 32256
# Inherit the environment (PATH etc.) and add the mtools flag — env= replaces,
# not merges, so a bare dict would hide mmd/mcopy from PATH. SOURCE_DATE_EPOCH
# must NOT leak through: the nix devshell exports it (=1980-01-01) and mtools
# honors it, stamping every copied file with the DOS epoch — which silently
# defeats the incremental build's "re-copy bumps the in-image mtime" mechanism
# (MAKE then never sees a changed source as newer than its object).
_MENV = {k: v for k, v in os.environ.items() if k != "SOURCE_DATE_EPOCH"}
_MENV["MTOOLS_SKIP_CHECK"] = "1"

FREEDOS_IMAGE = paths.TOOLCHAIN / "freedos" / "freedos.img"
EXIT_COM = paths.TOOLCHAIN / "freedos" / "EXIT.COM"
BC31_DIR = paths.TOOLCHAIN / "bc31"  # Borland C++ 3.1 (KVM)
BC30_DIR = paths.TOOLCHAIN / "bc30"  # Borland C++ 3.0 (KVM, invoked as C:\BC30\BCC)
BC20_DIR = paths.TOOLCHAIN / "bc20"  # BCCX 2.0 protected-mode (TCG)

BASE_IMG = paths.WORK / "base.img"
_BASE_KEY = paths.WORK / "base.key"


def _img(path: Path) -> str:
    return f"{path}@@{PART_OFFSET}"


def _mtool(tool: str, *args: str) -> None:
    subprocess.run([tool, *args], env=_MENV, check=True, capture_output=True)


def mmd(img: Path, *dos_dirs: str) -> None:
    """mkdir inside the image (ignores 'already exists')."""
    subprocess.run(["mmd", "-i", _img(img), *dos_dirs], env=_MENV, capture_output=True)


def mcopy_in(
    img: Path, dest_dos_dir: str, *host: Path, recursive: bool = False, text: bool = False
) -> None:
    # mtools wants forward slashes; "" / "/" => image root. text=True (-t) does
    # LF→CRLF translation — BCCX's preprocessor is picky about line endings.
    dest = dest_dos_dir.strip("/")
    target = "::/" if not dest else f"::/{dest}/"
    args = ["-o", "-i", _img(img)]
    if recursive:
        args.append("-s")
    if text:
        args.append("-t")
    _mtool("mcopy", *args, *[str(p) for p in host], target)


def mcopy_out(img: Path, dos_glob: str, dest_dir: Path) -> None:
    """Copy matching files out of the image (clobber; ignore if none match)."""
    subprocess.run(
        ["mcopy", "-n", "-i", _img(img), f"::{dos_glob}", str(dest_dir) + "/"],
        env=_MENV,
        capture_output=True,
    )


def write_in(img: Path, dos_path: str, text: str, scratch: Path) -> None:
    """Write ``text`` to ``dos_path`` inside the image (via a host temp file).

    The host temp file is namespaced by the image stem so two islands writing the
    same DOS path (``/FDAUTO.BAT``) into *different* images concurrently don't race
    on one shared scratch file (see ``vm.run_islands_parallel``)."""
    tmp = scratch / f"{img.stem}.{Path(dos_path).name}"
    tmp.write_text(text)
    _mtool("mcopy", "-o", "-i", _img(img), str(tmp), f"::{dos_path}")


def _reflink(src: Path, dst: Path) -> None:
    """Copy-on-write copy where the filesystem supports it (instant on btrfs),
    else a normal copy."""
    try:
        subprocess.run(
            ["cp", "--reflink=auto", str(src), str(dst)], check=True, capture_output=True
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        shutil.copy2(src, dst)
    # The toolchain source image is read-only (Nix store); a reflink/copy inherits
    # that mode, but mtools must write into the base image. Ensure it is writable.
    os.chmod(dst, 0o644)


def _toolchain_key() -> str:
    """Hash of the baked assets, so the base image rebuilds when they change."""
    h = hashlib.sha256()
    inputs: list[Path] = [FREEDOS_IMAGE, EXIT_COM]
    inputs += sorted((BC31_DIR / "BIN").glob("*"))
    inputs += sorted((BC31_DIR / "INCLUDE").rglob("*"))
    inputs += sorted((BC31_DIR / "LIB").glob("*"))
    inputs += sorted(BC20_DIR.glob("*"))
    inputs += sorted(BC30_DIR.glob("*"))
    for p in inputs:
        if p.is_file():
            st = p.stat()
            h.update(f"{p}:{st.st_size}:{int(st.st_mtime)}".encode())
    return h.hexdigest()


def build_base() -> Path:
    """Build (or reuse) the cached base image: FreeDOS + the Borland toolchain.

    An flock serializes the rebuild so two parallel cold builds don't both write
    base.img — the loser waits, then reuses."""
    paths.WORK.mkdir(parents=True, exist_ok=True)
    key = _toolchain_key()
    if BASE_IMG.exists() and _BASE_KEY.exists() and _BASE_KEY.read_text() == key:
        return BASE_IMG

    with (paths.WORK / ".base.lock").open("w") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        # Re-check under the lock: another builder may have finished while we waited.
        if BASE_IMG.exists() and _BASE_KEY.exists() and _BASE_KEY.read_text() == key:
            return BASE_IMG
        return _build_base_locked(key)


def _build_base_locked(key: str) -> Path:
    log.info("building FreeDOS base image (toolchain) …")
    _reflink(FREEDOS_IMAGE, BASE_IMG)
    mmd(BASE_IMG, "::/BC", "::/BC/BIN", "::/BC/INCLUDE", "::/BC/LIB", "::/BC20", "::/BC30")
    mcopy_in(BASE_IMG, "/", EXIT_COM)  # C:\EXIT.COM (flush + isa-debug-exit, both backends)
    mcopy_in(BASE_IMG, "BC/BIN", *sorted((BC31_DIR / "BIN").glob("*")))
    mcopy_in(BASE_IMG, "BC/INCLUDE", *sorted((BC31_DIR / "INCLUDE").glob("*")), recursive=True)
    mcopy_in(BASE_IMG, "BC/LIB", *sorted((BC31_DIR / "LIB").glob("*")))
    mcopy_in(BASE_IMG, "BC20", *sorted(BC20_DIR.glob("*")))
    mcopy_in(BASE_IMG, "BC30", *sorted(BC30_DIR.glob("*")))
    _BASE_KEY.write_text(key)
    return BASE_IMG


def command(
    img: Path, accel: str = "kvm", *, mem_mb: int | None = None, rtc_base: str | None = None
) -> list[str]:
    """qemu argv: headless FreeDOS VM. ``accel`` selects the per-compiler backend
    (``kvm`` for bc31/bc30/TASM, ``tcg -cpu 486`` for BCCX). ``rtc_base`` pins the
    VM clock — TLINK /o stamps the link DATE into the OVRINFO trailer, so the link
    stage pins it to the original's 1993 link date to reproduce those bytes."""
    if accel == "tcg":
        accel_args = ["-accel", "tcg", "-cpu", "486", "-m", str(mem_mb or 64)]
    else:
        accel_args = ["-enable-kvm", "-m", str(mem_mb or 32)]
    # Default the VM clock to host *local* time: mtools stamps synced files with
    # host-local mtimes, so a UTC VM clock would leave every fresh object "older"
    # than its just-synced source for hours, re-triggering MAKE each boot.
    rtc_args = ["-rtc", f"base={rtc_base}" if rtc_base else "base=localtime"]
    return [
        "qemu-system-i386",
        *accel_args,
        *rtc_args,
        "-display",
        "none",
        "-no-reboot",
        "-net",
        "none",
        "-device",
        "isa-debug-exit,iobase=0x501,iosize=1",
        "-drive",
        f"file={img},format=raw,if=ide,cache=writeback",
        "-boot",
        "c",
    ]
