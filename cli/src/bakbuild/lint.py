"""Check C sources against the naming conventions with clang-tidy.

Check-only, always: this module never passes ``--fix`` and none should be
added. Renaming an uninitialized (``_BSS``) global permutes bccx's
hash-ordered layout and diverges KRONDOR.EXE — naming fixes stay manual,
verified by ``bak build``.

The pinned check set (``clang-tidy.yaml``, a package resource) is applied
explicitly via ``--config-file`` — never dropped as a tree-wide
``.clang-tidy`` — mirroring the clang-format setup. Translation units come
from the repo's ``compile_commands.json`` (the ``bak compdb`` output whose
forced shim header makes the Borland dialect parseable), so headers are
covered through the TUs that include them; identical header findings from
different TUs are deduplicated.
"""

from __future__ import annotations

import json
import re
import subprocess
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from importlib.resources import as_file, files
from os import cpu_count
from pathlib import Path

from . import paths

_CONFIG = files("bakbuild").joinpath("clang-tidy.yaml")

_WARNING = re.compile(r"^(?P<loc>[^:\n]+:\d+:\d+): warning: (?P<msg>.*)$", re.MULTILINE)


def _compile_db_units() -> list[Path]:
    """The translation units listed in compile_commands.json, in file order."""
    db_path = paths.PROJECT_ROOT / "compile_commands.json"
    if not db_path.exists():
        raise FileNotFoundError(
            f"{db_path} not found — run `bak compdb` first (clang-tidy needs the compile flags)"
        )
    return [Path(entry["file"]) for entry in json.loads(db_path.read_text())]


def _run_one(config_path: Path, unit: Path) -> tuple[str, bool]:
    """clang-tidy one unit; returns (diagnostics stdout, parsed cleanly).

    A non-zero exit means the unit didn't fully parse under the IDE shim
    (Borland-isms host clang can't swallow, e.g. PALDRV.C's pointer-constant
    initializers). Findings emitted before the error are still usable, so the
    unit is reported, not fatal.
    """
    result = subprocess.run(
        [
            "clang-tidy",
            "-p",
            str(paths.PROJECT_ROOT),
            f"--config-file={config_path}",
            "--quiet",
            str(unit),
        ],
        capture_output=True,
        text=True,
    )
    return result.stdout, result.returncode == 0


def lint_files(units: Iterable[Path] | None = None) -> tuple[list[str], list[Path]]:
    """Lint the given TUs (default: every compile_commands.json unit).

    Returns ``(findings, failed_units)``: findings are deduplicated
    ``path:line:col: message`` strings (paths repo-relative), sorted by
    location — header findings repeated by several TUs appear once;
    failed_units are TUs that didn't fully parse (their pre-error findings
    are still included).
    """
    targets = list(units) if units else _compile_db_units()
    findings: dict[str, str] = {}
    failed: list[Path] = []
    with as_file(_CONFIG) as config_path, ThreadPoolExecutor(max_workers=cpu_count()) as pool:
        for unit, (output, ok) in zip(
            targets, pool.map(lambda u: _run_one(config_path, u), targets)
        ):
            if not ok:
                failed.append(unit)
            for m in _WARNING.finditer(output):
                loc = m.group("loc")
                try:
                    loc = str(Path(loc).relative_to(paths.PROJECT_ROOT))
                except ValueError:
                    pass
                findings.setdefault(f"{loc}: {m.group('msg')}", loc)

    def sort_key(item: str) -> tuple[str, int]:
        path, line = item.split(":", 2)[:2]
        return (path, int(line))

    return sorted(findings, key=sort_key), failed
