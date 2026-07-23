# CLAUDE.md

Betrayal at Krondor, reconstructed from the 1993 DOS binaries and rebuilt **byte-for-byte** identical with the period Borland toolchain. Two releases build from this one tree: 1.00 (floppy) and 1.02 (CD-ROM, carried as `#ifdef V102CD` source guards).

## The prime rule: stay byte-identical

Any change under `bak/SRC/` must keep `KRONDOR.EXE`, `VMCODE.OVL` and `SX.OVL` byte-identical to the shipped originals — for **both** releases: the default 1.00 build and the `--version 102` CD build. A change isn't done until both verify. Comments and names cost nothing (they don't reach codegen); code, declaration order, and data layout are load-bearing.

## CLI commands

```
uv run bak build                # build all three 1.00 artifacts and verify them by size + sha256
uv run bak build --version 102  # build + verify the 1.02 CD KRONDOR.EXE (OVLs are version-identical)
uv run bak diff <FILE.C>        # disassembly diff of one OBJ vs the last green build — debug a byte-match break
uv run bak lint                 # naming-convention check (clang-tidy, check-only)
uv run bak rmf <RMF>            # explore/debug the shipped data files: list/extract resources, dump a .TBL model, decode DDX dialog text
```

## Naming conventions

The project currently has a mix of several naming conventions and Hungarian notation. **Those are outdated**, the following is the standard from now on:

| Kind | Convention | Example |
|---|---|---|
| Trivial variable | one letter (if unclear, make it a local) | `i`, `n`, `c` |
| Local variable | `camelCase` | `count`, `curSlot` |
| Global variable | `g_` + `camelCase` (always, even pointers) | `g_modelTables`, `g_videoDriver` |
| Const / macro | `SCREAMING_SNAKE_CASE` | `MAX_ACTORS` |
| Struct / enum | bare `PascalCase`, no module prefix | `Model`, `ModelTable` |
| Struct member | `camelCase` | `kind`, `lodCount` |
| Enum value | `SCREAMING_SNAKE_CASE` | `LOC_CHEST` |
| Public function | `module_snake_case`, declared in the module `.H` | `pagedrec_get` |
| Private function | `static`, `snake_case` | `static build_lod` |

## Rules

- **Never add comments** — Never add comments to the code unless instructed to do so, all documentation is human-reviwed.
