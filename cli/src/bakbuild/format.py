"""Format C files in place with clang-format, under the project's pinned style.

We format *files* explicitly (``clang-format -i --style=file:…``): the style
(``clang-format.yaml``, a package resource) is never dropped as a tree-wide
``.clang-format``, so editors and other tools can't reach the byte-match-sensitive
units on their own, and the hand-written ``.asm`` files are never targeted.
"""

from __future__ import annotations

import subprocess
from collections.abc import Iterable
from importlib.resources import as_file, files
from pathlib import Path

_STYLE = files("bakbuild").joinpath("clang-format.yaml")


def format_files(paths: Iterable[Path]) -> None:
    """Reformat the given C files in place (no-op on an empty list).

    Raises ``FileNotFoundError`` if clang-format isn't on PATH (run in the nix dev
    shell) and ``subprocess.CalledProcessError`` if it rejects a file.
    """
    targets = [str(p) for p in paths]
    if not targets:
        return
    with as_file(_STYLE) as style_path:
        subprocess.run(
            ["clang-format", "-i", f"--style=file:{style_path}", *targets],
            check=True,
        )
