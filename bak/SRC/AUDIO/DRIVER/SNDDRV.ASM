; ============================================================================
; SNDDRV.ASM -- KRONDOR.EXE segment 0x3626: the sound-driver dispatch module.
;
; One TASM object: three dispatch shims plus the two CS-resident data slots
; they share. Base linear address 0x36260 (paragraph 0x3626, offset 0x0000).
;
; What this module does
; ---------------------
; It is the thin trampoline between the game's C code and whichever hardware
; sound driver (AdLib/SB/MT-32/...) was decompressed from Sx.ovl and installed
; at boot. The installed driver's far entry point is stored in a single far
; pointer that lives INSIDE this code segment (snddrv_pfnDispatch, CS:0x0e);
; snddrv_patch_farptr writes it, the two dispatch shims CALLF through it. The
; cached shim (snddrv_dispatch_cached) is the external that MIDI.ASM
; (segment 0x32c8) links against for its streamed-sample path.
;
; The driver call is a REGISTER ABI, not a C stack call: the shims marshal
;   AX = cmd  (from [BP+6]),  SI = data (from [BP+8])
; before the CALLF, matching what the sound drivers expect.
;
; CS-RESIDENT DATA
; ----------------
; The dispatch far pointer (0x0e) and the return cache (0x12) live in the CODE
; segment so they survive with no DS pointer. Every access carries a CS:
; segment-override prefix (opcode 0x2E):
;   MOV  CS:[0x0e],AX            -> 2E A3 0E 00
;   MOV  CS:[0x10],AX            -> 2E A3 10 00
;   CALL DWORD PTR CS:[0x0e]     -> 2E FF 1E 0E 00
;   MOV  CS:[0x12],AX            -> 2E A3 12 00
;   MOV  AX,CS:[0x12]            -> 2E A1 12 00
; TASM emits the 2E prefix automatically for a label in the segment covered by
; "ASSUME CS:S3626_TEXT". snddrv_dispatch_cached also saves DS/ES/FLAGS and
; every GPR across the driver call and caches the AX return so the pop sequence
; can't clobber it. The two CS-resident slots are declared once and shared by
; all three functions.
;
; The 0x00..0x0D head is positioning padding: those bytes are the tail of the
; PRECEDING segment's function (the load image overlaps at the paragraph
; boundary), before the first member so the gate never reads them. Zero fill
; that lands the labels at their correct segment offsets.
;
; Segment layout
; --------------
;   0x00..0x0D  positioning padding (14 bytes; preceding function's tail)
;   0x0E..0x11  _snddrv_pfnDispatch    far ptr to installed driver entry
;   0x12..0x13  _snddrv_nCachedResult  cache for the driver's AX return
;   0x14..0x28  _snddrv_patch_farptr   (21 bytes)
;   0x29..0x60  _snddrv_dispatch_cached (56 bytes)
;   0x61..0x7B  _snddrv_dispatch       (27 bytes)
; ============================================================================

.386P

; Medium-model near-data group.
_DATA   SEGMENT WORD PUBLIC 'DATA'
_DATA   ENDS
_BSS    SEGMENT WORD PUBLIC 'BSS'
_BSS    ENDS
DGROUP  GROUP _DATA, _BSS

; External DGROUP reference (the music-driver-installed gate flag).
        EXTRN   _g_bMusicDriverInstalled:WORD

S3626_TEXT SEGMENT WORD PUBLIC USE16 'CODE'
        ASSUME CS:S3626_TEXT, DS:DGROUP

; ---------------------------------------------------------------------------
; CS-resident data block, shared by all three shims below. The module starts at
; the segment's first content byte (offset 0x0E); the 14 bytes below belong to
; the previous segment's tail and are not emitted/reserved here. The CS-prefixed
; operands carry segment-relative fixups TLINK resolves against the frame, so
; the frame offsets (0x0E / 0x12) land at link time. See the header for why
; these live in CODE.
; ---------------------------------------------------------------------------
_snddrv_pfnDispatch   DD  0     ; frame 0x0E: far-ptr dispatch slot (0 until patched at install)
_snddrv_nCachedResult DW  0     ; 0x12: caches driver AX return across the register pops
; ---------------------------------------------------------------------------

        PUBLIC _snddrv_patch_farptr
        PUBLIC _snddrv_dispatch_cached
        PUBLIC _snddrv_dispatch

; ---------------------------------------------------------------------------
; void snddrv_patch_farptr(undefined2 offset, undefined2 segment)  -- 3626:0014
;   Installs the loaded driver's far entry point into snddrv_pfnDispatch.
;   [BP+6] = offset word, [BP+8] = segment word. Saves/restores AX (so it
;   returns the caller's first arg unchanged, a Borland side effect).
; ---------------------------------------------------------------------------
_snddrv_patch_farptr    PROC FAR
        push    bp
        mov     bp,sp
        push    ax
        mov     ax,word ptr [bp+6]
        mov     word ptr cs:[_snddrv_pfnDispatch],ax
        mov     ax,word ptr [bp+8]
        mov     word ptr cs:[_snddrv_pfnDispatch+2],ax
        pop     ax
        pop     bp
        retf
_snddrv_patch_farptr    ENDP

; ---------------------------------------------------------------------------
; ushort snddrv_dispatch_cached(int cmd, int data)  -- 3626:0029
;   CACHED dispatch. Saves ALL registers + FLAGS, loads DS=DGROUP, gates on
;   g_bMusicDriverInstalled, dispatches through the CS-resident far ptr, and
;   caches the AX return in snddrv_nCachedResult so the register pops can't
;   clobber it. Reloads the cached value into AX after POPF and returns it.
;   cmd=[BP+6] -> AX, data=[BP+8] -> SI (driver register ABI).
; ---------------------------------------------------------------------------
_snddrv_dispatch_cached PROC FAR
        push    bp
        mov     bp,sp
        push    ds
        push    es
        pushf
        push    ax
        push    cx
        push    dx
        push    bx
        push    bp
        push    si
        push    di
        mov     ax,DGROUP               ; DGROUP base (seg FIXUPP -> MZ reloc)
        mov     ds,ax
        cmp     word ptr [_g_bMusicDriverInstalled],0
        jz      short no_driver_cached
        mov     si,word ptr [bp+8]      ; data -> SI (driver register ABI)
        mov     ax,word ptr [bp+6]      ; cmd  -> AX (driver register ABI)
        call    dword ptr cs:[_snddrv_pfnDispatch]  ; CALLF through CS-resident slot
no_driver_cached:
        mov     word ptr cs:[_snddrv_nCachedResult],ax  ; cache the return value
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        popf
        mov     ax,word ptr cs:[_snddrv_nCachedResult]  ; reload cached result
        pop     es
        pop     ds
        pop     bp
        retf
_snddrv_dispatch_cached ENDP

; ---------------------------------------------------------------------------
; void snddrv_dispatch(int cmd, int data)  -- 3626:0061
;   FIRE-AND-FORGET dispatch. Saves only SI/DI, relies on DS already being
;   DGROUP (true at every C-ABI call site), does NOT cache the return. Gated on
;   g_bMusicDriverInstalled. cmd=[BP+6] -> AX, data=[BP+8] -> SI.
; ---------------------------------------------------------------------------
_snddrv_dispatch        PROC FAR
        push    bp
        mov     bp,sp
        push    si
        push    di
        cmp     word ptr [_g_bMusicDriverInstalled],0
        jz      short no_driver
        mov     si,word ptr [bp+8]      ; data -> SI (driver register ABI)
        mov     ax,word ptr [bp+6]      ; cmd  -> AX (driver register ABI)
        call    dword ptr cs:[_snddrv_pfnDispatch]  ; CALLF through CS-resident slot
no_driver:
        pop     di
        pop     si
        pop     bp
        retf
_snddrv_dispatch        ENDP

S3626_TEXT ENDS
        END
