; ============================================================================
; CDAUDIO.ASM -- KRONDOR.EXE 1.02 (CD-ROM) all-new resident MSCDEX Red Book
; CD-audio driver.  segment 0x168a.  v1.02-ONLY (guarded by /dV102CD).
;
; This entire TU exists ONLY in the 1.02 CD-ROM release: it is the "new resident
; TU" the Phase-2 module diff found between RESBLIT.C (160a) and DISTDIR.ASM
; (1678).  362 bytes, five far functions, all RETF, sharing one private DGROUP
; state block (the +70-byte 0x294..0x2cc insertion Phase-4 found).  The whole
; module assembles only when TASM is invoked with /dV102CD (a 1.00 build never
; sees this file -- the build's v102-only module list excludes it entirely, so
; not even an empty SEGDEF is emitted into the 1.00 link).
;
; WHY ASM (not C): the shipped bytes carry idioms NO Borland C++ recipe emits --
; this is genuine hand-written assembly, exactly like the game's other resident
; driver bands (RAND.ASM, DISP35E0.ASM, DISTDIR.ASM):
;   - status returned in the ZERO FLAG: v102_cdaudio_mscdex_request ends
;     `OR AX,AX ; RETF`, and callers `JNZ` on the flag the callee's OR set --
;     a hand-asm return-status ABI a C compiler cannot express;
;   - same-segment calls done as `PUSH CS ; CALL near` (0e e8 ..) -- BCC never
;     pushes CS for an intrasegment call;
;   - `MOV AX,DS ; MOV ES,AX` to point ES:BX at the DGROUP request header
;     (8c d8 / 8e c0) -- the classic hand-written far-buffer setup;
;   - direct INT 21h/INT 2Fh with hand-loaded AX (MSCDEX AX=1510h device
;     request, AX=150Bh drive check; INT 21h AX=1900h get-current-drive);
;   - `MUL BL` / `MUL BX` Red Book MSF arithmetic (min*60*75 + sec*75 + frame)
;     with hand ADC/SBB multi-word math -- C would emit long IMUL/idiv chains.
;
; The five functions, in segment order (module offset = segoff - 8, because the
; 8 bytes at 168a:0000..0007 are the PRIOR overlay's epilogue tail -- the FBOV
; minoff for 168a is 8, so this module's first content byte lands at CS:08h and
; the module emits no leading/placeholder bytes, exactly like DISTDIR.ASM):
;   168a:0008  v102_cdaudio_mscdex_request   (40 B)  build ES:BX->reqhdr;
;                                                     INT 2F AX=1510; ret 0/-1
;   168a:0030  v102_cdaudio_set_track_msf    (128 B) frame offset -> Red Book
;                                                     MSF start; fill play req
;   168a:00b0  v102_cdaudio_play             (89 B)  cmd 0x84 Play Audio
;   168a:0109  v102_cdaudio_stop             (20 B)  cmd 0x85 Stop Audio
;   168a:011d  v102_cddrive_detect           (85 B)  resolve+validate CD drive
;
; The private state block (_g_cdaudio_state, 0x39 bytes) is this TU's own DGROUP
; storage -- referenced ONLY here, so it is defined in this module's _BSS rather
; than in a C owner (no C TU touches it).  Field map (offset within the block,
; absolute 1.02 DGROUP offset in parens):
;   +00 (294) word  lba_base    -- LBA offset subtracted in play
;   +02 (296) word  drive_no    -- CD subunit / -1 = none
;   +04 (298) dword inA         -- caller frame-offset arg A (lo/hi)
;   +08 (29c) dword inB         -- caller frame-offset arg B (lo/hi)
;   +0c (2a0) dword lba         -- computed play LBA
;   +10 (2a4) dword byteoff     -- computed Red Book byte offset
;   +14 (2a8) word  last_track  -- last MSF'd track (cache)
;   +16 (2aa) byte  present     -- CD-present flag (g_cd_present source)
;   +18 (2ac) byte  playing     -- 0 while playing, 1 when stopped
;   +19 (2ad) byte  req_subcmd  -- MSCDEX request header BASE (ES:BX=0x2ad)
;   +1a (2ae) byte  req_media
;   +1b (2af) byte  req_command -- 0x84 play / 0x85 stop / 0x03 ioctl
;   +1d (2b1) byte  req_status  -- MSCDEX status word lo (error bit 0x80)
;   +26 (2ba) byte  req_data    -- transfer buffer / control byte
;   +27 (2bb) dword req_arg0    -- play: MSF/LBA start ; ioctl: addr
;   +2b (2bf) dword req_arg1    -- play: length ; ioctl: count
;   +34 (2c8) byte  req_track
;   +35 (2c9) byte  msf_frame
;   +36 (2ca) byte  msf_sec
;   +37 (2cb) byte  msf_min
;   +38 (2cc) byte  req_last
; ============================================================================

	.286

; --- DGROUP / segment declarations -----------------------------------------
_DATA	segment word public 'DATA'
_DATA	ends

_BSS	segment word public 'BSS'
_BSS	ends

DGROUP	group _DATA, _BSS

; The all-new 1.02 CD-audio state block (70 bytes at DGROUP 0x294..0x2d9) is
; INITIALIZED _DATA, not _BSS: the shipped image carries non-zero defaults
; (lba_base=0x72, last_track=0xffff "no-track-cached" sentinel, playing=1
; "stopped", plus the IOCTL-buffer/req_last defaults). It must land at absolute
; DGROUP 0x294 (this driver hardcodes the field offsets 0x294..0x2cc), which is
; GMAIN.C's link slot, right before g_nVec3DistResult -- NOT this overlay TU's
; late _DATA slot. So the block is DEFINED (with its 70-byte initializer) in
; GMAIN.C under #ifdef V102CD and only REFERENCED here.
	extrn	_g_cdaudio_state:byte

; field offsets within _g_cdaudio_state (absolute 1.02 DGROUP off - 0x294)
CD_LBA_BASE	equ	_g_cdaudio_state + 000h	; 294
CD_DRIVE_NO	equ	_g_cdaudio_state + 002h	; 296
CD_INA		equ	_g_cdaudio_state + 004h	; 298
CD_INB		equ	_g_cdaudio_state + 008h	; 29c
CD_LBA		equ	_g_cdaudio_state + 00ch	; 2a0
CD_BYTEOFF	equ	_g_cdaudio_state + 010h	; 2a4
CD_LAST_TRACK	equ	_g_cdaudio_state + 014h	; 2a8
CD_PRESENT	equ	_g_cdaudio_state + 016h	; 2aa
CD_PLAYING	equ	_g_cdaudio_state + 018h	; 2ac
CD_REQ_SUBCMD	equ	_g_cdaudio_state + 019h	; 2ad  (ES:BX request header base)
CD_REQ_MEDIA	equ	_g_cdaudio_state + 01ah	; 2ae
CD_REQ_COMMAND	equ	_g_cdaudio_state + 01bh	; 2af
CD_REQ_STATUS	equ	_g_cdaudio_state + 01dh	; 2b1
CD_REQ_DATA	equ	_g_cdaudio_state + 026h	; 2ba
CD_REQ_ARG0	equ	_g_cdaudio_state + 027h	; 2bb
CD_REQ_ARG0HI	equ	_g_cdaudio_state + 029h	; 2bd
CD_REQ_ARG1	equ	_g_cdaudio_state + 02bh	; 2bf
CD_REQ_ARG1HI	equ	_g_cdaudio_state + 02dh	; 2c1
CD_IOCTL_BUF	equ	_g_cdaudio_state + 033h	; 2c7  IOCTL transfer buffer (Q-channel read)
CD_REQ_TRACK	equ	_g_cdaudio_state + 034h	; 2c8
CD_MSF_FRAME	equ	_g_cdaudio_state + 035h	; 2c9
CD_MSF_SEC	equ	_g_cdaudio_state + 036h	; 2ca
CD_MSF_MIN	equ	_g_cdaudio_state + 037h	; 2cb
CD_REQ_LAST	equ	_g_cdaudio_state + 038h	; 2cc

; WORD-aligned: the shipped 1.02 lays this module's _TEXT on a word (even) boundary
; (load-module offset 0x68a0), padding the prior overlay's odd-length tail with one 00
; byte. A `byte`-aligned _TEXT starts one byte early (odd lm 0x689f) and shifts the whole
; segment + every far-call target into it by 1.
S168A_TEXT	segment word public use16 'CODE'
	assume	cs:S168A_TEXT, ds:DGROUP

	public	_v102_cdaudio_mscdex_request
	public	_v102_cdaudio_set_track_msf
	public	_v102_cdaudio_play
	public	_v102_cdaudio_stop
	public	_v102_cddrive_detect

; ----------------------------------------------------------------------------
; int v102_cdaudio_mscdex_request(void)
;   Point ES:BX at the DGROUP MSCDEX request header (0x2ad), issue INT 2Fh
;   AX=1510h (MSCDEX "send device driver request"), and return the error state
;   in BOTH AX (0 ok / -1 err) AND the zero flag (via OR AX,AX before RETF, so
;   callers can JNZ).  Called by the three request builders below.
; ----------------------------------------------------------------------------
_v102_cdaudio_mscdex_request	proc far
	mov	ax,ds				; 8c d8
	mov	es,ax				; 8e c0  ES:BX -> request header
	mov	bx,offset DGROUP:CD_REQ_SUBCMD	; bb ad 02   ES:BX -> request header
	mov	cx,word ptr [CD_DRIVE_NO]	; 8b 0e 96 02  CX = drive number
	mov	ax,1510h			; b8 10 15
	int	2fh				; cd 2f   MSCDEX send request
	mov	ah,byte ptr [CD_REQ_STATUS]	; 8a 26 b1 02
	and	ah,80h				; 80 e4 80  test ERROR bit
	cmp	ah,0				; 80 fc 00
	jnz	short cdreq_err			; 75 06
	mov	ax,0				; b8 00 00  success -> 0
	or	ax,ax				; 0b c0
	retf					; cb
cdreq_err:
	mov	ax,0ffffh			; b8 ff ff  error -> -1
	or	ax,ax				; 0b c0
	retf					; cb
_v102_cdaudio_mscdex_request	endp

; ----------------------------------------------------------------------------
; void v102_cdaudio_set_track_msf(int track, long msfBase, long frameOffset)
;   [bp+6]=track  [bp+8..b]=frameOffset(dword)  [bp+c..f]=msfBase(dword)
;   Stash the two dword args, and (unless this track is already cached) issue an
;   IOCTL (cmd 3, subcmd 0x1a) reading the drive's Red Book Q-channel into the
;   MSF buffer at 0x2c9..0x2cc, then compute the linear Red Book frame:
;     ((min*60 + sec) * 75 + frame)  via MUL BL (*0x3c) / MUL BX (*0x4b).
; ----------------------------------------------------------------------------
_v102_cdaudio_set_track_msf	proc far
	push	bp				; 55
	mov	bp,sp				; 8b ec
	mov	ax,word ptr [bp+8]		; 8b 46 08
	mov	word ptr [CD_INB],ax		; a3 9c 02
	mov	ax,word ptr [bp+0ah]		; 8b 46 0a
	mov	word ptr [CD_INB+2],ax		; a3 9e 02
	mov	ax,word ptr [bp+0ch]		; 8b 46 0c
	mov	word ptr [CD_INA],ax		; a3 98 02
	mov	ax,word ptr [bp+0eh]		; 8b 46 0e
	mov	word ptr [CD_INA+2],ax		; a3 9a 02
	mov	ax,word ptr [bp+6]		; 8b 46 06
	cmp	ax,word ptr [CD_LAST_TRACK]	; 3b 06 a8 02
	jz	short setmsf_done		; 74 53   already cached -> skip
	mov	byte ptr [CD_REQ_TRACK],al	; a2 c8 02
	mov	byte ptr [CD_REQ_COMMAND],3	; c6 06 af 02 03  IOCTL read
	mov	byte ptr [CD_REQ_SUBCMD],1ah	; c6 06 ad 02 1a
	mov	word ptr [CD_REQ_ARG1],7		; c7 06 bf 02 07 00
	mov	word ptr [CD_REQ_ARG0HI],ds	; 8c 1e bd 02
	mov	word ptr [CD_REQ_ARG0],offset DGROUP:CD_IOCTL_BUF	; c7 06 bb 02 c7 02
	push	ax				; 50
	push	cs				; 0e
	call	near ptr _v102_cdaudio_mscdex_request	; e8 92 ff
	pop	ax				; 58
	jnz	short setmsf_ret1		; 75 32   IOCTL failed
	mov	word ptr [CD_LAST_TRACK],ax	; a3 a8 02
	mov	al,byte ptr [CD_REQ_LAST]	; a0 cc 02   AL = min  (buffer byte 0x2cc)
	mov	bx,3ch				; bb 3c 00   BX = 60
	mul	bl				; f6 e3     AX = min*60
	add	al,byte ptr [CD_MSF_MIN]	; 02 06 cb 02   + sec  (0x2cb)  -> AX = min*60+sec
	mul	bx				; f7 e3     AX = (min*60+sec)*60
	mov	cl,byte ptr [CD_MSF_SEC]	; 8a 0e ca 02   CL = frames field (0x2ca)
	mov	ch,0				; b5 00
	add	ax,cx				; 03 c1
	mov	bx,4bh				; bb 4b 00   BX = 75
	mul	bx				; f7 e3     * 75
	mov	cl,byte ptr [CD_MSF_FRAME]	; 8a 0e c9 02   CL = sub-frame (0x2c9)
	add	ax,cx				; 03 c1
	adc	dx,0				; 83 d2 00   DX:AX = Red Book byte offset
	mov	word ptr [CD_BYTEOFF],ax	; a3 a4 02
	mov	word ptr [CD_BYTEOFF+2],dx	; 89 16 a6 02
setmsf_done:
	xor	ax,ax				; 33 c0
	pop	bp				; 5d
	retf					; cb
setmsf_ret1:
	mov	ax,1				; b8 01 00
	pop	bp				; 5d
	retf					; cb
_v102_cdaudio_set_track_msf	endp

; ----------------------------------------------------------------------------
; void v102_cdaudio_play(void)
;   Fill the request header with cmd 0x84 (Play Audio) at the computed MSF
;   start (byteoff + inB - lba_base), submit via the request helper.
; ----------------------------------------------------------------------------
_v102_cdaudio_play	proc far
	mov	byte ptr [CD_PLAYING],0		; c6 06 ac 02 00
	mov	byte ptr [CD_REQ_COMMAND],84h	; c6 06 af 02 84  Play Audio
	mov	byte ptr [CD_REQ_SUBCMD],16h	; c6 06 ad 02 16
	mov	ax,word ptr [CD_INA]		; a1 98 02
	mov	dx,word ptr [CD_INA+2]		; 8b 16 9a 02
	or	ax,ax				; 0b c0
	jnz	short cdplay_len		; 75 07
	or	dx,dx				; 0b d2
	jnz	short cdplay_len		; 75 03
	mov	dx,5				; ba 05 00  default length
cdplay_len:
	mov	word ptr [CD_REQ_ARG1],ax	; a3 bf 02
	mov	word ptr [CD_REQ_ARG1HI],dx	; 89 16 c1 02
	mov	ax,word ptr [CD_INB]		; a1 9c 02
	add	ax,word ptr [CD_BYTEOFF]	; 03 06 a4 02
	mov	word ptr [CD_REQ_ARG0],ax	; a3 bb 02
	mov	ax,word ptr [CD_INB+2]		; a1 9e 02
	adc	ax,word ptr [CD_BYTEOFF+2]	; 13 06 a6 02
	mov	word ptr [CD_REQ_ARG0HI],ax	; a3 bd 02
	mov	ax,word ptr [CD_LBA_BASE]	; a1 94 02
	sub	word ptr [CD_REQ_ARG0],ax	; 29 06 bb 02
	sbb	word ptr [CD_REQ_ARG0HI],0	; 83 1e bd 02 00
	mov	ax,word ptr [CD_REQ_ARG0]	; a1 bb 02
	mov	word ptr [CD_LBA],ax		; a3 a0 02
	mov	ax,word ptr [CD_REQ_ARG0HI]	; a1 bd 02
	mov	word ptr [CD_LBA+2],ax		; a3 a2 02
	push	cs				; 0e
	call	near ptr _v102_cdaudio_mscdex_request	; e8 00 ff
	retf					; cb
_v102_cdaudio_play	endp

; ----------------------------------------------------------------------------
; void v102_cdaudio_stop(void)
;   Request cmd 0x85 (Stop Audio), subcmd 0x0d, submit, mark not-playing.
; ----------------------------------------------------------------------------
_v102_cdaudio_stop	proc far
	mov	byte ptr [CD_REQ_COMMAND],85h	; c6 06 af 02 85  Stop Audio
	mov	byte ptr [CD_REQ_SUBCMD],0dh	; c6 06 ad 02 0d
	push	cs				; 0e
	call	near ptr _v102_cdaudio_mscdex_request	; e8 f1 fe
	mov	byte ptr [CD_PLAYING],1		; c6 06 ac 02 01
	retf					; cb
_v102_cdaudio_stop	endp

; ----------------------------------------------------------------------------
; int v102_cddrive_detect(char driveLetter)
;   [bp+6]=driveLetter.  Upper-case it (AND 0x5f); if zero (no letter) use the
;   current default drive (INT 21h AX=1900h), else letter-'A'.  Store the
;   0-based index at 0x296, then MSCDEX drive-check (INT 2Fh AX=150Bh): a CD
;   drive iff BX==0xADAD and AX!=0.  On success init the request-header defaults
;   and set present=1, return 1; on failure store drive_no=-1, return 0.
; ----------------------------------------------------------------------------
_v102_cddrive_detect	proc far
	push	bp				; 55
	mov	bp,sp				; 8b ec
	mov	al,byte ptr [bp+6]		; 8a 46 06
	and	al,5fh				; 24 5f   to upper
	or	al,al				; 0a c0
	jnz	short cddet_have		; 75 07
	mov	ax,1900h			; b8 00 19
	int	21h				; cd 21   current default drive
	jmp	short cddet_idx			; eb 02
cddet_have:
	sub	al,41h				; 2c 41   'A'.. -> 0-based
cddet_idx:
	xor	ah,ah				; 32 e4
	mov	word ptr [CD_DRIVE_NO],ax	; a3 96 02
	mov	cx,ax				; 8b c8
	mov	bx,0				; bb 00 00
	mov	ax,150bh			; b8 0b 15
	int	2fh				; cd 2f   MSCDEX drive check
	cmp	bx,0adadh			; 81 fb ad ad
	jnz	short cddet_fail		; 75 21
	cmp	ax,0				; 3d 00 00
	jz	short cddet_fail		; 74 1c
	mov	byte ptr [CD_REQ_MEDIA],0	; c6 06 ae 02 00
	mov	byte ptr [CD_REQ_DATA],0	; c6 06 ba 02 00
	mov	byte ptr [CD_REQ_COMMAND],0	; c6 06 af 02 00
	mov	byte ptr [CD_REQ_SUBCMD],0dh	; c6 06 ad 02 0d
	mov	ax,1				; b8 01 00
	mov	byte ptr [CD_PRESENT],al	; a2 aa 02
	pop	bp				; 5d
	retf					; cb
cddet_fail:
	mov	word ptr [CD_DRIVE_NO],0ffffh	; c7 06 96 02 ff ff
	xor	ax,ax				; 33 c0
	pop	bp				; 5d
	retf					; cb
_v102_cddrive_detect	endp

S168A_TEXT	ends
	end
