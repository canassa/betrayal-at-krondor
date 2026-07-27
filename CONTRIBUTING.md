# Contributing

## Where the project is

The reconstruction compiles and links to the shipped 1993 binaries, byte for byte,
for both releases. The build verifies this on every run: same sizes, same sha256.

That is a stronger result than it may look. A byte-match pins the *shape* of the
source, not just its behaviour. Borland C++ 3.1 at `-O1` is not a clever compiler. It
follows the source closely, so almost every choice the original programmers made is
still visible in the object code: which branch came first, whether a loop tested at
the top or the bottom, where a temporary lived, in what order the globals were
declared, how a struct was laid out. The code under `bak/SRC/` had to reproduce all of
it. So the C here is, in structure, very probably close to what Dynamix typed in 1993,
not merely code that behaves the same way.

The assembly is assembly for the same reason: the original modules were written in
assembly, so they stay assembly here. Nothing was hand-translated to dodge a hard
compile.

What the byte-match does **not** pin is everything a compiler throws away:

| Load-bearing (the build will tell you) | Free (costs nothing at codegen) |
|---|---|
| Control flow and expression shape | Identifier names (see the caveat below) |
| Declaration and definition order, within a file *and* across the link | Comments and documentation |
| Struct layout, field width, and any signedness that reaches an opcode | How a constant is *spelled*, given the same value and type |
| Which translation unit a global lives in | Formatting and whitespace |

So the skeleton is right and the flesh is missing. The tree is full of names a machine
invented, constants spelled as bare hex, and structs with `pad_` fields that aren't
padding. **There is no documentation at all, and that is deliberate**; see
[Documentation](#8-documentation).

The remaining work is human work: read the code until you actually understand it, then
say what it is.

> **Caveat on names.** Renaming is *usually* free, but not always. The BC++ 2.0 island
> lays out uninitialized globals by a hash of the identifier, so renaming one there
> reshuffles `_BSS`. Treat every rename as a change to be verified, not as an
> obviously-safe edit.

## The prime rule

Any change under `bak/SRC/` must keep `KRONDOR.EXE`, `VMCODE.OVL` and `SX.OVL`
byte-identical to the originals, for **both** releases. A change is not done until
both verify:

```
uv run bak build                # 1.00 (floppy): all three artifacts
uv run bak build --version 102  # 1.02 (CD-ROM): KRONDOR.EXE
uv run bak diff SRC/PATH/FILE.C # disassembly diff of one OBJ, to debug a break
```

See [BUILDING](docs/BUILDING.md) for the toolchain setup.

When something diverges, `bak diff` shows you where. A divergence on what you believed
was a pure rename means you changed something else too, most often a type whose width
or signedness reaches an opcode. That is information, not an obstacle: the compiler
just told you a fact about the original code. Write it down.

## The work

### 1. Understand the function before you touch it

This is the whole job; everything below is bookkeeping.

Read the function. Read its callers. Read what it writes and who reads that back.
Follow the values into the data files if that is where the answer lives
(`uv run bak rmf` explores the shipped assets). Only then name it.

**The names in the tree today are guesses, and many of them are wrong.** They were
produced in bulk by decompilers and language models, which name a thing by its shape
and by the code around it rather than by what it does. A wrong name is worse than no
name. It is a confident lie that the next reader, and the next model, will build on.

LLMs are genuinely useful for this grind, but hold them to evidence. They assume, they
pattern-match, they are fooled by exactly the wrong names we are trying to remove, and
they will happily invent a rationale for one. Ask for the citations: which lines write
this field, which read it, what the disassembly shows. "It's called `pad_6`, so it's
padding" is not evidence. Neither is "xbak calls it that"; earlier reverse-engineering
projects are useful leads, never proof.

Byte-identity proves the *data flow* is right. It never proves a *name* is right.

### 2. Names

The conventions are in [CLAUDE.md](CLAUDE.md). Briefly: `camelCase` locals,
`g_camelCase` globals, `SCREAMING_SNAKE_CASE` constants, `PascalCase` types,
`module_snake_case` public functions, `static snake_case` private ones. The tree still
carries Hungarian notation (`bKind`, `nCount`, `wFlags`, `pFoo`) inherited from the
decompiler. Those are artifacts, not 1993 house style, and they go.

`uv run bak lint` runs the naming check.

### 3. Give the constants names

Bare hex is how the decompiler saw the world. Replace the literals with named
constants: an `enum` when the values form a set, a `#define` when they don't.

```c
/* before */
switch (kind_picked) {
case 0:  item_id = 0x24; break;
case 2:  item_id = 0x26; break;
case 3:  item_id = 0x2a; break;
...
```

```c
/* after */
switch (kindPicked) {
case CBT_KIND_SWORDSMAN: itemId = ITEM_BROADSWORD; break;
case CBT_KIND_ARCHER:    itemId = ITEM_SHORT_BOW;  break;
...
```

Two rules for this one:

- **Do not restructure the switch.** Collapsing it into a lookup table changes codegen.
  Keep the cases, and keep them in their existing order. That order is not arbitrary,
  it is a fingerprint of the source it was reconstructed from.
- **Name from evidence.** If you can't tell what `0x2a` is, leave it and say so in the
  PR. A plausible-sounding wrong constant name is the failure mode this whole document
  exists to prevent.

### 4. `NULL` for pointers

A house rule, and about 380 sites still to fix:

```c
actor->inner->target = (CombatActor *)0;   /* before */
actor->inner->target = NULL;               /* after  */
```

`NULL` expands to `0` in this memory model, so it is free. Reserve bare `0` for
integers.

### 5. Structs: one member at a time

Struct work is the highest-value and the most easily botched. Every member gets
investigated on its own merits. Do not name a struct by analogy, and do not trust a
field name that came out of a decompiler.

Worked example. `CombatActorInner` carries this:

```c
unsigned char pad_6[2];
```

The name says padding. But 35 sites touch it, and they tell a different story: the AI
writes a candidate tile into it, spells write the current tile plus a knockback delta,
and several places compare it against `grid_x`/`grid_y` to ask "are we there yet?".
That is not padding. It is a destination tile, a two-byte `(x, y)` pair living next to
the actor's current one. Name it, split it into two fields if the evidence supports
that, and document what writes it and who consumes it.

Then **move the struct into its own module.** `bak/INCLUDE/structs.h` is a 1500-line
grab-bag of 111 structs, an artifact of reconstruction rather than a design. A struct
belongs in the header of the module that owns it (`CombatActorInner` goes to the
combat actor module). Moving types is usually free, but moving *variables* between
translation units is not, because DGROUP layout is load-bearing. Verify.

### 6. Casts

The code is drowning in casts. Most were added during reconstruction as the shortest
way to make an expression match the original codegen, not because the original had
them. There are roughly 4,800 in the C sources, and a large share can simply go.

Try removing a cast and run `bak diff`. Three things can happen, and each one means
something different.

**It vanishes with no divergence.** The cast was redundant, the operand already had
that type. Delete it.

**It diverges, and the operand is a variable.** The cast is doing real work, which
means the *variable* is declared with the wrong type and every use has been paying for
it. Fix the declaration instead:

```c
speed_thr = (int)g_acting_actor_speed - 3;   /* global declared unsigned short */
```

A `(char)x` cast that diverges when removed, on an `x` declared `unsigned char`, is the
clearest case: the variable is genuinely signed. Retype it, drop the cast, and the
build stays identical. Watch for the inverse, though: a byte field that carries a
`0xff` sentinel *and* is used as an array index is genuinely unsigned, and flipping it
to signed will diverge. The compiler is the arbiter, not intuition.

**It diverges at a call site.** Then the *function's* signature is wrong. When the same
cast appears at call site after call site, that is the prototype telling on itself:

```c
extern unsigned int stat_actor_get(CombatActor *actor, int stat_idx, int mode);

if ((int)stat_actor_get(actor, 0, 0) < 5)    /* 27 of 117 call sites cast like this */
```

Fix the return type once and 27 casts disappear. This is the highest-leverage version
of the job, and also the one that most needs a full build: a signature change touches
every caller.

Pointer casts follow the same logic. A `(Foo far *)` sprayed over every use of a
variable usually means the variable, field, or parameter should have been a `Foo far *`
all along. Retype it rather than casting at the point of use. Reaching for `void *` to
make casts go away is a last resort, since it deletes the type information instead of
recording it.

### 7. Structured control flow

This one is mostly **already done**, so read before you reach for it.

Ladders of `goto` with labels like `loop_body` / `loop_inc` / `loop_test` are what a
decompiler emits, not what anyone writes, and they have been ground out of the tree.
About four remain. They restructure into an ordinary `for` with `continue` and `break`,
byte-identically: the compiler cross-jumps the duplicated tails back together. Commit
`cb5346c` is a worked example.

The ~460 `goto`s still in the tree are overwhelmingly a different animal. Their labels
are `cleanup`, `done`, `fail`, `cancel`, `bail`, `close_file`: the single-exit idiom
that C programmers have always used for error paths and shared teardown, and that the
1993 authors almost certainly wrote themselves. **Those stay.** Rewriting one into
nested `if`s makes the code worse, and it will not survive the byte-check anyway.

What is left here is the ~36 jumps to raw `LAB_xxxx` labels. The decompiler never
worked out what they meant, so neither did we. Each needs reading. Some will turn out
to be a cleanup path wanting a real name; some will be a loop in disguise. Renaming a
label is free, but working out which kind you are looking at is the actual work.

### 8. Documentation

The codebase is undocumented on purpose. **Do not have a language model write
documentation for this project.** Documentation is the one artifact where a
confident-sounding hallucination survives review, gets read as fact, and quietly
poisons every future reader. All documentation here is written or reviewed by a human
who has read the code. It's also the rule LLM agents are given in
[CLAUDE.md](CLAUDE.md): never add comments unless explicitly asked.

That does not mean the code stays bare. It means documentation is earned, written
last, and written by whoever did the reading.

The style is Doxygen. The short version:

- Every file that declares anything gets a `@file` block.
- Public functions are documented at their declaration in the `.H`; `static` ones at
  their definition in the `.C`. One block per function, never both.
- Every parameter gets a `@param` carrying its *contract*: range, units, nullability,
  ownership, not a restatement of its name.
- Struct members get trailing `/**< */` comments with their byte offset.
- Every mention of a symbol is an `@ref`, never a bare name and never a `FILE.C:123`
  pin. Names and lines move; `@ref` is checked by Doxygen, prose isn't.
- Document *what* and *why*, not a walk-through of the *how*. The code is right there.
- Wrap at 80 columns.

The full rules, with patterns to copy, are in `.claude/skills/doxygen-c/SKILL.md`.
Match the reference modules:

- `bak/SRC/WORLD/ACTOR/ACTORREC.H`, the small case: two functions, fully specified.
- `bak/SRC/IO/RESOURCE.H`, a whole layer, including the `@defgroup` module page that
  explains what the subsystem is *for* before any individual function.
- `bak/SRC/R3D/TBLSTORE/SHAPETBL.H`, a reverse-engineered binary format: per-field byte
  offsets, and (the part worth copying) an honest record of what it *doesn't* know.
  Fields with no surviving reader are called out as such rather than given a confident
  invented purpose.

## Working style

Small commits, one concern each. The history of the resource layer
(`git log -- bak/SRC/IO/`) is the model: rename the globals, then rename the functions,
then fix a type, then document, each step separately verified and each one reversible.
A 40-file sweep that "cleans up combat" is unreviewable and, when it breaks the
byte-match, unbisectable.

Commit messages are an emoji, a short imperative subject, and a body that says *why*:

| | | | |
|---|---|---|---|
| 🔍 | naming / typing / RE findings | 🏗️ | structural, build, toolchain |
| 📝 | documentation | 🐛 | bug fix |
| 🎨 | style, formatting, no behaviour change | 🧹 | cleanup, dead code removal |
| 🚚 | a function migrated | 📦 | dependencies |

State in the body that both builds stay byte-identical. Describe the change itself, not
the process that produced it and not which tool you used.

## Picking something up

[docs/PROGRESS.md](docs/PROGRESS.md) lists every `.C`/`.H` module with its status.
Anything marked ⬜ is unclaimed. Small modules are good first contributions; the combat
and screen modules are the big ones.

Open an issue or a draft PR before a large module, partly to avoid collisions, partly
because a second reader on a naming decision is worth a lot here.
