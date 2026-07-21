"""bak build CLI — a 1993-authentic Borland MAKE build of KRONDOR.EXE.

`bak build` stages the DOS-mountable ``bak/`` tree + the Borland toolchain into a
FreeDOS qemu VM, runs period MAKE + TLINK, and verifies the linked EXE is
byte-identical to the shipped game. No host-side object post-processing.
"""
