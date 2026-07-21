"""``bak viewer`` — serve the browser-based asset viewer.

A tiny no-cache ``http.server`` over ``viewer/``. Caching is disabled so that
editing an ES module and reloading always runs the fresh JS (a plain cache would
serve stale modules and mimic "the change didn't save").
"""

from __future__ import annotations

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

import typer

from .. import paths


class _NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def viewer(port: int = typer.Option(8096, help="Port to serve on.")) -> None:
    """Serve the asset viewer at http://localhost:<port>/.

    Put your own KRONDOR.001 / KRONDOR.RMF / STARTUP.GAM in viewer/data/ first.
    """
    root = paths.PROJECT_ROOT / "viewer"
    handler = partial(_NoCacheHandler, directory=str(root))
    server = ThreadingHTTPServer(("0.0.0.0", port), handler)
    typer.echo(f"viewer: http://localhost:{port}/  (Ctrl-C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        typer.echo("\nstopped")


def register(app: typer.Typer) -> None:
    app.command(name="viewer")(viewer)
