# RECIPES.MAK -- compiler binaries + codegen flag bands (!included by every module
# .MAK). The per-file -zC<class> is appended in each object rule (the code-segment name
# is per-source, not per-band). Every band was byte-verified against the shipped EXE;
# this file is the source of truth -- no generator, hand-curate from here on.

BC31 = bcc
BC30 = c:\bc30\bcc
BC20 = c:\bc20\bccx
AS   = tasm
ASFLAGS = /mx /m /iINCLUDE
# INCLUDE = the project headers (bak\INCLUDE); C:\BC\INCLUDE = the Borland RTL headers
INC  = -IINCLUDE -IC:\BC\INCLUDE

# --- flag bands: $(<BAND>) = compiler + flags (each object rule appends -c -zC<class>) ---
C_3O1Y   = $(BC31) -3 -O1 -Y -i64 -k -mm
C_O2     = $(BC31) -O2 -i64 -k -mm
C_O22    = $(BC31) -O2 -i64 -mm
C_1O1Y   = $(BC31) -1 -O1 -Y -i64 -k -mm
C_3NY    = $(BC31) -3 -N -Y -i64 -k -mm
C_1      = $(BC31) -1 -i64 -k -mm
C_1OK    = $(BC31) -1 -O -i64 -k- -mm
C_GOZ    = $(BC31) -G -O -Z -k -mm
C_BOBOEO = $(BC31) -B -Ob -Ol -Os -Y -i64 -k -mm
D_STD    = $(BC30) -mm
D_OZK    = $(BC30) -O -Z -k- -mm
D_GOZ    = $(BC30) -G -O -Z -k -mm
X_GO     = $(BC20) -G -O -mm
X_GOZ    = $(BC20) -G -O -Z -mm
