"""``bak rmf`` — inspect and extract the shipped KRONDOR.RMF resource container.

A debugging aid, not part of the build. KRONDOR.RMF is only an *index*: a
small header naming the archive file (``krondor.001``) followed by
``(hashkey, offset)`` pairs. The payload bytes live in that sibling archive,
where every entry is self-describing::

    13-byte NUL-padded DOS name | u32 payload size | payload

so names and sizes are read from the archive at the offsets the RMF gives.

    bak rmf list PATH                 table of every resource (name/size/offset/hash)
    bak rmf extract PATH [NAMES]...   pull one or more resources out
    bak rmf extract PATH --all        pull everything
    bak rmf dump PATH NAME            decode a .TBL model table (chunks + per-model geometry)
    bak rmf dialog PATH KEY...         decode dialog record text from the DIAL_Z0N.DDX files

A .TBL is IFF-style chunks
MAP: (names) / APP: (empty) / GID: (2D collision zones) / DAT: (records + 3D mesh);
only DAT: and GID: are read at runtime. Each DAT: record is pointer-linked: a fixed
prefix (kind/flags/shift, then a count + near-pointer to the LOD-descriptor array,
then a bounding radius), and the mesh is *followed* from that pointer — never at a
fixed offset. GID: holds one collision zone per model, 1:1 with DAT: by index.
"""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated

import typer

app = typer.Typer(
    no_args_is_help=True,
    help="Inspect / extract the KRONDOR.RMF resource container (debugging aid).",
)

_NAME_LEN = 13  # fixed-width DOS 8.3 name + NUL, used in both the index and the archive
_HDR = struct.Struct("<IH")  # version (always 1), tag (always 4)


@dataclass(frozen=True)
class Entry:
    name: str
    hashkey: int
    offset: int  # of the entry header in the archive
    size: int  # payload only — excludes the 17-byte entry header

    @property
    def data_offset(self) -> int:
        return self.offset + _NAME_LEN + 4


def _find_archive(rmf_path: Path, archive_name: str) -> Path:
    """The RMF names its archive in lowercase (``krondor.001``) while DOS disks
    usually carry it uppercase — resolve the sibling case-insensitively."""
    for cand in rmf_path.parent.iterdir():
        if cand.name.lower() == archive_name.lower():
            return cand
    raise typer.BadParameter(
        f"archive {archive_name!r} (named in the RMF header) not found next to {rmf_path}"
    )


def _load(rmf_path: Path) -> tuple[Path, bytes, list[Entry]]:
    """Parse the index, resolve the archive, and materialize every entry
    (names/sizes come from the archive's per-entry headers)."""
    rmf = rmf_path.read_bytes()
    if len(rmf) < _HDR.size + _NAME_LEN + 2:
        raise typer.BadParameter(f"{rmf_path}: too short to be an RMF index")
    version, tag = _HDR.unpack_from(rmf, 0)
    if version != 1 or tag != 4:
        raise typer.BadParameter(
            f"{rmf_path}: bad magic (version={version}, tag={tag}; expected 1, 4)"
        )
    archive_name = rmf[_HDR.size : _HDR.size + _NAME_LEN].split(b"\0", 1)[0].decode("ascii")
    (count,) = struct.unpack_from("<H", rmf, _HDR.size + _NAME_LEN)
    table = _HDR.size + _NAME_LEN + 2
    if len(rmf) != table + count * 8:
        raise typer.BadParameter(
            f"{rmf_path}: size {len(rmf)} does not match {count} entries "
            f"(expected {table + count * 8})"
        )

    archive_path = _find_archive(rmf_path, archive_name)
    archive = archive_path.read_bytes()

    entries: list[Entry] = []
    for i in range(count):
        hashkey, offset = struct.unpack_from("<II", rmf, table + i * 8)
        if offset + _NAME_LEN + 4 > len(archive):
            raise typer.BadParameter(
                f"entry {i}: offset {offset:#x} past the end of {archive_path.name}"
            )
        name = archive[offset : offset + _NAME_LEN].split(b"\0", 1)[0].decode("ascii")
        (size,) = struct.unpack_from("<I", archive, offset + _NAME_LEN)
        if offset + _NAME_LEN + 4 + size > len(archive):
            raise typer.BadParameter(
                f"{name}: payload ({size} bytes at {offset:#x}) past the end of {archive_path.name}"
            )
        entries.append(Entry(name, hashkey, offset, size))
    return archive_path, archive, entries


_PathArg = Annotated[Path, typer.Argument(exists=True, dir_okay=False, help="path to KRONDOR.RMF")]


@app.command(name="list")
def list_(rmf_path: _PathArg) -> None:
    """Print every resource in the container: name, size, archive offset, hashkey."""
    archive_path, _, entries = _load(rmf_path)
    typer.secho(f"{archive_path}  ({len(entries)} resources)", fg="cyan")
    typer.secho(f"{'NAME':<14}{'SIZE':>10}  {'OFFSET':>10}  HASHKEY", fg="bright_black")
    for e in entries:
        typer.echo(f"{e.name:<14}{e.size:>10}  {e.offset:>10}  {e.hashkey:#010x}")


@app.command()
def extract(
    rmf_path: _PathArg,
    names: Annotated[
        list[str] | None,
        typer.Argument(help="resource name(s) to extract (case-insensitive)"),
    ] = None,
    all_: Annotated[bool, typer.Option("--all", help="extract every resource")] = False,
    out: Annotated[
        Path | None,
        typer.Option(
            "--out",
            help="output file (single name) or directory (multiple names / --all); "
            "default: resource name(s) in the current directory",
        ),
    ] = None,
) -> None:
    """Extract resource payload(s) from the container."""
    if bool(names) == all_:
        raise typer.BadParameter("give one or more NAMES, or --all (not both, not neither)")

    _, archive, entries = _load(rmf_path)
    if names:
        by_name = {e.name.lower(): e for e in entries}
        missing = [n for n in names if n.lower() not in by_name]
        if missing:
            raise typer.BadParameter(f"not in the container: {', '.join(missing)}")
        picked = [by_name[n.lower()] for n in names]
    else:
        picked = entries

    # --out is a file path only in the unambiguous single-resource case;
    # otherwise it names a directory (created on demand).
    single_out = out if len(picked) == 1 and out is not None and not out.is_dir() else None
    out_dir = out or Path.cwd()
    if single_out is None:
        out_dir.mkdir(parents=True, exist_ok=True)

    for e in picked:
        dest = single_out or out_dir / e.name
        dest.write_bytes(archive[e.data_offset : e.data_offset + e.size])
        typer.echo(f"{e.name} → {dest}  ({e.size} bytes)")


def _chunks(tbl: bytes) -> list[tuple[str, int, bytes]]:
    """Walk the .TBL's ``4-byte tag | u32 size | data`` chunk stream in order."""
    out: list[tuple[str, int, bytes]] = []
    pos = 0
    while pos + 8 <= len(tbl):
        tag = tbl[pos : pos + 4].decode("ascii", "replace")
        (size,) = struct.unpack_from("<I", tbl, pos + 4)
        data = tbl[pos + 8 : pos + 8 + size]
        out.append((tag, size, data))
        pos += 8 + size
    return out


def _map_names(data: bytes) -> list[str]:
    """Ordered NUL-terminated model names from the MAP: chunk (ignore the pointer table)."""
    return [m.group(1).decode("ascii") for m in re.finditer(rb"([ -~]{2,})\x00", data)]


def _ptr_table(data: bytes) -> list[int]:
    """The 0-terminated u32 seg:off pointer table shared by DAT: and GID:."""
    ptrs: list[int] = []
    pos = 0
    while pos + 4 <= len(data):
        (v,) = struct.unpack_from("<I", data, pos)
        pos += 4
        if v == 0:
            break
        ptrs.append(v)
    return ptrs


def _seg_byte(v: int) -> tuple[int, int]:
    """(segment base, record byte offset) for a seg:off pointer.
    Inner near offsets are relative to the segment base."""
    seg = ((v >> 16) & 0xFFFF) * 16
    return seg, seg + (v & 0xFFFF)


@dataclass(frozen=True)
class Record:
    bkind: int
    flag2: int
    shift: int
    lods: int  # LOD-descriptor count (0 = placeholder, no mesh)
    radius: int
    parts: int | None  # parts / vertices of the first (highest-detail) LOD
    verts: int | None


def _dat_records(data: bytes) -> list[Record]:
    """Decode each DAT: record, following the near-pointer to the mesh to count
    the first LOD's parts and vertices. Fields left None if out of bounds."""
    n = len(data)
    out: list[Record] = []
    for v in _ptr_table(data):
        seg, b = _seg_byte(v)
        if b + 14 > n:
            out.append(Record(-1, -1, -1, 0, 0, None, None))
            continue
        lods = struct.unpack_from("<h", data, b + 0x8)[0]
        parts = verts = None
        if lods > 0:
            try:
                lod = seg + struct.unpack_from("<H", data, b + 0xA)[0]  # LOD-desc array
                parts = struct.unpack_from("<h", data, lod + 0x2)[0]
                pbase = seg + struct.unpack_from("<H", data, lod + 0x4)[0]
                verts = sum(data[pbase + k * 14 + 3] for k in range(parts))
            except (IndexError, struct.error):
                parts = verts = None
        out.append(
            Record(
                bkind=data[b + 1],
                flag2=data[b + 2],
                shift=data[b + 3],
                lods=lods,
                radius=struct.unpack_from("<h", data, b + 0xC)[0],
                parts=parts,
                verts=verts,
            )
        )
    return out


def _gid_polycounts(data: bytes) -> list[int | None]:
    """Per-model collision-polygon count (ProximityZone byte +5)."""
    n = len(data)
    out: list[int | None] = []
    for v in _ptr_table(data):
        _, b = _seg_byte(v)
        out.append(data[b + 5] if b + 6 <= n else None)
    return out


@app.command()
def dump(
    rmf_path: _PathArg,
    name: Annotated[str, typer.Argument(help="resource name to dump (case-insensitive)")],
) -> None:
    """Decode a .TBL model table: metadata, chunks, and per-model geometry."""
    _, archive, entries = _load(rmf_path)
    by_name = {e.name.lower(): e for e in entries}
    entry = by_name.get(name.lower())
    if entry is None:
        raise typer.BadParameter(f"not in the container: {name}")

    payload = archive[entry.data_offset : entry.data_offset + entry.size]
    typer.secho(f"{entry.name}  offset={entry.offset}  size={entry.size}", fg="cyan")

    chunks = _chunks(payload)
    if not chunks or not chunks[0][0].endswith(":"):
        typer.secho("not a recognizable chunked TBL", fg="yellow")
        return

    # Only DAT: and GID: are read at runtime; MAP:/APP: are authoring-only.
    runtime = {"DAT:", "GID:"}
    typer.secho("chunks:", fg="bright_black")
    for tag, size, _ in chunks:
        note = "" if tag in runtime else "  (authoring-only, unread at runtime)"
        typer.echo(f"  {tag} size={size}{note}")

    by_tag = {tag: data for tag, _, data in chunks}
    if "DAT:" not in by_tag:
        return

    names = _map_names(by_tag["MAP:"]) if "MAP:" in by_tag else []
    recs = _dat_records(by_tag["DAT:"])
    gid = _gid_polycounts(by_tag["GID:"]) if "GID:" in by_tag else []

    # LODS/RAD/PARTS/VERTS are the DAT: mesh; GIDPOLY is the GID: collision zone.
    typer.secho(
        f"\n{'IDX':>4} {'BKIND':>5} {'F2':>3} {'SH':>3} {'LODS':>4} "
        f"{'RAD':>6} {'PARTS':>5} {'VERTS':>5} {'GIDPOLY':>7}  NAME",
        fg="bright_black",
    )
    for i, r in enumerate(recs):
        nm = names[i] if i < len(names) else "null"
        parts = "" if r.parts is None else str(r.parts)
        verts = "" if r.verts is None else str(r.verts)
        gp = "" if i >= len(gid) or gid[i] is None else str(gid[i])
        typer.echo(
            f"{i:>4} {r.bkind:>5} {r.flag2:>3} {r.shift:>3} {r.lods:>4} "
            f"{r.radius:>6} {parts:>5} {verts:>5} {gp:>7}  {nm}"
        )

    kinds = sorted({r.bkind for r in recs})
    meshed = sum(1 for r in recs if r.lods > 0)
    typer.secho(
        f"\n{len(recs)} records ({meshed} with mesh, {len(recs) - meshed} placeholder); "
        f"distinct bKind: {kinds}",
        fg="cyan",
    )


# A DDX record header is 9 bytes, packed, matching struct DDXRecord:
# bStyle u8 | wSpeaker_id u16 | wFlags u16 | bCnt1 u8 | bCnt2 u8 | wBody_len u16.
# The count bytes give (bCnt1 + bCnt2) * 10 bytes of sub-records before the body.
_DDX_HDR = struct.Struct("<BHHBBH")


def _ddx_filename(key: int) -> str:
    """The chapter file a record lives in, chosen from the key exactly as
    dialog_load_record_by_key does: chapter = key / 100000, two decimal digits."""
    chapter = key // 100000
    return f"DIAL_Z{chapter // 10}{chapter % 10}.DDX"


def _ddx_render(body: bytes) -> str:
    """Render a record body: printable ASCII literal, ``\\n`` for the 0x0a break,
    every other control byte shown as ``[xx]``. Drops one trailing NUL terminator."""
    if body.endswith(b"\x00"):
        body = body[:-1]
    out: list[str] = []
    for b in body:
        if b == 0x0A:
            out.append("\n")
        elif 0x20 <= b < 0x7F:
            out.append(chr(b))
        else:
            out.append(f"[{b:02x}]")
    return "".join(out)


@dataclass(frozen=True)
class DialogRecord:
    style: int
    speaker: int
    flags: int
    body_len: int
    text: str


def _ddx_lookup(payload: bytes, key: int) -> DialogRecord | None:
    """Find a record in a DDX payload by key: a ``u16`` count, then that many
    ``(u32 node_id, u32 file_off)`` directory entries, then the record at the
    matching offset. Returns None when the key is absent."""
    (count,) = struct.unpack_from("<H", payload, 0)
    pos = 2
    file_off = 0
    for _ in range(count):
        node_id, off = struct.unpack_from("<II", payload, pos)
        pos += 8
        if node_id == key:
            file_off = off
            break
    if file_off == 0:
        return None
    style, speaker, flags, cnt1, cnt2, body_len = _DDX_HDR.unpack_from(payload, file_off)
    start = file_off + _DDX_HDR.size + (cnt1 + cnt2) * 10
    body = payload[start : start + body_len]
    return DialogRecord(style, speaker, flags, body_len, _ddx_render(body))


@app.command()
def dialog(
    rmf_path: _PathArg,
    keys: Annotated[
        list[str],
        typer.Argument(help="dialog record key(s), decimal or 0x-hex (e.g. 332 or 0x14c)"),
    ],
) -> None:
    """Decode dialog record text from the DIAL_Z0N.DDX files.

    The chapter file is chosen from each key (key // 100000), matching the game's
    dialog_load_record_by_key. Non-printable control bytes are shown as [xx]."""
    _, archive, entries = _load(rmf_path)
    by_name = {e.name.lower(): e for e in entries}
    for raw in keys:
        try:
            key = int(raw, 0)
        except ValueError:
            raise typer.BadParameter(f"not a number: {raw}") from None
        fname = _ddx_filename(key)
        entry = by_name.get(fname.lower())
        if entry is None:
            typer.secho(f"{key:#x} ({key}): {fname} not in container", fg="yellow")
            continue
        payload = archive[entry.data_offset : entry.data_offset + entry.size]
        rec = _ddx_lookup(payload, key)
        if rec is None:
            typer.secho(f"{key:#x} ({key}): not found in {fname}", fg="yellow")
            continue
        typer.secho(
            f"{key:#x} ({key})  {fname}  style={rec.style} "
            f"speaker={rec.speaker} flags={rec.flags:#06x} bodyLen={rec.body_len}",
            fg="cyan",
        )
        typer.echo(rec.text)
        typer.echo("")


def register(root: typer.Typer) -> None:
    root.add_typer(app, name="rmf")
