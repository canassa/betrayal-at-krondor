Build output directory: every .OBJ, KRONDOR.EXE and KRONDOR.MAP land here.
This file only exists so the (otherwise empty) directory survives git; the
1993 build simply had the directory on disk.

Note for MAKE archaeologists: creating this directory from a makefile target
(`-md OUT`) wedges Borland MAKE 3.6 under FreeDOS -- the spawned COMMAND.COM
never returns control (verified 2026-07-06) -- so the directory ships in the
tree instead.
