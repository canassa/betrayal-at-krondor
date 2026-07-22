---
name: doxygen-c
description: Write or review Doxygen documentation comments for C code — especially structs and their members, plus enums, unions, typedefs, and functions. Use when adding/reviewing `/** */`, `/*! */`, or trailing `/**< */` doc comments in C, documenting binary-format/reverse-engineered structs with per-field offset notes, setting up a Doxyfile for a C-only project, or when the user says "document this struct/function/enum with Doxygen".
---

# Document C code with Doxygen

Actionable rules and copy-pasteable patterns for documenting C (not C++) with Doxygen.
Prefer `@` command prefixes (Javadoc style) over `\` — both work; be consistent.

## Golden rules

1. **Every file that declares globals/typedefs/structs needs a `@file` block**, or
   Doxygen documents *nothing* file-level from it. This is the #1 gotcha.
2. **Put the doc comment adjacent to the item** (directly before, or after with
   `/**< */`). Adjacency means Doxygen auto-associates it — no `@struct`/`@enum`/`@var`
   needed. You only need those structural commands when the comment is *not* adjacent.
3. **Brief vs detailed**: with `JAVADOC_AUTOBRIEF = YES`, the first sentence (up to the
   first `.`, `?`, or `!` + space) is the brief; a blank line starts the detail. Without
   it, use explicit `@brief` / `@details`. Pick one convention project-wide.
4. Use trailing `/**< */` for one-line-per-field structs/enums; use a preceding `/** */`
   block when a field needs multiple lines.
5. **Where the function block lives**: public functions are documented in the `.H` at the
   declaration; private (`static`) functions in the `.C` at the definition. One block per
   function — never duplicate the same block in both files.
6. **Every parameter gets a `@param` line — no exceptions.** Self-evident names are not
   exempt; the line then carries the contract instead (valid range, units, ownership,
   whether it is bounds-checked). Keep it to the caller-facing WHAT — a `@param` that
   merely restates the name means the contract is still missing, so find it (range?
   nullability? who frees it?) and write that.
7. **HARD RULE — every reference to a symbol is an `@ref`. No bare names, no autolinks, no
   line pins.** This codebase is under heavy refactoring: names get renamed, files get
   split, lines shift. Only `@ref` / `\ref` is *verified* by Doxygen — an unresolved one
   warns and fails the doc-lint. Autolinks (`fn()`, `::Type`, `Struct::member`) and
   `@see`/`@sa` render as links only while they resolve and rot **silently** when they
   break, so they are **not acceptable** for naming a symbol. The rule, no exceptions:
   - Naming a function, type, member, macro, global, enum value, or file → **`@ref <name>`**
     (function form: `@ref foo`, not `@ref foo()` — the parens aren't needed and `@ref`
     renders the name without them anyway).
   - Target not yet visible to Doxygen (its header still lacks `@file`, or it isn't
     documented) → the inert placeholder **`@c <name>  (TBD-ref: <why>)`**, literally the
     token `TBD-ref`. Use parentheses, **not** a `/* */` comment — a `*/` inside a `/** */`
     doc block closes it early. **Never `#tbd`** — `#` is a live link operator and warns.
     `grep -rn 'TBD-ref'` finds every one to upgrade to `@ref` once the target is documented.
   - **Forbidden always:** bare symbol names as prose, `FILE.C:NNN` pins, "see line 249".

   Sequencing (so the gate doesn't cry wolf): `@ref` only resolves to a *documented* target,
   and file-scope symbols need `@file` — so land `@file`/doc coverage **before** turning on
   `WARN_AS_ERROR`. See [Cross-referencing](#cross-referencing-never-hardcode-a-symbol).
8. **Wrap comment text at 80 columns.** Every line of a doc block — `@file`, a
   preceding `/** */`, or a trailing `/**< */` — must fit within 80 columns; break the
   prose onto a continuation line before it would cross column 80. The formatter will
   **not** do this for you: the pinned clang-format style sets `ReflowComments: false`
   (it must — auto-reflow mangles `@ref`/`@param` tags and byte-offset tables), so
   wrapping is a hand discipline. When a trailing `/**< */` would overflow, convert the
   field to a preceding `/** */` block (Rule 4) and wrap inside it. Never split an
   `@ref <name>` or `@p name` across a line break — keep each reference token whole.

## Comment block styles Doxygen recognizes

```c
/** Javadoc block. */          /*! Qt block. */          /// C++ line comment
/**                            /*!                        //! C++ line (Qt flavor)
 *  multi-line                  *  multi-line
 */                            */
```

**Member post-comment** — the critical one for struct fields (note the `<`):

```c
int width;   /**< trailing block: documents the PRECEDING member */
int height;  //!< trailing line comment, same effect
```

`/**< */` and `//!<` can *only* document members and parameters — never a file, struct,
enum, union, or group as a whole.

## 1. File header (`@file`)

```c
/**
 * @file    czone.h
 * @brief   Combat-zone actor pool and grid geometry.
 * @details Structures and helpers for the 50x50 tile combat grid. All offsets
 *          in this file are relative to the on-disk TEMP.GAM save image.
 * @author  <name or reverse-eng credit>
 * @date    1993
 */
```

Bare minimum if you just need file-level symbols to appear: `/** @file */`.

## 2. Struct with every member documented (trailing `/**< */` style)

Use this compact style when each field fits on one line.

```c
/**
 * @brief One combatant on the tactical grid.
 *
 * Spawned from the zone actor pool; lives for the duration of one encounter.
 */
typedef struct CombatActor {
    unsigned short id;      /**< Stable actor id; 0xFFFF = empty slot. */
    unsigned char  kind;    /**< Dispatch tag: 1=solid, 2=blocker, 3=trigger. */
    unsigned char  flags;   /**< Bitfield, see @ref CombatActorFlags. */
    short          tileX;   /**< Grid column, 0..49. */
    short          tileY;   /**< Grid row, 0..49. */
    short          hp;      /**< Current hit points; <=0 means dead. */
} CombatActor;
```

## 3. Struct member documented with a preceding block

Use a preceding `/** */` when a field needs a longer explanation.

```c
struct PagedRecord {
    /**
     * @brief Far pointer to the decompressed page payload.
     *
     * Owned by the record store; do not free directly — call
     * @ref pagedrec_release so the LRU cache can reclaim the slot.
     */
    unsigned char far *data;

    unsigned short pageId;  /**< Source page index within the .DAT container. */
};
```

**Mixing is fine and encouraged**: trailing `/**< */` for simple fields, a preceding
block for the one field that needs prose.

## 4. Binary-format / reverse-engineered struct (byte offsets)

The primary use case here. Note **offset, size, and meaning** in each member comment so
the C stays truthful to the on-disk / in-memory layout.

```c
/**
 * @brief On-disk header of a TEMP.GAM save image.
 *
 * Little-endian, packed (no padding — verify with a static_assert on sizeof).
 * Offsets are byte offsets from the start of the file.
 */
typedef struct SaveHeader {
    char           magic[4];    /**< 0x00, 4B: "BAK\0" signature. */
    unsigned short version;     /**< 0x04, 2B: format version (currently 3). */
    unsigned short flags;       /**< 0x06, 2B: bitfield, see @ref SaveFlags. */
    unsigned long  timestamp;   /**< 0x08, 4B: DOS packed date/time. */
    unsigned short partyCount;  /**< 0x0C, 2B: number of party members (1..6). */
    unsigned char  chapter;     /**< 0x0E, 1B: current chapter (1..9). */
    unsigned char  _pad0;       /**< 0x0F, 1B: padding / reserved, always 0. */
    unsigned long  zoneOffset;  /**< 0x10, 4B: file offset to the zone block. */
} SaveHeader;                   /**< total size: 0x14 (20 bytes). */
```

## 5. Enum with per-value documentation

```c
/**
 * @brief Actor flag bits stored in @ref CombatActor::flags.
 */
typedef enum CombatActorFlags {
    CAF_NONE    = 0x00,  /**< No flags set. */
    CAF_VISIBLE = 0x01,  /**< Rendered this frame. */
    CAF_HOSTILE = 0x02,  /**< Attacks the party on sight. */
    CAF_DEAD    = 0x04,  /**< HP depleted; awaiting cleanup. */
    CAF_SCOUTED = 0x08   /**< Party has spotted this actor. */
} CombatActorFlags;
```

Enum values can also be documented with a preceding `/** */` block when they need prose.

## 6. Union / anonymous members

```c
/** @brief Tagged value read from a record field. */
typedef union RecordValue {
    long          asLong;   /**< Interpreted as a 32-bit signed integer. */
    unsigned char asBytes[4]; /**< Raw 4-byte little-endian representation. */
    void far     *asPtr;    /**< Interpreted as a far pointer. */
} RecordValue;
```

For an **anonymous** struct/union member, document the containing member; Doxygen
folds the anonymous fields into the parent.

## 7. Function with `@param` / `@return` / `@retval`

```c
/**
 * @brief   Look up a combat actor by id.
 * @details Linear scan of the zone actor pool. Empty slots (id 0xFFFF) are skipped.
 *
 * @param[in]  zone   Zone whose pool is searched; must be non-NULL.
 * @param[in]  id     Actor id to find.
 * @param[out] index  On success, receives the pool slot index. May be NULL.
 * @return     Pointer to the actor, or NULL if not found.
 * @retval     NULL   No actor with @p id exists in @p zone.
 * @note       O(n) in pool size; callers in a hot loop should cache the result.
 * @warning    The returned pointer is invalidated by @ref pagedrec_release.
 * @see        @ref czone_actor_count
 */
CombatActor *czone_find_actor(CombatZone *zone, unsigned short id, int *index);
```

Refer to a parameter inside prose with `@p id`. Direction tags: `[in]`, `[out]`,
`[in,out]`. Comma-join names to document several at once: `@param[in] x, y  Coordinates.`

## 8. Grouping into a module (`@defgroup` + `@{ @}`)

```c
/**
 * @defgroup combat_grid Combat Grid
 * @brief Tactical 50x50 grid: actor pools, geometry, collision.
 * @{
 */

CombatActor *czone_find_actor(CombatZone *zone, unsigned short id, int *index);
int          czone_actor_count(const CombatZone *zone);

/** @} */  /* end of combat_grid */
```

- Add a symbol declared *elsewhere* to the group with `@ingroup combat_grid` in its block.
- `@addtogroup combat_grid` (with `@{ @}`) appends to an existing group across files.
- `@name Grid helpers` + `@{ @}` groups members *within* one struct/file without a module.

## Cross-referencing (never hardcode a symbol)

**HARD RULE: every reference to a symbol is an `@ref`.** It is the only form Doxygen
verifies, so it is the only form allowed. Autolinks are not a "readable alternative" here —
they are banned for naming a symbol, because a rename orphans them silently.

| You want to reference… | Write | Never |
|---|---|---|
| A function | `@ref worldrender_sprite_billboard` | `worldrender_sprite_billboard()`, bare name |
| A type (struct/enum/union/typedef) | `@ref MeshPolygon` | `::MeshPolygon`, `MeshPolygon` |
| A struct/union member | `@ref PolyListBlock::bTag` | `PolyListBlock::bTag`, `@c bTag` |
| A macro / global / enum value | `@ref SHAPE_SCALE_UNITY` | bare name |
| A file | `@ref SHAPEBLD.H` | `SHAPEBLD.H`, `FILE.C:249` |
| A parameter, in prose | `@p vtxCount` | `vtxCount` |
| **Target not yet documented** | `@c name  TBD-ref: <why>` | `#tbd name` (it warns), `@ref name` (false warn) |

Rules:

- **Use `@ref <name>` for the symbol itself.** For a function, `@ref foo` (no parens — `@ref`
  renders the name link without them). For a member, `@ref Struct::member`.
- **Never a bare autolink** (`foo()`, `::Type`, `Struct::member`) and never `@see`/`@sa` for
  anything you want the lint to guard — they don't warn when broken (measured below).
- **Never pin a location.** No `FILE.C:249`, no "at line 249", no "see the loop below."
  Reference the *symbol* (`@ref r3d_mesh_part_polygons`), which relocates with its code, or
  the file (`@ref FILE.C`). A raw `FILE.C:NNN` is never acceptable.
- **`TBD-ref` is the only sanctioned escape hatch.** When a target genuinely isn't in
  Doxygen yet (its header lacks `@file`, or it's undocumented), write `@c name` plus the
  literal token `TBD-ref` and a reason. It's inert (no warning), greppable, and marks the
  spot to upgrade to `@ref` once the target is documented. Do **not** reach for `#name` —
  `#` is a live link operator and warns exactly like `@ref`.

### What the doc-lint actually catches (measured, not assumed)

Only an **explicit `@ref` / `\ref`** (and the `#name` operator) to a missing target warns
(`unable to resolve reference to 'X' for \ref command` / `explicit link request to 'X'
could not be resolved`). Everything else that fails to resolve is **silent**:

| Broken reference | Warns? |
|---|---|
| `@ref gone_symbol` | **yes** — fails the lint |
| `#gone_symbol` | **yes** (but use `@ref`; `#` is easy to fire by accident) |
| `fn()`, `::Type`, `Struct::member` autolinks | no |
| `@see gone()` / `@sa ::Gone` | no |
| `@c name`, `TBD-ref: name` (inert markers) | no — intended |

The lint additionally catches, regardless of `@ref`: `@param` names that don't match the
signature (`WARN_NO_PARAMDOC`), malformed `@commands`, and incomplete docs.

**`@ref` only resolves to a *documented* target — and `@file` gates that (ties back to
Golden Rule #1). This is why the `@ref` mandate must be sequenced.** With `EXTRACT_ALL =
NO`, **file-scope symbols — functions, globals, macros — are extracted only if their
declaring header has an `@file` block**; compound types (structs/enums/typedefs) and their
members are extracted regardless. So `@ref my_func` warns as *unresolved even though the
function exists* when its header is missing `@file`. **Order of operations:**

1. Land `@file` blocks on every header (`grep -L @file **/*.h **/*.H`) and grow doc coverage.
2. Convert references to `@ref`; use `@c name  TBD-ref:` for anything still undocumented.
3. Only once the tree lints clean, turn on `WARN_AS_ERROR = FAIL_ON_WARNINGS` as the gate.

Turn the gate on before step 1 and every undocumented target is a false positive — the lint
becomes noise and gets ignored.

Enforcement knobs (in the Doxyfile):

```ini
WARN_NO_PARAMDOC       = YES               # every @param must match a real parameter
WARN_IF_DOC_ERROR      = YES               # malformed @commands, bad @ref
WARN_AS_ERROR          = FAIL_ON_WARNINGS  # any warning → non-zero exit (CI gate)
```

Lint-only run (parse + warn, no doc output on disk — one cheap generator must stay on to
avoid Doxygen's own "No output formats selected" warning, so aim it at scratch):

```sh
( cat Doxyfile; printf 'GENERATE_HTML=NO\nGENERATE_XML=YES\nXML_OUTPUT=/tmp/dox\nHAVE_DOT=NO\nWARN_AS_ERROR=FAIL_ON_WARNINGS\n' ) | doxygen -
```

## Doxyfile for C

Generate a template, then set the C-relevant keys:

```sh
doxygen -g Doxyfile      # write a default Doxyfile
doxygen Doxyfile         # build docs into ./html
```

Minimal C-oriented overrides:

```ini
PROJECT_NAME           = "MyProject"
OPTIMIZE_OUTPUT_FOR_C  = YES    # C mode: "Functions" not "Member Functions", etc.
JAVADOC_AUTOBRIEF      = YES    # first sentence = brief (skip explicit @brief)
TYPEDEF_HIDES_STRUCT   = YES    # document `typedef struct {..} Foo;` under the name Foo
EXTRACT_ALL            = YES    # document even undocumented items (good while filling in)
EXTRACT_STATIC         = YES    # include file-static functions/vars
INPUT                  = ./src ./include
FILE_PATTERNS          = *.c *.h
RECURSIVE              = YES
GENERATE_HTML          = YES
GENERATE_LATEX         = NO
```

Notes:
- `EXTRACT_ALL = YES` lists undocumented items too — useful early, but it hides *missing*
  docs. Turn it OFF once coverage is good so gaps surface as warnings.
- `TYPEDEF_HIDES_STRUCT = YES` makes `typedef struct {..} Foo;` appear as `Foo`, not as an
  anonymous struct plus a typedef.

## Gotchas checklist

- [ ] **`@file` present** in every header/source you want file-level symbols from —
      otherwise globals, typedefs, and macros are silently undocumented.
- [ ] **`/**< */` has the `<`** and comes *after* the member on the same line (or the next
      line). A plain `/** */` after a member documents the *next* item, not the previous one.
- [ ] **Lines wrap at 80 columns** — no doc-comment line exceeds 80; overflow a trailing
      `/**< */` by switching to a preceding `/** */` block. Never split an `@ref`/`@p`
      token across lines (`ReflowComments` is off, so this is a manual check).
- [ ] **Brief/detail**: rely on `JAVADOC_AUTOBRIEF` (first sentence) *or* explicit
      `@brief`/`@details`, not a confusing mix. A blank line separates brief from detail.
- [ ] **C, not C++**: set `OPTIMIZE_OUTPUT_FOR_C = YES`; use `typedef struct` idioms and
      `TYPEDEF_HIDES_STRUCT` rather than C++ class docs.
- [ ] **Every parameter has a `@param` line** stating its contract (range, units,
      nullability, ownership) — not a restatement of its name.
- [ ] **No structural command needed** when the block is adjacent to its item. Reach for
      `@struct`/`@enum`/`@union`/`@var`/`@typedef`/`@fn` only for detached comments.
- [ ] **`\` vs `@`**: both prefixes are equivalent (`\brief` == `@brief`). Stay consistent.
- [ ] **HARD RULE — every symbol reference is `@ref`.** Functions, types, members, macros,
      globals, files: `@ref name` (never bare prose, never a `fn()`/`::Type` autolink, never
      `@see`/`@sa` for a guarded ref — those don't warn when broken). **Zero** `FILE.C:NNN`
      pins or "see line N" pointers. Undocumented target → `@c name  TBD-ref:` marker, never
      `#tbd`. Sequence: `@file`/doc coverage first, then the `WARN_AS_ERROR` gate.
```