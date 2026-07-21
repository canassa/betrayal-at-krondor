---
name: commit
description: Commit (and push) staged work in this repo's house style — an emoji-prefixed subject line plus a short why-focused body. Use whenever the user asks to commit, save, or "commit and push". Picks the single best-fit emoji from the project map, writes a tight body (no wall of text), commits, and pushes — without asking for confirmation.
---

# commit

Commit the current work in this project's format, then push. **When the user asks
to commit, commit AND push — don't ask for confirmation, don't stop to summarize
first.**

## Message format

```
<emoji> <short subject>

<body>
```

- **Subject** — one line, imperative mood, lower-ish case, no trailing period.
  Keep it short and concrete ("migrate lzw_get_next_code", not "did some work").
- **Body** — what was done and *why*, plus context only if it's not obvious.
  **No wall of text. No exhaustive list of every change — that's what the diff is
  for.** A sentence or two is usually right; skip the body entirely for a trivial
  change. Explain intent, not mechanics.

## Emoji map

Pick the **single** emoji that best fits the dominant change. If a commit spans
two areas, choose the one that's the point of the commit.

| Emoji | Use for |
|-------|---------|
| 🚚 | A KRONDOR function migrated (Phase 3: C/asm leaf reconstructed + byte-verified) |
| 🔍 | Ghidra reverse-engineering — naming/typing functions, globals, structs, switch fixes |
| 🐍 | `bak` CLI work — a command, sync generators, the DB layer, the cgen emitter |
| 🏗️ | Structural work — refactors, build-system / toolchain plumbing |
| 🐛 | Bug fix |
| ✅ | Tests — add or fix |
| 🤖 | AI tooling — skills, agents, workflows, prompts |
| 📝 | Docs — README, `CLAUDE.md`, code comments |
| 🧹 | Cleanup — remove dead files, dedupe, `.gitignore`, LFS housekeeping |
| 🎨 | Formatting / style only (no behavior change) |
| 🗃️ | DB schema, migrations, the ledger |
| 📦 | Dependencies / lockfiles / `flake.nix` |
| 🔧 | Config — settings, `.mcp.json`, git plumbing |
| 🔊 | Sound/music driver work (SX.OVL) |
| 🖥️ | Video driver / rendering work (VMCODE.OVL) |

If nothing fits, use ✨ and pick a clear subject.

## Procedure

1. **See what's there.** `git status` + `git diff` (and `git diff --cached`). If
   nothing is staged, stage the relevant changes (`git add -A` for a normal
   "commit everything", or the specific paths the user named).
2. **Sanity-check the staged set** — no scratch, build artifacts, secrets, or
   stray files slipping in. The repo's `.gitignore`s cover the usual ones; if
   something odd is staged, flag it rather than committing it blindly.
3. **Pick the emoji** from the map and **write the message** (subject + tight
   body) per the rules above.
4. **Commit** with that message, then **`git push`**. Report the short hash and
   subject when done.

## Notes

- Use a HEREDOC for the message so the blank line and any punctuation survive:
  `git commit -F - <<'EOF' … EOF`.
- If the push is rejected (remote moved), pull/rebase and push again; don't
  force-push unless the user says so.
- Large binaries are LFS-tracked (`.gitattributes`); just commit normally — the
  filter handles them.
