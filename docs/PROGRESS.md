# Module status

Every C module in the reconstruction, with how far the cleanup described in
[CONTRIBUTING](../CONTRIBUTING.md) has got. Assembly modules (`.ASM`) are tracked
separately; they follow the `asm-documenter` conventions, not these.

| | |
|---|---|
| ✅ | Done: named, typed, documented. Use these as references. |
| 🚧 | In progress: partly cleaned or partly documented; check `git log` before starting. |
| ⬜ | Untouched. Names, constants and structure are still as reconstructed. |

Status is a read of the tree, not a promise: a ⬜ module may still have had a pass of
global renames from an earlier sweep. `Lines` counts the `.C` and `.H` together and is
the only difficulty signal offered. A 200-line module is an afternoon, a 2000-line one
is a project.

Headers with no `.C` are declaration headers for an assembly module; they mostly need a
`@file` block and documented prototypes, which makes them good first contributions.


### `bak/SRC/AUDIO`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CDAUDIO` | .H | 12 | ⬜ |

### `bak/SRC/AUDIO/CHAN`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `AUDCCHG` | .C + .H | 22 | ⬜ |
| `AUDCHBYT` | .C + .H | 22 | ⬜ |
| `AUDCHFID` | .C + .H | 19 | ⬜ |
| `AUDCHORD` | .C + .H | 22 | ⬜ |
| `AUDCHWRD` | .C + .H | 22 | ⬜ |
| `AUDCMD07` | .C + .H | 15 | ⬜ |
| `AUDSETIN` | .C + .H | 29 | ⬜ |
| `AUDSTPCT` | .C + .H | 25 | ⬜ |
| `AUDSTPID` | .C + .H | 25 | ⬜ |
| `SFXCHAN` | .C + .H | 39 | ⬜ |
| `SFXEVENT` | .C + .H | 15 | ⬜ |

### `bak/SRC/AUDIO/DRIVER`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `DISP35E0` | .H | 9 | ⬜ |
| `MIDI` | .H | 77 | ⬜ |
| `MUSDISP` | .H | 16 | ⬜ |
| `SNDDRV` | .H | 10 | ⬜ |

### `bak/SRC/AUDIO/ENGINE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `AUDDRVST` | .C + .H | 69 | ⬜ |
| `AUDIO` | .C + .H | 491 | ⬜ |
| `AUDITER` | .C + .H | 57 | ⬜ |
| `AUDSTART` | .C + .H | 76 | ⬜ |
| `AUDSTOP` | .C + .H | 65 | ⬜ |
| `AUDSTPFL` | .C + .H | 42 | ⬜ |
| `AUDSTPND` | .C + .H | 41 | ⬜ |

### `bak/SRC/AUDIO/MUSIC`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `MUSCREAT` | .C + .H | 29 | ⬜ |
| `MUSFADE` | .C + .H | 36 | ⬜ |
| `MUSSTART` | .C + .H | 22 | ⬜ |
| `MUSSTOP` | .C + .H | 19 | ⬜ |
| `SNDLADV` | .C + .H | 18 | ⬜ |

### `bak/SRC/AUDIO/RES`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `AUDLOAD` | .C + .H | 69 | ⬜ |
| `AUDRES` | .C + .H | 235 | ⬜ |
| `AUDRESIN` | .C + .H | 176 | ⬜ |
| `AUDRESLD` | .C + .H | 90 | ⬜ |
| `PASCREC` | .C + .H | 13 | ⬜ |
| `POOL` | .C + .H | 109 | ⬜ |

### `bak/SRC/AUDIO/SFX`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `SFXFIND` | .C + .H | 21 | ⬜ |
| `SFXPLAY` | .C + .H | 44 | ⬜ |
| `SFXSTOP` | .C + .H | 26 | ⬜ |
| `SFXSTPAL` | .C + .H | 23 | ⬜ |

### `bak/SRC/AUDIO/SND`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `SFXTERM` | .C + .H | 43 | ⬜ |
| `SNDBUFAL` | .C + .H | 33 | ⬜ |
| `SNDBUFFR` | .C + .H | 26 | ⬜ |
| `SNDINIT` | .C + .H | 50 | ⬜ |
| `SNDINST` | .C + .H | 59 | ⬜ |
| `SNDSTOP` | .C + .H | 60 | ⬜ |

### `bak/SRC/CHAR`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CHARSCRN` | .C + .H | 567 | ⬜ |
| `STAT` | .C + .H | 524 | ⬜ |

### `bak/SRC/COMBAT/ACTOR`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CACTOR` | .C + .H | 2204 | ⬜ |

### `bak/SRC/COMBAT/AI`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CBTAI` | .C + .H | 416 | ⬜ |
| `CBTAIACT` | .C + .H | 383 | ⬜ |
| `CBTAITRN` | .C + .H | 398 | ⬜ |
| `CMBTAI` | .C + .H | 544 | ⬜ |

### `bak/SRC/COMBAT/ARENA`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `COMBAT` | .C + .H | 2765 | ⬜ |

### `bak/SRC/COMBAT/ENC`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CBENC` | .C + .H | 1234 | ⬜ |

### `bak/SRC/COMBAT/GRID`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CMBTGRID` | .C + .H | 1736 | ⬜ |

### `bak/SRC/COMBAT/SPELL`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CSPELL` | .C + .H | 2584 | ⬜ |
| `HEXANIM` | .C + .H | 108 | ⬜ |
| `SPELLFX` | .C + .H | 460 | ⬜ |

### `bak/SRC/COMBAT/STATS`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CBSTAT` | .C + .H | 673 | ⬜ |
| `MONSTAT` | .C + .H | 97 | ⬜ |

### `bak/SRC/DIALOG`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `ASKABOUT` | .C + .H | 548 | ⬜ |
| `DIALOG` | .C + .H | 1562 | ⬜ |
| `EVTCOND` | .C + .H | 475 | ⬜ |

### `bak/SRC/GAME`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `MAINDATA` | .C + .H | 30 | 🚧 |

### `bak/SRC/GAME/ACTOR`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `ACTOR` | .H | 215 | 🚧 |
| `ACTORREC` | .C + .H | 118 | ✅ |
| `ACTSPAWN` | .C + .H | 358 | ⬜ |
| `ITEMTBL` | .C + .H | 214 | ⬜ |

### `bak/SRC/GAME/ENC`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `HOTSPOT` | .C + .H | 1241 | ⬜ |
| `RGNENC` | .C + .H | 926 | ⬜ |
| `WORLDDOR` | .C + .H | 106 | ⬜ |

### `bak/SRC/GAME/STATE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `GMAIN` | .C + .H | 796 | ⬜ |
| `GSTATE` | .C + .H | 547 | 🚧 |
| `SAVEGAME` | .C + .H | 257 | ⬜ |
| `TIMERPL` | .C + .H | 98 | ⬜ |

### `bak/SRC/GAME/WORLD`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `MAP` | .C + .H | 586 | ⬜ |
| `WORLDCRS` | .C + .H | 281 | ⬜ |
| `WORLDLP` | .C + .H | 519 | ⬜ |
| `WORLDMOV` | .C + .H | 843 | ⬜ |

### `bak/SRC/GEN`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `GFXCTX` | .H | 13 | ⬜ |
| `RNDVTBL` | .H | 10 | ⬜ |
| `VIDVTBL` | .H | 55 | ⬜ |

### `bak/SRC/GFX/DRIVER`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `PALDAC` | .H | 10 | ⬜ |
| `PALDRV` | .C + .H | 213 | ⬜ |
| `VIDDET` | .H | 10 | ⬜ |
| `VIDDRV` | .C + .H | 130 | ⬜ |
| `VIDINIT` | .H | 13 | ⬜ |
| `VIDMODE` | .H | 10 | ⬜ |
| `VTHUNKS` | .H | 14 | ⬜ |

### `bak/SRC/GFX/FONT`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `FONT` | .C + .H | 379 | ⬜ |

### `bak/SRC/GFX/PALETTE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `PALCYC` | .C + .H | 24 | ⬜ |
| `PALETTE` | .C + .H | 386 | ⬜ |

### `bak/SRC/GFX/RASTER`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CIRCLE` | .C + .H | 162 | ⬜ |
| `DRAWLINE` | .H | 8 | ⬜ |
| `GOURAUD` | .H | 12 | ⬜ |
| `ILBMPACK` | .H | 8 | ⬜ |
| `ILBMSAVE` | .C + .H | 130 | ⬜ |
| `PIXEL` | .H | 9 | ⬜ |
| `POLYCLIP` | .H | 8 | ⬜ |
| `POLYFILL` | .C + .H | 27 | ⬜ |
| `POLYGON` | .H | 32 | ⬜ |
| `POLYRAST` | .H | 11 | ⬜ |
| `PRESENT` | .H | 8 | ⬜ |
| `VGABLIT` | .H | 11 | ⬜ |
| `VGAFILL` | .H | 9 | ⬜ |
| `VGARESET` | .C + .H | 26 | ⬜ |

### `bak/SRC/GFX/SCREEN`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `DISSOLV` | .C + .H | 82 | ⬜ |
| `SCREEN` | .C + .H | 551 | ⬜ |

### `bak/SRC/GFX/SPRITE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `BLITAA` | .C + .H | 57 | ⬜ |
| `BLITCHNK` | .H | 9 | ⬜ |
| `DECOMP` | .H | 10 | ⬜ |
| `PALBLEND` | .H | 8 | ⬜ |
| `RECTSPR` | .H | 9 | ⬜ |
| `RESBLIT` | .C + .H | 305 | ⬜ |
| `ROTBLIT` | .H | 30 | ⬜ |
| `SPRTHNKS` | .H | 11 | ⬜ |
| `STRBLIT` | .C + .H | 195 | ⬜ |

### `bak/SRC/INPUT`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `INT00` | .H | 14 | ⬜ |
| `JOYSTICK` | .H | 30 | ⬜ |
| `KEYBOARD` | .H | 25 | ⬜ |
| `MOUSE` | .H | 33 | ⬜ |
| `TIMER` | .H | 21 | ⬜ |
| `WCURSOR` | .C + .H | 1436 | ⬜ |

### `bak/SRC/IO`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `DOSRW` | .H | 33 | ✅ |
| `IOCHUNK` | .C + .H | 47 | ⬜ |
| `RESOURCE` | .C + .H | 980 | ✅ |

### `bak/SRC/R3D/ACTOR`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `ACTMOTN` | .C + .H | 136 | ⬜ |
| `ACTOROVL` | .C + .H | 82 | ⬜ |
| `ACTRENDR` | .C + .H | 359 | ⬜ |
| `ACTSHAKE` | .C + .H | 29 | ⬜ |

### `bak/SRC/R3D/CORE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `DISTDIR` | .H | 10 | ⬜ |
| `R3D` | .H | 674 | 🚧 |

### `bak/SRC/R3D/FX`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `WORLDFX` | .C + .H | 676 | ⬜ |

### `bak/SRC/R3D/PROJECT`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `PROJECT` | .C + .H | 90 | ⬜ |

### `bak/SRC/R3D/SCENE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CZONE` | .C + .H | 340 | ⬜ |
| `PROXIM` | .C + .H | 256 | ⬜ |
| `WORLDFRM` | .C + .H | 535 | ⬜ |
| `WORLDHIT` | .C + .H | 863 | ⬜ |
| `ZONE` | .C + .H | 394 | ⬜ |

### `bak/SRC/R3D/SKY`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `SKY` | .C + .H | 177 | ⬜ |
| `SKYREND` | .C + .H | 307 | ⬜ |

### `bak/SRC/R3D/SPRITE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `WORLDRND` | .C + .H | 405 | ⬜ |

### `bak/SRC/R3D/TBLSTORE`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `SHAPEBLD` | .C + .H | 471 | ✅ |
| `SHAPETBL` | .C + .H | 511 | ✅ |

### `bak/SRC/R3D/VIS`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `PROXSCAN` | .C + .H | 815 | ⬜ |
| `VISENTRY` | .C + .H | 50 | ⬜ |
| `VISLIST` | .C + .H | 98 | ⬜ |

### `bak/SRC/SCREENS`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `BOOKTEXT` | .C + .H | 559 | ⬜ |
| `BOOKVIEW` | .C + .H | 249 | ⬜ |
| `CIPHER` | .C + .H | 450 | ⬜ |
| `CMBINV` | .C + .H | 1124 | ⬜ |
| `CREDITS` | .C + .H | 233 | ⬜ |
| `ENCAMP` | .C + .H | 577 | ⬜ |
| `FMAP` | .C + .H | 398 | ⬜ |
| `INVENTOR` | .C + .H | 855 | ⬜ |
| `INVINSP` | .C + .H | 445 | ⬜ |
| `ITEMUSE` | .C + .H | 686 | ⬜ |
| `MAINMENU` | .C + .H | 1884 | ⬜ |
| `MODALSCR` | .C + .H | 838 | ⬜ |
| `PICKLOCK` | .C + .H | 226 | ⬜ |
| `SHOP` | .C + .H | 262 | ⬜ |
| `TOWNSCN` | .C + .H | 840 | ⬜ |

### `bak/SRC/SCRIPT`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `ADSCRIPT` | .C + .H | 417 | ⬜ |
| `ANIMSCR` | .C + .H | 1409 | ⬜ |
| `TTM` | .C + .H | 1071 | ⬜ |
| `TTMDLG` | .C + .H | 139 | ⬜ |

### `bak/SRC/STREAM/BUFLOAD`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `CHUNKRD` | .C + .H | 122 | ⬜ |
| `LOADCHNK` | .C + .H | 35 | ⬜ |
| `STRMLOAD` | .C + .H | 41 | ⬜ |

### `bak/SRC/STREAM/CODEC`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `BLITRLE` | .H | 10 | ⬜ |
| `CODEC` | .C + .H | 337 | ⬜ |
| `LZHINIT` | .C + .H | 65 | ⬜ |
| `LZHOPEN` | .C + .H | 34 | ⬜ |
| `LZHUF` | .H | 59 | ⬜ |
| `LZW` | .C + .H | 249 | ⬜ |
| `LZWDEC` | .H | 14 | ⬜ |
| `RLEWRITE` | .C + .H | 71 | ⬜ |
| `STREAM` | .C + .H | 205 | ⬜ |

### `bak/SRC/STREAM/RESLOAD`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `FONTLOAD` | .C + .H | 172 | ⬜ |
| `IFFREAD` | .C + .H | 233 | ⬜ |
| `IMGLOAD` | .C + .H | 246 | ⬜ |
| `RELBUF` | .C + .H | 25 | ⬜ |

### `bak/SRC/SYS`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `BIOSCHK` | .C + .H | 33 | ⬜ |
| `BOOT` | .C + .H | 318 | ⬜ |
| `CFGPARSE` | .C + .H | 254 | ✅ |
| `DOSMEM` | .C + .H | 144 | ✅ |
| `EMS` | .C + .H | 199 | ⬜ |
| `EMSDET` | .C + .H | 63 | ⬜ |
| `EMSIMG` | .C + .H | 186 | ⬜ |
| `FARPTR` | .H | 18 | ⬜ |
| `FARTHUNK` | .C + .H | 108 | ⬜ |
| `HWSHUT` | .C + .H | 20 | ⬜ |
| `MDACON` | .C + .H | 92 | ⬜ |
| `MEM` | .C + .H | 58 | ⬜ |
| `PANIC` | .C + .H | 34 | ⬜ |
| `PANICF` | .C + .H | 28 | ⬜ |
| `RAND` | .H | 49 | ✅ |
| `SYSLOWIO` | .C + .H | 36 | ⬜ |

### `bak/SRC/UI`

| Module | Files | Lines | Status |
|---|---|---:|:--:|
| `DLGWIDG` | .C + .H | 688 | ⬜ |
| `LISTWDG` | .C + .H | 439 | ⬜ |
| `MENULBL` | .C + .H | 72 | ⬜ |
| `MENUPAGE` | .C + .H | 590 | ⬜ |
| `NAMEDTBL` | .C + .H | 104 | ⬜ |
| `SCROLL` | .C + .H | 406 | ⬜ |
| `SHOWMSG` | .C + .H | 15 | ⬜ |
| `TEXTWRAP` | .C + .H | 161 | ⬜ |
| `UIWIDGET` | .C + .H | 266 | ⬜ |
| `WIDGET` | .C + .H | 563 | ⬜ |

---

**207 modules — 8 done, 4 in progress, 195 untouched.**
