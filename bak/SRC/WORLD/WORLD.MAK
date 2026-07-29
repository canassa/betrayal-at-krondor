# WORLD module -- object list + rules (byte-verified recipes; hand-curate).
WORLD_OBJS = OUT\E_7878.OBJ

OUT\E_7878.OBJ : SRC\WORLD\CURSOR\E_7878.ASM
	$(AS) $(ASFLAGS) SRC\WORLD\CURSOR\E_7878.ASM,OUT\E_7878.OBJ
