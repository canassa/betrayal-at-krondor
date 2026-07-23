Build output directory for the v1.02 CD relink: every OUT102\*.OBJ (the TUs
recompiled with -DV102CD), KRONDOR.EXE and KRONDOR.MAP land here. This file only
exists so the (otherwise empty) directory survives git; the 1994 CD build simply
had the directory on disk.

Note for MAKE archaeologists: creating this directory from a makefile target
(`-md OUT102`) wedges Borland MAKE 3.6 under FreeDOS -- the spawned COMMAND.COM
never returns control (verified 2026-07-06) -- so the directory ships in the
tree instead. See OUT\README.TXT.
