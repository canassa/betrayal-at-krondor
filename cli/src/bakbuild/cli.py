"""bak — the build CLI entry point.

The root Typer app is assembled here; each command module owns its own wiring and
registers itself. Adding a command = a new ``commands/<name>.py`` plus one
``register(app)`` line below.

    bak build [STAGE]   1993-authentic MAKE build of KRONDOR.EXE (default: all)
    bak diff SOURCE     disassembly diff of one source's OBJ vs the last green build
    bak format [FILES]  clang-format the C sources in place (default: whole tree)
    bak lint [FILES]    naming-convention check, clang-tidy check-only (default: all TUs)
    bak compdb          emit compile_commands.json for CLion / clangd indexing
    bak rmf …           inspect / extract the KRONDOR.RMF resource container
    bak viewer          serve the browser-based asset viewer
    bak clean           remove the build scratch (work/)
"""

from __future__ import annotations

import shutil

import typer

from . import paths
from .commands import build as build_cmd
from .commands import compdb as compdb_cmd
from .commands import diff as diff_cmd
from .commands import format as format_cmd
from .commands import lint as lint_cmd
from .commands import rmf as rmf_cmd
from .commands import viewer as viewer_cmd

app = typer.Typer(
    name="bak",
    help="1993-authentic Borland MAKE build of KRONDOR.EXE (Betrayal at Krondor).",
    no_args_is_help=True,
    add_completion=False,
)

build_cmd.register(app)
diff_cmd.register(app)
format_cmd.register(app)
lint_cmd.register(app)
compdb_cmd.register(app)
rmf_cmd.register(app)
viewer_cmd.register(app)


@app.command()
def clean() -> None:
    """Remove the build scratch (work/): the disk image, pulled objs, and logs."""
    if paths.WORK.exists():
        shutil.rmtree(paths.WORK)
        typer.echo(f"removed {paths.WORK}")
    else:
        typer.echo("nothing to clean")


def main() -> None:
    app()


if __name__ == "__main__":
    main()
