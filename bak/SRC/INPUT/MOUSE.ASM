;; MOUSE.ASM -- the mouse subsystem (unit `mouse`, segment 180c,
;; linear 0x1c932..0x1cb79, 583 bytes, hole-free).
;;
;; One translation unit: hardware install/teardown, the cursor clip + handler
;; plumbing, the INT 33h-driven event callback (with its VGA GC/SC save+restore
;; helpers), and the cursor position / button-state query API. Every routine is
;; INT 33h register protocol (driver function in AX, params in BX/CX/DX, results
;; in registers or through an ES:DX far pointer) plus flag-driven control flow.
;;
;; Functions, in address order (all FAR, __cdecl16 stack args at [bp+6]..):
;;   _mouse_install              0x1c932  INT33 reset+detect, ranges, install cb
;;   _mouse_set_cursor_clip_rect 0x1c9a2  INT33 fn 7/8: clip cursor to a rect
;;   _mouse_set_handler_cb       0x1c9d3  store the user handler far pointer
;;   _mouse_event_callback       0x1c9e4  INT33 event handler (ISR-like)
;;   _vga_save_and_setup_gc_sc   0x1ca27  save+prime VGA GC/SC for the handler
;;   _vga_restore_registers      0x1ca8c  restore VGA GC/SC after the handler
;;   _mouse_restore_handler      0x1cae5  uninstall: INT33 reset + clear handler
;;   _mouse_get_position         0x1cb01  read cursor pos (mickeys>>2) via *out
;;   _mouse_set_position         0x1cb2b  set cursor pos (pixels<<2)
;;   _mouse_button_pressed       0x1cb56  test one button's pressed bit
;;
;; INTERNAL linkage: _mouse_install NEAR-calls _mouse_set_cursor_clip_rect and
;; takes `offset _mouse_event_callback`; _mouse_event_callback NEAR-calls the
;; two VGA helpers. All ten live in this one module, so those references resolve
;; at ASSEMBLE time (self-relative), with no external FIXUPP.
;;
;; ---------------------------------------------------------------------------
;; PRIMER 1: the DOS mouse driver (INT 33h)
;;
;; A DOS mouse is driven through software interrupt 33h, a vendor API installed
;; by MOUSE.COM (or equivalent). The caller picks a service by loading its
;; number into AX, puts arguments in BX/CX/DX/ES, executes `int 33h`, and reads
;; results back out of those same registers. The services this unit uses:
;;
;;   AX=00h  reset + detect.   Returns AX=0FFFFh if a driver is present (else 0)
;;                             and resets the driver to defaults.
;;   AX=01h  show cursor.
;;   AX=02h  hide cursor.
;;   AX=04h  set cursor position.  CX = x, DX = y (in mickeys; see below).
;;   AX=07h  set horizontal range. CX = min x, DX = max x (cursor clip).
;;   AX=08h  set vertical range.   CX = min y, DX = max y (cursor clip).
;;   AX=0Ch  install event handler. CX = event mask, ES:DX = handler far ptr.
;;                             ES:DX = 0:0 with mask 0 removes the handler.
;;   AX=0Fh  set mickey/pixel ratio. CX = horiz mickeys per 8 px, DX = vert.
;;
;; A "mickey" is the mouse's raw motion unit. This driver tracks the cursor in
;; quarter-pixel units (pixels*4), so position arguments are scaled <<2 going
;; out to the driver and >>2 coming back -- hence the paired SHL/SHR below.
;; (See Ralf Brown's Interrupt List, INT 33h.)
;;
;; The fn-00h "is a driver present?" check appears several times as
;; `NEG`-after-load: NEG sets CF iff the operand is non-zero, so `JC` then means
;; "present". The same NEG-sets-CF trick also distinguishes button 0 from
;; button 1 in _mouse_button_pressed.
;;
;; ---------------------------------------------------------------------------
;; PRIMER 2: the VGA register save/restore (event-callback only)
;;
;; The mouse event handler may draw the software cursor straight into video
;; memory, which means it reprograms several VGA registers. To avoid corrupting
;; whatever the foreground code was doing, _vga_save_and_setup_gc_sc snapshots
;; those registers before the user handler runs and _vga_restore_registers puts
;; them back afterwards.
;;
;; The VGA exposes two register files used here, each as an index/data port
;; pair: write the register number to the index port, then read or write its
;; value at the data port (index+1):
;;
;;   Graphics Controller (GC): index 3CEh, data 3CFh
;;     reg 0  Set/Reset            reg 4  Read Map Select
;;     reg 1  Enable Set/Reset     reg 5  Graphics Mode
;;     reg 3  Data Rotate          reg 8  Bit Mask
;;   Sequencer (SC):           index 3C4h, data 3C5h
;;     reg 2  Map Mask (per-plane write enable)
;;
;; The save slots in DGROUP pack a register value in the high byte (AH) and the
;; port's previously-latched index byte in the low byte (AL); _vga_restore_*
;; unpacks them in reverse order. The dummy A000h:FFFFh memory touch around the
;; GC Mode write loads the VGA's internal latch registers so the mode change
;; takes effect on the next planar access. (See FreeVGA / the VGA Documentation
;; Project for register details.)

	.286

	;; g_wScreen_width/height are standalone DGROUP globals (DS:0x26fa/0x26fc) and
	;; g_bVideoAdapter an interior field of the graphics-context; gfxctx.inc extrn's/EQUs them.
	include	gfxctx.inc

	;; This module's _DATA block (DG 0x2f8c..0x3138, 428B): the mouse
	;; subsystem's DGROUP state. Every symbol is written+read only by this
	;; module (mouse_event_callback tops SP at g_abMouseCbStack+190h;
	;; vga_save_and_setup_gc_sc / vga_restore_registers fill the save slots;
	;; g_mouse_installed is read by several C TUs but MOUSE.ASM is the sole
	;; definer/writer). Two interior word-align pads (0x3124/0x312f).
	;; g_pMouseHandlerCb stays `dd 0` -- a runtime-relocated far ptr. Even
	;; length (428B), self-word-aligning. Ends at 0x3138 = the POLYGON block.
	_DATA	segment word public 'DATA'

	public	_g_mouse_x_mickeys, _g_mouse_y_mickeys, _g_pMouseHandlerCb
	public	_g_abMouseCbStack, _dgroup_pad_3124
	public	_g_wSavedVgaGcReg0AndIdx, _g_wSavedVgaGcReg1And4, _g_wSavedVgaGcReg5And8
	public	_g_wSavedVgaScReg2AndIdx, _g_bSavedVgaGcReg3, _dgroup_pad_312f
	public	_g_bVgaGcReg5ModeA, _g_bVgaGcReg5Mode8AltA, _g_bVgaGcReg5ModeB
	public	_g_bVgaGcReg5Mode8AltB, _g_mouse_installed, _g_mouse_buttons

_g_mouse_x_mickeys	dw	0		; DGROUP+0x2f8c (2B) ushort  x*4
_g_mouse_y_mickeys	dw	0		; DGROUP+0x2f8e (2B) ushort  y*4
_g_pMouseHandlerCb	dd	0		; DGROUP+0x2f90 (4B) far ptr, runtime-relocated
_g_abMouseCbStack	db	400 dup(0)	; DGROUP+0x2f94 (400B) uchar[400] private cb stack (+190h top)
_dgroup_pad_3124	db	2 dup(0)	; DGROUP+0x3124 (2B) word-align pad (interior)
_g_wSavedVgaGcReg0AndIdx	dw	0		; DGROUP+0x3126 (2B) word
_g_wSavedVgaGcReg1And4	dw	0		; DGROUP+0x3128 (2B) word
_g_wSavedVgaGcReg5And8	dw	0		; DGROUP+0x312a (2B) word
_g_wSavedVgaScReg2AndIdx	dw	0		; DGROUP+0x312c (2B) word
_g_bSavedVgaGcReg3	db	0		; DGROUP+0x312e (1B) byte
_dgroup_pad_312f	db	3 dup(0)	; DGROUP+0x312f (3B) word-align pad (interior)
_g_bVgaGcReg5ModeA	db	02h		; DGROUP+0x3132 (1B) byte  initialized
_g_bVgaGcReg5Mode8AltA	db	40h		; DGROUP+0x3133 (1B) uchar initialized
_g_bVgaGcReg5ModeB	db	01h		; DGROUP+0x3134 (1B) byte  initialized
_g_bVgaGcReg5Mode8AltB	db	41h		; DGROUP+0x3135 (1B) byte  initialized
_g_mouse_installed	db	0		; DGROUP+0x3136 (1B) uchar (1=present)
_g_mouse_buttons	db	0		; DGROUP+0x3137 (1B) uchar button mask latch
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_mouse_install
	public	_mouse_set_cursor_clip_rect
	public	_mouse_set_handler_cb
	public	_mouse_event_callback
	public	_vga_save_and_setup_gc_sc
	public	_vga_restore_registers
	public	_mouse_restore_handler
	public	_mouse_get_position
	public	_mouse_set_position
	public	_mouse_button_pressed

; ============================================================================
; _mouse_install -- reset/detect the mouse, configure it, install the handler.
;
;   Detects the driver, configures cursor ranges and the mickey/pixel ratio,
;   clips the cursor to the screen rectangle, and installs the event callback.
;   The INT 33h sequence is: fn 0 reset+detect, fn 4 set position, fn 1 show
;   cursor, fn 2 hide cursor, fn 0Fh set mickey/pixel ratio, fn 4 home cursor,
;   then clip to the screen rect (via _mouse_set_cursor_clip_rect) and fn 0Ch
;   install the handler. On a VGA adapter (id 8) it swaps the alternate GC
;   reg-5 mode bytes into the active mode-byte slots the callback uses.
;
;   Type:         FAR procedure (public)
;   Category:     Mouse install/teardown
;   Callers:      external (engine setup)
;   Callees:      _mouse_set_cursor_clip_rect (near, intra-module)
;
;   Inputs:       none (reads _g_graphics_context screen size + adapter id)
;   Outputs:      AX -- 1 if a driver is present, else 0
;   Side effects: sets _g_mouse_installed; installs the INT 33h handler;
;                 on VGA copies _g_bVgaGcReg5Mode8Alt{A,B} into the
;                 _g_bVgaGcReg5Mode{A,B} slots.
;   Notes:        re-entry guard -- if _g_mouse_installed is already non-zero
;                 it returns AX=0 without touching the driver (AX was just
;                 zeroed for the fn-0 call), so a second install is a no-op.
; ============================================================================
_mouse_install	proc far
	sub	ax,ax				; +0x000  AX = 0 (INT33 fn 0: reset)
	cmp	byte ptr _g_mouse_installed,al	; +0x002  already installed?
	jnz	mi_done				; +0x006  yes -> return AX=0 (no-op)
	int	33h				; +0x008  reset -> AX = present?
	neg	ax				; +0x00a  CF = (AX != 0)
	mov	byte ptr _g_mouse_installed,al	; +0x00c  installed = present
	jnc	mi_done				; +0x00f  not present -> return 0
	mov	ax,4				; +0x011  fn 4: set cursor position
	mov	cx,7fffh			; +0x014
	mov	dx,cx				; +0x017
	int	33h				; +0x019
	mov	ax,1				; +0x01b  fn 1: show cursor
	int	33h				; +0x01e
	mov	ax,2				; +0x020  fn 2: hide cursor
	int	33h				; +0x023
	mov	ax,0fh				; +0x025  fn 0Fh: set mickey ratio
	mov	cx,8				; +0x028
	mov	dx,8				; +0x02b
	int	33h				; +0x02e
	mov	ax,4				; +0x030  fn 4: home cursor (0,0)
	xor	cx,cx				; +0x033
	mov	dx,cx				; +0x035
	int	33h				; +0x037
	push	word ptr _g_wScreen_height	; +0x039  clip h
	push	word ptr _g_wScreen_width	; +0x03d  clip w
	xor	ax,ax				; +0x041  origin x=y=0
	push	ax				; +0x043
	push	ax				; +0x044
	push	cs				; +0x045  far-return CS for near callee
	call	near ptr _mouse_set_cursor_clip_rect	; +0x046  (intra-module)
	add	sp,8				; +0x049
	mov	ax,0ch				; +0x04c  fn 0Ch: install handler
	mov	cx,1fh				; +0x04f  event mask
	push	cs				; +0x052  ES:DX = handler far ptr
	pop	es				; +0x053  ES = this segment
	mov	dx,offset _mouse_event_callback	; +0x054  DX = handler offset
	int	33h				; +0x057
	mov	al,byte ptr _g_graphics_context.bVideoAdapter	; +0x059
	cmp	al,8				; +0x05c  VGA?
	jnz	mi_novga			; +0x05e  no -> skip GC mode swap
	mov	al,byte ptr _g_bVgaGcReg5Mode8AltA	; +0x060
	mov	byte ptr _g_bVgaGcReg5ModeA,al	; +0x063
	mov	al,byte ptr _g_bVgaGcReg5Mode8AltB	; +0x066
	mov	byte ptr _g_bVgaGcReg5ModeB,al	; +0x069
mi_novga:
	mov	ax,1				; +0x06c  return 1 (installed)
mi_done:
	retf					; +0x06f
_mouse_install	endp

; ============================================================================
; _mouse_set_cursor_clip_rect(int x, int y, int w, int h) -- clip the cursor
; to a rectangle.
;
;   INT 33h fn 7 sets the horizontal range [x*4, (x+w-1)*4] and fn 8 the
;   vertical range [y*4, (y+h-1)*4], both in 1/4-pixel (mickey) units.
;
;   Type:         FAR procedure (public)
;   Category:     Mouse install/teardown
;   Callers:      _mouse_install (near), external
;   Inputs:       [bp+6]=x, [bp+8]=y, [bp+0Ah]=w, [bp+0Ch]=h (pixels)
;   Outputs:      none
;   Side effects: programs the INT 33h cursor clip range.
; ============================================================================
_mouse_set_cursor_clip_rect	proc far
	push	bp
	mov	bp,sp
	mov	ax,7				; fn 7: set horizontal range
	mov	cx,word ptr [bp+6]		; x
	mov	dx,cx
	add	dx,word ptr [bp+0ah]		; dx = x + w
	shl	cx,1				; cx = x*4  (min)
	shl	cx,1
	dec	dx				; dx = x + w - 1
	shl	dx,1				; dx = (x+w-1)*4  (max)
	shl	dx,1
	int	33h
	mov	ax,8				; fn 8: set vertical range
	mov	cx,word ptr [bp+8]		; y
	mov	dx,cx
	add	dx,word ptr [bp+0ch]		; dx = y + h
	shl	cx,1				; cx = y*4  (min)
	shl	cx,1
	dec	dx				; dx = y + h - 1
	shl	dx,1				; dx = (y+h-1)*4  (max)
	shl	dx,1
	int	33h
	pop	bp
	retf
_mouse_set_cursor_clip_rect	endp

; ============================================================================
; _mouse_set_handler_cb(void far *cb) -- store the user event-handler far
; pointer that _mouse_event_callback dispatches through.
;
;   Type:         FAR procedure (public)
;   Category:     Handler plumbing
;   Inputs:       [bp+6]=cb offset, [bp+8]=cb segment
;   Outputs:      none
;   Side effects: writes _g_pMouseHandlerCb (far pointer).
; ============================================================================
_mouse_set_handler_cb	proc far
	push	bp
	mov	bp,sp
	mov	ax,word ptr [bp+6]		; cb offset
	mov	word ptr _g_pMouseHandlerCb,ax
	mov	ax,word ptr [bp+8]		; cb segment
	mov	word ptr _g_pMouseHandlerCb+2,ax
	pop	bp
	retf
_mouse_set_handler_cb	endp

; ============================================================================
; _mouse_event_callback -- the INT 33h event handler the driver far-calls on a
; mouse event.
;
;   Runs a brief CLI critical section, switches to a private stack in DGROUP
;   (the driver calls this with an unknown SS:SP), latches the event state into
;   globals, then dispatches the user handler bracketed by the VGA GC/SC
;   save/restore so the handler may draw the cursor without corrupting the
;   foreground's VGA register state.
;
;   Type:         FAR procedure (public) -- invoked by the mouse driver, ISR-like
;   Category:     Event dispatch
;   Callees:      _vga_save_and_setup_gc_sc, _vga_restore_registers (near);
;                 the user handler via CALLF through _g_pMouseHandlerCb
;
;   Inputs:       CX = x mickeys, DX = y mickeys, BL = button mask
;                 (register-IN, set by the driver; not stack args)
;   Outputs:      none
;   Touches:      saves/restores flags, DS, ES, BP, SI (and SS:SP); AX/BX/CX/DX
;                 are scratch per the mouse-handler ABI
;   Side effects: latches _g_mouse_buttons / _g_mouse_x_mickeys /
;                 _g_mouse_y_mickeys; calls the user handler if one is set.
;   Notes:        SS/SP are swapped to the private cb stack and back inside
;                 CLI so an interrupt never sees a half-switched stack.
; ============================================================================
_mouse_event_callback	proc far
	pushf					; +0x000  save flags
	push	ds				; +0x001
	push	es				; +0x002
	push	bp				; +0x003
	push	si				; +0x004
	mov	bp,sp				; +0x005
	mov	si,ss				; +0x007  save caller SS in SI
	mov	ax,DGROUP			; +0x009  AX = DGROUP paragraph
	cli					; +0x00c
	mov	sp,offset DGROUP:_g_abMouseCbStack + 190h	; +0x00d  SP = top of the 190h-byte cb stack (grows down)
	mov	ss,ax				; +0x010  SS = DGROUP
	sti					; +0x012
	cld					; +0x013
	mov	ds,ax				; +0x014  DS = DGROUP
	mov	byte ptr _g_mouse_buttons,bl	; +0x016  latch button mask
	mov	word ptr _g_mouse_x_mickeys,cx	; +0x01a  latch x mickeys
	mov	word ptr _g_mouse_y_mickeys,dx	; +0x01e  latch y mickeys
	mov	ax,word ptr _g_pMouseHandlerCb	; +0x022  handler off
	or	ax,word ptr _g_pMouseHandlerCb+2	; +0x025  | handler seg
	jz	cb_nohandler			; +0x029  no handler -> skip
	push	cs				; +0x02b  far-return CS for near callee
	call	near ptr _vga_save_and_setup_gc_sc	; +0x02c  save VGA GC/SC state
	call	dword ptr _g_pMouseHandlerCb	; +0x02f  invoke user handler
	push	cs				; +0x033
	call	near ptr _vga_restore_registers	; +0x034  restore VGA state
cb_nohandler:
	cli					; +0x037
	mov	ss,si				; +0x038  restore caller SS
	mov	sp,bp				; +0x03a  restore caller SP
	sti					; +0x03c
	pop	si				; +0x03d
	pop	bp				; +0x03e
	pop	es				; +0x03f
	pop	ds				; +0x040
	popf					; +0x041
	retf					; +0x042
_mouse_event_callback	endp

; ============================================================================
; _vga_save_and_setup_gc_sc -- snapshot the VGA Graphics-Controller and
; Sequencer registers the cursor blit will touch (GC 0/1/4/5/8/3, SC 2) and
; prime them so the user handler can draw planar pixels.
;
;   For each register it writes the index, reads the current value back from
;   the data port, packs (value:index) into a DGROUP save slot, then writes the
;   value the cursor blit needs. See PRIMER 2 for the port model.
;
;   Type:         FAR procedure (public)
;   Category:     VGA register save
;   Callers:      _mouse_event_callback (near)
;   Inputs:       reads the GC mode bytes _g_bVgaGcReg5Mode{A,B}
;   Outputs:      none
;   Touches:      AX, BX, DX, DI, ES (no save/restore -- caller already pushed)
;   Side effects: fills the _g_wSavedVga* / _g_bSavedVgaGcReg3 slots; leaves the
;                 GC/SC primed for the cursor blit.
; ============================================================================
_vga_save_and_setup_gc_sc	proc far
	mov	dx,3ceh				; GC index/data port
	in	al,dx
	mov	ah,al
	xor	al,al				; GC index 0 (set/reset)
	out	dx,al
	inc	dx
	in	al,dx
	mov	[_g_wSavedVgaGcReg0AndIdx],ax
	dec	dx
	mov	al,1h				; GC index 1 (enable set/reset)
	out	dx,al
	inc	dx
	in	al,dx
	mov	ah,al
	xor	al,al
	out	dx,al
	dec	dx
	mov	al,4h				; GC index 4 (read map select)
	out	dx,al
	inc	dx
	in	al,dx
	mov	[_g_wSavedVgaGcReg1And4],ax
	dec	dx
	mov	al,5h				; GC index 5 (mode)
	out	dx,al
	inc	dx
	in	al,dx
	mov	ah,al
	mov	al,[_g_bVgaGcReg5ModeB]
	out	dx,al
	mov	di,0ffffh			; latch via a dummy A000:FFFF write
	mov	bx,0a000h
	mov	es,bx
	stosb
	mov	al,[_g_bVgaGcReg5ModeA]
	out	dx,al
	dec	dx
	mov	al,8h				; GC index 8 (bit mask)
	out	dx,al
	inc	dx
	in	al,dx
	mov	[_g_wSavedVgaGcReg5And8],ax
	mov	al,0ffh
	out	dx,al
	dec	dx
	mov	al,3h				; GC index 3 (data rotate)
	out	dx,al
	inc	dx
	in	al,dx
	mov	[_g_bSavedVgaGcReg3],al
	xor	al,al
	out	dx,al
	mov	dx,3c4h				; SC index/data port
	in	al,dx
	mov	ah,al
	mov	al,2h				; SC index 2 (map mask)
	out	dx,al
	inc	dx
	in	al,dx
	mov	[_g_wSavedVgaScReg2AndIdx],ax
	mov	al,0fh
	out	dx,al
	retf
_vga_save_and_setup_gc_sc	endp

; ============================================================================
; _vga_restore_registers -- restore the VGA SC/GC registers saved by
; _vga_save_and_setup_gc_sc, in reverse order, after the user handler returns.
;
;   Unpacks each (value:index) save slot and replays the original register
;   value.
;
;   Type:         FAR procedure (public)
;   Category:     VGA register restore
;   Callers:      _mouse_event_callback (near)
;   Inputs:       the _g_wSavedVga* / _g_bSavedVgaGcReg3 slots
;   Outputs:      none
;   Touches:      AX, BX, DX, DI, ES (no save/restore -- caller already pushed)
;   Side effects: restores GC regs 0/1/4/5/8/3 and SC reg 2 to their saved
;                 values.
; ============================================================================
_vga_restore_registers	proc far
	mov	dx,3c4h				; 3c4h VGA SC index port (out)
	mov	al,2h
	out	dx,al
	mov	ax,[_g_wSavedVgaScReg2AndIdx]
	inc	dx
	out	dx,al
	dec	dx
	mov	al,ah
	out	dx,al
	mov	dx,3ceh				; 3ceh VGA GC index port (out)
	mov	al,3h
	out	dx,al
	mov	al,[_g_bSavedVgaGcReg3]
	inc	dx
	out	dx,al
	dec	dx
	mov	al,8h
	out	dx,al
	mov	ax,[_g_wSavedVgaGcReg5And8]
	inc	dx
	out	dx,al
	dec	dx
	mov	al,5h
	out	dx,al
	inc	dx
	mov	al,[_g_bVgaGcReg5ModeB]
	out	dx,al
	mov	di,0ffffh			; latch via a dummy A000:FFFF read
	mov	bx,0a000h
	mov	es,bx
	mov	al,byte ptr es:[di]
	mov	al,ah
	out	dx,al
	dec	dx
	mov	al,4h
	out	dx,al
	mov	ax,[_g_wSavedVgaGcReg1And4]
	inc	dx
	out	dx,al
	dec	dx
	mov	al,1h
	out	dx,al
	mov	al,ah
	inc	dx
	out	dx,al
	dec	dx
	xor	al,al
	out	dx,al
	mov	ax,[_g_wSavedVgaGcReg0AndIdx]
	inc	dx
	out	dx,al
	dec	dx
	mov	al,ah
	out	dx,al
	retf
_vga_restore_registers	endp

; ============================================================================
; _mouse_restore_handler -- uninstall the mouse.
;
;   If a mouse was installed, clears the flag, issues INT 33h fn 0 (reset),
;   then fn 0Ch with ES:DX = 0:0 and mask 0 to remove the event handler.
;
;   Type:         FAR procedure (public)
;   Category:     Mouse install/teardown
;   Inputs:       none
;   Outputs:      AX -- 1 if it had been installed, else 0
;   Side effects: clears _g_mouse_installed; resets the driver and removes the
;                 handler.
;   Notes:        frameless (no BP set up -- no stack args).
; ============================================================================
_mouse_restore_handler	proc far
	xor	ax,ax
	cmp	byte ptr _g_mouse_installed,al	; was it installed?
	jz	rh_ret				; no -> return 0
	mov	byte ptr _g_mouse_installed,al	; clear flag
	int	33h				; fn 0: reset driver
	mov	ax,0ch				; fn 0Ch: install handler...
	xor	cx,cx				; ...with mask 0 and
	mov	dx,cx				; ES:DX = 0:0 -> remove it
	mov	es,cx
	int	33h
	mov	ax,1				; return 1
rh_ret:
	retf
_mouse_restore_handler	endp

; ============================================================================
; _mouse_get_position(uint *out_x, uint *out_y) -- read the cursor position.
;
;   If a mouse is installed, writes the latched cursor position (mickeys >> 2 =
;   pixels) through the two near out-pointers. If not installed, leaves the
;   out-pointers untouched.
;
;   Type:         FAR procedure (public)
;   Category:     Position/button query
;   Inputs:       [bp+6]=out_x (uint near*), [bp+8]=out_y (uint near*)
;   Outputs:      none (writes through the pointers)
;   Side effects: *out_x, *out_y set to the current pixel position when installed.
; ============================================================================
_mouse_get_position	proc far
	push	bp
	mov	bp,sp
	sub	cx,cx
	mov	dx,cx
	mov	ax,cx
	mov	al,byte ptr _g_mouse_installed
	neg	ax				; CF = installed
	jnc	gp_ret				; not installed -> return
	mov	bx,word ptr [bp+6]		; out_x
	mov	ax,word ptr _g_mouse_x_mickeys
	shr	ax,1				; >> 2 = mickeys -> pixels
	shr	ax,1
	mov	word ptr [bx],ax		; *out_x = x
	mov	bx,word ptr [bp+8]		; out_y
	mov	ax,word ptr _g_mouse_y_mickeys
	shr	ax,1
	shr	ax,1
	mov	word ptr [bx],ax		; *out_y = y
gp_ret:
	pop	bp
	retf
_mouse_get_position	endp

; ============================================================================
; _mouse_set_position(int x, int y) -- set the cursor position.
;
;   If installed, sets the cursor (INT 33h fn 4) to (x,y) in pixels, also
;   caching it as mickeys (pixels << 2) in the latched-position globals.
;
;   Type:         FAR procedure (public)
;   Category:     Position/button query
;   Inputs:       [bp+6]=x, [bp+8]=y (pixels)
;   Outputs:      AX -- 1 if installed, else 0
;   Side effects: sets _g_mouse_x_mickeys / _g_mouse_y_mickeys and the driver
;                 cursor position when installed.
; ============================================================================
_mouse_set_position	proc far
	push	bp
	mov	bp,sp
	mov	al,byte ptr _g_mouse_installed
	neg	al				; CF = installed
	jnc	sp_ret				; not installed -> return 0
	mov	ax,4				; fn 4: set cursor position
	mov	cx,word ptr [bp+6]		; x
	shl	cx,1				; << 2 = pixels -> mickeys
	shl	cx,1
	mov	word ptr _g_mouse_x_mickeys,cx
	mov	dx,word ptr [bp+8]		; y
	shl	dx,1
	shl	dx,1
	mov	word ptr _g_mouse_y_mickeys,dx
	int	33h
	mov	al,1				; AL = 1 (installed)
sp_ret:
	mov	ah,0				; AX = AL (0 or 1)
	pop	bp
	retf
_mouse_set_position	endp

; ============================================================================
; _mouse_button_pressed(int button) -- test one button's pressed bit.
;
;   Returns 1 iff `button` is currently held in the latched button mask, else 0.
;   A SHR by 1 brings the requested button's bit (only 0 or 1 are handled) down
;   to bit 0; the final AND isolates it.
;
;   Type:         FAR procedure (public)
;   Category:     Position/button query
;   Inputs:       [bp+6]=button (0 = left, 1 = right)
;   Outputs:      AX -- 1 if that button is held, else 0 (also 0 if not installed)
;   Side effects: none (pure read of _g_mouse_buttons).
; ============================================================================
_mouse_button_pressed	proc far
	push	bp
	mov	bp,sp
	sub	bx,bx
	mov	bl,byte ptr _g_mouse_installed
	neg	bx				; CF = installed
	jnc	bp_ret				; not installed -> return 0
	mov	bl,byte ptr _g_mouse_buttons	; BL = button mask
	xor	bh,bh				; BX = mask (zero-extended)
	mov	ax,word ptr [bp+6]		; button index
	neg	ax				; CF = (button != 0)
	jnc	bp_ret				; button 0 -> test bit 0 as-is
	shr	bx,1				; button 1 -> shift bit 1 to bit 0
bp_ret:
	mov	ax,bx
	and	ax,1				; isolate bit 0
	pop	bp
	retf
_mouse_button_pressed	endp

S180C_TEXT	ends
	end
