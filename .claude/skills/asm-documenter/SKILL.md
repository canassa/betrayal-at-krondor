---
name: asm-documenter
description: >-
  The standard for writing and reviewing comments in the hand-disassembled
  TASM `.asm` files under `bak/SRC/`: what to document (banners, function
  plates, inline comments, naming) and which edits stay byte-identical. Use
  when documenting, commenting, or reviewing any `.asm` file. Triggers:
  "document this .asm", "review asm documentation", "/asm-documenter".
---

# ASM documentation & byte-neutrality standard

The single standard for documenting the hand-disassembled TASM source under
`bak/SRC/`. It covers two things:

1. **What to write** — file anatomy, banners, function plates, inline
   comments, naming, data documentation, historical quirks, anti-patterns.
2. **What edits are byte-safe** — the TASM 3.1 mechanics that decide whether a
   change moves emitted bytes (§11–§18 below).

Naming conventions defer to [`CLAUDE.md`](../../../CLAUDE.md). On any conflict
about emitted bytes, the byte-neutrality mechanics (§11+) win — they are
verified from our actual `TASM.EXE`.

**The goal is hard:**

> A reader fluent in assembly but who has **never used DOS** and **doesn't know
> what AdLib/OPL2/VGA is** should be able to read any one of our `.asm` files
> top-to-bottom and understand what it does and why.

Every `.asm` file teaches as it goes. No external prerequisite reading is
required — the file itself is the home for the background it needs, and a
specific external citation (RBIL, a chip datasheet, the OPL wiki) covers
anything too long to inline.

---

## 0. The two families of ASM

The repo's TASM source comes in two families that share this standard but
differ in **segment model, naming, banner style, and how they are verified**.
Identify which one you're editing before you start — the segment directives and
public labels tell you at a glance.

**C-linked modules** — assembled and linked into `KRONDOR.EXE` alongside the
decompiled C. They live throughout the tree (`bak/SRC/SYS/RAND.ASM`,
`bak/SRC/IO/DOSRW.ASM`, `bak/SRC/INPUT/TIMER.ASM`,
`bak/SRC/GFX/RASTER/DRAWLINE.ASM`, `bak/SRC/R3D/...`).

- MASM mode, medium/tiny model, real `_TEXT`/`_DATA`/`_BSS` segments with
  `DGROUP` and `assume ds:DGROUP`.
- **Public labels are the exact C-mangled name** the linker resolves against
  (case-sensitive under `/mx`).
- Verified with `uv run bak diff SRC/PATH/FILE.ASM`.

**Standalone drivers** — self-contained overlays packed into `SX.OVL` (audio)
and `Vmcode.OVL` (video), never linked with the C. Audio drivers are
`bak/SRC/DRIVERS/SX/<TAG>.ASM` (ADL, ASB, M32, GMD, PRO, STD, NLD, APA, ADS,
SBP, PS1); video drivers are `bak/SRC/DRIVERS/VMCODE/<TAG>.ASM` (CGA, EGA, VGA,
MCG, HEG, EVA, EVG, TAN).

- `.MODEL TINY`, flat single-segment, ORG-0 image, explicit `CS:` overrides
  (DS/ES unreliable at slot entry), internal `<dr>_`-prefixed labels, and a
  per-family dispatch ABI (DUDE for audio, the renderer-vtable for video).
- Verified with a full `uv run bak build` (which repacks the OVL and `cmp`s the
  shipped artifacts). `uv run bak diff` on the object is the fast gate.

Running examples below are mostly the audio-driver family (OPL2, DUDE) because
that source is the most heavily documented, but every structural rule applies
to both. Where a rule is family-specific it says so.

---

## 1. Audience and reading model

Assume the reader:

- **Is fluent in assembly.** `MOV BX, AX`, `XOR CX, CX`, `REP MOVSW`,
  `CMP / JZ`, `PUSH BP / MOV BP, SP / … / POP BP / RET`, indexed addressing —
  all second nature. Knows registers, the stack, condition codes, segment
  overrides at the CPU level.
- **Knows nothing about DOS.** Interrupt vectors, INT 10h/21h/33h subfunctions,
  the PSP, BIOS data area, real-mode segment arithmetic and 1 MB+HMA wraparound,
  DOS memory allocators (`AH=48h/49h/4Ah`), EMS/XMS, COM-vs-EXE-vs-OVL formats,
  TSR conventions — all alien.
- **Knows nothing about the target hardware.** CGA/EGA/VGA register layouts,
  sequencer/GC/AC/CRTC ports, planar vs chunky pixels, OPL2 FM synthesis, SB DSP
  commands, MT-32 SysEx, General-MIDI semantics, MPU-401, gameport monostable
  timing — all alien.
- **Knows nothing about this codebase's conventions.** The DUDE driver format,
  the Vmcode.OVL chunk layout, the renderer-vtable dispatch model, BAK resource
  archives, the DGROUP/segment model, palette cycling, dithering — all alien.
- Reads the file linearly, top to bottom, like a story.

The reader **should not have to** open a DOS tutorial to learn what
`INT 21h AH=48h` does, look up which I/O port controls the OPL2 / VGA DAC, or
reverse-engineer this codebase's naming and layout decisions.

The reader **should not need** these comments — they are pure noise:

- Mnemonic restatements (`MOV AX, BX ; copy BX to AX`).
- Addressing-mode explanations (`[BP+6] ; memory at BP+6`).
- Standard control-flow restatements (`JZ loop ; jump if zero`).
- Stack-frame boilerplate (`PUSH BP / MOV BP, SP ; set up frame`).

In practice:

- **Comment the WHAT / WHY / HOW** of every DOS-, hardware-, or
  codebase-specific operation. The first `INT 21h AH=48h` gets 3–4 lines on
  DOS's AllocateMemory API; the first OPL2 register write gets a hardware-primer
  pointer; the first far-pointer normalisation gets a one-line note on why
  Borland's huge-pointer fixup is needed.
- **Do not comment standard assembly.** Register saves, condition-code
  branches, `REP MOVSW`/`REP STOSW`, prologue/epilogue — these speak for
  themselves. Comment only when they do something genuinely unusual.
- **Teach inline, then taper.** First mention of a register layout, hardware
  quirk, or DOS API gets the full treatment (3–6 lines or a primer subsection).
  Second mention 200 lines later: one line. Third: nothing.
- **Link to depth.** `; see asm-documenter §N`, a cross-reference to another
  section of *this same file*, or an external citation (RBIL, OPL chip wiki,
  FreeVGA, Yamaha YM3812 datasheet) for material too long to inline. Cite
  specifically — `; see RBIL INT 10h AX=4F02h` beats a bare `; see online
  docs`. Never point at a companion `.md`: the `.asm` file must stand alone.

---

## 2. File anatomy

Every file opens with a **preamble** that takes the reader from zero to ready,
then presents data and code in the file's on-disk / link order.

**C-linked module** (e.g. RAND.ASM):

```
1. Banner header (module name, address/size, one-paragraph purpose)
2. Encoding-idioms / hardware / DOS notes as the module needs them
3. Segment + DGROUP declarations
4. Data (_DATA initialized, _BSS uninitialized) — file order is the spec
5. _TEXT: public decls, then function bodies in original order
6. END
```

**Standalone driver** (e.g. ADL.ASM):

```
1. Banner header
2. Module overview ("What this driver is")
3. Hardware primer (per-driver — OPL2, SB-DSP, MT-32 SysEx, VGA, …)
4. The dispatch ABI (DUDE for audio, renderer-vtable for video)
5. How to read this source (project/TASM-specific conventions)
6. Data section (header, tables, state, register shadow, working space)
7. Function-pointer dispatch table
8. Dispatch trampoline
9. Function bodies, ordered exactly as in the original binary
10. END _start
```

The data-then-code ordering matches every driver's on-disk layout — keep it.

### 2.1 Banner header

Keep it factual: module identity, load address/size where known, a
one-paragraph purpose, and any toolchain note that matters. **Do not narrate the
reconstruction** — no "historical reconstruction that assembles byte-for-byte…"
boilerplate, no `Provenance:`, Ghidra/decompiler, offset-size, or byte-verified
commentary. The source documents the *module*, not the RE process that recovered
it. The narrow exception is a note that helps a reader understand the code in
front of them — an assembler-parser quirk (the hex-literal-needs-a-leading-digit
rule) or a segment assumption (`DS = DGROUP` here). A note whose only purpose is
to preserve the shipped binary's layout (link order, DGROUP slot, "do not
reorder") is **not** that exception; keep it out (see §7.4, §10.4).

C-linked module (real RAND.ASM style):

```asm
; ============================================================================
; RAND.ASM -- lagged-Fibonacci PRNG @ 1000:02c8  (70 bytes)
;
; Two procs from ONE original TU, contiguous at 02c8/0301:
;   rand                @ 02c8 (57 bytes) -- draw the next pseudo-random word
;   _rand_reset_indices @ 0301 (13 bytes) -- reseed the two ring indices
;
; <one-paragraph description of the algorithm and its state>
; ============================================================================
```

Standalone driver (real ADL.ASM style):

```asm
; ============================================================================
; Sx.SSM.ADL.bin -- Dynamix DUDE-format AdLib (OPL2) sound driver, v2.24
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993).
;
; Packing: TASM + TLINK produce an MZ .EXE; PACKOVL strips the MZ header to
; the flat ORG-0 image, then LZW-packs it into SX.OVL.
; ============================================================================
```

### 2.2 Module overview (drivers)

In 20–40 lines, explain at a high level what the driver does. **Avoid hardware
jargon here**; that goes in the next section. A small C-linked module needs no
separate overview — the banner paragraph plus its encoding-idioms notes suffice.

### 2.3 Hardware / DOS primer

The section that makes the file self-contained. For a driver, write a focused
primer (~30–80 lines) for *exactly* the hardware this driver controls. For a
C-linked module that touches a DOS API or a device, inline the primer at the
first use instead. Cover:

- What the chip / API does (one sentence per concept).
- How the host CPU talks to it (which I/O ports or interrupt, what a "register"
  is, timing requirements).
- The structural model the code reflects (OPL2: "9 voices, each two operators in
  a modulator/carrier pair").
- A compact register-group / subfunction reference card — just the groups this
  file uses.

Example (excerpt, AdLib driver): the OPL2 primer names the two I/O ports (0x388
index, 0x389 data), notes that a register "write" is a *pair* of OUTs with a
timing delay, states the structural model ("9 voices, each a modulator/carrier
operator pair, 18 operators addressed by adl_voice_oppair"), lists just the
register groups this file touches, and pins the one counter-intuitive fact
("Total level" is attenuation, not volume: 0=loudest, 0x3F=silent), closing with
`; see shikadi.net/moddingwiki/OPL_chip`.

### 2.4 The dispatch ABI (drivers)

Explain how the game reaches the driver. Cover: what the format is and why it
exists (multi-driver soundsystem for DUDE; the video renderer-vtable for
VMCODE); the header magic and meaning; the dispatch table and trampoline; the
register-argument conventions (DUDE: BP=slot, AL=ch, CL/CH=data bytes; caller
does `CALL FAR seg:offset`, trampoline returns `RETF`); and a per-driver slot
table listing what each slot does in *this* driver and its argument convention.

### 2.5 How to read this source

The audience is fluent in assembly. Do **not** re-explain Intel syntax,
addressing modes, or condition codes. Cover only the project- or TASM-specific
conventions the reader can't infer, e.g.:

- **TASM hex-literal parser:** hex must begin with a digit (`0AH`, not `AH` —
  which parses as a register); `H`=hex, `B`=binary, none=decimal.
- **Segment model:** drivers are flat single-segment with explicit `CS:`
  overrides (DS/ES unreliable at slot entry); C-linked modules use
  `_TEXT`/`_DATA`/`_BSS` + `DGROUP` with `assume ds:DGROUP`.
- **Local jump targets** use `LOCALS` + named `@@name:` scope, resetting at each
  public label (§12).
- **Calling conventions vary per function;** each plate names its ABI in domain
  terms (register-passing hand-asm cores vs stack-arg compiler-shaped code). In
  C-linked modules the public label IS the C-mangled name.
- **`dead -- preserved for byte-exactness`** marks code unreachable at runtime
  but present in the original; removing it breaks byte-identity.

---

## 3. Function documentation

Every `PROC` gets a header block. Two styles, by family.

### 3.1 C-linked module: C-prototype + Entry/Exit/Trashes

The module banner already carries the deep teaching, so plates stay light. Lead
with the C prototype the label satisfies; add Entry/Exit/Trashes only when the
register ABI isn't obvious:

```asm
; ----------------------------------------------------------------------------
; int rand(void)
;   Entry:    (none) -- all state in this module's DGROUP _DATA
;   Exit:     AX = next pseudo-random word (also cached in _g_randLast)
;   Trashes:  AX BX  (SI saved+restored)
; ----------------------------------------------------------------------------
_rand           proc far
```

For a trivial helper, the C-prototype line alone is enough. **Never add a
`Provenance:` line or reconstruction narration** (§10.4). An optional
C-equivalent block below the plate is welcome when it aids comprehension.

### 3.2 Standalone driver: fuller plate

Drivers carry more per-function context because the dispatch model spreads
control flow across a table. Adopt Mark Moxon's Elite-source structure, adapted
for TASM:

```asm
; ----------------------------------------------------------------------------
; <address>  --  <function_name>
;
;   <one-paragraph summary in plain English, present tense>
;
;   Type:        Subroutine (or "Slot handler", "OPL writer", etc.)
;   Category:    <Voice management | OPL register I/O | MIDI dispatch | ...>
;   Dispatch:    Slot N (called as: BP=N, AL=ch, CH=note, CL=vel)   [handlers]
;   Callers:     <functions that call this, or "Game (via dispatch)">
;   Callees:     <functions this calls, with brief why>
;
;   Inputs:
;     <REG>  --  <what it means in domain terms, not just "byte">
;   Outputs:
;     <REG>  --  <what's returned>   (or "none")
;   Touches:
;     <REG>  --  <if clobbered without restore>   (or "all preserved")
;   Side effects:
;     <global writes / hardware writes>   (or "none")
;   Notes:
;     <quirks, performance hacks, byte-exactness preservation>
; ----------------------------------------------------------------------------
```

Skip any section that doesn't apply (don't write "Notes: none.").

### 3.3 What "Inputs / Outputs" actually contains

Don't write `AL -- byte`. Translate from "register holding a byte" to "named
domain concept the reader can hold in their head":

```
;     AL  --  MIDI channel (0..15). Channel 9 is the percussion channel and
;             triggers the drum-clamp path below.
;     CH  --  MIDI note number (0..127). Out-of-range notes are silently
;             dropped before any voice work happens.
```

---

## 4. Inline comments

Three kinds, in order of frequency.

**Block comments (most common — every 5–15 lines).** Drop a 1–3 line comment
before any logical group of instructions that does one conceptual thing. Comment
the *purpose*, not the mechanics:

```asm
                ; Walk all 9 voices; for any voice still playing on channel AL,
                ; recompute its OPL frequency word so the chip picks up the new
                ; pitch-bend value.
                XOR     BX, BX
                JMP     SHORT pb_scan_test
pb_scan_body:   CMP     CS:[BX + adl_voice_channel], AL
```

**End-of-line comments (selective).** Only when the *what* of an instruction
isn't obvious from mnemonic + operands. Vertically align so they form a readable
right column:

```asm
                SHL     CX, 1
                SHL     CX, 1                   ; CX = MIDI note * 4 (table step)
                MOV     DH, 30H                 ; divisor for note->block
                DIV     DH                      ; AL = octave, AH = note mod 48
```

Bad: `MOV AX, 0 ; set AX to 0`, `INC SI ; increment SI`, `POP CX ; pop CX`.
Good: `MOV AX, 0 ; (DX:AX) dividend = AX`, `INC SI ; advance to next voice`.

**In-band background notes.** For one-off teaching moments — the first use of a
non-obvious x86 idiom or hardware quirk — a 3–6 line block comment. Use
sparingly; after the first call site the reader has seen the pattern.

---

## 5. Naming conventions

Naming is where the two families diverge most. [`CLAUDE.md`](../../../CLAUDE.md)
is the authority for the C-side conventions the mangled labels mirror.

### 5.1 C-linked module labels

- **Public labels are the exact C-mangled name** the linker resolves — a leading
  underscore matching the C declaration byte-for-byte. `int rand(void)` →
  `_rand`; `void _rand_reset_indices(void)` → `__rand_reset_indices` (the
  source-level leading underscore mangles to a second one). Under `/mx`, globals
  are **case-sensitive**, so the case must match the C decl exactly. Never
  rename these.
- **Globals follow `CLAUDE.md`**: `g_` + `camelCase`, mangled with a leading
  underscore — e.g. `_g_nJoy0CenterX`, `_g_bJoystick0Installed`. (The `w`/`b`/`n`
  Hungarian tags are legacy Ghidra artifacts — don't add them to new labels.
  Dropping them from an existing global is a *rename*, not a doc pass:
  byte-neutral only if the label and every reference — including any C `extern`
  and its callers — move together and `bak diff` stays clean.)
- **Local labels** are free (`/mx` makes them case-insensitive and they're never
  public). Use TASM's `LOCALS` + named `@@name:` scope (`@@store_j`,
  `@@next_vertex`) — the period-authentic Borland idiom the tree is converging
  on; the `@@` scope resets at each `public` label. Avoid only the anonymous
  `@@:` / `@F` / `@B` form (hard to reference from comments). See §12.

### 5.2 Driver labels

| What                        | Convention                         | Example                                    |
| --------------------------- | ---------------------------------- | ------------------------------------------ |
| Driver-namespaced data      | `<dr>_<noun>_<suffix>`             | `adl_voice_note`                           |
| Driver-namespaced functions | `<dr>_<verb>_<noun>`               | `adl_voice_release`                        |
| Slot handlers               | `<dr>_midi_<event>` / `<dr>_set_*` | `adl_midi_note`, `adl_set_master_volume`   |
| Chip write helpers          | `<dr>_<chip>_write[_<what>]`       | `adl_opl_write`, `adl_opl_write_op_level`  |
| Hardware port constants     | `<dr>_port_<purpose>`              | `adl_port_reg`, `adl_port_data`            |
| DUDE header fields          | `dude_<field>`                     | `dude_magic_a`, `dude_driver_kind`         |
| Padding / alignment         | `pad_<hex_addr>`                   | `pad_188f`                                 |

Snake_case throughout. The `<dr>_` prefix keeps namespaces separate across the
14 drivers. Don't over-shorten — `adl_voice_render_freq` beats `avrf`.

### 5.3 Constants

`UPPER_SNAKE_CASE` for symbolic constants introduced via `EQU`. Hex numeric
literals in code use trailing `H`:

```asm
OPL_KEYON_BIT       EQU 20H              ; bit 5 of reg 0xB0+v
MIDI_NOTE_MIN       EQU 0CH
MIDI_NOTE_MAX       EQU 6BH
```

Introducing an `EQU` and substituting it for a literal is byte-neutral only if
the value is identical — verify with `bak diff` (see §13). For one-shot magic
numbers explained on the spot by a comment, inline literals are fine.

---

## 6. Layout, formatting, indentation

The common tab stops (derived from Borland's own shipped TASM source):

| Column | Purpose                                                     |
| ------ | ---------------------------------------------------------- |
| 1      | Standalone `;` for full-line comments and section banners. |
| 1      | Labels (`name:` or `name PROC`).                           |
| 17     | Mnemonics (`MOV`, `CALL`, `JMP`, `DB`, ...).               |
| 25     | First operand.                                             |
| 49     | End-of-line `;` comment (right of operands).               |

Some transcribed modules (e.g. RAND.ASM) are tab-indented rather than
space-aligned to these exact stops — **match the file's existing convention**
rather than reflowing a whole module; a mass realignment is churn that adds
review noise. Align *new* comments you add to the surrounding code.

**Mnemonic case:** TASM accepts any case. The convention is **uppercase** for
mnemonics, registers, and directives; **lowercase** for our own labels and
identifiers. Match whatever case the target file already uses consistently;
don't mass-recase.

**Section banners:** major regions get a double banner; subsections a single
one.

```asm
; ============================================================================
; 0x183C  --  velocity-clamp lookup table (62 bytes saturated at 0x3C)
; ============================================================================
```

```asm
; ----------------------------------------------------------------------------
; 0x1952  --  adl_midi_note_off  (slot 4)
; ----------------------------------------------------------------------------
```

**White space inside a function:** group related instructions with blank lines
so a function reads like prose paragraphs, each group introduced by a block
comment.

---

## 7. Documenting data

Data declarations need almost as much commentary as code. In C-linked modules
the byte order is load-bearing (DGROUP/BSS placement), so **document, never
reorganise**.

**7.1 Every data label gets a one-line role.** Name the *domain* the bytes mean,
not the storage shape — "voice -> MIDI note" beats "9 bytes of voice notes":

```asm
adl_voice_note         DB 9 DUP(0FFH)        ; voice -> MIDI note (FF = idle)
```

**7.2 Tables get a multi-line block at the top.** For arrays larger than 16
bytes, write a banner explaining layout, units, range, and consumers:

```asm
; ----------------------------------------------------------------------------
; 0x003D  --  OPL2 F-number / block lookup, 48 entries (1 entry = 2 bytes)
;
;   Each entry is the OPL F-number for a MIDI-note-within-octave. Range
;   0x0157 (note 0 mod 48) .. 0x02A4 (note 47 mod 48). Block (octave) bits are
;   computed separately by adl_voice_render_freq via `note / 48`.
; ----------------------------------------------------------------------------
adl_note_fnum_table LABEL WORD
                DW      0157H, 015CH, 0161H, 0166H, 016BH, 0171H, 0176H, 017BH
```

**7.3 Parallel arrays get aligned, semantic names.** When several parallel
arrays form a logical struct-of-arrays, group them visually and align their
declarations. Don't fold them into a `STRUC` — separate top-level globals read
better and, in C-linked modules, keep the byte layout obvious:

```asm
adl_voice_channel      DB 9 DUP(0FFH)       ; voice -> MIDI channel (FF = idle)
                       DB 2 DUP(0FFH)       ; pad_199 (alignment to 0x19B)
adl_voice_note         DB 9 DUP(0FFH)       ; voice -> MIDI note (FF = idle)
                       DB 2 DUP(0FFH)       ; pad_1a4
```

**7.4 Byte-matching layout constraints are NOT source comments.** A C-linked
module's `_DATA` placement, `_BSS` file order, and public/extrn declaration
order are load-bearing for byte-identity — but that is a *byte-matching*
concern, and narrating it in the source (link position, DGROUP slot, "so it
lands at its shipped slot", "linked between SYSLOWIO.OBJ and AUDIO.OBJ", "do not
reorder to match the original") is reconstruction narration. Keep it **out** of
the `.asm`. The ordering constraint is real, but it is enforced by the link
script (`KRONDOR.RSP`) and recorded in project memory — that is where it
belongs. Document the *data* (§7.1–7.3); do not document why its address must
not move.

---

## 8. Preserving and explaining historical quirks

The source is a reconstruction with a **byte-exact** target. When it ships code
that contradicts apparent intent, the comment is the place to be honest about
it. §11+ says which constructs are byte-neutral to touch.

**8.1 Dead code.**

```asm
                JMP     SHORT qry_end
                JMP     SHORT qry_unknown   ; dead JMP preserved for
                                            ; byte-exactness; never reachable
                                            ; (both arms above JMP to qry_end).
```

**8.2 Magic literals that double as code.** When a data byte is the encoded
prefix of an instruction never executed but positioning the following bytes at a
specific offset, explain the trick at the declaration:

```asm
                ; The byte 0xB8 is the opcode for `MOV AX, imm16`. It is never
                ; executed -- nothing jumps here -- but its presence makes the
                ; following 16-bit value land where adl_load_patch_bank reads
                ; [adl_bank_size].
                       DB 0B8H              ; MOV AX opcode (operand below)
adl_bank_size          DW 1507H             ; doubles as MOV AX immediate
```

**8.3 Non-symmetric register saves.** When the original pushes and pops
registers in the *same* order (swapping them on return), document why it's safe
and that it's preserved for byte-exactness.

**8.4 Hand-rolled arithmetic.** The 8086 has slow IMUL and no DIV-by-immediate.
Hand-rolled `shift + add` multiplications are common; add a comment showing the
formula ("14 = 2 + 4 + 8"). RAND.ASM's `SUB reg,2 ; JNS` (a fused sign test that
reads the flag the subtraction already set) is worth a one-line note the first
time it appears.

**8.5 Timing loops.** Anywhere the code stalls deliberately to satisfy hardware
timing (OPL2 register absorb delay, etc.), explain the requirement and why the
dummy-read count satisfies it.

**8.6 Pass-dependence and prologue pins.** Where the source pins a size
(`JMP SHORT`, `word ptr`) or avoids TASM's auto-prologue (bare `PROC`, no
`ARG`/`USES`), a one-line comment noting *why the pin is load-bearing* is
welcome. See §11 and §15.

---

## 9. Cross-references and glossary

The `.asm` file must be readable standalone — the file itself is the home for
the background it needs. Do **not** offload context to a companion `.md` and
link out to it; a reader with only the one `.asm` file in front of them should
never hit a dangling "see the such-and-such doc". Cross-reference only *within*
the file (`see §<section>` / a named banner) or to a stable external source
(RBIL, a chip datasheet, `CLAUDE.md` for the naming conventions the mangled
labels mirror), and only for *deeper* context — never for core comprehension.

**Glossary:** every `.asm` file ends with a glossary of every acronym it uses,
so a reader who jumps into the middle can resolve terms. It lives in the file
itself — never in a separate doc. For a driver, minimum coverage: MIDI
channel/note/velocity/
controller/program/pitch-bend (audio) or the CGA/EGA/VGA plane/register terms
(video); the dispatch format and its slot/vtable ABI; every chip abbreviation
(OPL2: TL, KSL, AR, DR, SL, RR, AM, VIB, KSR, MULT, FB, ALG, F-num, block,
key-on); "voice" vs "operator", "patch"/"instrument"/"program"; "CS-relative",
"near", "far", "DGROUP" if used. A small C-linked module's banner usually
carries enough; a full glossary is a driver-scale requirement.

---

## 10. Anti-patterns

Avoid these — they add noise without information.

- **10.1 Restating the mnemonic.** `MOV AX, BX ; move BX into AX`,
  `XOR AX, AX ; AX gets zero`. Explain the *intent* or omit.
- **10.2 Cryptic abbreviations.** `; Init st, gv to 0, run wcb w/ KSR off`.
  Acronyms defined in the primer (KSR, TL, FB) are fine; ad-hoc shorthand
  (`wcb`, `st`, `gv`) is not.
- **10.3 Stale comments.** If you flip a `JNZ` to `JZ` (or fix a `db`-faked
  mnemonic), the comment must change too. A wrong comment actively misleads.
- **10.4 Reconstruction narration.** No Ghidra/decompiler/`Provenance:`/
  offset-size/byte-verified/campaign commentary, and no byte-matching layout
  narration (link order, DGROUP slot, "do not reorder to match the shipped
  binary" — §7.4). The source documents the *module*, not how it was recovered
  or how it is kept byte-identical. Narrow exception: a note that helps a reader
  understand the code itself (an assembler-parser quirk, a segment assumption).
- **10.5 Repeating the file header in every function.** The overview is in the
  preamble; each plate is concise. Don't re-explain AdLib / the DGROUP model
  everywhere.
- **10.6 Wall-of-text inline blocks.** 30 lines of context in the middle of a
  function is too much — hoist the primer into the file's preamble (§2.3) and
  keep the inline note to ~10 lines, or cite a specific external source (RBIL, a
  datasheet). Don't shunt it into a companion `.md`; the file stands alone.
- **10.7 Inline disassembly tables.** `; 0x1F8C: F6 E1 MUL CL` shadows the
  assembler. The source is canonical; the byte encoding is irrelevant once we
  have byte-exact match. Original-binary offsets in section banners are fine.

---

## Worked example — a C-linked module, end to end

One function from `bak/SRC/SYS/RAND.ASM`: a factual banner, a light
C-prototype + Entry/Exit/Trashes plate, block comments that break the body into
conceptual steps, `@@` local labels, and no reconstruction narration.

```asm
; ----------------------------------------------------------------------------
; int rand(void)
;   Entry:    (none) -- all state in this module's DGROUP _DATA
;   Exit:     AX = next pseudo-random word (also cached in _g_randLast)
;   Trashes:  AX BX  (SI saved+restored)
; ----------------------------------------------------------------------------
_rand	proc far
	push	si

	; Load the two lag cursors: J in BX (caller-saved), I in SI (callee-saved,
	; hence the lone push/pop). Each transfer routes through AX.
	mov	ax,word ptr [_g_randPosJ]
	mov	bx,ax
	mov	ax,word ptr [_g_randPosI]
	mov	si,ax

	; draw = ring[J] + ring[I]; write it back at ring[I] and cache the result.
	mov	ax,word ptr [bx + _g_randState]
	add	ax,word ptr [si + _g_randState]
	mov	word ptr [si + _g_randState],ax
	mov	word ptr [_g_randLast],ax

	; Retreat J one word. SUB sets the sign flag that JNS then reads; wrap on
	; underflow to the last slot (offset 0x6e = slot 55).
	sub	bx,2
	jns	short @@store_j
	mov	bx,6eh
@@store_j:
	mov	ax,bx
	mov	word ptr [_g_randPosJ],ax
	; ... I is handled identically, then AX = _g_randLast is returned ...
	pop	si
	retf
_rand	endp
```

The plate gives the C prototype and register ABI; block comments carry the
*why* of each step; end-of-line comments would carry only the non-obvious (the
`0x6e` wrap constant, the J=BX/I=SI hand-pick). No provenance, no mnemonic
restatement, no link-order narration.

---

# Byte-neutrality mechanics (which edits are byte-safe)

The **what edits move bytes** reference, verified from our actual
`$BAK_TOOLCHAIN/bc31/BIN/TASM.EXE` (`Turbo Assembler Version 3.1`). Every module
is MASM mode (no `IDEAL`), medium/tiny model, `.286` (drivers `.MODEL TINY` /
`.386`). Our invocation is `bak/RECIPES.MAK` → `AS = tasm`,
`ASFLAGS = /mx /m /iINCLUDE`.

**Every byte-neutrality claim here is a hypothesis until `bak diff` confirms it
for the specific module.** Verify **every** change:

```
uv run bak diff SRC/PATH/FILE.ASM     # disasm the fresh .OBJ, diff vs reference
uv run bak build                      # drivers: reassemble + repack OVL + cmp
```

A clean diff means byte-identical. That is the gate — never "it looks right".

## 11. The three ASFLAGS (`/mx /m /iINCLUDE`)

Straight from the binary's switch help:

```
/ml,/mx,/mu   Case sensitivity: ml=all, mx=globals, mu=none
/m#           Allow # multiple passes to resolve forward references
```

- **`/mx` = globals CASE-SENSITIVE, locals NOT.** This is why public labels must
  match the C-mangled name exactly (`_r3d_polygon_clip_near_z`), and why an
  `EQU`/local label's case is free *except* where it becomes `public`. `public
  Foo` and `public foo` are two different symbols.
- **`/m` (= `/m1`) raises the pass cap** to resolve forward refs; it does **not**
  force determinism. TASM emits `Symbol redefined or moved between passes` when a
  symbol's pass-1 size estimate differs from pass 2 — the pass-dependence trap.
  Any construct whose encoded size can shift between passes (a forward jump that
  could be short or near; a forward `EQU` used in a size context) is a hazard:
  pin sizes explicitly (`jmp short`, `word ptr`) so both passes agree.
- **`/iINCLUDE`** adds `INCLUDE\` to the search path. Not style-relevant; don't
  touch.

**None of these flags change emitted bytes on their own** — they change symbol
matching and the pass budget. Byte changes come from the source constructs below.

## 12. LOCALS + `@@` local labels

`LOCALS` enables the `@@`-prefix local-label scope in MASM mode. Two forms:

- **Named locals `@@name:`** — scoped between two non-local labels (typically
  PROC-to-PROC or public-to-public). Use these for per-function jump targets.
- **Anonymous `@@:`** with `@F`/`@B` references — **avoid** (hard to reference
  from comments).

Each function is delimited by its `public _foo` / `_foo:` — exactly the boundary
`@@` locals reset at — so `@@clip_loop` in one function cannot collide with
another's. Label *names* never emit bytes; a jump emits the same displacement
regardless of spelling **provided the jump's size is unchanged**.

**Rule: rename labels only; never touch the mnemonic, its `short` qualifier, or
label ordering in the same edit.** Add `LOCALS` once near the top (after `.286`,
before the first proc). Then `bak diff` must be empty.

```asm
L_22e8:         mov SI,CX        →   @@next_vertex:  mov SI,CX
    jz L_233f                            jz @@prev_behind
    jmp short L_235d                     jmp short @@continue
L_233f:                              @@prev_behind:
```

**Pitfall:** never localize a label that appears in an `extrn`/`public` line, or
that a *cross-module* `jmp`/`call` targets — it must stay a regular label.

**Macro-local hazard:** a macro that declares `local` labels (e.g. `COS`) emits
a non-`@@` symbol at each expansion, and that symbol TERMINATES the current `@@`
scope. A forward `jmp @@name` whose target lies beyond such an expansion fails
"Undefined symbol". In functions mixing `@@` labels with such macros, any label
whose reference crosses an expansion must stay a GLOBAL label — give it a
meaningful function-prefixed snake_case name (`bld_rot_done`). Macros without
`local` don't break scope.

## 13. EQU / `=` for constants and stack args

- **`EQU`** = permanent alias; **`=`** = redefinable numeric. Use `EQU` for
  magic numbers: `CLIP_BEHIND_NEAR EQU 3` then `cmp AH,CLIP_BEHIND_NEAR` — pure
  substitution, byte-identical to `cmp AH,3h`.
- **Named stack args via `EQU` to a `[bp+n]` operand** is the standard 1993 way
  (Borland's own `HEX.ASM`). It emits the *identical* ModRM/displacement bytes,
  generates **no prologue, no code**. This is the blessed replacement for
  `PROC ... ARG` (§15):

  ```asm
  ; Parameters (+2 because of push bp)
  byteCount EQU BYTE PTR  ss:[bp+6]
  num       EQU DWORD PTR ss:[bp+8]
  ```

- **Gotchas:** `EQU` symbols are module-global (no block scope) — name them
  per-function-uniquely or accept sharing; they cannot be forward-referenced in
  a size-sensitive context without risking the pass trap (§11). Under `/mx` an
  `EQU` you also `public`ise becomes case-sensitive. `PURGE` removes a
  macro/EQU; avoid unless reproducing a genuine original redefinition.

## 14. STRUC field addressing

Defining a `STRUC` emits **no bytes** (compile-time template); a STRUC *instance*
(`FACE <...>`) emits data — only ever use it as an offset dictionary, never
instantiate.

```asm
FACE    STRUC
    v0  dw ?
    v1  dw ?
FACE    ENDS
    mov ax, [di].v1          ; MASM dot form -> disp 2 (byte-identical to [di+2])
```

- **VERIFIED on our TASM 3.1: the `[reg+STRUCNAME.field]` form does NOT
  assemble** ("Need right square bracket"). Use the dot form `[reg].field`.
- Field names are *global* constants in MASM mode — prefix per STRUC (`fFlags`,
  `mType`, `vX`) to avoid collisions.
- **Segment overrides are orthogonal:** the struc reference supplies only the
  displacement. `mov ax, es:[si].v1` emits the `26h` (ES) prefix + the same
  ModRM the raw `es:[si+2]` produced. Verify with `bak diff` — a struc whose
  offsets don't sum to the original raw displacement diverges immediately.

## 15. PROC/ENDP — the prologue trap (critical)

- **Plain `label PROC NEAR|FAR` … `ENDP` emits nothing** — it only sets the
  default distance for `RET` and marks the symbol. Safe to adopt for
  readability, but our files deliberately use a bare `_name:` label + explicit
  `push BP` and explicit `retf`. **Do not switch a bare label to `PROC` unless
  you keep the explicit RET** — a `PROC FAR` can make a bare `ret` assemble as
  `retf`, changing a byte. Confirm `bak diff`.
- **`ARG`, `USES`, `LOCAL` (the high-level PROC extensions) EMIT
  PROLOGUE/EPILOGUE CODE — DO NOT USE THEM.** `USES si di` injects
  `push`/`pop`; `PROC ... LOCAL x:WORD` emits `push bp / mov bp,sp / sub sp,N`;
  `PROC name C arg:DWORD` generates a frame. Our prologues are hand-written and
  exact. Use the `EQU ... ss:[bp+n]` idiom (§13) for named stack args instead.

## 16. RECORD — self-documenting flag bytes

`RECORD` defines named bit-fields and generates shift-count and mask symbols.
`MASK field` and `WIDTH field` are compile-time constants → **byte-neutral**;
they let a raw `test al,80h` become `test al,MASK behind`. Use for clip-state and
render-state flag bytes.

```asm
CLIPST  RECORD  behind:1, left:1, right:1, top:1, bottom:1
    test al, MASK behind          ; -> the field's bit mask
    mov  cl, behind               ; the field name -> its shift count
```

**Pitfall:** a RECORD *instance* emits data — only use the type for `MASK`/shift
constants against runtime values, never instantiate. Field names are global
constants — name them to avoid collision with EQUs.

## 17. Directives that MUST stay as-is (danger list)

- **`JUMPS` must stay OFF** (default `NOJUMPS` in MASM mode). `JUMPS`
  auto-stretches an out-of-`short`-range conditional jump into a
  `jcc-around + jmp near` pair — **it inserts bytes**. Never add it. When a
  target is genuinely out of range, the original used a near/`jmp` explicitly —
  reproduce that literally.
- **`SMART`/`NOSMART`** — MIDI.ASM toggles `nosmart`…`smart` around far-call
  command handlers so TASM does **not** pre-collapse a same-segment `call far`
  into push-cs+near-call (TLINK does that, matching the shipped bytes).
  **Preserve verbatim** — removing a `nosmart` region changes far-call encodings.
- **`ASSUME`** — drives whether a segment override prefix is emitted (e.g.
  `assume cs:...` makes an operand emit the `2E` CS prefix). Don't add/remove
  casually; each governs real prefix bytes.
- **`.MODEL` / segment (`SEGMENT`/`ENDS`/`GROUP`) / `.286` / `.386p`** — layout
  and encoding critical. Leave exactly as transcribed. `GROUP` (e.g. DGROUP)
  governs FIXUPP frames; a wrong group diverges relocations.
- **Radix:** MASM/TASM default is decimal; hex must start with a digit and end
  in `h` (`0ffffh`). Never introduce a `.RADIX` change — it reinterprets every
  bare number. `1h` → `1` is byte-neutral; prefer leaving the transcribed form.

## 18. Macros, repeats, and byte-neutral aids

- **`name MACRO … ENDM`** expands to text; the expansion assembles to the *exact
  same bytes* as writing the sequence by hand. Folding a repeated instruction
  group into a macro is byte-neutral *iff* every expansion is identical.
- **`LOCAL lbl1, lbl2` as a macro's first line** generates a unique hidden label
  per expansion (byte-neutral) — but see §12's macro-local scope hazard.
- **`REPT n` / `IRP arg,<list>`** unroll at assembly time, byte-identical to the
  written-out form — only if the original was actually unrolled to the same
  count. Keep macro bodies size-deterministic (`jmp short`, explicit `ptr`) or
  they re-introduce the §11 pass trap at every call site.
- **Byte-neutral self-documentation aids:** `LABEL` (`name LABEL WORD` — typed
  alias to the current location, no data); `%TITLE`/`%SUBTTL`/`PAGE` (listing
  headers only, never touch the `.OBJ`). Avoid `CODEPTR`/`DATAPTR` (model-
  dependent) — prefer explicit `word ptr`/`dword ptr` as our files already do.

## 19. Rewrite recipe — one function, each step `bak diff`-verified

Convert one function at a time. **Require an empty `bak diff` after every step
before proceeding.** If a step diverges, revert just that step.

1. **Banner** (§2.1, §3) — comments only, empty by construction.
2. **Constants → EQU** (§13) — numeric-identical.
3. **Flag bytes → RECORD** (§16), optional.
4. **Struct field offsets → STRUC refs** (§14) — a wrong offset diverges at
   once; keep the segment override.
5. **Named stack args → EQU** (§13), if the function has a bp-frame. **Never**
   `PROC ARG`.
6. **Local labels → `@@`** (§12), last. With `LOCALS` enabled once at top,
   rename `L_xxxx` → `@@meaningful` — only labels that are neither `public` nor
   `extrn` and not targeted from another module. Rename spelling only; touch no
   mnemonic, no `short`, no ordering.

Do **not** in any step: add `JUMPS`; remove `NOSMART`/`SMART`/`ASSUME`; change a
jump's short/near form; reorder declarations, labels, or `public`/`extrn` lines
(decl order is load-bearing for TLINK); change radix or segment directives.

---

## 20. References

- Mark Moxon, *Fully documented source code for Elite on the 6502* —
  bbcelite.com — the canonical thoroughly-commented retro-game RE.
- Mike Shute, *Comments in assembly language* — d.umn.edu/~gshute/asm.
- Source Format, *Assembly Language Style Guidelines / Comments* —
  sourceformat.com — column alignment, comment density.
- The OPL chip wiki — shikadi.net/moddingwiki/OPL_chip — OPL2/OPL3 register
  reference.
- Bochs AdLib/SoundBlaster technical document —
  bochs.sourceforge.io/techspec/adlib_sb.txt — period-correct timing notes.
- Ralf Brown's Interrupt List (RBIL) — DOS/BIOS/mouse/EMS/XMS interrupts.
- FreeVGA (osdever.net/FreeVGA) — register-level video.
- `CLAUDE.md` — naming conventions (the authority the mangled labels mirror).
