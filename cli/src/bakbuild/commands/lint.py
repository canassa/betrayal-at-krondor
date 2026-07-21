"""``bak lint`` — check the C sources against the naming conventions.

With no arguments it lints every translation unit in ``compile_commands.json``;
pass file paths to lint just those. Findings print as ``path:line:col: message``
with header findings deduplicated across TUs. Exits 1 when anything is flagged,
0 on a clean tree — check-only, never rewrites (see bakbuild.lint on why
``--fix`` is forbidden here).
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from ..lint import lint_files


def lint(
    files: Annotated[
        list[Path] | None,
        typer.Argument(help="Translation units to lint; default: every compile_commands.json unit."),
    ] = None,
) -> None:
    """Check naming conventions (clang-tidy, pinned config, check-only)."""
    findings, failed = lint_files(files)
    for line in findings:
        typer.echo(line)
    for unit in failed:
        typer.echo(f"note: {unit} did not fully parse under the IDE shim; findings may be partial")
    if findings:
        typer.echo(f"{len(findings)} naming finding(s)")
        raise typer.Exit(code=1)
    typer.echo("naming clean")


def register(app: typer.Typer) -> None:
    app.command(name="lint")(lint)
