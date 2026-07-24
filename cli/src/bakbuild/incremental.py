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


# A header change is coarse: the current TU is not the only rebuild. We resolve the
# real include graph so the pass/link decision follows the *actual* dependents, not a
# blanket "a header could feed anything". `.C`/`.H` use `#include "..."` (bcc: -IINCLUDE
# then project-root then file-local); `.ASM`/`.INC` use TASM `INCLUDE <file>` (assembled
# with /iINCLUDE, so the same search order). Only quoted/bare includes are graphed —
# `<system>` includes resolve to the Borland CRT, never a bak/ source, so they can't
# make a bak/ header a dependent.
_C_INCLUDE = re.compile(r'^[ \t]*#[ \t]*include[ \t]*"([^"]+)"', re.MULTILINE)
_ASM_INCLUDE = re.compile(r'^[ \t]*INCLUDE[ \t]+(\S+)', re.MULTILINE | re.IGNORECASE)


def _resolve_include(spec: str, from_file: Path) -> Path | None:
    """Resolve one ``#include``/``INCLUDE`` spec to a bak/ file, or None if it names no
    tracked source (a system/CRT header). Search order mirrors the toolchain: the
    ``-IINCLUDE`` dir, the project (image) root, then the including file's own dir."""
    rel = spec.replace("\\", "/")
    for cand in (paths.BAK / "INCLUDE" / rel, paths.BAK / rel, from_file.parent / rel):
        if cand.is_file():
            return cand.resolve()
    return None


def _direct_includes() -> dict[Path, set[Path]]:
    """Map every bak/ source (``.C``/``.H``/``.INC``/``.ASM``) to the set of bak/ files
    it directly ``#include``s / ``INCLUDE``s."""
    edges: dict[Path, set[Path]] = {}
    for f in paths.BAK.rglob("*"):
        if not f.is_file() or f.suffix.upper() not in (".C", ".H", ".INC", ".ASM"):
            continue
        text = f.read_text(errors="replace")
        deps = {r for m in _C_INCLUDE.finditer(text)
                if (r := _resolve_include(m.group(1), f)) is not None}
        if f.suffix.upper() in (".ASM", ".INC"):
            deps |= {r for m in _ASM_INCLUDE.finditer(text)
                     if (r := _resolve_include(m.group(1), f)) is not None}
        edges[f.resolve()] = deps
    return edges


def _dependent_tus(headers: list[Path]) -> set[Path] | None:
    """The set of TUs (``.C``/``.ASM``) that transitively include any of *headers*,
    or None if the include graph can't be resolved for one of them (→ caller falls back
    to the conservative "rebuild everything" so an unresolved edge never drops work).

    A header not found in the graph means an unmodelled include path — treat it as
    reaching every TU (return None) rather than risk skipping a real dependent."""
    edges = _direct_includes()
    if any(h.resolve() not in edges for h in headers):
        return None
    frontier = {h.resolve() for h in headers}
    seen: set[Path] = set(frontier)
    while frontier:
        nxt = {f for f, deps in edges.items() if deps & frontier} - seen
        seen |= nxt
        frontier = nxt
    return {f for f in seen if f.suffix.upper() in (".C", ".ASM")}


def classify(changed: list[str]) -> tuple[bool, bool, bool]:
    """Decide which passes a set of changed source paths requires.

    Returns ``(kvm_needed, tcg_needed, must_full)``:
      * ``.C`` → KVM or TCG by whether its basename is in the island.
      * ``.ASM`` → KVM (GEN vtables + TASM anchors all build under KVM).
      * ``.H``/``.INC`` → the passes of its *real dependents*, resolved from the
        include graph: a header that reaches no TCG-island TU skips the (slow) TCG
        boot entirely; one that reaches no KVM TU skips the KVM compile. MAKE's
        ``.autodepend`` then narrows to the exact objects within each booted pass.
        If the graph can't be resolved, fall back to both passes.
      * MAKEFILE / ``*.MAK`` → build *rules* changed; force a clean rebuild.
      * anything else (``.RSP``/``.PAK``/``.BIN``/``.TXT``) → no compile; the
        always-run link/pack stage picks it up.
    """
    island = _tcg_basenames()
    kvm = tcg = full = False
    headers: list[Path] = []
    for rel in changed:
        p = Path(rel)
        name, ext, stem = p.name.upper(), p.suffix.upper(), p.stem.upper()
        if name == "MAKEFILE" or ext == ".MAK":
            full = True
        elif ext in (".H", ".INC"):
            headers.append(paths.BAK / rel)
        elif ext == ".C":
            if stem in island:
                tcg = True
            else:
                kvm = True
        elif ext == ".ASM":
            kvm = True

    if headers:
        tus = _dependent_tus(headers)
        if tus is None:
            kvm = tcg = True  # unresolved include graph — rebuild both passes
        else:
            stems = {t.stem.upper() for t in tus}
            if stems & island:
                tcg = True
            if stems - island:  # any non-island (KVM) dependent TU
                kvm = True
    return kvm, tcg, full


def _all_kvm_stems() -> set[str]:
    """Every KVM-island object basename (upper), parsed from the MAKEFILE's KVMOBJ
    macro — the universe a shard target may draw from."""
    text = (paths.BAK / "MAKEFILE").read_text()
    joined = re.sub(r"\\\s*\n", " ", text)
    m = re.search(r"^KVMOBJ\s*=(.*)$", joined, re.MULTILINE)
    if not m:
        raise RuntimeError("could not find KVMOBJ macro in bak/MAKEFILE")
    return {b.upper() for b in re.findall(r"OUT\\(\w+)\.OBJ", m.group(1))}


def kvm_targets(changed: list[str]) -> list[str] | None:
    """The explicit KVM object stems a build must recompile, for sharding the KVM
    compile across several concurrent VMs — or None when the exact set can't be
    enumerated (an unresolvable include graph), in which case the caller builds the
    whole ``kvmobjs`` target in one VM.

    Only ``.C``/``.ASM``/``.H``/``.INC`` inputs contribute objects; a bare ``.C``/
    ``.ASM`` edit is its own single object, a header expands to its KVM dependents.
    The returned stems are a *superset* of what's actually stale — MAKE's own mtime
    check still no-ops the fresh ones, so an over-broad shard target is safe, never
    wrong. Stems outside the KVMOBJ universe (e.g. GEN vtables built implicitly) are
    dropped; they ride the always-run link."""
    island = _tcg_basenames()
    all_kvm = _all_kvm_stems()
    stems: set[str] = set()
    headers: list[Path] = []
    for rel in changed:
        p = Path(rel)
        ext, stem = p.suffix.upper(), p.stem.upper()
        if ext in (".H", ".INC"):
            headers.append(paths.BAK / rel)
        elif ext == ".C" and stem not in island:
            stems.add(stem)
        elif ext == ".ASM":
            stems.add(stem)
    if headers:
        tus = _dependent_tus(headers)
        if tus is None:
            return None  # unresolved graph — can't enumerate; caller builds all
        stems |= {t.stem.upper() for t in tus} - island
    return sorted(stems & all_kvm)


def tcg_targets(changed: list[str]) -> list[str] | None:
    """The explicit TCG-island object stems a build must recompile, for sharding the
    TCG compile across concurrent VMs — or None when the set can't be enumerated (an
    unresolvable include graph → build the whole ``tcgobjs`` target in one VM).

    Same superset guarantee as ``kvm_targets``: MAKE no-ops any listed object that is
    already fresh, so an over-broad shard target can't build the wrong thing."""
    island = _tcg_basenames()
    stems: set[str] = set()
    headers: list[Path] = []
    for rel in changed:
        p = Path(rel)
        ext, stem = p.suffix.upper(), p.stem.upper()
        if ext in (".H", ".INC"):
            headers.append(paths.BAK / rel)
        elif ext == ".C" and stem in island:
            stems.add(stem)
    if headers:
        tus = _dependent_tus(headers)
        if tus is None:
            return None
        stems |= {t.stem.upper() for t in tus} & island
    return sorted(stems)


def needs_full_link(changed: list[str]) -> bool:
    """True if the link must run the full ``make all`` (tlink ``/m`` + OVL repack);
    False if a plain KRONDOR.EXE relink suffices (the dev fast path, which drops the
    unused ``/m`` public-symbol map + the OVL repack, ~0.77s).

    A relink-only is safe exactly when nothing changed feeds the OVLs or their packer:
    not a driver chunk (``SRC/DRIVERS``), not the PACKOVL tool (``TOOLS``), not an OVL
    data blob (``.PAK``/``.BIN``). For a changed **header** this is decided by its real
    include closure — the OVL drivers are pure TASM (``INCLUDE gfxctx.inc`` only) and no
    C header reaches them, so a C-header edit never forces the repack. An unresolvable
    graph falls back to the full link."""
    driver_or_tool = ("SRC/DRIVERS", "TOOLS")
    headers: list[Path] = []
    for rel in changed:
        u = rel.upper()
        ext = Path(rel).suffix.upper()
        if ext in (".H", ".INC"):
            # A header/inc that physically lives beside the OVL drivers or the packer
            # tool is treated as OVL-affecting outright: TASM's own include search can
            # resolve a driver-local .INC ahead of the -iINCLUDE copy, which the C-style
            # include graph doesn't model — so repack rather than guess.
            if u.startswith(driver_or_tool):
                return True
            headers.append(paths.BAK / rel)
            continue
        exe_only = ext in (".C", ".ASM") and not u.startswith(driver_or_tool)
        if not exe_only:
            return True  # driver/tool source or an OVL data blob (.PAK/.BIN)

    if headers:
        tus = _dependent_tus(headers)
        if tus is None:
            return True  # unresolved include graph — be safe, repack the OVLs
        if any(str(t.relative_to(paths.BAK)).upper().replace("\\", "/").startswith(
                driver_or_tool) for t in tus):
            return True
    return False
