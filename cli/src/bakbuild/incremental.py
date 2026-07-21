"""Incremental-build bookkeeping for the default ``bak build``.

The hermetic ``--clean`` build always works because every build fingerprints the
three artifacts against the shipped 1993 SHA-256s (see ``paths.ARTIFACTS``): an
incremental build can only ever cause a *false failure* (a stale object → wrong
bytes → verify fails loudly), never a false success. That safety net is what lets
incremental be the default.

Mechanics: after every build — green or red — we snapshot every ``bak/`` source's
content hash into ``work/build_manifest.json`` (the manifest tracks what the IMAGE
contains, plus whether that state verified). The next build diffs current hashes to
learn what changed, syncs only those files into the persistent ``build.img`` (so
their mtime bumps ahead of the existing objects), and lets Borland MAKE's own
``.autodepend`` + mtime logic rebuild exactly the stale objects — including
header-triggered rebuilds. We only decide *which of the two accel passes* to boot;
MAKE decides which objects within a pass to recompile.
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from . import paths

MANIFEST = paths.WORK / "build_manifest.json"


def source_hashes() -> dict[str, str]:
    """Map every ``bak/`` file (relative POSIX path) to its content SHA-256.

    Mirrors exactly the file set ``vm.mirror`` stages into the image, so the diff
    sees everything the build could depend on."""
    out: dict[str, str] = {}
    for f in sorted(p for p in paths.BAK.rglob("*") if p.is_file()):
        out[f.relative_to(paths.BAK).as_posix()] = hashlib.sha256(f.read_bytes()).hexdigest()
    return out


def load_manifest() -> tuple[dict[str, str], bool] | None:
    """``(source hashes, verified)`` recorded after the last build, or None.

    *verified* is whether that build's artifacts fingerprinted byte-identical.
    It distinguishes a working tree that is *intentionally divergent* (unchanged
    sources + red artifacts + verified=False → nothing to rebuild) from a wedged
    image (unchanged sources + red artifacts + verified=True → clean rebuild).
    Manifests written before the flag existed read as unverified — the safe
    direction (at worst one fast re-verify instead of a spurious clean build)."""
    if not MANIFEST.exists():
        return None
    try:
        data = json.loads(MANIFEST.read_text())
        return data["sources"], bool(data.get("verified", False))
    except (json.JSONDecodeError, KeyError, OSError):
        return None


def save_manifest(hashes: dict[str, str], verified: bool) -> None:
    paths.WORK.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(
        json.dumps({"sources": hashes, "verified": verified}, indent=0, sort_keys=True)
    )


def diff(old: dict[str, str], new: dict[str, str]) -> tuple[list[str], bool]:
    """(paths whose content changed or are new, structural?) where *structural*
    means files were added or removed — the file *set* differs. A structural change
    forces a clean rebuild: new/removed units can shift the link and can't be
    reasoned about from a content diff alone."""
    changed = sorted(p for p, h in new.items() if old.get(p) != h)
    structural = set(old) != set(new)
    return changed, structural


def _tcg_basenames() -> set[str]:
    """The 18 object basenames of the TCG island, parsed from the MAKEFILE's
    ``TCGOBJ`` macro so we stay in sync with the real backend split (bak/MAKEFILE)."""
    text = (paths.BAK / "MAKEFILE").read_text()
    # Join backslash line-continuations, then isolate the TCGOBJ = ... assignment.
    joined = re.sub(r"\\\s*\n", " ", text)
    m = re.search(r"^TCGOBJ\s*=(.*)$", joined, re.MULTILINE)
    if not m:
        raise RuntimeError("could not find TCGOBJ macro in bak/MAKEFILE")
    return {b.upper() for b in re.findall(r"OUT\\(\w+)\.OBJ", m.group(1))}


def classify(changed: list[str]) -> tuple[bool, bool, bool]:
    """Decide which passes a set of changed source paths requires.

    Returns ``(kvm_needed, tcg_needed, must_full)``:
      * ``.C`` → KVM or TCG by whether its basename is in the island.
      * ``.ASM`` → KVM (GEN vtables + TASM anchors all build under KVM).
      * ``.H``/``.INC`` → both passes (a header can feed either; ``.autodepend``
        then narrows it to the real dependents within each pass).
      * MAKEFILE / ``*.MAK`` → build *rules* changed; force a clean rebuild.
      * anything else (``.RSP``/``.PAK``/``.BIN``/``.TXT``) → no compile; the
        always-run link/pack stage picks it up.
    """
    island = _tcg_basenames()
    kvm = tcg = full = False
    for rel in changed:
        p = Path(rel)
        name, ext, stem = p.name.upper(), p.suffix.upper(), p.stem.upper()
        if name == "MAKEFILE" or ext == ".MAK":
            full = True
        elif ext in (".H", ".INC"):
            kvm = tcg = True
        elif ext == ".C":
            if stem in island:
                tcg = True
            else:
                kvm = True
        elif ext == ".ASM":
            kvm = True
    return kvm, tcg, full


def needs_full_link(changed: list[str]) -> bool:
    """True if the link must run the full ``make all`` (tlink ``/m`` + OVL repack);
    False if a plain KRONDOR.EXE relink suffices (the dev fast path, which drops the
    unused ``/m`` public-symbol map, ~0.77s).

    A relink-only is safe exactly when every changed file is a ``.C``/``.ASM`` that
    feeds *only* KRONDOR.EXE — i.e. not a driver chunk (``SRC/DRIVERS``), not the
    PACKOVL tool (``TOOLS``), and not a header (which via ``.autodepend`` could pull a
    driver chunk) or an OVL data blob (``.PAK``/``.BIN``). Anything else → full link,
    so the OVLs and their tool stay correct."""
    for rel in changed:
        u = rel.upper()
        ext = Path(rel).suffix.upper()
        exe_only = (
            ext in (".C", ".ASM")
            and not u.startswith("SRC/DRIVERS")
            and not u.startswith("TOOLS")
        )
        if not exe_only:
            return True
    return False
