# DRIVERS.MAK -- builds the loadable .OVL driver chunk inputs (VMCODE video +
# SX audio) that PACKOVL then packs into VMCODE.OVL / SX.OVL.
#
# Each driver is ONE hand-written TASM module.  Both archives use the same recipe:
#   tasm -> tlink -> MZ .EXE   (PACKOVL strips the MZ header to the flat ORG-0
#   image, then LZW-packs it).  The SX drivers are .MODEL TINY / ORG 0 flat
#   images; linked as .EXE and MZ-stripped they yield the exact headerless chunk
#   (a .COM link would need ORG 100h and change every offset).
# All output lands in OUT\ (OUT\VGA.EXE, OUT\GMD.EXE, ...), which is exactly what
# SRC\DRIVERS\VMCODE.PAK and SRC\DRIVERS\SX.PAK name as PACKOVL's inputs.
#
# This file is !included by the top-level MAKEFILE and IS part of the build: the
# `ovls` / `all` targets depend on these .EXE outputs, and `bak build` runs
# them. (There is no host-side repack step: PACKOVL.EXE -- built in the same DOS
# VM, see TOOLS\TOOLS.MAK -- packs the archives, so .OVL byte-identity is verified
# end-to-end by the launcher's fingerprint check.)

AS = tasm
VASM = /m /iSRC\DRIVERS\VMCODE
SASM = /m
OUT = OUT

VMCODE = cga ega eva evg heg mcg tan vga
SX     = adl ads apa asb gmd m32 nld pro ps1 sbp std

VMEXE = $(OUT)\CGA.EXE $(OUT)\EGA.EXE $(OUT)\EVA.EXE $(OUT)\EVG.EXE \
        $(OUT)\HEG.EXE $(OUT)\MCG.EXE $(OUT)\TAN.EXE $(OUT)\VGA.EXE
SXEXE = $(OUT)\ADL.EXE $(OUT)\ADS.EXE $(OUT)\APA.EXE $(OUT)\ASB.EXE $(OUT)\GMD.EXE \
        $(OUT)\M32.EXE $(OUT)\NLD.EXE $(OUT)\PRO.EXE $(OUT)\PS1.EXE $(OUT)\SBP.EXE $(OUT)\STD.EXE

drivers : $(VMEXE) $(SXEXE)

# --- VMCODE video drivers: TASM (gfxctx.inc via /i) -> TLINK -> MZ .EXE ---
$(OUT)\CGA.EXE : SRC\DRIVERS\VMCODE\CGA.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\CGA.ASM,$(OUT)\CGA.OBJ
	tlink $(OUT)\CGA.OBJ,$(OUT)\CGA.EXE,$(OUT)\CGA.MAP
$(OUT)\EGA.EXE : SRC\DRIVERS\VMCODE\EGA.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\EGA.ASM,$(OUT)\EGA.OBJ
	tlink $(OUT)\EGA.OBJ,$(OUT)\EGA.EXE,$(OUT)\EGA.MAP
$(OUT)\EVA.EXE : SRC\DRIVERS\VMCODE\EVA.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\EVA.ASM,$(OUT)\EVA.OBJ
	tlink $(OUT)\EVA.OBJ,$(OUT)\EVA.EXE,$(OUT)\EVA.MAP
$(OUT)\EVG.EXE : SRC\DRIVERS\VMCODE\EVG.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\EVG.ASM,$(OUT)\EVG.OBJ
	tlink $(OUT)\EVG.OBJ,$(OUT)\EVG.EXE,$(OUT)\EVG.MAP
$(OUT)\HEG.EXE : SRC\DRIVERS\VMCODE\HEG.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\HEG.ASM,$(OUT)\HEG.OBJ
	tlink $(OUT)\HEG.OBJ,$(OUT)\HEG.EXE,$(OUT)\HEG.MAP
$(OUT)\MCG.EXE : SRC\DRIVERS\VMCODE\MCG.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\MCG.ASM,$(OUT)\MCG.OBJ
	tlink $(OUT)\MCG.OBJ,$(OUT)\MCG.EXE,$(OUT)\MCG.MAP
$(OUT)\TAN.EXE : SRC\DRIVERS\VMCODE\TAN.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\TAN.ASM,$(OUT)\TAN.OBJ
	tlink $(OUT)\TAN.OBJ,$(OUT)\TAN.EXE,$(OUT)\TAN.MAP
$(OUT)\VGA.EXE : SRC\DRIVERS\VMCODE\VGA.ASM
	$(AS) $(VASM) SRC\DRIVERS\VMCODE\VGA.ASM,$(OUT)\VGA.OBJ
	tlink $(OUT)\VGA.OBJ,$(OUT)\VGA.EXE,$(OUT)\VGA.MAP

# --- SX audio drivers: TASM (.MODEL TINY, ORG 0) -> TLINK -> MZ .EXE (stripped) ---
$(OUT)\ADL.EXE : SRC\DRIVERS\SX\ADL.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\ADL.ASM,$(OUT)\ADL.OBJ
	tlink $(OUT)\ADL.OBJ,$(OUT)\ADL.EXE,$(OUT)\ADL.MAP
$(OUT)\ADS.EXE : SRC\DRIVERS\SX\ADS.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\ADS.ASM,$(OUT)\ADS.OBJ
	tlink $(OUT)\ADS.OBJ,$(OUT)\ADS.EXE,$(OUT)\ADS.MAP
$(OUT)\APA.EXE : SRC\DRIVERS\SX\APA.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\APA.ASM,$(OUT)\APA.OBJ
	tlink $(OUT)\APA.OBJ,$(OUT)\APA.EXE,$(OUT)\APA.MAP
$(OUT)\ASB.EXE : SRC\DRIVERS\SX\ASB.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\ASB.ASM,$(OUT)\ASB.OBJ
	tlink $(OUT)\ASB.OBJ,$(OUT)\ASB.EXE,$(OUT)\ASB.MAP
$(OUT)\GMD.EXE : SRC\DRIVERS\SX\GMD.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\GMD.ASM,$(OUT)\GMD.OBJ
	tlink $(OUT)\GMD.OBJ,$(OUT)\GMD.EXE,$(OUT)\GMD.MAP
$(OUT)\M32.EXE : SRC\DRIVERS\SX\M32.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\M32.ASM,$(OUT)\M32.OBJ
	tlink $(OUT)\M32.OBJ,$(OUT)\M32.EXE,$(OUT)\M32.MAP
$(OUT)\NLD.EXE : SRC\DRIVERS\SX\NLD.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\NLD.ASM,$(OUT)\NLD.OBJ
	tlink $(OUT)\NLD.OBJ,$(OUT)\NLD.EXE,$(OUT)\NLD.MAP
$(OUT)\PRO.EXE : SRC\DRIVERS\SX\PRO.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\PRO.ASM,$(OUT)\PRO.OBJ
	tlink $(OUT)\PRO.OBJ,$(OUT)\PRO.EXE,$(OUT)\PRO.MAP
$(OUT)\PS1.EXE : SRC\DRIVERS\SX\PS1.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\PS1.ASM,$(OUT)\PS1.OBJ
	tlink $(OUT)\PS1.OBJ,$(OUT)\PS1.EXE,$(OUT)\PS1.MAP
$(OUT)\SBP.EXE : SRC\DRIVERS\SX\SBP.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\SBP.ASM,$(OUT)\SBP.OBJ
	tlink $(OUT)\SBP.OBJ,$(OUT)\SBP.EXE,$(OUT)\SBP.MAP
$(OUT)\STD.EXE : SRC\DRIVERS\SX\STD.ASM
	$(AS) $(SASM) SRC\DRIVERS\SX\STD.ASM,$(OUT)\STD.OBJ
	tlink $(OUT)\STD.OBJ,$(OUT)\STD.EXE,$(OUT)\STD.MAP
