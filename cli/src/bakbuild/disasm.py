"""``bak diff``'s disassembly + comparison layer.

Renders an OMF ``.obj`` into a list of :class:`Row`s (one per instruction /
data line / label / segment summary) and aligns two such lists. Every row
carries three strings:

  ``loose``    alignment key — relocated bytes AND local-branch displacement
               bytes masked, branch targets normalized to ``L``. A branch whose
               target merely *shifted* (because an edit moved code between the
               branch and its target) still matches under this key.
  ``strict``   comparison key — same normalization but true displacement bytes.
               A row that loose-matches while strict-differing is a layout
               shift, rendered demoted (``~``), not a real change.
  ``display``  the human line: offset column, hex bytes, per-side label
               ordinals, fixup symbols overlaid (``; -> _symbol``).

Relocated bytes are masked (``··``) in BOTH keys: their in-file values are
placeholders the linker patches, but the *symbol* each fixup targets is part of
both keys, so retargeting a call/data ref is always a real diff. The loose
masking is the moral equivalent of the reference project's ``--loose`` mode,
minus the linked-EXE slack arithmetic OBJ-vs-OBJ comparison doesn't need.
"""

from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path

from . import omf

# non-'j' mnemonics that take a local (same-segment, relative) target
_BRANCH = {"call", "jmp", "loop", "loope", "loopne", "jcxz"}


@dataclass(frozen=True)
class Row:
    loose: str
    strict: str
    display: str
    func: str  # owning public symbol, for hunk headers ("" outside any)


@dataclass(frozen=True)
class DiffLine:
    tag: str  # " " match | "~" layout shift | "-" ref-only | "+" cand-only
    text: str
    func: str


def _is_local_branch(mn: str, op: str) -> bool:
    return (mn in _BRANCH or mn.startswith("j")) and op.startswith("0x")


def _disp_width(raw: bytes) -> int:
    """Displacement byte count of a local relative branch encoding."""
    return 2 if raw[0] in (0xE8, 0xE9, 0x0F) else 1


def _decode(seg: omf.ModuleSegment):
    """Linear-sweep decode -> [(off, raw, mnemonic, op_str)]. Undecodable bytes
    become ``db`` pseudo-instructions so the sweep always terminates."""
    from capstone import CS_ARCH_X86, CS_MODE_16, Cs  # type: ignore[import-untyped]

    md = Cs(CS_ARCH_X86, CS_MODE_16)
    out, pos, data = [], 0, seg.data
    while pos < len(data):
        got = None
        for insn in md.disasm(data[pos:], pos):
            got = (insn.address, bytes(insn.bytes), insn.mnemonic, insn.op_str)
            break
        if got is None:
            got = (pos, data[pos : pos + 1], "db", f"0x{data[pos]:02x}")
        out.append(got)
        pos += len(got[1])
    return out


def _fixup_map(seg: omf.ModuleSegment) -> dict[int, omf.Fixup]:
    m: dict[int, omf.Fixup] = {}
    for f in seg.fixups:
        for k in range(omf.LOC_WIDTH.get(f.location, 2)):
            m[f.offset_in_segment + k] = f
    return m


def _code_rows(seg: omf.ModuleSegment, publics: dict[int, str], rows: list[Row]) -> None:
    insns = _decode(seg)
    fixups = _fixup_map(seg)
    targets = sorted({int(op, 16) for _, _, mn, op in insns if _is_local_branch(mn, op)})
    label_no = {t: i + 1 for i, t in enumerate(targets)}
    func = ""
    for off, raw, mn, op in insns:
        if off in publics:
            func = publics[off]
            rows.append(Row(f"{func}:", f"{func}:", f"{func}:", func))
        if off in label_no:
            rows.append(Row("L:", "L:", f"        L{label_no[off]}:", func))
        local = _is_local_branch(mn, op)
        disp = _disp_width(raw) if local else 0
        hex_strict, hex_loose, sym = [], [], None
        for k, b in enumerate(raw):
            f = fixups.get(off + k)
            if f is not None:
                hex_strict.append("··")
                hex_loose.append("··")
                sym = sym or f.target_name or f"seg#{f.target_idx}"
            elif disp and k >= len(raw) - disp:
                hex_strict.append(f"{b:02x}")
                hex_loose.append("~~")
            else:
                hex_strict.append(f"{b:02x}")
                hex_loose.append(f"{b:02x}")
        key_text = f"{mn} {'L' if local else op}".strip()
        disp_text = f"{mn} {f'L{label_no[int(op, 16)]}' if local else op}".strip()
        if sym:
            key_text += f"  ; -> {sym}"
            disp_text += f"  ; -> {sym}"
        rows.append(
            Row(
                f"{''.join(hex_loose)} {key_text}",
                f"{''.join(hex_strict)} {key_text}",
                f"  {off:04x}: {''.join(hex_strict):<16} {disp_text}",
                func,
            )
        )


def _data_rows(seg: omf.ModuleSegment, publics: dict[int, str], rows: list[Row]) -> None:
    fixups = _fixup_map(seg)
    func = ""
    data = seg.data
    for base in range(0, len(data), 8):
        for off in range(base, min(base + 8, len(data))):
            if off in publics:
                func = publics[off]
                rows.append(Row(f"{func}:", f"{func}:", f"{func}:", func))
        chunk, syms = [], []
        for off in range(base, min(base + 8, len(data))):
            f = fixups.get(off)
            if f is not None:
                chunk.append("··")
                if f.target_name and f.target_name not in syms:
                    syms.append(f.target_name)
            else:
                chunk.append(f"{data[off]:02x}")
        text = "db " + " ".join(chunk) + (f"  ; -> {', '.join(syms)}" if syms else "")
        rows.append(Row(text, text, f"  {base:04x}: {text[3:]}", func))


def render_rows(path: Path) -> tuple[list[Row], omf.OmfObject]:
    """The comparable row list for one ``.obj`` (segment summaries, then every
    CODE segment's instructions, then every DATA segment's bytes)."""
    obj = omf.parse(path)
    rows: list[Row] = []
    for seg in obj.segments:
        text = f"segment {seg.name} '{seg.class_name}' length={seg.length}"
        rows.append(Row(text, text, text, ""))
    for extract, emit in ((omf.extract_code_segments, _code_rows),
                          (omf.extract_data_segments, _data_rows)):
        for mseg in extract(obj):
            if mseg.is_zero_emission:
                continue
            publics = {p.offset: p.name for p in obj.publics if p.segment_idx == mseg.index}
            head = f"-- {mseg.name} --"
            rows.append(Row(head, head, head, ""))
            emit(mseg, publics, rows)
    return rows, obj


def diff_rows(
    ref: list[Row], cand: list[Row], *, loose: bool = True
) -> tuple[list[DiffLine], int, int]:
    """Align two row lists. Returns ``(lines, changed, shifted)`` where *changed*
    counts real ``-``/``+`` lines and *shifted* the loose-only ``~`` demotions.
    In strict mode shifts are not demoted — they count as real changes."""
    key = (lambda r: r.loose) if loose else (lambda r: r.strict)
    sm = SequenceMatcher(None, [key(r) for r in ref], [key(r) for r in cand], autojunk=False)
    lines: list[DiffLine] = []
    changed = shifted = 0
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == "equal":
            for i, j in zip(range(i1, i2), range(j1, j2), strict=True):
                if loose and ref[i].strict != cand[j].strict:
                    lines.append(DiffLine("~", cand[j].display, cand[j].func))
                    shifted += 1
                else:
                    lines.append(DiffLine(" ", cand[j].display, cand[j].func))
            continue
        for i in range(i1, i2):
            lines.append(DiffLine("-", ref[i].display, ref[i].func))
            changed += 1
        for j in range(j1, j2):
            lines.append(DiffLine("+", cand[j].display, cand[j].func))
            changed += 1
    return lines, changed, shifted
