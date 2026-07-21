; ============================================================================
; VIDMODE.ASM -- KRONDOR.EXE BIOS video-mode helpers (segment 180c).
;
; Three near routines, contiguous in the image (linear 0x1adc2..0x1ae11):
;
;   _bios_set_video_mode_bits  writes the "initial video mode" field (bits 5:4)
;                             of the BIOS Data Area equipment word at 0040:0010
;                             from its uchar arg (shifted left 4), preserving the
;                             other bits, then issues INT 10h (AX=3, BX=3).
;   _bios_get_video_mode_bits  reads that same field back and returns it in the
;                             low nibble (0=EGA/VGA, 1=CGA-40, 2=CGA-80, 3=MDA).
;   _bios_video_int10_helper   forces 80x25 colour text: ES is an implicit input
;                             (=0x40 BDA segment); it clears bits 5:4 (AND 0xCF)
;                             and sets bit 5 (OR 0x20) of the equipment word,
;                             then INT 10h.
;
; All three do direct BIOS-Data-Area access via a segment register (mov ax,40h /
; mov es,ax / mov bx,10h / es:[bx]). No DGROUP globals and no external calls.
; All three are near procs (RET 0xc3); callers reach them via near CALL (e.g.
; VIDDET.ASM's video_detect_adapter calls bios_video_int10_helper, and
; video_shutdown calls bios_set_video_mode_bits, both cross-unit extrn :near).
; ============================================================================

	.286

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_bios_set_video_mode_bits, _bios_get_video_mode_bits
	public	_bios_video_int10_helper

; ----------------------------------------------------------------------------
; void near bios_set_video_mode_bits(uchar mode_bits /* [bp+4] */)
; Writes mode_bits<<4 into BDA bits 5:4 (0040:0010), preserving the rest, then
; INT 10h (AX=3, BX=3) so the BIOS applies it. Inverse of get.
; ----------------------------------------------------------------------------
_bios_set_video_mode_bits	proc near
	push	bp
	mov	bp,sp
	mov	ax,40h
	mov	es,ax
	mov	ax,[bp+4]			; uchar mode_bits (word-aligned arg slot)
	mov	cl,4
	shl	ax,cl
	mov	bx,10h
	and	byte ptr es:[bx],0cfh		; clear BDA bits 5:4 (0040:0010)
	or	byte ptr es:[bx],al		; set them from mode_bits<<4
	mov	ax,3h
	mov	bx,3h
	int	10h
	pop	bp
	ret
_bios_set_video_mode_bits	endp

; ----------------------------------------------------------------------------
; int near bios_get_video_mode_bits(void)  -> AX
; Reads BDA bits 5:4 (0040:0010), returns them right-aligned in the low nibble.
; Note the DEAD stack frame (BP saved/restored but never referenced).
; ----------------------------------------------------------------------------
_bios_get_video_mode_bits	proc near
	push	bp
	mov	bp,sp
	mov	ax,40h
	mov	es,ax
	mov	bx,10h
	mov	al,byte ptr es:[bx]		; BDA equipment word low byte
	and	al,30h				; isolate bits 5:4
	mov	cl,4
	shr	al,cl				; right-align to low nibble
	xor	ah,ah				; zero-extend AL->AX
	pop	bp
	ret
_bios_get_video_mode_bits	endp

; ----------------------------------------------------------------------------
; void near bios_video_int10_helper(void)
; ES is an implicit input (=0x40, BDA segment; callers set it before the near
; call). Rewrites BDA bits 5:4 to 10b (80x25 colour text) then INT 10h (AX=3,
; BX=3). No stack frame.
; ----------------------------------------------------------------------------
_bios_video_int10_helper	proc near
	mov	bx,10h
	and	byte ptr es:[bx],0cfh		; clear bits 5:4
	or	byte ptr es:[bx],20h		; set bit 5 -> 80x25 colour text
	mov	ax,3h
	mov	bx,3h
	int	10h
	ret
_bios_video_int10_helper	endp

S180C_TEXT	ends

	end
