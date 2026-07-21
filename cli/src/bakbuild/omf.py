"""OMF parser for Borland C++ 3.x / TASM ``.obj`` files.

Implements the subset of Intel OMF ``bak diff`` needs: THEADR, LNAMES, SEGDEF,
EXTDEF, PUBDEF, LEDATA, FIXUPP (16-bit forms — what the 1993 toolchain emits).
:func:`extract_code_segments` / :func:`extract_data_segments` return each
segment's laid-out bytes plus the FIXUPP records covering it (which byte
positions are relocations, and the symbol each points at).

LIDATA (iterated data, occasionally emitted by TASM for data modules) is not
expanded — affected offsets read as zero-fill and :attr:`OmfObject.has_lidata`
is set so callers can warn.

Reference: Intel Tool Interface Standard (TIS) OMF spec. Trimmed port of the
bak-scratch-area ``bak/recomp/omf.py``.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path


class Rec(IntEnum):
    """OMF record-type bytes. Low bit = 32-bit variant; Borland 3.x emits 16-bit."""

    THEADR = 0x80
    COMENT = 0x88
    MODEND_16 = 0x8A
    MODEND_32 = 0x8B
    EXTDEF = 0x8C
    PUBDEF_16 = 0x90
    PUBDEF_32 = 0x91
    LINNUM_16 = 0x94
    LINNUM_32 = 0x95
    LNAMES = 0x96
    SEGDEF_16 = 0x98
    SEGDEF_32 = 0x99
    GRPDEF = 0x9A
    FIXUPP_16 = 0x9C
    FIXUPP_32 = 0x9D
    LEDATA_16 = 0xA0
    LEDATA_32 = 0xA1
    LIDATA_16 = 0xA2
    LIDATA_32 = 0xA3


class Loc(IntEnum):
    """FIXUPP location field — the kind (and width) of fix."""

    LO_BYTE = 0  # 8-bit low byte of an offset
    OFFSET_16 = 1  # 16-bit offset (the [_global] data ref)
    BASE_16 = 2  # 16-bit segment base
    POINTER_16 = 3  # 16:16 far pointer (the `9A seg:off` far-call form)
    HI_BYTE = 4  # 8-bit high byte
    LOADER_OFFSET_16 = 5
    OFFSET_32 = 9
    POINTER_32 = 11
    LOADER_OFFSET_32 = 13


#: byte width each fixup location patches (used to mask relocated bytes)
LOC_WIDTH = {
    Loc.LO_BYTE: 1,
    Loc.HI_BYTE: 1,
    Loc.OFFSET_16: 2,
    Loc.BASE_16: 2,
    Loc.LOADER_OFFSET_16: 2,
    Loc.POINTER_16: 4,
    Loc.OFFSET_32: 4,
    Loc.LOADER_OFFSET_32: 4,
    Loc.POINTER_32: 6,
}


class TargetMethod(IntEnum):
    """FIXUPP target method (low 2 bits of fix_data when T=0)."""

    SEGMENT = 0  # target is a SEGDEF index
    GROUP = 1  # target is a GRPDEF index
    EXTERN = 2  # target is an EXTDEF index
    FRAME = 3  # target is an absolute frame number


@dataclass
class Segment:
    name_idx: int
    class_idx: int
    length: int
    name: str = ""
    class_name: str = ""
    align: int = 0  # OMF ACBP alignment field: 0=absolute 1=byte 2=word 3=para


@dataclass
class Public:
    name: str
    segment_idx: int  # 1-based; matches OMF
    offset: int


@dataclass
class Ledata:
    segment_idx: int
    offset: int  # offset within the segment
    data: bytes


@dataclass
class Fixup:
    location: Loc
    mode_segrel: bool
    segment_idx: int
    offset_in_segment: int  # absolute offset within the patched segment
    target_method: TargetMethod
    target_idx: int
    target_name: str = ""  # resolved post-parse
    displacement: int = 0
    frame_method: int = 0
    frame_idx: int = 0


@dataclass
class OmfObject:
    path: Path
    module_name: str = ""
    lnames: list[str] = field(default_factory=list)
    segments: list[Segment] = field(default_factory=list)
    externs: list[str] = field(default_factory=list)
    publics: list[Public] = field(default_factory=list)
    ledatas: list[Ledata] = field(default_factory=list)
    fixups: list[Fixup] = field(default_factory=list)
    has_lidata: bool = False


# --------------------------------------------------------------------------- #
# Primitive readers
# --------------------------------------------------------------------------- #


def _read_index(buf: bytes, pos: int) -> tuple[int, int]:
    """OMF variable-length index: 1 byte (0..127) if the high bit is clear, else
    2 bytes (128..32767). Returns ``(index, new_pos)``."""
    b = buf[pos]
    if b & 0x80:
        return ((b & 0x7F) << 8) | buf[pos + 1], pos + 2
    return b, pos + 1


def _read_pstring(buf: bytes, pos: int) -> tuple[str, int]:
    """Length-prefixed (Pascal) string. Returns ``(string, new_pos)``."""
    length = buf[pos]
    return buf[pos + 1 : pos + 1 + length].decode("latin-1"), pos + 1 + length


# --------------------------------------------------------------------------- #
# Record parsers
# --------------------------------------------------------------------------- #


def _parse_segdef(payload: bytes, obj: OmfObject) -> None:
    acbp = payload[0]
    align = (acbp >> 5) & 0x7
    p = 1
    if align == 0:  # alignment A==0 -> absolute segment: frame(2)+offset(1)
        p += 3
    length = struct.unpack_from("<H", payload, p)[0]
    p += 2
    name_idx, p = _read_index(payload, p)
    class_idx, p = _read_index(payload, p)
    obj.segments.append(Segment(name_idx=name_idx, class_idx=class_idx, length=length, align=align))


def _parse_extdef(payload: bytes, obj: OmfObject) -> None:
    p = 0
    while p < len(payload):
        name, p = _read_pstring(payload, p)
        _, p = _read_index(payload, p)  # type_idx, ignored
        obj.externs.append(name)


def _parse_pubdef(payload: bytes, obj: OmfObject) -> None:
    _, p = _read_index(payload, 0)  # group_idx, ignored
    segment_idx, p = _read_index(payload, p)
    if segment_idx == 0:
        p += 2  # absolute pubs carry a frame_number
    while p < len(payload):
        name, p = _read_pstring(payload, p)
        offset = struct.unpack_from("<H", payload, p)[0]
        p += 2
        _, p = _read_index(payload, p)  # type_idx, ignored
        obj.publics.append(Public(name=name, segment_idx=segment_idx, offset=offset))


def _parse_ledata(payload: bytes, obj: OmfObject) -> Ledata:
    segment_idx, p = _read_index(payload, 0)
    offset = struct.unpack_from("<H", payload, p)[0]
    p += 2
    led = Ledata(segment_idx=segment_idx, offset=offset, data=bytes(payload[p:]))
    obj.ledatas.append(led)
    return led


def _parse_fixupp(payload: bytes, obj: OmfObject, last_ledata: Ledata | None) -> None:
    """Walk FIXUP / THREAD subrecords within a FIXUPP payload."""
    p = 0
    while p < len(payload):
        b = payload[p]
        if (b & 0x80) == 0:
            # THREAD subrecord (Borland 3.x rarely emits these) — skip past it.
            p += 1
            _, p = _read_index(payload, p)
            continue

        # FIXUP subrecord. Locat (2 bytes): bit15=marker, bit14=M (mode),
        # bits13-10 = location type, bits9-0 = data_record_offset into the LEDATA.
        b1, b2 = payload[p], payload[p + 1]
        locat = (b1 << 8) | b2
        mode_segrel = bool((locat >> 14) & 1)
        location_type = (locat >> 10) & 0xF
        data_record_offset = locat & 0x3FF
        p += 2

        # Fix_data byte: F[7] frame[6-4] T[3] P[2] target[1-0].
        fix_data = payload[p]
        p += 1
        F = bool(fix_data & 0x80)
        frame_method = (fix_data >> 4) & 0x7
        T = bool(fix_data & 0x08)
        P = bool(fix_data & 0x04)
        target_method_bits = fix_data & 0x03

        frame_idx = 0
        if not F and frame_method < 4:
            frame_idx, p = _read_index(payload, p)

        target_idx = 0
        if not T:
            target_idx, p = _read_index(payload, p)

        displacement = 0
        if not P:
            displacement = struct.unpack_from("<H", payload, p)[0]
            p += 2

        if last_ledata is None:
            continue  # FIXUPP with no preceding LEDATA — malformed; skip

        try:
            tm = TargetMethod(target_method_bits)
        except ValueError:
            tm = TargetMethod.SEGMENT
        try:
            loc = Loc(location_type)
        except ValueError:
            loc = Loc.OFFSET_16

        obj.fixups.append(
            Fixup(
                location=loc,
                mode_segrel=mode_segrel,
                segment_idx=last_ledata.segment_idx,
                offset_in_segment=last_ledata.offset + data_record_offset,
                target_method=tm,
                target_idx=target_idx,
                displacement=displacement,
                frame_method=frame_method,
                frame_idx=frame_idx,
            )
        )


# --------------------------------------------------------------------------- #
# Driver
# --------------------------------------------------------------------------- #


def parse(path: str | Path) -> OmfObject:
    """Parse an OMF ``.obj`` file into an :class:`OmfObject`."""
    path = Path(path)
    data = path.read_bytes()
    obj = OmfObject(path=path)

    pos = 0
    last_ledata: Ledata | None = None
    while pos < len(data):
        rec_type = data[pos]
        rec_len = struct.unpack_from("<H", data, pos + 1)[0]
        payload = data[pos + 3 : pos + 3 + rec_len - 1]  # excl. trailing checksum
        try:
            rt = Rec(rec_type)
        except ValueError:
            pos += 3 + rec_len
            continue

        if rt == Rec.THEADR:
            obj.module_name, _ = _read_pstring(payload, 0)
        elif rt == Rec.LNAMES:
            q = 0
            while q < len(payload):
                name, q = _read_pstring(payload, q)
                obj.lnames.append(name)
        elif rt == Rec.SEGDEF_16:
            _parse_segdef(payload, obj)
        elif rt == Rec.EXTDEF:
            _parse_extdef(payload, obj)
        elif rt == Rec.PUBDEF_16:
            _parse_pubdef(payload, obj)
        elif rt == Rec.LEDATA_16:
            last_ledata = _parse_ledata(payload, obj)
        elif rt == Rec.FIXUPP_16:
            _parse_fixupp(payload, obj, last_ledata)
        elif rt in (Rec.LIDATA_16, Rec.LIDATA_32):
            obj.has_lidata = True
        # COMENT, GRPDEF, LINNUM, MODEND — silently skipped.
        pos += 3 + rec_len

    for seg in obj.segments:  # resolve segment names from LNAMES
        if 0 < seg.name_idx <= len(obj.lnames):
            seg.name = obj.lnames[seg.name_idx - 1]
        if 0 < seg.class_idx <= len(obj.lnames):
            seg.class_name = obj.lnames[seg.class_idx - 1]

    for fix in obj.fixups:  # resolve fixup target names
        if fix.target_method == TargetMethod.SEGMENT:
            if 0 < fix.target_idx <= len(obj.segments):
                fix.target_name = obj.segments[fix.target_idx - 1].name
        elif fix.target_method == TargetMethod.EXTERN:
            if 0 < fix.target_idx <= len(obj.externs):
                fix.target_name = obj.externs[fix.target_idx - 1]
        elif fix.target_method == TargetMethod.GROUP:
            fix.target_name = f"<group {fix.target_idx}>"
        elif fix.target_method == TargetMethod.FRAME:
            fix.target_name = f"<frame {fix.target_idx}>"

    return obj


# --------------------------------------------------------------------------- #
# Segment extraction
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class ModuleSegment:
    """One SEGDEF of a module, laid out at segment offsets 0..length-1. ``data`` is
    the full SEGDEF-length buffer with every LEDATA filled in; ``emitted`` is the set
    of offsets a LEDATA actually covers (offsets not in it are reserved zero-fill)."""

    index: int  # 1-based OMF segment index (matches Fixup/Public.segment_idx)
    name: str
    class_name: str
    length: int
    data: bytes
    fixups: list[Fixup]
    emitted: frozenset[int]
    align: int = 0

    @property
    def is_zero_emission(self) -> bool:
        return not self.emitted


def _lay_out_segment(obj: OmfObject, seg_idx: int, seg: Segment) -> tuple[bytes, set[int]]:
    buf = bytearray(seg.length)
    covered: set[int] = set()
    for led in obj.ledatas:
        if led.segment_idx == seg_idx:
            buf[led.offset : led.offset + len(led.data)] = led.data
            covered.update(range(led.offset, led.offset + len(led.data)))
    return bytes(buf), covered


def _extract_class(obj: OmfObject, class_name: str) -> list[ModuleSegment]:
    out: list[ModuleSegment] = []
    for seg_idx, seg in enumerate(obj.segments, start=1):
        if seg.class_name != class_name:
            continue
        data, covered = _lay_out_segment(obj, seg_idx, seg)
        out.append(
            ModuleSegment(
                index=seg_idx,
                name=seg.name,
                class_name=seg.class_name,
                length=seg.length,
                data=data,
                fixups=[f for f in obj.fixups if f.segment_idx == seg_idx],
                emitted=frozenset(covered),
                align=seg.align,
            )
        )
    return out


def extract_code_segments(obj: OmfObject) -> list[ModuleSegment]:
    """Every CODE-class SEGDEF of the module, in module (SEGDEF) order, each with its
    laid-out bytes, fixups, and emitted-offset set."""
    return _extract_class(obj, "CODE")


def extract_data_segments(obj: OmfObject) -> list[ModuleSegment]:
    """Every DATA-class SEGDEF of the module — the DATA analogue of
    :func:`extract_code_segments` (BSS has no emitted bytes and is summarized by
    the caller from ``obj.segments`` instead)."""
    return _extract_class(obj, "DATA")
