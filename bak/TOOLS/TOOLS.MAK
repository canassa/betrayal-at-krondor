# TOOLS.MAK -- build rules for the in-tree build tools (compiled in the DOS VM).
#
# Currently one tool: PACKOVL, the Dynamix "RES" resource-archive packer that
# weaves the driver chunk images into VMCODE.OVL / SX.OVL (see TOOLS\PACKOVL\
# PACKOVL.C for the full format + algorithm).  It is a single C89 translation
# unit built with the vendored Borland C++ 3.1 in MEDIUM model (-mm) -- the tree's
# LIB ships only C0M.OBJ / CM.LIB (the medium-model startup + RTL), so -mm is
# mandatory; no other model's runtime exists here.  It uses only the C RTL
# (stdio/stdlib/string) and NO floating point, so:
#   -IC:\BC\INCLUDE  RTL headers        -LC:\BC\LIB  medium startup+RTL (C0M/CM)
#   -f-              no FP: PACKOVL is pure integer, and the vendored LIB ships no
#                    FP-emulator library (EMU.LIB), which bcc would otherwise link.

OUT\PACKOVL.EXE : TOOLS\PACKOVL\PACKOVL.C
	$(BC31) -mm -f- -IC:\BC\INCLUDE -LC:\BC\LIB -eOUT\PACKOVL.EXE TOOLS\PACKOVL\PACKOVL.C
