# Building Betrayal at Krondor

This document describes how to compile `KRONDOR.EXE`, `SX.OVL` and `VMCODE.OVL`.

## Background

Betrayal at Krondor is a triple-compiler beast. The original was built with the following:

- Borland C++ 3.1 (The main compiler)
- Borland C++ 3.0
- Borland C++ 2.0 (protected-mode)
- TASM (Turbo Assembler)

Dynamix already had a long lineage of 3D simulators, and my guess is they reused a lot of that code for Betrayal at Krondor. They probably never bothered recompiling their older libraries with BCC 3.1, so a few islands still use 3.0 and 2.0.

Unfortunately for us, no single emulator can run all of them without crashing:

| backend | `bcc31` + TASM (the bulk) | `bccx` (BC++ 2.0/3.0) |
|---|:--:|:--:|
| DOSBox | ✅ | ❌ `JMP Illegal descriptor type` |
| qemu `-enable-kvm` | ✅ | ❌ `Bad selector` (#GP) |
| qemu `-accel tcg` | ❌ TASM never emits `.OBJ` | ✅ (software, slow) |

So the build is split per compiler: **KVM** for `bcc31` + TASM (the ~213-object bulk), **TCG** for the BC++ 2.0/3.0 island (~18 objects), then link under KVM.

We include a Python CLI (`uv run bak build`) that handles all that plumbing automatically.

## Requirements

Building this project requires the following:

- uv (Python)
- QEMU
- Borland C++ 3.1
- Borland C++ 3.0
- Borland C++ 2.0
- FreeDOS
- The original *Betrayal at Krondor* game files (only if you actually want to play it)

Sourcing all those compilers can be a pain, so I've packaged them into a GitHub release. The project also uses Nix, which is the easiest way to get everything running.

### Option 1: Nix

The easiest. `flake.nix` pulls `uv`, `qemu` and `mtools`, and fetches the pinned toolchain tarball for you. With Nix (flakes enabled):

```
nix develop        # or: direnv allow
uv run bak build
```

### Option 2: Manual install + pre-packaged toolchain

Install `uv`, `qemu` and `mtools` from your package manager yourself, then grab the pre-packaged toolchain from the GitHub release and drop it in `./toolchain` (or point `$BAK_TOOLCHAIN` at it):

```
curl -L <release-url>/toolchain.tar.gz | tar xz   # -> ./toolchain
uv run bak build
```

### Option 3: Full self-sourced

Install `uv`, `qemu` and `mtools` from your package manager yourself. This time there's no pre-packaged tarball, so you also source the compilers and assemble `./toolchain` in the layout the CLI expects. Where to get them:

- Borland C++ 3.0 and 3.1: <https://winworldpc.com/product/borland-c/30>
- Borland C++ 2.0: <https://winworldpc.com/product/borland-c/20>
- FreeDOS: <https://www.freedos.org/download/>

Then lay it out like this:

```
toolchain/
  bc31/     BC++ 3.1: BIN/ (BCC, CPP, TASM, TLINK, MAKE, MAKER, DPMI host), INCLUDE/, LIB/
  bc30/     BC++ 3.0: BCC.EXE, CPP.EXE, DPMI trio
  bc20/     BC++ 2.0: BCCX.EXE + BCCX.OVY + TKERNEL.EXE (the 286 extender)
  freedos/  freedos.img + EXIT.COM
```

Then `uv run bak build`.


## Editor support

This project's custom build system is invisible to your editor, so code intelligence (go-to-definition, completion, inline errors) won't work out of the box. Generate a clangd compilation database with:

```
uv run bak compdb
```

This writes a `compile_commands.json` that any clangd-based editor (VS Code, Neovim, CLion, ...) picks up automatically. It records absolute, machine-local paths, so it's gitignored; re-run it whenever you add files or move the project.