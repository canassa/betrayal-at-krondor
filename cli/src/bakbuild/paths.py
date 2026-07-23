"""Filesystem anchors for the build.

The project is fully self-contained: the DOS-mountable ``bak/`` tree, the vendored
period toolchain (``toolchain/``: Borland compilers + the FreeDOS boot image),
and this launcher. Nothing outside the repo is read.
"""

from __future__ import annotations

import os
from pathlib import Path

# project root: cli/src/bakbuild/paths.py -> parents[3]
PROJECT_ROOT = Path(__file__).resolve().parents[3]
BAK = PROJECT_ROOT / "bak"  # the DOS-mountable tree (SRC/, INCLUDE/, MAKEFILE, KRONDOR.RSP)
WORK = PROJECT_ROOT / "work"  # build scratch (gitignored): disk images, pulled artifacts, logs
IMG = WORK / "build.img"

# The period toolchain: bc31 (BIN incl. MAKE + real-mode MAKER, INCLUDE, LIB with
# C0M.OBJ/CM.LIB/OVERLAY.LIB), bc30, bc20 (BCCX), FreeDOS image + EXIT.COM. Not
# committed — the flake fetches a hash-pinned tarball and points $BAK_TOOLCHAIN at
# it; falls back to ./toolchain when unset (e.g. running outside the nix shell).
TOOLCHAIN = Path(os.environ.get("BAK_TOOLCHAIN") or (PROJECT_ROOT / "toolchain"))

# The byte-identity targets: the complete shipped 1993 binary set — the main
# executable KRONDOR.EXE and the two loadable driver archives VMCODE.OVL (video)
# and SX.OVL (sound/music). We do NOT keep copies of the originals in-tree —
# instead the build validates against their fingerprints, so success is provable
# without any reference file to compare against. (name, size, sha256):
ARTIFACTS = (
    ("KRONDOR.EXE", 453904, "c943fd895a570224813c767d47acf44299c0aff972f1ea5f743aef303ebdd7fe"),
    ("VMCODE.OVL", 44582, "cd0cf73df9b11b7f70aa2036c813a64a8178ba60d24f9bbe548155c3e56237e0"),
    ("SX.OVL", 40742, "d73d92d8ff1a698ad64df9b108a04bc1ee7221bc4c336b4a6073191e5f4dabdb"),
)

RTC = "1993-06-16T12:00:00"  # TLINK stamps the OVRINFO date from the VM clock

# The v1.02 CD build. Only KRONDOR.EXE differs from 1.00 (VMCODE.OVL/SX.OVL are
# byte-identical across versions — no 102 variants). The 1.02 EXE is a surgical
# patch: 30 TUs recompiled -DV102CD + the all-new CDAUDIO resident module, relinked
# via KRN102.RSP. Its OVRINFO date is stamped from a 1994-03-21 VM clock.
ARTIFACTS_102 = (
    ("KRONDOR.EXE", 456048, "e254770143e003dbac55b739e9efddfe84a70cbc5a8186f1bf79f38386056a59"),
)

RTC_102 = "1994-03-21T12:00:00"  # TLINK stamps the 1.02 OVRINFO date from the VM clock
