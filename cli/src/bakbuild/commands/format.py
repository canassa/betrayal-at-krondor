"""``bak format`` — clang-format the project's C sources in place.

With no arguments it formats every ``.c``/``.h`` under ``bak/`` (the INCLUDE
headers, the SRC units, and the TOOLS sources like PACKOVL.C); pass file paths to
format just those (what the lefthook pre-commit hook does with the staged
``*.{c,h}``). The pinned style lives in ``bakbuild/clang-format.yaml`` and is
applied explicitly — never as a tree-wide ``.clang-format`` — so nothing
reformats these units except this command.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from .. import paths
from ..format import format_files


def _default_targets() -> list[Path]:
    """Every ``.c``/``.h`` under ``bak/`` — INCLUDE headers, SRC units, TOOLS.

    Hand-written assembly (``bak/SRC/DRIVERS/**/*.ASM`` and friends) is
    intentionally excluded — a C formatter has no business there. The extension
    match is case-insensitive: the units carry uppercase DOS names (``IO.C``).
    """
    return sorted(p for p in paths.BAK.rglob("*") if p.suffix.lower() in (".c", ".h"))


def format_(
    files: Annotated[
        list[Path] | None,
        typer.Argument(help="C files to format; default: the whole bak/ C tree."),
    ] = None,
) -> None:
    """Format C sources in place (clang-format, pinned style)."""
    targets = list(files) if files else _default_targets()
    format_files(targets)
    typer.echo(f"formatted {len(targets)} file(s)")


def register(app: typer.Typer) -> None:
    app.command(name="format")(format_)
