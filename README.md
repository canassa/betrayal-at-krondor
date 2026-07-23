<h1 align="center">
  <img src="https://github.com/user-attachments/assets/017732ab-3e84-4ee1-9780-3a3c0f831588" width="600" alt="Betrayal at Krondor">
</h1>

<p align="center">A byte-perfect recompilation of the 1993 classic <em>Betrayal at Krondor</em>.</p>

## About

This is a reconstruction of the original *Betrayal at Krondor* source, recovered by reverse-engineering the DOS binaries. It reaches a full byte-match with the original, reproducing the shipped binaries exactly. We even wind the computer's clock back to June 16, 1993 during linking!

No shortcuts were taken: any assembly in this project exists because the original was written in assembly too.

The goals are educational: digital archaeology and preservation. It won't add support for modern systems or mod the game. I plan to do that in a separate fork.

## Supported releases

The following releases build byte-identically from this one tree:

- **1.00** (floppy, June 16, 1993) — `c943fd895a57`
- **1.02** (CD-ROM, March 21, 1994) — `e254770143e0`

## Asset viewer

Reverse-engineering the code is half the work (okay, maybe more). *Betrayal at Krondor* is a big game, with lots of assets and a branching, data-driven dialogue system. To explore all that, this project includes a browser-based asset viewer:

<img width="828" height="420" alt="viewer" src="https://github.com/user-attachments/assets/84f9ce3e-ddc7-4ff2-9914-03e2fb59853a" />

Drop your own game files into `viewer/data/` and run `uv run bak viewer`, then open the printed URL.

## Building the project

See [BUILDING](docs/BUILDING.md)

## Contributing

The project has achieved a full byte-match, but it isn't finished: the code still carries decompilation artifacts, baked-in constants, and wrong names. PRs that improve code quality are welcome. See [`ACTORREC.C`](bak/SRC/WORLD/ACTOR/ACTORREC.C) and [`ACTORREC.H`](bak/SRC/WORLD/ACTOR/ACTORREC.H) for examples of clean modules.

## Acknowledgements

This reconstruction builds on earlier reverse-engineering of *Betrayal at Krondor*:

- **Guido de Jong**, for xbak
- **Emmanuel Jacyna**, for BaKGL

## License & legal status

The original work in this repository is released under the MIT License (see
[`LICENSE`](LICENSE)).

**This project does not grant, and cannot grant, any rights to third-party
material:**

- ***Betrayal at Krondor***, its code, data, and assets are copyright © 1993
  Dynamix, Inc. / Sierra On-Line. The reconstructed C source under `bak/SRC/`
  is a reverse-engineered derivative of that copyrighted program, provided for
  research, preservation, and interoperability study. This repository contains
  **no original game data files**; to build a runnable binary or to use the
  viewer you must supply your own legally-obtained copy of the game.

This is an independent preservation effort and is not affiliated with or
endorsed by Dynamix, Sierra, or their successors.
