; ============================================================================
; Sx.SSM.ASB.bin -- Dynamix DUDE-format "CMS Sound Blaster" driver
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993).
;
; Packing: TASM + TLINK produce an MZ .EXE; PACKOVL strips the MZ header to
; the flat ORG-0 image, then LZW-packs it into SX.OVL.
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is, and what hardware it actually drives
;
; A sound driver is a small piece of code that the game loads at startup and
; calls every time it wants to make a sound. Different sound cards need
; different code, so the game ships one driver per supported card (AdLib,
; Sound Blaster, Pro AudioSpectrum, Roland MT-32, etc.) and picks the right
; one at runtime based on the user's "sound setup" choice.
;
; The DUDE header's device-name field says "CMS Sound Blaster". The name
; refers to the original Creative Music System / Game Blaster card from
; 1987, which used two Philips SAA1099 square-wave synthesis chips. The
; Sound Blaster v1.0 / v1.5 cards (1989-1991) shipped with the same two
; SAA1099 chips alongside the Yamaha YM3812 (OPL2) FM chip and the
; Creative DSP for digital sample playback.
;
; HOWEVER: this driver does NOT program the SAA1099 chips. It drives only:
;
;   - Sound Blaster DSP at base+6 / base+A / base+C / base+E
;     (reset, read data, write data, buffer status)
;   - 8237 DMA controller (channel 1: ports 0x02, 0x03, 0x0A, 0x0B,
;     0x0C, 0x83 page register)
;   - 8259 PIC at port 0x20 (EOI) and 0x21 (mask register)
;
; In other words: despite the "CMS" in its name, this is a Sound Blaster
; DSP-driven digital sample playback driver, not a square-wave SAA1099
; synthesis driver. The "CMS" prefix in the device name reflects the
; CARD it expects (a Sound Blaster v1.x that happens to have CMS chips
; populated), not the chip it programs. A separate driver file
; `Sx.SSM.ADL.bin` handles the OPL2 FM synthesis side of the same card.
;
; The data section is mostly zero on disk (state buffers and a sample
; ring buffer that the game populates at run-time). The code section is
; about 3.6 KB of probe + DSP-write + DMA-program + dispatch glue.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the Sound Blaster DSP, 8237 DMA, and 8259 PIC
;
; The Sound Blaster card has an internal microcontroller called the "DSP"
; (Digital Signal Processor; a misnomer -- it's actually an Intel 8051
; derivative running custom firmware). The DSP is reached through four
; I/O ports relative to the card's base address (typically 0x220 on real
; hardware, but the driver reads the chosen base from a config byte at
; offset 0x72 + 0x200; see asb_get_info):
;
;   base + 0x6  reset            -- write 1 then 0 to reset the DSP
;   base + 0xA  read data        -- read one byte returned by the DSP
;   base + 0xC  write command    -- write one command/data byte to the DSP
;   base + 0xE  buffer status    -- bit 7 = "a byte is available for read"
;
; Sending a command/data byte to the DSP is "wait until bit 7 of base+0xC
; is clear, then OUT base+0xC, value". Reading a return byte is "wait
; until bit 7 of base+0xE is set, then IN AL, base+0xA". The DSP echoes
; 0xAA on a successful reset; the autoprobe code looks for that.
;
; The DSP plays back a buffer of PCM samples by reading them from system
; RAM via 8237 DMA. The driver:
;   1. Fills the bank buffer with sample data at slot 1 (load_patch_bank).
;   2. Programs the DMA controller (channel 1 by default) to point at
;      the buffer and to count down as samples are consumed.
;   3. Tells the DSP "start auto-init DMA playback at rate N" via a
;      command-byte sequence on base+0xC.
;   4. Services an IRQ when the DMA half-buffer empties, refilling the
;      half just played and acknowledging via the DSP.
;
; The 8237 DMA controller programming this driver uses involves:
;
;   port 0x0A  mask register      -- bit 2 = mask channel; set to suspend,
;                                    clear to allow DMA on channel 1.
;   port 0x0B  mode register      -- selects single/auto-init, read/write,
;                                    address direction, and the channel
;                                    being programmed.
;   port 0x0C  clear byte-pointer -- writes here reset the high/low byte
;                                    latch used for the 16-bit count and
;                                    address registers.
;   port 0x02  channel 1 address  -- 16 bits, written low byte then high.
;   port 0x03  channel 1 count    -- 16 bits, written low byte then high.
;   port 0x83  channel 1 page     -- upper 8 bits of the 24-bit physical
;                                    address.
;
; For DMA to work, the buffer must be in a region that doesn't cross a
; 64 KB page boundary. The driver computes the buffer's flat linear
; address and trims the buffer length if necessary.
;
; IRQ: the SB card asserts a hardware IRQ when each half-buffer's playback
; is complete. The driver installs an ISR at the user's chosen IRQ line
; (default 7 on most SB-1.x configurations). The ISR reads the DSP-ack
; byte from base+0xE, refills the just-played half, and writes EOI (0x20)
; to the master 8259 PIC at port 0x20.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI (this driver's variant)
;
; "DUDE" is Dynamix's internal sound-driver container format. Every driver
; in the family is a flat binary that begins with a header containing two
; magic numbers (0x87654321 and 0xFEDCBA98), an ASCII subsystem tag, a
; human-readable device-name string, and a driver kind. This driver uses
; the v2.x ("audblast"/8-byte-tag) variant of the DUDE header rather than
; the v1.x ("dude"/4-byte-tag) variant used by ADL/M32/etc.
;
; Header layout:
;
;   0x00  JMP rel16              -> entry point (the dispatch trampoline)
;   0x03  pad byte (00)
;   0x04  magic_a = 0x87654321 (LE)
;   0x08  iface version: 2, 8
;   0x0A  tag = "audblast" (8 bytes; NOT "dude" which is 4 bytes)
;   0x12  device_name length (1 byte, Pascal-style)
;   0x13  device name: "CMS Sound Blaster" (17 chars)
;   0x24  magic_b = 0xFEDCBA98 (LE)
;   0x28  driver kind = 4 (LE dword)
;   0x2C  8-byte init curve (00 01 02 03 06 0A 0F 15) -- see asb_init_curve
;
; The game communicates with this driver through a far call into the
; dispatch trampoline at offset 0x08BF. Before the call:
;
;   AX    = slot index (0..15)             -- which operation to invoke
;   SS:SI = pointer to slot arguments      -- per-slot argument block
;
; The dispatch trampoline (18 bytes at 0x08BF):
;
;       PUSH DS                          ; preserve caller DS
;       MOV  BX, AX                      ; slot index <- AX
;       SHL  BX, 1                       ; index -> byte offset (each
;                                          slot is a 2-byte near pointer)
;       MOV  AX, CS                      ; DS = CS so the handler can
;       MOV  DS, AX                      ;   read our data section as DS:
;       CALL CS:[BX + asb_func_table]    ; near indirect call
;       POP  DS                          ; restore caller DS
;       OR   AX, AX                      ; (set ZF based on return value)
;       RETF                             ; far return to game
;
; And there are 16 dispatch slots (not 18 as in ADL). Slot semantics are
; partly inferred from the analysis of each handler; the per-handler
; header comments below explain what is known about each.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions. The first operand is the
;   destination, the second is the source -- read it as "BX = AX".
;
; - `CS:[offset]` is a memory access using the Code Segment register as
;   the base. The dispatch trampoline sets DS := CS up front, so DS and
;   CS reference the same data.
;
; - Functions are wrapped in `name PROC NEAR ... name ENDP`. Inside,
;   labels like `lpb_08f1:` are jump targets local to the function;
;   they're named "<short-prefix>_<hex-address>".
;
; - Numbers ending in `H` are hexadecimal (3FH = 63). Plain numbers are
;   decimal. Numbers starting with a letter need a leading `0`.
;
; - Some helpers are invoked as PUSH CS / CALL near, so they return with
;   RETF (0xCB) instead of RET (0xC3). The pseudo-far-call pattern lets
;   one helper push the caller's CS by hand rather than relying on a
;   real far call.
;
; - IRQ entry stubs end in IRET (0xCF). DOS hooks (INT 1Ch, INT 24h) also
;   use IRET. Plain handlers end in RET.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ============================================================================
; 0x0000  --  DUDE v2 header  (interface 2.8, tag "audblast")
; ============================================================================
_start          LABEL   BYTE
                JMP     asb_dispatch                ; E9 BC 08

                DB      0                           ; pad_03

dude_magic_a    DD      87654321H
dude_iface_ver  DB      2, 8
dude_tag        DB      'audblast'                  ; 8-byte tag variant

device_name_len DB      17
device_name     DB      'CMS Sound Blaster'

dude_magic_b    DD      0FEDCBA98H
dude_driver_kind DD     4

; ----------------------------------------------------------------------------
; 0x002C  --  asb_init_curve  (8 bytes; small lookup table)
;
; Doubles-pattern (each entry roughly 1.5x the previous, ending at 0x15)
; suggests this is a non-linear ramp -- possibly an attack/decay curve
; used by the DSP volume helper at asb_helper_0c8e. Semantics not fully
; confirmed.
; ----------------------------------------------------------------------------
asb_init_curve  DB      00H, 01H, 02H, 03H, 06H, 0AH, 0FH, 15H

; ============================================================================
; 0x0034..0x089E  --  zero-initialized state region (2155 bytes)
;
; The bulk of the data section is per-channel state, ring buffer, and
; saved interrupt vectors. Every byte ships as zero on disk; the engine
; populates these at runtime.
;
; Notable offsets:
;
;   0x0034  asb_stereo          stereo-swap flag (1 byte)
;   0x0035  asb_version         DSP version byte from probe
;   0x0038  asb_flag_38         general flag
;   0x003B  asb_init_state      initialization-step byte
;   0x003C  asb_state_3c        state byte (set during slot dispatch)
;   0x003E  asb_irq_depth       IRQ ISR depth counter
;   0x003F  asb_nest_flag       another nesting flag
;   0x0042  asb_irq_reentry     re-entry guard for IRQ ISR
;   0x0044  asb_dsp_ver         DSP version byte from autoprobe
;   0x0045  asb_probe_step      flag byte (probe step)
;   0x0046  asb_flag_46         flag
;   0x0047  asb_rhythm          rhythm-mode flag
;   0x0048  asb_master_mute     master mute flag
;   0x0049  asb_flag_49         flag
;   0x004B  asb_flag_4b         flag
;   0x004C  asb_flag_4c         flag
;   0x004D  asb_saved_pic_mask  saved PIC mask register
;   0x004E..0x0051  multi-bit flag bank
;   0x0052  asb_flag_52         init flag
;   0x0053  asb_flag_53         init flag
;   0x0054  asb_volume_a        master volume word
;   0x0058  asb_volume_b        secondary master volume
;   0x005A  asb_count           count word
;   0x005C  asb_buf_off         DSP buffer offset (16-bit)
;   0x005E  asb_buf_seg         DSP buffer segment (16-bit)
;   0x0060  asb_buf_size        DSP buffer size (16-bit)
;   0x0062  asb_pos_lo          current playback position low
;   0x0064  asb_pos_hi          current playback position high
;   0x0066  asb_loop_count      loop counter
;   0x0068  asb_half_size       half-buffer size
;   0x006A  asb_counter         another counter
;   0x006C  asb_dma_channel     DMA channel number (default 1)
;   0x006E  asb_port_mirror     port-mirror byte
;   0x0070  asb_master_volume   master volume (word)
;   0x0072  asb_base_port       SB base port (default 0x0220)
;   0x0074  asb_driver_state    driver-state word (probe + flags)
;   0x0076  asb_caller_int25    caller-supplied INT 25h vector pointer
;   0x007A  asb_ring_seg        game-side ring buffer segment
;   0x007C..0x0080  saved interrupt vectors (DOS get-vector)
;   0x0082  asb_play_off        current play pointer offset
;   0x0084  asb_buf_len         buffer length word (running count)
;   0x0086  asb_patch_base      patch-bank base pointer (slot 1 destination)
;   0x008A..0x009D  more saved vectors (INT 4/25/26/35 etc.)
; ============================================================================
                DB      2155 DUP(0)

; ============================================================================
; 0x089F  --  asb_func_table  (16 near pointers; 32 bytes)
;
; The dispatch trampoline indexes this table by `AX * 2`. Each entry is
; a 16-bit near pointer to a slot handler. The 16 slots:
;
;   Slot  0  asb_get_info             -- one-time: probe DSP, hook ints
;   Slot  1  asb_load_patch_bank      -- begin playing a buffered sample
;   Slot  2  asb_reset_voices         -- shutdown: restore vectors
;   Slot  3  asb_slot_3               -- init playback parameters
;   Slot  4  asb_midi_note_off        -- query state
;   Slot  5  asb_midi_note            -- shutdown-stop wrapper
;   Slot  6  asb_slot_6               -- set sample rate
;   Slot  7  asb_slot_7               -- no-op RET stub
;   Slot  8  asb_slot_8               -- clear busy flag
;   Slot  9  asb_slot_9               -- open file, decode chunk
;   Slot 10  asb_slot_10              -- pause/resume
;   Slot 11  asb_slot_11              -- IRQ setup
;   Slot 12  asb_set_master_volume    -- stop playback
;   Slot 13  asb_slot_13              -- query playback position
;   Slot 14  asb_slot_14              -- xor ax,ax; ret  (no-op)
;   Slot 15  asb_slot_15              -- no-op RET stub
;
; The slot-to-handler mapping diverges from APA in non-trivial ways
; (the names above borrow APA's vocabulary where the handler structure
; matches APA's, but ASB is its own driver with its own semantics).
; ============================================================================
asb_func_table  LABEL   WORD
                DW      asb_get_info                ; slot  0  -- 0x13E6
                DW      asb_load_patch_bank         ; slot  1  -- 0x08D1
                DW      asb_reset_voices            ; slot  2  -- 0x09F8
                DW      asb_slot_3                  ; slot  3  -- 0x0933
                DW      asb_midi_note_off           ; slot  4  -- 0x09CF
                DW      asb_midi_note               ; slot  5  -- 0x09F4
                DW      asb_slot_6                  ; slot  6  -- 0x08F8
                DW      asb_slot_7                  ; slot  7  -- 0x0905
                DW      asb_slot_8                  ; slot  8  -- 0x0906
                DW      asb_slot_9                  ; slot  9  -- 0x0CB5
                DW      asb_slot_10                 ; slot 10  -- 0x0F2B
                DW      asb_slot_11                 ; slot 11  -- 0x0F46
                DW      asb_set_master_volume       ; slot 12  -- 0x090F
                DW      asb_slot_13                 ; slot 13  -- 0x12BC
                DW      asb_slot_14                 ; slot 14  -- 0x0CB2
                DW      asb_slot_15                 ; slot 15  -- 0x08F7

; ============================================================================
; 0x08BF  --  asb_dispatch  --  the trampoline (18 bytes)
;
;   The ONLY far-callable entry point the game ever calls. The game does:
;
;       MOV  AX, <slot index>
;       <other regs per the slot's convention>
;       CALL FAR asb_seg:asb_dispatch
;
;   The trampoline saves DS, sets DS := CS so the handler can use the
;   data section through DS without a CS: override, does a near indirect
;   CALL through asb_func_table, restores DS, sets flags from AX, and
;   far-returns to the caller.
;
;   Type:        Dispatch trampoline (PROC FAR -- the only one in the file)
;   Category:    DUDE dispatch ABI
;   Callers:     game engine, via CALL FAR <asb_seg>:asb_dispatch
;   Callees:     whichever asb_func_table[AX] entry the slot index selects
;
;   Inputs:
;     AX     --  slot index (0..15)
;     SS:SI  --  pointer to slot-specific argument block (handler-defined)
;
;   Outputs:
;     AX     --  per-slot return value (zero on success in most slots);
;                ZF reflects AX on RETF (set by the OR AX, AX before
;                RETF) so the caller can JZ/JNZ on it.
;
;   Touches:     BX, AX; DS restored on exit.
; ============================================================================
asb_dispatch    PROC    FAR
                PUSH    DS
                MOV     BX, AX
                SHL     BX, 1
                MOV     AX, CS
                MOV     DS, AX
                CALL    WORD PTR CS:[BX + asb_func_table]
                POP     DS
                OR      AX, AX
                RETF
asb_dispatch    ENDP

; ============================================================================
; FUNCTION BODIES
;
; Each function below is emitted as `name PROC NEAR ... name ENDP`. Helpers
; called via `PUSH CS / CALL <name>` (simulated far call) return with RETF;
; helpers called via plain CALL return with RET.
; ============================================================================


; ----------------------------------------------------------------------------
; 0x08D1  --  asb_load_patch_bank  (38 bytes)
;
;   Slot 1 of the dispatch table. Despite its name (borrowed from the ADL
;   driver's slot 1), this handler does NOT load a patch bank in the
;   ASB driver -- it's the "service the buffer" tick. The game calls
;   this periodically to drive playback forward: if the driver isn't
;   suspended AND has been fully initialized AND isn't master-muted,
;   bump the master-volume counter and refill / advance the buffer.
;
;   Type:        Slot handler
;   Category:    Buffer servicing
;   Dispatch:    Slot 1 (called as: AX=1 -- no SS:SI argument block used)
;   Callees:     asb_helper_1242 (advance state machine), asb_helper_0fd9
;                (run the buffer producer).
;
;   Inputs:      none
;   Outputs:     AX = 0 (success)
;   Touches:     AX clobbered.
; ----------------------------------------------------------------------------
asb_load_patch_bank     PROC    NEAR
                CMP     BYTE PTR CS:[52H], 1
                JE      lpb_08f4
                CMP     BYTE PTR CS:[3BH], 1
                JNE     lpb_08f4
                CMP     BYTE PTR CS:[48H], 0
                JNE     lpb_08f1
                INC     WORD PTR CS:[70H]
                CALL    asb_helper_1242
lpb_08f1:       CALL    asb_helper_0fd9
lpb_08f4:       XOR     AX, AX
                RET     
asb_load_patch_bank     ENDP

; ----------------------------------------------------------------------------
; 0x08F7  --  asb_slot_15  (1 byte)
;
;   Bare-RET stub. Slot 15 in the dispatch table.
;
;   Type:        Slot handler (ABI placeholder; no caller observed in
;                  this driver -- may be reserved for future use, or
;                  invoked by game code we haven't analysed yet. Present
;                  so the slot table has the right shape).
;   Dispatch:    Slot 15 (AX=15)
;   Inputs:      none      Outputs: (return value not set explicitly --
;                                    caller observes whatever AX held)
; ----------------------------------------------------------------------------
asb_slot_15             PROC    NEAR
                RET     
asb_slot_15             ENDP

; ----------------------------------------------------------------------------
; 0x08F8  --  asb_slot_6  (13 bytes)
;
;   Slot 6 in the dispatch table -- sets the sample rate. The game passes
;   a 16-bit sample-rate value in SS:[SI]; we cache it at CS:[74H]
;   (asb_driver_state slot) and then call asb_helper_0bbd, which converts
;   the rate into the DSP "time constant" byte and programs the DSP via
;   command 0x40.
;
;   Type:        Slot handler
;   Category:    DSP setup
;   Dispatch:    Slot 6 (AX=6, SS:SI -> WORD sample_rate_hz)
;   Callees:     asb_helper_0bbd (compute & write DSP time constant).
;
;   Inputs:      SS:[SI] -- desired sample rate (Hz).
;   Outputs:     AX = 0 (success).
;   Touches:     AX, CX, DX clobbered (via the helper).
; ----------------------------------------------------------------------------
asb_slot_6              PROC    NEAR
                MOV     AX, SS:[SI]
                MOV     CS:[74H], AX
                CALL    asb_helper_0bbd
                XOR     AX, AX
                RET     
asb_slot_6              ENDP

; ----------------------------------------------------------------------------
; 0x0905  --  asb_slot_7  (1 byte)
;
;   Bare-RET stub. Slot 7 in the dispatch table.
;
;   Type:        Slot handler (ABI placeholder; no caller observed in
;                  this driver -- may be reserved for future use, or
;                  invoked by game code we haven't analysed yet).
;   Dispatch:    Slot 7 (AX=7)
; ----------------------------------------------------------------------------
asb_slot_7              PROC    NEAR
                RET     
asb_slot_7              ENDP

; ----------------------------------------------------------------------------
; 0x0906  --  asb_slot_8  (9 bytes)
;
;   Slot 8 in the dispatch table -- clear the master-mute flag. After
;   this returns, asb_load_patch_bank's "if master-mute is set, skip the
;   refill" path no longer kicks in.
;
;   Type:        Slot handler
;   Category:    Master mixer control
;   Dispatch:    Slot 8 (AX=8 -- no argument block)
;   Inputs:      none
;   Outputs:     AX = 0
;   Side effects: asb_master_mute (CS:[48H]) <- 0.
; ----------------------------------------------------------------------------
asb_slot_8              PROC    NEAR
                MOV     BYTE PTR CS:[48H], 0
                XOR     AX, AX
                RET     
asb_slot_8              ENDP

; ----------------------------------------------------------------------------
; 0x090F  --  asb_set_master_volume  (36 bytes)
;
;   Slot 12 in the dispatch table -- stop playback and reset the master-
;   volume state. If the driver is already suspended (CS:[52H] == 1) this
;   is a no-op; otherwise we set the suspended flag, speaker-off the DSP
;   (asb_helper_0c1b), acknowledge any pending IRQ on the DMA-IRQ line
;   (asb_helper_0b14), and restore the saved PIC mask via asb_helper_0c8e.
;
;   Type:        Slot handler
;   Category:    Playback control
;   Dispatch:    Slot 12 (AX=12 -- no argument block)
;   Callers:     asb_midi_note (slot 5), asb_slot_3 (slot 3),
;                asb_slot_9 (slot 9), asb_reset_voices (slot 2)
;   Callees:     asb_helper_0c1b (DSP speaker-off),
;                asb_helper_0b14 (DSP IRQ ack),
;                asb_helper_0c8e (restore PIC mask, unhook ISR).
;
;   Inputs:      none.
;   Outputs:     AX = 0.
;   Side effects:
;     asb_flag_52 (CS:[52H]) <- 1 (driver suspended).
;     DSP speaker disabled; 8259 PIC mask restored to pre-driver value.
; ----------------------------------------------------------------------------
asb_set_master_volume   PROC    NEAR
                CMP     BYTE PTR CS:[52H], 1
                JE      smv_0930
                MOV     BYTE PTR CS:[52H], 1
                PUSH    CS
                CALL    asb_helper_0c1b
                PUSH    CS
                CALL    asb_helper_0b14
                MOV     AL, CS:[44H]
                MOV     BX, 86H
                PUSH    CS
                CALL    asb_helper_0c8e
smv_0930:       XOR     AX, AX
                RET     
asb_set_master_volume   ENDP

; ----------------------------------------------------------------------------
; 0x0933  --  asb_slot_3  (156 bytes)
;
;   Slot 3 in the dispatch table -- initialize playback. Takes the
;   buffer's seg:off, length, and sample-rate parameters from the
;   SS:SI argument block, programs the DSP time constant, normalizes
;   the buffer linear address via asb_helper_segoff (to handle the
;   64 KB DMA page-boundary case), installs the DMA-IRQ ISR via
;   asb_helper_0c50, and clears the "suspended" flag.
;
;   Type:        Slot handler
;   Category:    Playback setup
;   Dispatch:    Slot 3 (AX=3, SS:SI -> argument block:
;                  [SI+0]  WORD  stereo / loop flags
;                  [SI+2]  WORD  sample rate (Hz)
;                  [SI+4]  WORD  buffer offset
;                  [SI+6]  WORD  buffer segment
;                  [SI+8]  WORD  buffer length in samples)
;   Callees:     asb_set_master_volume (stop any in-progress playback),
;                asb_helper_0bbd (program DSP time constant),
;                asb_helper_segoff (normalize seg:off -> page+offset),
;                asb_helper_0c50 (install DMA-IRQ ISR at 0xB22),
;                asb_helper_0a3d (start the DMA cycle).
;
;   Inputs:      SS:[SI..SI+8] -- argument block (see above).
;   Outputs:     none (AX clobbered).
;   Side effects:
;     Driver state at CS:[34H..70H] is initialized; the DMA controller
;     is programmed and the DSP is started playing.
; ----------------------------------------------------------------------------
asb_slot_3              PROC    NEAR
                PUSH    SI
                CALL    asb_set_master_volume
                POP     SI
                MOV     AX, SS:[SI]
                OR      AH, AH
                JNE     s3_0947
                MOV     BYTE PTR CS:[46H], 0
                JMP     s3_094d
s3_0947:        MOV     BYTE PTR CS:[46H], 1
s3_094d:        MOV     AX, SS:[SI+2]
                CALL    asb_helper_0bbd
                MOV     AX, SS:[SI+4]
                MOV     DX, SS:[SI+6]
                PUSH    CS
                CALL    asb_helper_segoff
                MOV     CS:[34H], DL
                MOV     CS:[56H], AX
                MOV     AX, SS:[SI+8]
                MOV     CS:[54H], AX
                ADD     AX, CS:[56H]
                JAE     s3_0991
                MOV     CS:[58H], AX
                SUB     CS:[54H], AX
                MOV     WORD PTR CS:[5AH], 0
                INC     DL
                MOV     CS:[35H], DL
                JMP     s3_0998
s3_0991:        MOV     WORD PTR CS:[58H], 0
s3_0998:        MOV     AL, CS:[44H]
                MOV     DX, 0B22H
                MOV     BX, 86H
                PUSH    CS
                CALL    asb_helper_0c50
                MOV     BYTE PTR CS:[4BH], 0
                MOV     BYTE PTR CS:[3BH], 0
                MOV     BYTE PTR CS:[3DH], 1
                CALL    asb_helper_0a3d
                MOV     WORD PTR CS:[70H], 0
                MOV     BYTE PTR CS:[52H], 0
                MOV     BYTE PTR CS:[45H], 0
                RET     
asb_slot_3              ENDP

; ----------------------------------------------------------------------------
; 0x09CF  --  asb_midi_note_off  (37 bytes)
;
;   Slot 4 in the dispatch table -- query state. Despite the name (which
;   echoes the ADL driver's slot 4), this handler does NOT stop a MIDI
;   note in the ASB driver. It reads the loop flag from SS:[SI], updates
;   asb_flag_46, returns the current suspended flag in AL and the probe-
;   step / ready flag in AH, and clears asb_probe_step.
;
;   Type:        Slot handler
;   Category:    State query
;   Dispatch:    Slot 4 (AX=4, SS:SI -> WORD loop_flag)
;
;   Inputs:      SS:[SI] -- loop / one-shot flag (high byte: 0 = one-shot,
;                                                 nonzero = loop).
;   Outputs:     AL = asb_flag_52 (1 = driver suspended).
;                AH = asb_probe_step (previous value before clear).
;   Side effects:
;     asb_flag_46 set per the input flag; asb_probe_step cleared.
; ----------------------------------------------------------------------------
asb_midi_note_off       PROC    NEAR
                MOV     AX, SS:[SI]
                OR      AH, AH
                JNE     noff_09de
                MOV     BYTE PTR CS:[46H], 0
                JMP     noff_09e4
noff_09de:      MOV     BYTE PTR CS:[46H], 1
noff_09e4:      MOV     AL, CS:[52H]
                MOV     AH, CS:[45H]
                MOV     BYTE PTR CS:[45H], 0
                RET     
asb_midi_note_off       ENDP

; ----------------------------------------------------------------------------
; 0x09F4  --  asb_midi_note  (4 bytes)
;
;   Slot 5 in the dispatch table -- shutdown-stop wrapper. A one-line
;   thunk that just tail-calls asb_set_master_volume. Despite the name
;   (which echoes ADL's slot 5), this is NOT "play a MIDI note" in the
;   ASB driver -- it's the user-facing "stop now" entry point.
;
;   Type:        Slot handler
;   Category:    Playback control
;   Dispatch:    Slot 5 (AX=5 -- no argument block)
;   Callees:     asb_set_master_volume.
;
;   Inputs:      none      Outputs: AX = 0 (from the tail call)
; ----------------------------------------------------------------------------
asb_midi_note           PROC    NEAR
                CALL    asb_set_master_volume
                RET     
asb_midi_note           ENDP

; ----------------------------------------------------------------------------
; 0x09F8  --  asb_reset_voices  (69 bytes)
;
;   Slot 2 in the dispatch table -- shutdown the driver. Restores the
;   three saved interrupt vectors that asb_get_info installed (INT 0x10,
;   INT 0x0D, INT 0x74), closes the file handle at asb_caller_int25,
;   and returns. The "reset voices" name echoes the ADL slot 2; for
;   this driver it's the driver-unload path.
;
;   Type:        Slot handler
;   Category:    Driver shutdown
;   Dispatch:    Slot 2 (AX=2 -- no argument block)
;   Callees:     asb_set_master_volume; DOS INT 21h services
;                AH=25h (set vector), AH=3Eh (close file).
;
;   Inputs:      none.
;   Outputs:     AX = 0.
;   Side effects:
;     Three IVT vectors restored to their pre-driver values; open file
;     handle (if any) closed; CS:[76H] reset to 0xFFFF.
; ----------------------------------------------------------------------------
asb_reset_voices        PROC    NEAR
                CALL    asb_set_master_volume
                PUSH    DS
                LDS     DX, CS:[9AH]
                MOV     AH, 25H
                MOV     AL, 10H
                INT     21H
                POP     DS
                PUSH    DS
                LDS     DX, CS:[92H]
                MOV     AH, 25H
                MOV     AL, 0DH
                INT     21H
                POP     DS
                PUSH    DS
                LDS     DX, CS:[96H]
                MOV     AH, 25H
                MOV     AL, 74H
                INT     21H
                POP     DS
                CMP     WORD PTR CS:[76H], 0FFFFH
                JE      rv_0a3a
                MOV     BX, CS:[76H]
                MOV     AH, 3EH
                INT     21H
                MOV     WORD PTR CS:[76H], 0FFFFH
rv_0a3a:        XOR     AX, AX
                RET     
asb_reset_voices        ENDP

; ----------------------------------------------------------------------------
; 0x0A3D  --  asb_helper_0a3d  (88 bytes)
;
;   Select which buffer half to play next (based on the asb_flag_4b
;   toggle) and call asb_helper_0a95 to actually program the 8237 DMA
;   controller and kick the DSP. If we're in a state where the next
;   half isn't ready yet (rhythm mode + initial half flag), bails
;   out without programming DMA.
;
;   Type:        Internal helper (DMA-cycle launcher)
;   Category:    DMA / DSP control
;   Callers:     asb_slot_3, asb_isr_dma_complete (the IRQ handler),
;                asb_helper_1242 (state-machine refill).
;   Callees:     asb_helper_0a95 (the actual DMA programmer; called
;                via PUSH CS / CALL so it returns RETF).
;
;   Inputs:      reads driver state through CS:.
;   Outputs:     none.
;   Touches:     AX, CX, DL clobbered.
;
;   Side effects:
;     asb_dma_channel-mirror (CS:[6CH]), asb_page_byte (CS:[39H]),
;     asb_dma_addr (CS:[6EH]) all updated with the chosen-half values
;     before launching DMA.
; ----------------------------------------------------------------------------
asb_helper_0a3d         PROC    NEAR
                CMP     BYTE PTR CS:[4BH], 0
                JNE     h0a3d_0a55
                MOV     DL, CS:[34H]
                MOV     AX, CS:[56H]
                MOV     CX, CS:[54H]
                JMP     h0a3d_0a63
h0a3d_0a55:     MOV     DL, CS:[35H]
                MOV     AX, CS:[5AH]
                MOV     CX, CS:[58H]
h0a3d_0a63:     MOV     CS:[6CH], CX
                MOV     CS:[39H], DL
                MOV     CS:[6EH], AX
                CMP     BYTE PTR CS:[3BH], 1
                JNE     h0a3d_0a90
                CMP     BYTE PTR CS:[49H], 1
                JNE     h0a3d_0a90
                CMP     BYTE PTR CS:[3DH], 0
                JNE     h0a3d_0a8a
                RET     
h0a3d_0a8a:     MOV     BYTE PTR CS:[3DH], 0
h0a3d_0a90:     PUSH    CS
                CALL    asb_helper_0a95
                RET     
asb_helper_0a3d         ENDP

; ----------------------------------------------------------------------------
; 0x0A95  --  asb_helper_0a95  (127 bytes)
;
;   Program the 8237 DMA controller channel 1 to point at the current
;   half-buffer and send the DSP "begin single-cycle DMA playback at
;   8-bit (cmd 0x14) or 16-bit (cmd 0x1C) format" command sequence. The
;   16-bit branch sends DSP command 0x1C only; the 8-bit branch sends
;   0x14 followed by the (count-1) byte pair, which is the classic SB
;   "single-cycle playback of N samples" sequence.
;
;   Type:        Internal helper (8237 DMA programmer + DSP starter)
;   Category:    DMA / DSP control
;   Callers:     asb_helper_0a3d (via plain CALL, but issues RETF --
;                this helper was originally PUSH CS / CALL-invoked).
;   Callees:     asb_dsp_wait_ready (via PUSH CS / CALL).
;
;   Inputs:      reads driver state through CS:.
;   Outputs:     none.
;
;   Side effects:
;     - 8237 DMA: port 0x0A <- 0x05 (mask channel 1).
;     - Port 0x0C <- anything (clear hi/lo latch).
;     - Port 0x02 <- DMA address (lo then hi).
;     - Port 0x0B <- mode register (0x49 single-cycle, 0x59 auto-init).
;     - Port 0x83 <- DMA page register (high 8 bits of physical addr).
;     - Port 0x03 <- DMA count (lo then hi, value = nsamples-1).
;     - Port 0x0A <- 0x01 (unmask channel 1).
;     - DSP: cmd 0x14 / 0x1C + LSB(count-1) + MSB(count-1).
; ----------------------------------------------------------------------------
asb_helper_0a95         PROC    NEAR
                MOV     AL, 5
                OUT     0AH, AL
                XOR     AL, AL
                OUT     0CH, AL
                MOV     AX, CS:[6EH]
                OUT     2, AL
                MOV     AL, AH
                OUT     2, AL
                MOV     AL, 49H
                MOV     CX, CS:[6CH]
                CMP     BYTE PTR CS:[3BH], 1
                JNE     h0a95_0ac2
                CMP     BYTE PTR CS:[49H], 1
                JNE     h0a95_0ac2
                MOV     AL, 59H
                SHL     CX, 1
h0a95_0ac2:     MOV     CS:[6AH], CX
                OUT     0BH, AL
                MOV     AL, CS:[39H]
                OUT     83H, AL
                MOV     AX, CX
                DEC     AX
                OUT     3, AL
                MOV     AL, AH
                OUT     3, AL
                MOV     AL, 1
                OUT     0AH, AL
                MOV     DX, CS:[72H]
                ADD     DL, 0CH
                CMP     BYTE PTR CS:[3BH], 1
                JNE     h0a95_0afb
                CMP     BYTE PTR CS:[49H], 1
                JNE     h0a95_0afb
                MOV     AL, 1CH
                PUSH    CS
                CALL    asb_dsp_wait_ready
                RETF    
h0a95_0afb:     MOV     AL, 14H
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     CX, CS:[6CH]
                DEC     CX
                MOV     AL, CL
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     AL, CH
                PUSH    CS
                CALL    asb_dsp_wait_ready
                RETF    
asb_helper_0a95         ENDP

; ----------------------------------------------------------------------------
; 0x0B14  --  asb_helper_0b14  (14 bytes)
;
;   The first half of the original 169-byte glued block at 0xB14. This is
;   the "DSP DMA-IRQ acknowledge" sequence: mask DMA channel 1, read the
;   DSP buffer-status port at base+0xE (the act of READING that port clears
;   the SB card's pending IRQ line), then far-return to the caller. The
;   far-return is because this is invoked via PUSH CS / CALL near (the
;   pseudo-far-call idiom).
;
;   Type:        Internal helper (DSP-IRQ acknowledge)
;   Category:    Sound Blaster DSP I/O
;   Callers:     asb_set_master_volume (line 411 in source);
;                asb_isr_dma_complete (line 0xB22 -- ISR re-enters here
;                from inside the ISR body to acknowledge the IRQ a second
;                time when running in stereo/16-bit mode and an extra
;                ack is required between halves).
;   Callees:     none.
;
;   Inputs:      none (reads CS:[72H] = asb_base_port).
;   Outputs:     none (AL clobbered with the DSP status byte; ignored).
;   Touches:     AL, DX clobbered.
;
;   Side effects:
;     - 8237 DMA mask register (port 0x0A) <- 0x05 (mask channel 1).
;     - Reads DSP buffer-status at asb_base_port + 0x0E to clear the
;       SB card's pending IRQ on the PIC line.
;
;   Notes:
;     This PROC used to be glued to the ISR body that now lives in
;     asb_isr_dma_complete (split apart at 0xB22; the bytes themselves
;     are unchanged). The recursive `CALL asb_helper_0b14` inside the
;     ISR body targets the start of THIS routine (the DSP ack), not
;     the ISR.
; ----------------------------------------------------------------------------
asb_helper_0b14         PROC    NEAR
                MOV     AL, 5
                OUT     0AH, AL
                MOV     DX, CS:[72H]
                ADD     DL, 0EH
                IN      AL, DX
                RETF
asb_helper_0b14         ENDP

; ----------------------------------------------------------------------------
; 0x0B22  --  asb_isr_dma_complete  (155 bytes)
;
;   The Sound Blaster DSP-completion IRQ handler. The DSP asserts the
;   card's hardware IRQ line (default 7) whenever a half-buffer of DMA
;   PCM samples has finished playing; the 8259 PIC then vectors here.
;   Installed at slot-3 setup time and at slot-11 (IRQ-setup) via
;   asb_helper_0c50 -- caller passes `DX = 0B22H` and the helper writes
;   this routine's CS:offset into the real-mode IVT entry corresponding
;   to the chosen IRQ line. The ISR ends in IRET (returns from interrupt,
;   pops flags + CS + IP) rather than RET / RETF.
;
;   Type:        Interrupt service routine (hardware IRQ vector)
;   Category:    DMA / IRQ servicing
;   Reached by:  CPU hardware vectoring (NOT called by other code in
;                this driver).
;   Callees:
;     asb_helper_0b14         -- DSP IRQ acknowledge (in stereo path)
;     asb_helper_1238         -- mid-suspend refill flag set
;     asb_helper_0a3d         -- DMA reprogram for next buffer half
;     asb_midi_note           -- fallback when not currently playing
;
;   Inputs:      none (re-reads driver state through CS:).
;   Outputs:     none.
;   Touches:     all registers preserved (saves DS / DX / AX / CX / BX /
;                SI / DI / ES / BP on entry, pops them in reverse on
;                exit; flags restored by IRET).
;
;   Side effects:
;     - Reads asb_base_port + 0x0E to clear the SB card's IRQ.
;     - Writes EOI (0x20) to the 8259 master PIC at port 0x20 to tell
;       the PIC the IRQ has been serviced.
;     - Bumps the running play-position counter at CS:[62H..64H].
;     - May refill the just-played half-buffer via asb_helper_0a3d.
;
;   Notes:
;     The IRET-tail return path means CS:IP and FLAGS were pushed by the
;     CPU at vector time; nothing else has saved them. Re-entry into this
;     ISR is guarded only by the IF (interrupt-enable) flag in EFLAGS,
;     which the CPU clears on vectoring; we leave it clear for the whole
;     body and let IRET pop the saved (originally-set) IF back.
; ----------------------------------------------------------------------------
asb_isr_dma_complete    PROC    NEAR
                PUSH    DS
                PUSH    DX
                PUSH    AX
                PUSH    CX
                PUSH    BX
                PUSH    SI
                PUSH    DI
                PUSH    ES
                PUSH    BP
                CLD
                MOV     AX, CS
                MOV     DS, AX
                CMP     BYTE PTR CS:[3BH], 1
                JNE     dmaisr_0b7b
                CMP     BYTE PTR CS:[49H], 1
                JNE     dmaisr_0b5b
                XOR     BYTE PTR CS:[3AH], 1
                JNE     dmaisr_0b6e
                MOV     AX, CS:[6CH]
                SHL     AX, 1
                ADD     CS:[64H], AX
                ADC     WORD PTR CS:[62H], 0
                JMP     dmaisr_0b6e
dmaisr_0b5b:    MOV     AX, CS:[6CH]
                ADD     CS:[64H], AX
                ADC     WORD PTR CS:[62H], 0
                PUSH    CS
                CALL    asb_helper_0b14
dmaisr_0b6e:    CMP     BYTE PTR CS:[52H], 1
                JE      dmaisr_0ba6
                CALL    asb_helper_1238
                JMP     dmaisr_0ba6
dmaisr_0b7b:    CMP     WORD PTR CS:[58H], 0
                JE      dmaisr_0b90
                XOR     BYTE PTR CS:[4BH], 1
                JE      dmaisr_0b90
                CALL    asb_helper_0a3d
                JMP     dmaisr_0ba6
dmaisr_0b90:    CMP     BYTE PTR CS:[46H], 1
                JNE     dmaisr_0ba3
                CALL    asb_helper_0a3d
                MOV     BYTE PTR CS:[45H], 1
                JMP     dmaisr_0ba6
dmaisr_0ba3:    CALL    asb_midi_note
dmaisr_0ba6:    MOV     DX, CS:[72H]
                ADD     DL, 0EH
                IN      AL, DX
                MOV     AL, 20H
                OUT     20H, AL
                POP     BP
                POP     ES
                POP     DI
                POP     SI
                POP     BX
                POP     CX
                POP     AX
                POP     DX
                POP     DS
                IRET
asb_isr_dma_complete    ENDP

; ----------------------------------------------------------------------------
; 0x0BBD  --  asb_helper_0bbd  (39 bytes)
;
;   Program the DSP "time constant" -- the value that selects the
;   playback sample rate. The DSP formula is `time_constant = 256 -
;   (1000000 / sample_rate_hz)`. The code computes 0x40 / rate (via
;   DIV) into AL, then negates AL, then sends DSP command 0x40 + the
;   time-constant byte.
;
;   Type:        Internal helper (DSP rate programmer)
;   Category:    DSP I/O
;   Callers:     asb_get_info (init), asb_slot_6 (slot 6 rate set),
;                asb_helper_0ea4 (decoded-rate set), asb_slot_11 (IRQ
;                setup), asb_slot_3 (playback start).
;   Callees:     asb_dsp_wait_ready.
;
;   Inputs:
;     AX  --  desired sample rate (Hz).
;
;   Outputs:     none (DSP programmed; AL = time constant on exit).
;   Side effects:
;     asb_sample_rate_cache (CS:[80H]) <- AX (the rate, cached for
;     later playback-position math).
; ----------------------------------------------------------------------------
asb_helper_0bbd         PROC    NEAR
                MOV     CS:[80H], AX
                MOV     CX, AX
                MOV     DX, 0FH
                MOV     AX, 4240H
                DIV     CX
                MOV     CL, AL
                NEG     CL
                MOV     DX, CS:[72H]
                ADD     DL, 0CH
                MOV     AL, 40H
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     AL, CL
                PUSH    CS
                CALL    asb_dsp_wait_ready
                RET     
asb_helper_0bbd         ENDP

; ----------------------------------------------------------------------------
; 0x0BE4  --  asb_helper_0be4  (35 bytes)
;
;   Send the DSP "block-size set" command (0x48) + 16-bit count. Used
;   by slot 9 to tell the DSP how many bytes are in the next playback
;   block when streaming PCM from disk in chunks. Saves all clobbered
;   registers, so callers can use this without losing context.
;
;   Type:        Internal helper (DSP block-size programmer)
;   Category:    DSP I/O
;   Callers:     asb_slot_9.
;   Callees:     asb_dsp_wait_ready.
;
;   Inputs:
;     AX  --  block size in bytes (16-bit, low/high pair).
;
;   Outputs:     none.
;   Touches:     all caller registers preserved (saves AX/CX/DX).
; ----------------------------------------------------------------------------
asb_helper_0be4         PROC    NEAR
                PUSH    AX
                PUSH    CX
                PUSH    DX
                MOV     CX, AX
                MOV     DX, CS:[72H]
                ADD     DL, 0CH
                MOV     AL, 48H
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     AL, CL
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     AL, CH
                PUSH    CS
                CALL    asb_dsp_wait_ready
                POP     DX
                POP     CX
                POP     AX
                RET     
asb_helper_0be4         ENDP

; ----------------------------------------------------------------------------
; 0x0C07  --  asb_helper_segoff  (20 bytes)
;
;   Normalize a real-mode seg:off pair into a 20-bit linear address and
;   split it into (DMA page, 16-bit offset). The 8237 DMA controller
;   uses a "page" register holding the upper 8 bits of the 24-bit
;   physical address and a 16-bit offset register for the lower bits.
;   This helper transforms a segment:offset pair into that representation.
;
;   Type:        Internal helper (real-mode -> DMA addressing)
;   Category:    Address arithmetic
;   Callers:     asb_slot_3, asb_slot_9, asb_init_setup.
;
;   Inputs:
;     DX  --  segment.
;     AX  --  offset.
;
;   Outputs:
;     DX  --  high 4 bits of segment (DMA page byte).
;     AX  --  20-bit linear address (low 16 bits).
;
;   Touches:     CX restored by PUSH/POP.
;
;   Notes:
;     Returns RETF -- always invoked as PUSH CS / CALL.
; ----------------------------------------------------------------------------
asb_helper_segoff       PROC    NEAR
                PUSH    CX
                MOV     CL, 4
                ROL     DX, CL
                MOV     CX, DX
                AND     DX, 0FH
                AND     CX, 0FFF0H
                ADD     AX, CX
                ADC     DX, 0
                POP     CX
                RETF    
asb_helper_segoff       ENDP

; ----------------------------------------------------------------------------
; 0x0C1B  --  asb_helper_0c1b  (20 bytes)
;
;   Send DSP command 0xD0 (halt 8-bit DMA / "speaker off") then poll
;   base+0x0C bit 7 until the DSP reports "ready" -- this serves both
;   as a hard stop and as a wait-for-DSP-quiescent guard.
;
;   Type:        Internal helper (DSP halt)
;   Category:    DSP I/O
;   Callers:     asb_set_master_volume; asb_helper_1242.
;   Callees:     asb_dsp_wait_ready (PUSH CS / CALL).
;
;   Inputs:      none (reads asb_base_port).
;   Outputs:     none.
;
;   Notes:
;     Returns RETF.
; ----------------------------------------------------------------------------
asb_helper_0c1b         PROC    NEAR
                MOV     DX, CS:[72H]
                ADD     DL, 0CH
                MOV     AL, 0D0H
                PUSH    CS
                CALL    asb_dsp_wait_ready
h0c1b_0c29:     IN      AL, DX
                OR      AL, AL
                JS      h0c1b_0c29
                RETF    
asb_helper_0c1b         ENDP

; ----------------------------------------------------------------------------
; 0x0C2F  --  asb_helper_0c2f  (20 bytes)
;
;   Send DSP command 0xD4 (continue 8-bit DMA) then poll base+0x0C bit
;   7 until the DSP reports "ready". The companion to asb_helper_0c1b
;   (0xD0 halt) -- used to resume after a temporary pause.
;
;   Type:        Internal helper (DSP DMA resume)
;   Category:    DSP I/O
;   Callers:     asb_helper_1242 (mid-playback resume).
;   Callees:     asb_dsp_wait_ready (PUSH CS / CALL).
;
;   Inputs:      none.      Outputs: none.
;
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_helper_0c2f         PROC    NEAR
                MOV     DX, CS:[72H]
                ADD     DL, 0CH
                MOV     AL, 0D4H
                PUSH    CS
                CALL    asb_dsp_wait_ready
h0c2f_0c3d:     IN      AL, DX
                OR      AL, AL
                JS      h0c2f_0c3d
                RETF    
asb_helper_0c2f         ENDP

; ----------------------------------------------------------------------------
; 0x0C43  --  asb_dsp_wait_ready  (13 bytes)
;
;   Poll the DSP command-port write-busy bit (bit 7 of base+0x0C) until
;   it's clear, then write one byte to the DSP. This is the universal
;   "send one byte to the DSP" primitive used by every other DSP I/O
;   helper in this file.
;
;   Type:        Internal helper (atomic DSP byte-write with wait)
;   Category:    DSP I/O
;   Callers:     ~12 helpers including asb_helper_0bbd, _0be4, _0c1b,
;                _0c2f, _0a95, asb_init_setup, asb_dsp_simple,
;                asb_dsp_get_version.
;
;   Inputs:
;     AL  --  byte to send to the DSP.
;     DX  --  DSP command port (must be base+0x0C).
;
;   Outputs:     none.
;   Touches:     AH (temporary holding the byte).
;
;   Notes:
;     Returns RETF -- the helper is *always* invoked via PUSH CS / CALL.
;     The 5-byte timing-budget polling loop is the canonical "DSP busy"
;     idiom (see glossary).
; ----------------------------------------------------------------------------
asb_dsp_wait_ready      PROC    NEAR
                MOV     AH, AL
                MOV     AL, 0F0H
dwr_0c47:       IN      AL, DX
                OR      AL, AL
                JS      dwr_0c47
                MOV     AL, AH
                OUT     DX, AL
                RETF    
asb_dsp_wait_ready      ENDP

; ----------------------------------------------------------------------------
; 0x0C50  --  asb_helper_0c50  (62 bytes)
;
;   Install a new ISR for IRQ line `AL`: save the current IVT entry for
;   IRQ (8 + AL) into the 4-byte caller-supplied buffer at CS:[BX], then
;   write our (CS:DX) into the IVT, then clear the PIC mask bit for the
;   chosen IRQ line so it's unmasked. The previous PIC mask is saved at
;   asb_saved_pic_mask (CS:[4DH]) so asb_helper_0c8e can restore it on
;   driver unload.
;
;   Type:        Internal helper (IRQ hook installer)
;   Category:    IRQ / IVT management
;   Callers:     asb_slot_3 (IRQ on slot 3), asb_slot_11 (slot 11),
;                asb_init_setup (during probe).
;
;   Inputs:
;     AL  --  IRQ line index (0..7 for the master 8259 PIC). The IVT
;             vector number used is (8 + AL).
;     BX  --  near pointer to a 4-byte buffer in our data section where
;             the saved (old) seg:off should be written.
;     DX  --  near offset of the new ISR (CS is implicit; the helper
;             stores CS as the seg half).
;
;   Outputs:     none.
;   Touches:     AX, CL, DI clobbered; ES preserved via PUSH/POP.
;
;   Notes:
;     Runs inside a CLI/STI window so the IVT swap is atomic vs any
;     pending IRQ on this line. Returns RETF.
; ----------------------------------------------------------------------------
asb_helper_0c50         PROC    NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                CLI     
                MOV     CL, AL
                ADD     AL, 8
                CBW     
                SHL     AL, 1
                SHL     AL, 1
                MOV     DI, AX
                PUSH    ES
                SUB     AX, AX
                MOV     ES, AX
                MOV     AX, ES:[DI]
                MOV     [BX], AX
                MOV     ES:[DI], DX
                MOV     AX, ES:[DI+2]
                MOV     CS:[BX+2], AX
                MOV     ES:[DI+2], CS
                POP     ES
                MOV     AH, 1
                SHL     AH, CL
                NOT     AH
                IN      AL, 21H
                MOV     CS:[4DH], AL
                AND     AL, AH
                OUT     21H, AL
                STI     
                POP     DX
                POP     CX
                POP     BX
                RETF    
asb_helper_0c50         ENDP

; ----------------------------------------------------------------------------
; 0x0C8E  --  asb_helper_0c8e  (36 bytes)
;
;   The companion to asb_helper_0c50: uninstall the ISR for IRQ line AL
;   by restoring the saved IVT entry from the 4-byte buffer at CS:[BX]
;   and restoring the saved PIC mask byte from asb_saved_pic_mask.
;
;   Type:        Internal helper (IRQ hook uninstaller)
;   Category:    IRQ / IVT management
;   Callers:     asb_set_master_volume (shutdown), asb_init_setup.
;
;   Inputs:
;     AL  --  IRQ line index (0..7) -- must match the original install.
;     BX  --  near pointer to the saved 4-byte seg:off buffer.
;
;   Outputs:     none.
;
;   Notes:       Returns RETF; CLI/STI guarded.
; ----------------------------------------------------------------------------
asb_helper_0c8e         PROC    NEAR
                CLI     
                ADD     AL, 8
                CBW     
                SHL     AL, 1
                SHL     AL, 1
                MOV     DI, AX
                PUSH    ES
                SUB     AX, AX
                MOV     ES, AX
                MOV     AX, [BX]
                MOV     ES:[DI], AX
                MOV     AX, [BX+2]
                MOV     ES:[DI+2], AX
                POP     ES
                MOV     AL, CS:[4DH]
                OUT     21H, AL
                STI     
                RETF    
asb_helper_0c8e         ENDP

; ----------------------------------------------------------------------------
; 0x0CB2  --  asb_slot_14  (3 bytes)
;
;   Slot 14 in the dispatch table. Returns AX = 0 unconditionally.
;
;   Type:        Slot handler (no-op).
;   Dispatch:    Slot 14 (AX=14).
; ----------------------------------------------------------------------------
asb_slot_14             PROC    NEAR
                XOR     AX, AX
                RET     
asb_slot_14             ENDP

; ----------------------------------------------------------------------------
; 0x0CB5  --  asb_slot_9  (380 bytes)
;
;   Slot 9 in the dispatch table -- open a sample-data file and decode
;   the first chunk. The argument block at SS:SI provides:
;
;       [SI+0]  WORD  near offset of an ASCIIZ filename (or 0 for
;                     "use already-open handle at asb_caller_int25")
;       [SI+2]  WORD  segment of the ASCIIZ filename
;       [SI+4]  WORD  starting file-offset (low)
;       [SI+6]  WORD  starting file-offset (high)
;       [SI+8]  WORD  total byte count to play (low)
;       [SI+0A] WORD  total byte count to play (high)
;       [SI+0C] WORD  ring-buffer offset (in seg from SI+0E)
;       [SI+0E] WORD  ring-buffer segment
;       [SI+10] WORD  ring-buffer size in bytes (must be even)
;       [SI+12] BYTE  loop flag (0 = one-shot, 1 = loop forever)
;       [SI+13] BYTE  format flags (bit 0 = stereo, bit 2 = 16-bit, ...)
;
;   The handler opens the file (DOS INT 21h AH=3Dh), seeks to the
;   starting offset (AH=42h), and reads the first chunk into the ring
;   buffer. Several pre-decode passes handle stereo / 16-bit /
;   companding-curve format conversions before the data is copied into
;   the ring buffer.
;
;   Type:        Slot handler
;   Category:    Streaming PCM playback
;   Dispatch:    Slot 9 (AX=9, SS:SI -> argument block above).
;   Callers:     game engine.
;   Callees:     asb_set_master_volume, asb_helper_0e31 (decode format
;                flags), asb_helper_0ea4 (parse "SOL" header in file),
;                asb_helper_0be4 (DSP block size), asb_helper_segoff.
;
;   Inputs:      SS:[SI..SI+13] argument block.
;   Outputs:     AX = 0 on success, undefined on early-exit error.
; ----------------------------------------------------------------------------
asb_slot_9              PROC    NEAR
                PUSH    SI
                CALL    asb_set_master_volume
                POP     SI
                CMP     BYTE PTR SS:[SI+12H], 0
                JNE     s9_0cc9
                MOV     BYTE PTR CS:[43H], 0
                JMP     s9_0ccf
s9_0cc9:        MOV     BYTE PTR CS:[43H], 1
s9_0ccf:        MOV     AL, SS:[SI+13H]
                CALL    asb_helper_0e31
                MOV     AX, SS:[SI+8]
                MOV     CS:[84H], AX
                MOV     AX, SS:[SI+0AH]
                MOV     CS:[82H], AX
                MOV     AX, SS:[SI+0CH]
                MOV     CS:[5CH], AX
                MOV     DX, SS:[SI+0EH]
                MOV     CS:[5EH], DX
                PUSH    CS
                CALL    asb_helper_segoff
                MOV     CS:[34H], DL
                MOV     CS:[35H], DL
                MOV     CS:[56H], AX
                MOV     AX, SS:[SI+10H]
                SHR     AX, 1
                MOV     CS:[60H], AX
                CMP     BYTE PTR CS:[38H], 1
                JNE     s9_0d41
                MOV     BYTE PTR CS:[49H], 1
                PUSH    AX
                MOV     BYTE PTR CS:[3AH], 0
                MOV     DI, CS:[5CH]
                MOV     AX, CS:[5EH]
                MOV     ES, AX
                MOV     CX, CS:[60H]
                SHL     CX, 1
                MOV     AL, 80H
                REP     STOSB
                POP     AX
                JMP     s9_0d47
s9_0d41:        MOV     BYTE PTR CS:[49H], 0
s9_0d47:        ADD     AX, CS:[56H]
                MOV     CS:[5AH], AX
                JAE     s9_0d57
                INC     BYTE PTR CS:[35H]
s9_0d57:        MOV     AX, SS:[SI]
                OR      AX, SS:[SI+2]
                JNE     s9_0d67
                MOV     BX, CS:[76H]
                JMP     s9_0da8
s9_0d67:        CMP     WORD PTR SS:[SI+2], 0FFFFH
                JNE     s9_0d73
                MOV     BX, SS:[SI]
                JMP     s9_0da3
s9_0d73:        CMP     WORD PTR CS:[76H], 0FFFFH
                JE      s9_0d8b
                MOV     BX, CS:[76H]
                MOV     AH, 3EH
                INT     21H
                MOV     WORD PTR CS:[76H], 0FFFFH
s9_0d8b:        PUSH    DS
                MOV     DX, SS:[SI]
                MOV     AX, SS:[SI+2]
                MOV     DS, AX
                MOV     AL, 0
                MOV     AH, 3DH
                INT     21H
                POP     DS
                JAE     s9_0da1
                XOR     AX, AX
                RET     
s9_0da1:        MOV     BX, AX
s9_0da3:        MOV     CS:[76H], BX
s9_0da8:        MOV     DX, SS:[SI+4]
                MOV     CS:[7AH], DX
                MOV     CX, SS:[SI+6]
                MOV     CS:[78H], CX
                MOV     AL, 0
                MOV     AH, 42H
                INT     21H
                JAE     s9_0dc5
                XOR     AX, AX
                RET     
s9_0dc5:        CALL    asb_helper_0ea4
                MOV     BYTE PTR CS:[4CH], 0
                MOV     AX, CS:[84H]
                MOV     BX, CS:[82H]
                MOV     CS:[7EH], AX
                MOV     CS:[7CH], BX
                CMP     BYTE PTR CS:[36H], 1
                JNE     s9_0dec
                SHL     AX, 1
                RCL     BX, 1
s9_0dec:        MOV     CX, 3CH
                MUL     CX
                PUSH    AX
                PUSH    DX
                MOV     AX, BX
                MUL     CX
                POP     DX
                ADD     DX, AX
                POP     AX
                CMP     DX, CS:[80H]
                JAE     s9_0e09
                DIV     WORD PTR CS:[80H]
                JMP     s9_0e0c
s9_0e09:        MOV     AX, 0FFFEH
s9_0e0c:        CMP     BYTE PTR CS:[49H], 1
                JNE     s9_0e30
                PUSH    AX
                MOV     AX, CS:[60H]
                CMP     WORD PTR CS:[82H], 0
                JNE     s9_0e2c
                CMP     AX, CS:[84H]
                JBE     s9_0e2c
                MOV     AX, CS:[84H]
s9_0e2c:        CALL    asb_helper_0be4
                POP     AX
s9_0e30:        RET     
asb_slot_9              ENDP

; ----------------------------------------------------------------------------
; 0x0E31  --  asb_helper_0e31  (115 bytes)
;
;   Decode the format-flags byte that the slot-9 caller supplies into
;   six per-bit driver-state bytes. Each bit of the input controls one
;   feature toggle:
;
;     bit 0  -> asb_36  (1 = stereo)
;     bit 1  -> asb_4e  (1 = byte-swap nibbles)
;     bit 2  -> asb_50  (1 = 16-bit PCM samples)
;     bit 3  -> asb_4f  (1 = signed -> unsigned PCM conversion)
;     bit 4  -> asb_51  (1 = decode "ROL each sample" obfuscation)
;     bit 7  -> asb_47  (1 = rhythm-mode)
;
;   Also sets asb_37 = 0x80 unconditionally (the running running-sum
;   accumulator for the companding decode in asb_helper_0fd9).
;
;   Type:        Internal helper (format-flag decoder)
;   Category:    Slot-9 setup
;   Callers:     asb_slot_9, asb_helper_0ea4.
;
;   Inputs:
;     AL  --  packed format-flag byte (bit positions per the table above).
;
;   Outputs:     none.
;   Side effects: writes six driver-state bytes.
; ----------------------------------------------------------------------------
asb_helper_0e31         PROC    NEAR
                MOV     BYTE PTR CS:[37H], 80H
                TEST    AL, 1
                JE      h0e31_0e43
                MOV     BYTE PTR CS:[36H], 1
                JMP     h0e31_0e49
h0e31_0e43:     MOV     BYTE PTR CS:[36H], 0
h0e31_0e49:     TEST    AL, 2
                JE      h0e31_0e55
                MOV     BYTE PTR CS:[4EH], 1
                JMP     h0e31_0e5b
h0e31_0e55:     MOV     BYTE PTR CS:[4EH], 0
h0e31_0e5b:     TEST    AL, 4
                JE      h0e31_0e67
                MOV     BYTE PTR CS:[50H], 1
                JMP     h0e31_0e6d
h0e31_0e67:     MOV     BYTE PTR CS:[50H], 0
h0e31_0e6d:     TEST    AL, 8
                JE      h0e31_0e79
                MOV     BYTE PTR CS:[4FH], 1
                JMP     h0e31_0e7f
h0e31_0e79:     MOV     BYTE PTR CS:[4FH], 0
h0e31_0e7f:     TEST    AL, 10H
                JE      h0e31_0e8b
                MOV     BYTE PTR CS:[51H], 1
                JMP     h0e31_0e91
h0e31_0e8b:     MOV     BYTE PTR CS:[51H], 0
h0e31_0e91:     TEST    AL, 80H
                JE      h0e31_0e9d
                MOV     BYTE PTR CS:[47H], 1
                JMP     h0e31_0ea3
h0e31_0e9d:     MOV     BYTE PTR CS:[47H], 0
h0e31_0ea3:     RET     
asb_helper_0e31         ENDP

; ----------------------------------------------------------------------------
; 0x0EA4  --  asb_helper_0ea4  (135 bytes)
;
;   Read the file header (sniffed from the start of the just-opened
;   slot-9 file). If the file begins with the magic bytes 0x8D 'S' 'O'
;   'L' 0x00 (the Dynamix "SOL" voice-format header), parse the format
;   flags + sample-rate + block size from the header, update the slot-9
;   state accordingly, and advance the file pointer past the header.
;   Otherwise rewind to the requested starting offset and proceed as
;   raw PCM.
;
;   Type:        Internal helper (SOL header sniffer)
;   Category:    Slot-9 setup / file I/O
;   Callers:     asb_slot_9.
;   Callees:     asb_helper_0e31 (decode format-flag byte),
;                asb_helper_0bbd (program DSP time constant).
;
;   Inputs:      Reads driver state set up by slot 9 (file handle in
;                CS:[76H], temp buffer at CS:[5CH..5EH]).
;
;   Outputs:     none.
;
;   Side effects:
;     File pointer moved (DOS AH=42h); driver-state byte/word fields
;     updated from header (rate, block size, flags); DSP rate programmed.
; ----------------------------------------------------------------------------
asb_helper_0ea4         PROC    NEAR
                MOV     BX, CS:[76H]
                MOV     CX, 2
                MOV     DX, CS:[5CH]
                MOV     AX, CS:[5EH]
                PUSH    DS
                MOV     DS, AX
                MOV     SI, DX
                MOV     AH, 3FH
                INT     21H
                LODSB   
                CMP     AL, 8DH
                JNE     h0ea4_0ee0
                LODSB   
                MOV     CL, AL
                MOV     SI, DX
                MOV     AH, 3FH
                INT     21H
                LODSB   
                CMP     AL, 53H
                JNE     h0ea4_0ee0
                LODSB   
                CMP     AL, 4FH
                JNE     h0ea4_0ee0
                LODSB   
                CMP     AL, 4CH
                JNE     h0ea4_0ee0
                LODSB   
                CMP     AL, 0
                JE      h0ea4_0ef2
h0ea4_0ee0:     POP     DS
                MOV     DX, CS:[7AH]
                MOV     CX, CS:[78H]
                MOV     AL, 0
                MOV     AH, 42H
                INT     21H
                RET     
h0ea4_0ef2:     ADD     CX, 2
                ADD     CS:[7AH], CX
                ADC     WORD PTR CS:[78H], 0
                LODSB   
                MOV     AH, AL
                LODSB   
                XCHG    AL, AH
                PUSH    AX
                LODSB   
                MOV     CL, AL
                LODSW   
                MOV     BX, AX
                LODSW   
                MOV     DX, AX
                POP     AX
                POP     DS
                MOV     CS:[84H], BX
                MOV     CS:[82H], DX
                PUSH    AX
                MOV     AL, CL
                CALL    asb_helper_0e31
                POP     AX
                MOV     CS:[74H], AX
                CALL    asb_helper_0bbd
                RET     
asb_helper_0ea4         ENDP

; ----------------------------------------------------------------------------
; 0x0F2B  --  asb_slot_10  (27 bytes)
;
;   Slot 10 in the dispatch table -- pause / soft-stop. Sets the
;   "pause flag" (asb_flag_4c) and twice calls asb_helper_0fd9 to
;   drain the in-flight buffer halves.
;
;   Type:        Slot handler
;   Category:    Playback control
;   Dispatch:    Slot 10 (AX=10 -- no argument block).
;   Callees:     asb_helper_0fd9 (buffer producer / drain pass).
;
;   Inputs:      none.
;   Outputs:     AX = 0.
; ----------------------------------------------------------------------------
asb_slot_10             PROC    NEAR
                MOV     BYTE PTR CS:[4CH], 1
                MOV     BYTE PTR CS:[4BH], 0FFH
                MOV     BYTE PTR CS:[3CH], 0
                CALL    asb_helper_0fd9
                CALL    asb_helper_0fd9
                XOR     AX, AX
                RET     
asb_slot_10             ENDP

; ----------------------------------------------------------------------------
; 0x0F46  --  asb_slot_11  (147 bytes)
;
;   Slot 11 in the dispatch table -- install the DMA-IRQ ISR and start
;   the streaming-PCM machinery. Called by the game after slot 9 has
;   loaded the file and decoded its header. Installs
;   asb_isr_dma_complete (at offset 0xB22) at the IRQ line stored in
;   asb_dsp_ver (CS:[44H]), re-programs the DSP sample rate if it has
;   changed, kicks the buffer producer twice, and clears the suspended
;   / mute flags.
;
;   Type:        Slot handler
;   Category:    Playback start
;   Dispatch:    Slot 11 (AX=11 -- no argument block).
;   Callees:     asb_helper_0c50 (install ISR), asb_helper_0bbd (DSP
;                rate), asb_helper_0fd9 (buffer producer),
;                asb_helper_1242 (state-machine refill).
;
;   Inputs:      none (reads driver state).
;   Outputs:     AX = 0.
;   Side effects:
;     IRQ vector installed; asb_flag_3b / _4a / _4b / _3d / _53 set.
;     Driver enters the "playing" state.
; ----------------------------------------------------------------------------
asb_slot_11             PROC    NEAR
                MOV     AL, CS:[44H]
                MOV     DX, 0B22H
                MOV     BX, 86H
                PUSH    CS
                CALL    asb_helper_0c50
                MOV     AX, CS:[74H]
                CMP     AX, CS:[80H]
                JE      s11_0f62
                CALL    asb_helper_0bbd
s11_0f62:       MOV     BYTE PTR CS:[3BH], 1
                MOV     BYTE PTR CS:[4AH], 1
                CMP     BYTE PTR CS:[4CH], 1
                JE      s11_0f8a
                MOV     BYTE PTR CS:[4BH], 0FFH
                MOV     BYTE PTR CS:[3CH], 0
                CALL    asb_helper_0fd9
                CALL    asb_helper_0fd9
                JMP     s11_0f90
s11_0f8a:       MOV     BYTE PTR CS:[4CH], 0
s11_0f90:       MOV     BYTE PTR CS:[4BH], 1
                MOV     WORD PTR CS:[64H], 0
                MOV     WORD PTR CS:[62H], 0
                MOV     BYTE PTR CS:[3DH], 1
                MOV     BYTE PTR CS:[53H], 0
                MOV     AL, CS:[3CH]
                PUSH    AX
                MOV     BYTE PTR CS:[3CH], 0FFH
                CALL    asb_helper_1242
                POP     AX
                MOV     CS:[3CH], AL
                MOV     BYTE PTR CS:[48H], 0
                MOV     WORD PTR CS:[70H], 0
                MOV     BYTE PTR CS:[52H], 0
                XOR     AX, AX
                RET     
asb_slot_11             ENDP

; ----------------------------------------------------------------------------
; 0x0FD9  --  asb_helper_0fd9  (562 bytes)
;
;   The buffer producer. This is the busiest function in the driver:
;   reads the next half-buffer's worth of bytes from disk into a scratch
;   region, runs whichever decode passes the format flags demand (signed
;   PCM unbiasing, byte-swap, ROL-decode, 16-bit -> 8-bit downconvert,
;   companding-curve unpack), and writes the result into the DSP ring
;   buffer at the half we're currently refilling. Re-entrancy is guarded
;   by asb_busy_flag (CS:[41H]) -- if a second invocation arrives while
;   the first is producing, the second returns immediately.
;
;   Type:        Internal helper (buffer producer)
;   Category:    Streaming PCM
;   Callers:     asb_load_patch_bank, asb_slot_10, asb_slot_11.
;   Callees:     asb_int_check (early-out test), DOS INT 21h AH=3Fh
;                (read file), AH=42h (lseek).
;
;   Inputs:      reads driver state through CS:.
;   Outputs:     none.
;
;   Side effects:
;     Writes a half-buffer's worth of PCM bytes into the ring buffer
;     at (CS:[5EH]):(CS:[5CH]+offset); advances the file pointer; updates
;     asb_half_size_a / b at CS:[54H] / [58H] with the produced count.
;
;   Notes:
;     The four DB-body sites inside the companding-curve unpack loop
;     encode ADD / SUB AH, CS:[BX + asb_init_curve].
; ----------------------------------------------------------------------------
asb_helper_0fd9         PROC    NEAR
                CMP     BYTE PTR CS:[41H], 1
                JE      h0fd9_0ffc
                MOV     AX, CS:[84H]
                OR      AX, CS:[82H]
                JE      h0fd9_0ffc
                MOV     AL, CS:[3CH]
                CMP     AL, CS:[4BH]
                JE      h0fd9_0ffc
                CALL    asb_int_check
                JE      h0fd9_0ffd
h0fd9_0ffc:     RET     
h0fd9_0ffd:     MOV     BYTE PTR CS:[41H], 1
                PUSHF   
                STI     
                MOV     WORD PTR CS:[66H], 0
                MOV     CX, CS:[60H]
                CMP     BYTE PTR CS:[3CH], 0
                JNE     h0fd9_101e
                MOV     DX, 0
                JMP     h0fd9_1020
h0fd9_101e:     MOV     DX, CX
h0fd9_1020:     CMP     BYTE PTR CS:[50H], 1
                JNE     h0fd9_102a
                SHL     CX, 1
h0fd9_102a:     CMP     BYTE PTR CS:[36H], 1
                JNE     h0fd9_1034
                SHR     CX, 1
h0fd9_1034:     CMP     WORD PTR CS:[82H], 0
                JNE     h0fd9_1048
                CMP     CX, CS:[84H]
                JBE     h0fd9_1048
                MOV     CX, CS:[84H]
h0fd9_1048:     SUB     CS:[84H], CX
                SBB     WORD PTR CS:[82H], 0
                MOV     DI, DX
                CMP     BYTE PTR CS:[36H], 1
                JNE     h0fd9_105f
                ADD     DX, CX
h0fd9_105f:     MOV     BX, CS:[76H]
                MOV     AX, CS:[5EH]
                CMP     BYTE PTR CS:[50H], 1
                JNE     h0fd9_1093
                MOV     ES, AX
                MOV     DX, 9FH
                MOV     AX, DS
                CMP     CX, 800H
                JBE     h0fd9_108c
                MOV     CS:[68H], CX
                MOV     CX, 800H
                SUB     CS:[68H], CX
                JMP     h0fd9_1093
h0fd9_108c:     MOV     WORD PTR CS:[68H], 0
h0fd9_1093:     MOV     SI, DX
                PUSH    DS
                MOV     DS, AX
                MOV     AH, 3FH
                INT     21H
                POP     DS
                JAE     h0fd9_10a1
                MOV     AX, CX
h0fd9_10a1:     CMP     BYTE PTR CS:[50H], 1
                JNE     h0fd9_10c7
                SHR     AX, 1
                PUSH    AX
                PUSH    SI
                PUSH    DI
                MOV     CX, AX
h0fd9_10b0:     LODSW   
                CMP     BYTE PTR CS:[4FH], 1
                JNE     h0fd9_10bf
                MOV     AL, 7FH
                SUB     AL, AH
                JMP     h0fd9_10c1
h0fd9_10bf:     MOV     AL, AH
h0fd9_10c1:     STOSB   
                LOOP    h0fd9_10b0
                POP     DI
                POP     SI
                POP     AX
h0fd9_10c7:     CMP     BYTE PTR CS:[4EH], 1
                JNE     h0fd9_10e7
                PUSH    AX
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     CX, AX
                MOV     AX, CS:[5EH]
                MOV     DS, AX
                MOV     ES, AX
h0fd9_10dd:     LODSB   
                ROL     AX, 1
                STOSB   
                LOOP    h0fd9_10dd
                POP     DS
                POP     DI
                POP     SI
                POP     AX
h0fd9_10e7:     CMP     BYTE PTR CS:[36H], 1
                JNE     h0fd9_115c
                PUSH    AX
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     CX, AX
                MOV     DL, CS:[37H]
                MOV     AX, CS:[5EH]
                MOV     DS, AX
                MOV     ES, AX
                MOV     AH, DL
h0fd9_1106:     LODSB   
                MOV     DL, AL
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                CMP     AL, 8
                JL      h0fd9_1121
                MOV     BX, 0FH
                SUB     BL, AL
                DB      02EH, 02AH, 0A7H, 02CH, 000H                    ; SUB AH, CS:[BX + asb_init_curve]
                JMP     h0fd9_112a
h0fd9_1121:     MOV     BL, AL
                XOR     BH, BH
                DB      02EH, 002H, 0A7H, 02CH, 000H                    ; ADD AH, CS:[BX + asb_init_curve]
h0fd9_112a:     MOV     AL, AH
                STOSB   
                AND     DL, 0FH
                CMP     DL, 8
                JL      h0fd9_1141
                MOV     BX, 0FH
                SUB     BL, DL
                DB      02EH, 02AH, 0A7H, 02CH, 000H                    ; SUB AH, CS:[BX + asb_init_curve]
                JMP     h0fd9_114a
h0fd9_1141:     MOV     BL, DL
                XOR     BH, BH
                DB      02EH, 002H, 0A7H, 02CH, 000H                    ; ADD AH, CS:[BX + asb_init_curve]
h0fd9_114a:     MOV     AL, AH
                STOSB   
                LOOP    h0fd9_1106
                POP     DS
                MOV     CS:[37H], AH
                POP     DI
                POP     SI
                POP     DX
                POP     BX
                POP     AX
                SHL     AX, 1
h0fd9_115c:     ADD     CS:[66H], AX
                CMP     BYTE PTR CS:[50H], 1
                JNE     h0fd9_117b
                CMP     WORD PTR CS:[68H], 0
                JE      h0fd9_117b
                ADD     DI, AX
                MOV     CX, CS:[68H]
                JMP     h0fd9_105f
h0fd9_117b:     CMP     BYTE PTR CS:[43H], 1
                JNE     h0fd9_11e7
                MOV     CX, CS:[84H]
                OR      CX, CS:[82H]
                JNE     h0fd9_11e7
                MOV     CS:[64H], CX
                MOV     CS:[62H], CX
                MOV     CS:[70H], CX
                PUSH    AX
                PUSH    DX
                MOV     DX, CS:[7AH]
                MOV     CX, CS:[78H]
                MOV     AL, 0
                MOV     AH, 42H
                INT     21H
                POP     DX
                POP     AX
                MOV     CX, CS:[7EH]
                MOV     CS:[84H], CX
                MOV     CX, CS:[7CH]
                MOV     CS:[82H], CX
                CMP     BYTE PTR CS:[36H], 1
                JNE     h0fd9_11d6
                MOV     BYTE PTR CS:[37H], 80H
                SHR     AX, 1
h0fd9_11d6:     MOV     CX, CS:[60H]
                SUB     CX, CS:[66H]
                JE      h0fd9_11e7
                ADD     DX, AX
                JMP     h0fd9_1020
h0fd9_11e7:     MOV     AX, CS:[66H]
                CMP     BYTE PTR CS:[3CH], 0
                JNE     h0fd9_11f9
                MOV     CS:[54H], AX
                JMP     h0fd9_11fd
h0fd9_11f9:     MOV     CS:[58H], AX
h0fd9_11fd:     XOR     BYTE PTR CS:[3CH], 1
                MOV     BYTE PTR CS:[41H], 0
                POPF    
                RET     
asb_helper_0fd9         ENDP

; ----------------------------------------------------------------------------
; 0x120B  --  asb_helper_120b  (45 bytes)
;
;   Silence-fill the just-played half of the DSP ring buffer with the
;   neutral-PCM value 0x80 (unsigned-PCM zero). Picks which half by
;   reading asb_active_half (CS:[3CH]): 0 = front half, 1 = back half;
;   any other value is "skip, do nothing".
;
;   Type:        Internal helper (silence-fill)
;   Category:    Ring-buffer maintenance
;   Callers:     asb_helper_1242.
;
;   Inputs:      reads driver state.
;   Outputs:     none.
;
;   Side effects:
;     Writes 0x80 to CS:[5EH]:[5CH+offset .. +offset+60H] (or the back-
;     half equivalent).
; ----------------------------------------------------------------------------
asb_helper_120b         PROC    NEAR
                CMP     BYTE PTR CS:[3CH], 0
                JNE     h120b_1218
                MOV     DI, 0
                JMP     h120b_1228
h120b_1218:     CMP     BYTE PTR CS:[3CH], 1
                JNE     h120b_1227
                MOV     DI, CS:[60H]
                JMP     h120b_1228
h120b_1227:     RET     
h120b_1228:     MOV     AX, CS:[5EH]
                MOV     ES, AX
                MOV     CX, CS:[60H]
                MOV     AL, 80H
                REP     STOSB
                RET     
asb_helper_120b         ENDP

; ----------------------------------------------------------------------------
; 0x1238  --  asb_helper_1238  (10 bytes)
;
;   Tiny wrapper that sets asb_refill_pending (CS:[4AH]) <- 1 and tail-
;   calls asb_helper_1242. The IRQ ISR uses this to request a refill
;   pass from outside the ISR context (the actual refill happens on the
;   next mainline tick when asb_load_patch_bank polls).
;
;   Type:        Internal helper
;   Category:    State-machine toggle
;   Callers:     asb_isr_dma_complete (the IRQ handler).
;   Callees:     asb_helper_1242.
; ----------------------------------------------------------------------------
asb_helper_1238         PROC    NEAR
                MOV     BYTE PTR CS:[4AH], 1
                CALL    asb_helper_1242
                RET     
asb_helper_1238         ENDP

; ----------------------------------------------------------------------------
; 0x1242  --  asb_helper_1242  (122 bytes)
;
;   The "advance buffer state machine" routine. Guarded by an
;   asb_advance_busy re-entrancy flag at CS:[40H]; when called, decides
;   between four actions based on the relationship between the
;   "currently playing" half and the "just produced" half:
;
;     - If everything has been consumed (the size-counter at 84H/82H
;       hit zero), tail-call asb_set_master_volume to stop playback.
;     - If we're still streaming (rhythm-mode bit), send DSP halt
;       (0xD0) and stash that we're in "stream-halt-issued" state.
;     - If we already sent halt, send DSP resume (0xD4) and clear
;       the halt-state flag.
;     - Otherwise toggle the active-half bit, call asb_helper_0a3d
;       to launch the next half via DMA, and call asb_helper_120b to
;       silence-fill the half we just finished playing.
;
;   Type:        Internal helper (refill state machine)
;   Category:    Playback control
;   Callers:     asb_load_patch_bank, asb_slot_11, asb_helper_1238.
;   Callees:     asb_set_master_volume, asb_helper_0c1b (PUSH CS),
;                asb_helper_0c2f (PUSH CS), asb_helper_0a3d,
;                asb_helper_120b.
; ----------------------------------------------------------------------------
asb_helper_1242         PROC    NEAR
                CMP     BYTE PTR CS:[40H], 1
                JE      h1242_12bb
                CMP     BYTE PTR CS:[4AH], 1
                JNE     h1242_12bb
                MOV     BYTE PTR CS:[40H], 1
                MOV     AL, CS:[4BH]
                XOR     AL, 1
                CMP     AL, CS:[3CH]
                JNE     h1242_1291
                MOV     AX, CS:[84H]
                OR      AX, CS:[82H]
                JNE     h1242_1275
                CALL    asb_set_master_volume
                JMP     h1242_12b5
h1242_1275:     CMP     BYTE PTR CS:[49H], 1
                JNE     h1242_128f
                CMP     BYTE PTR CS:[53H], 0
                JNE     h1242_128f
                MOV     BYTE PTR CS:[53H], 1
                PUSH    CS
                CALL    asb_helper_0c1b
h1242_128f:     JMP     h1242_12b5
h1242_1291:     CMP     BYTE PTR CS:[53H], 1
                JNE     h1242_12a3
                PUSH    CS
                CALL    asb_helper_0c2f
                MOV     BYTE PTR CS:[53H], 0
h1242_12a3:     MOV     BYTE PTR CS:[4AH], 0
                XOR     BYTE PTR CS:[4BH], 1
                CALL    asb_helper_0a3d
                CALL    asb_helper_120b
h1242_12b5:     MOV     BYTE PTR CS:[40H], 0
h1242_12bb:     RET     
asb_helper_1242         ENDP

; ----------------------------------------------------------------------------
; 0x12BC  --  asb_slot_13  (209 bytes)
;
;   Slot 13 in the dispatch table -- query the current playback position.
;   Reads the 8253 timer-1 channel for sub-DMA-tick resolution, combines
;   with the running play-counter at CS:[62H..64H], and writes a 3-word
;   result into the caller's SS:SI buffer:
;
;     SS:[SI+0]  WORD  loop count (CS:[70H])
;     SS:[SI+2]  WORD  current play position, low (bytes from start)
;     SS:[SI+4]  WORD  current play position, high
;
;   Special-cases: if asb_flag_4c (paused) is set, returns all zeros;
;   if asb_flag_52 (suspended) is set, returns 0xFFFF in all three words
;   (the "no playback" sentinel).
;
;   Type:        Slot handler
;   Category:    State query
;   Dispatch:    Slot 13 (AX=13, SS:SI -> 6-byte output buffer).
;
;   Inputs:      SS:SI -- output buffer pointer.
;   Outputs:     AX = 0.
;
;   Notes:
;     Reads the 8253 PIT counter at port 0x03 twice for the lo+hi pair.
;     Runs inside PUSHF/CLI/POPF to avoid getting interrupted between
;     the two reads and seeing a torn value.
; ----------------------------------------------------------------------------
asb_slot_13             PROC    NEAR
                CMP     BYTE PTR CS:[4CH], 1
                JNE     s13_12d8
                MOV     WORD PTR SS:[SI], 0
                MOV     WORD PTR SS:[SI+2], 0
                MOV     WORD PTR SS:[SI+4], 0
                XOR     AX, AX
                RET     
s13_12d8:       CMP     BYTE PTR CS:[52H], 1
                JNE     s13_12f4
                MOV     WORD PTR SS:[SI], 0FFFFH
                MOV     WORD PTR SS:[SI+2], 0FFFFH
                MOV     WORD PTR SS:[SI+4], 0FFFFH
                XOR     AX, AX
                RET     
s13_12f4:       PUSHF   
                CLI     
                MOV     DX, 3
                IN      AL, DX
                MOV     CL, AL
                IN      AL, DX
                MOV     CH, AL
                MOV     DX, CS:[6AH]
                MOV     AX, CS:[64H]
                MOV     BX, CS:[62H]
                POPF    
                SUB     DX, CX
                ADD     AX, DX
                ADC     BX, 0
                CMP     BYTE PTR CS:[50H], 1
                JNE     s13_1321
                SHL     AX, 1
                RCL     BX, 1
s13_1321:       CMP     BYTE PTR CS:[43H], 1
                JE      s13_137b
                CMP     BYTE PTR CS:[36H], 1
                JNE     s13_1335
                SHR     BX, 1
                RCR     AX, 1
s13_1335:       CMP     BX, CS:[7CH]
                JNE     s13_1359
                CMP     AX, CS:[7EH]
                JBE     s13_136f
                MOV     WORD PTR SS:[SI], 0FFFFH
                MOV     WORD PTR SS:[SI+2], 0FFFFH
                MOV     WORD PTR SS:[SI+4], 0FFFFH
                XOR     AX, AX
                RET
                JMP     s13_136f
s13_1359:       JB      s13_136f
                MOV     WORD PTR SS:[SI], 0FFFFH
                MOV     WORD PTR SS:[SI+2], 0FFFFH
                MOV     WORD PTR SS:[SI+4], 0FFFFH
                XOR     AX, AX
                RET     
s13_136f:       CMP     BYTE PTR CS:[36H], 1
                JNE     s13_137b
                SHL     AX, 1
                RCL     BX, 1
s13_137b:       MOV     SS:[SI+2], AX
                MOV     SS:[SI+4], BX
                MOV     AX, CS:[70H]
                MOV     SS:[SI], AX
                XOR     AX, AX
                RET     
asb_slot_13             ENDP

; ----------------------------------------------------------------------------
; 0x138D  --  asb_int_check  (32 bytes)
;
;   "Are any of the hooked DOS/BIOS interrupts currently re-entrant?"
;   Reads the in-progress flags written by asb_int_hook_a / _b / _c
;   (the thin wrappers installed at INT 0x10, INT 0x0D, INT 0x74) plus
;   the asb_irq_depth byte at CS:[3EH] and the nest flags. Returns
;   ZF = 1 if all are clear (safe to proceed), ZF = 0 if any are set.
;
;   Type:        Internal helper (re-entrancy guard)
;   Category:    DOS / IRQ safety
;   Callers:     asb_helper_0fd9 (skip buffer producer if anything
;                is in flight).
;
;   Inputs:      none.
;   Outputs:     AL = OR of all checked flags; ZF set if no re-entry.
; ----------------------------------------------------------------------------
asb_int_check           PROC    NEAR
                LES     BX, CS:[8AH]
                MOV     AL, ES:[BX]
                LES     BX, CS:[8EH]
                OR      AL, ES:[BX]
                OR      AL, CS:[42H]
                OR      AL, CS:[3EH]
                OR      AL, CS:[3FH]
                RET     
asb_int_check           ENDP

; ----------------------------------------------------------------------------
; 0x13AD  --  asb_int_hook_a  (19 bytes)
;
;   Thin wrapper installed at INT 0x10 (BIOS video). Sets the
;   in-progress flag at CS:[42H], chains to the original BIOS handler
;   stored at CS:[9AH..9DH], and clears the flag on return. asb_int_check
;   uses the flag to detect "video service is currently running, don't
;   touch shared state" -- relevant because the buffer producer can be
;   triggered from inside an IRQ.
;
;   Type:        Interrupt service routine (DOS/BIOS chain)
;   Category:    DOS / IRQ safety
;   Reached by:  CPU hardware vectoring (installed in IVT by asb_get_info).
;   Callees:     the previous INT 0x10 handler (via CALL FAR PTR).
;
;   Inputs:      whatever the caller passed to INT 0x10.
;   Outputs:     IRET-tail; chains the chained handler's return.
; ----------------------------------------------------------------------------
asb_int_hook_a          PROC    NEAR
                MOV     BYTE PTR CS:[42H], 1
                PUSHF   
                CALL    DWORD PTR CS:[9AH]
                MOV     BYTE PTR CS:[42H], 0
                IRET    
asb_int_hook_a          ENDP

; ----------------------------------------------------------------------------
; 0x13C0  --  asb_int_hook_b  (19 bytes)
;
;   Thin wrapper installed at INT 0x0D (originally the printer-port
;   IRQ 5 / "EOM mark" on some BIOSes; in modern terms an obscure
;   vector but used here as a re-entrancy detector). Identical shape
;   to asb_int_hook_a; sets/clears the flag at CS:[3EH] (asb_irq_depth).
;
;   Type:        Interrupt service routine (DOS/BIOS chain)
;   Category:    DOS / IRQ safety
;   Reached by:  CPU hardware vectoring.
; ----------------------------------------------------------------------------
asb_int_hook_b          PROC    NEAR
                MOV     BYTE PTR CS:[3EH], 1
                PUSHF   
                CALL    DWORD PTR CS:[92H]
                MOV     BYTE PTR CS:[3EH], 0
                IRET    
asb_int_hook_b          ENDP

; ----------------------------------------------------------------------------
; 0x13D3  --  asb_int_hook_c  (19 bytes)
;
;   Thin wrapper installed at INT 0x74 (PS/2 mouse / generic AT-class
;   IRQ 12). Same shape as the other int-hooks; toggles the flag at
;   CS:[3FH] (asb_nest_flag).
;
;   Type:        Interrupt service routine (DOS/BIOS chain)
;   Category:    DOS / IRQ safety
;   Reached by:  CPU hardware vectoring.
; ----------------------------------------------------------------------------
asb_int_hook_c          PROC    NEAR
                MOV     BYTE PTR CS:[3FH], 1
                PUSHF   
                CALL    DWORD PTR CS:[96H]
                MOV     BYTE PTR CS:[3FH], 0
                IRET    
asb_int_hook_c          ENDP

; ----------------------------------------------------------------------------
; 0x13E6  --  asb_get_info  (230 bytes)
;
;   Slot 0 in the dispatch table -- one-time driver initialization.
;   Sets the SB base port (defaults to 0x220), runs asb_probe to
;   identify the DSP, saves and replaces three IVT vectors (INT 0x10,
;   INT 0x0D, INT 0x74) with our chained-handler stubs (asb_int_hook_a
;   / _b / _c), reads the DOS verify-flag and current PSP (via INT 21h
;   AH=34h, AH=35h, AH=25h services), and returns 0x13E6 in AX as a
;   sentinel that probe succeeded.
;
;   Type:        Slot handler (driver init)
;   Category:    Initialization
;   Dispatch:    Slot 0 (AX=0, SS:SI -> argument block:
;                  [SI+0]  WORD  override base port (0 means use 0x220))
;   Callers:     game engine, exactly once at startup.
;   Callees:     asb_probe (PUSH CS), asb_helper_0bbd; DOS INT 21h
;                AH=35h (get vector), AH=25h (set vector), AH=19h
;                (current drive), AH=34h (in-DOS flag); multiplex
;                INT 2Fh AX=150Bh (CD-ROM probe).
;
;   Inputs:      SS:[SI] -- override base port, or 0 for default.
;   Outputs:     AX = 0x13E6 on success, 0 on failure.
;
;   Notes:
;     The probe path is unusual: at line 1565-1577 the code checks for
;     a CD-ROM extension via INT 2Fh AX=150Bh and bails out if found
;     -- this is the period-correct way to refuse to coexist with
;     MSCDEX when MSCDEX has hooked INT 25h.
; ----------------------------------------------------------------------------
asb_get_info            PROC    NEAR
                CMP     WORD PTR SS:[SI], 0
                JE      gi_13f5
                MOV     AX, SS:[SI]
                MOV     CS:[72H], AX
                JMP     gi_13fc
gi_13f5:        MOV     WORD PTR CS:[72H], 220H
gi_13fc:        PUSH    CS
                CALL    asb_probe
                OR      AX, AX
                JE      gi_1407
                XOR     AX, AX
                RET     
gi_1407:        MOV     BYTE PTR CS:[52H], 1
                CMP     BYTE PTR CS:[16FBH], 0CDH
                JNE     gi_1435
                MOV     AH, 19H
                INT     21H
                XOR     AH, AH
                MOV     CX, AX
                MOV     BX, 0
                MOV     AX, 150BH
                INT     2FH
                CMP     BX, 0ADADH
                JE      gi_142e
                XOR     AX, AX
                RET     
gi_142e:        OR      AX, AX
                JNE     gi_1435
                XOR     AX, AX
                RET     
gi_1435:        MOV     AH, 35H
                MOV     AL, 10H
                INT     21H
                MOV     CS:[9AH], BX
                MOV     CS:[9CH], ES
                PUSH    DS
                MOV     DX, 13ADH
                MOV     AX, CS
                MOV     DS, AX
                MOV     AH, 25H
                MOV     AL, 10H
                INT     21H
                POP     DS
                MOV     AH, 35H
                MOV     AL, 0DH
                INT     21H
                MOV     CS:[92H], BX
                MOV     CS:[94H], ES
                PUSH    DS
                MOV     DX, 13C0H
                MOV     AX, CS
                MOV     DS, AX
                MOV     AH, 25H
                MOV     AL, 0DH
                INT     21H
                POP     DS
                MOV     AH, 35H
                MOV     AL, 74H
                INT     21H
                MOV     CS:[96H], BX
                MOV     CS:[98H], ES
                PUSH    DS
                MOV     DX, 13D3H
                MOV     AX, CS
                MOV     DS, AX
                MOV     AH, 25H
                MOV     AL, 74H
                INT     21H
                POP     DS
                MOV     AH, 34H
                INT     21H
                MOV     CS:[8EH], BX
                MOV     CS:[90H], ES
                DEC     BX
                MOV     CS:[8AH], BX
                MOV     CS:[8CH], ES
                MOV     AX, 2B11H
                MOV     CS:[74H], AX
                CALL    asb_helper_0bbd
                MOV     BYTE PTR CS:[41H], 0
                MOV     BYTE PTR CS:[40H], 0
                MOV     WORD PTR CS:[76H], 0FFFFH
                MOV     AX, 13E6H
                RET     
asb_get_info            ENDP

; ----------------------------------------------------------------------------
; 0x14CC  --  asb_probe  (31 bytes)
;
;   Probe the Sound Blaster card: reset the DSP, send-and-receive the
;   "echo" command (DSP cmd 0xE0 / 0xAA -> expect 0x55 back; verifies
;   the DSP firmware is alive), read its version number, run the
;   one-time init-setup (DMA + IRQ test), and finally send DSP command
;   0xD1 (speaker on). Each step early-exits with a non-zero AX on
;   failure.
;
;   Type:        Internal helper (probe sequencer)
;   Category:    Probe / init
;   Callers:     asb_get_info (PUSH CS).
;   Callees:     asb_dsp_reset, asb_probe_1516, asb_dsp_get_version,
;                asb_init_setup, asb_dsp_simple (each PUSH CS / CALL).
;
;   Inputs:      none (uses asb_base_port).
;   Outputs:     AX = 0 on success, non-zero error code on any failure.
;
;   Notes:       Returns RETF -- always invoked via PUSH CS / CALL.
; ----------------------------------------------------------------------------
asb_probe               PROC    NEAR
                PUSH    CS
                CALL    asb_dsp_reset
                JNE     pr_14ea
                PUSH    CS
                CALL    asb_probe_1516
                JNE     pr_14ea
                PUSH    CS
                CALL    asb_dsp_get_version
                JNE     pr_14ea
                PUSH    CS
                CALL    asb_init_setup
                JNE     pr_14ea
                PUSH    CS
                CALL    asb_dsp_simple
                XOR     AX, AX
pr_14ea:        RETF    
asb_probe               ENDP

; ----------------------------------------------------------------------------
; 0x14EB  --  asb_dsp_reset  (43 bytes)
;
;   Hardware-reset the DSP and wait for it to report ready. The reset
;   sequence is: write 1 to base+0x6, wait ~3 microseconds (the four
;   dummy IN reads provide the delay on era CPUs), write 0 to base+0x6,
;   then poll the read-data port for the 0xAA "DSP ready" byte. Tries
;   up to 32 read attempts before giving up.
;
;   Type:        Internal helper (DSP reset primitive)
;   Category:    DSP I/O
;   Callers:     asb_probe (PUSH CS).
;   Callees:     asb_dsp_read_byte (PUSH CS).
;
;   Inputs:      none.
;   Outputs:     AX = 0 if DSP responded with 0xAA, AX = 2 on timeout;
;                ZF set on success (the OR AX,AX before RETF).
;
;   Notes:
;     The four `IN AL, DX` reads in the body are the timing-loop
;     idiom -- they stall ~3 microseconds for the DSP to
;     latch the reset pulse. Returns RETF.
; ----------------------------------------------------------------------------
asb_dsp_reset           PROC    NEAR
                MOV     DX, CS:[72H]
                ADD     DL, 6
                MOV     AL, 1
                OUT     DX, AL
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                SUB     AL, AL
                OUT     DX, AL
                MOV     CX, 20H
drst_1500:      PUSH    CS
                CALL    asb_dsp_read_byte
                CMP     AL, 0AAH
                LOOPNE  drst_1500
                CMP     AL, 0AAH
                JE      drst_1511
                MOV     AX, 2
                JMP     drst_1513
drst_1511:      XOR     AX, AX
drst_1513:      OR      AX, AX
                RETF    
asb_dsp_reset           ENDP

; ----------------------------------------------------------------------------
; 0x1516  --  asb_probe_1516  (43 bytes)
;
;   The DSP echo-test: send command 0xE0 (echo) followed by data 0xAA;
;   the DSP should respond by writing 0x55 (~AA, the bitwise inverse)
;   into the read-data port. This is the canonical SB "is the DSP
;   alive?" handshake.
;
;   Type:        Internal helper (DSP echo probe)
;   Category:    DSP I/O
;   Callers:     asb_probe (PUSH CS).
;   Callees:     asb_dsp_write_busy (PUSH CS), asb_dsp_read_byte (PUSH CS).
;
;   Inputs:      none.
;   Outputs:     AX = 0 on success (got 0x55 back), AX = 2 on failure.
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_probe_1516          PROC    NEAR
                MOV     AL, 0E0H
                MOV     DX, CS:[72H]
                ADD     DX, 0CH
                PUSH    CS
                CALL    asb_dsp_write_busy
                JB      p1516_153b
                MOV     AL, 0AAH
                PUSH    CS
                CALL    asb_dsp_write_busy
                JB      p1516_153b
                PUSH    CS
                CALL    asb_dsp_read_byte
                JB      p1516_153b
                CMP     AL, 55H
                JNE     p1516_153b
                XOR     AX, AX
                RETF    
p1516_153b:     MOV     AX, 2
                OR      AX, AX
                RETF    
asb_probe_1516          ENDP

; ----------------------------------------------------------------------------
; 0x1541  --  asb_dsp_write_busy  (20 bytes)
;
;   Like asb_dsp_wait_ready but with a 2048-iteration polling cap: if
;   the DSP doesn't acknowledge ready within ~2048 reads of bit 7 of
;   base+0x0C, set CF and bail out. Used exclusively at probe time so
;   a missing card / hung DSP doesn't hang the loader.
;
;   Type:        Internal helper (bounded DSP write)
;   Category:    DSP I/O
;   Callers:     asb_probe_1516 (PUSH CS) -- twice.
;
;   Inputs:
;     AL  --  byte to send.
;     DX  --  DSP command port (base+0x0C).
;
;   Outputs:     CF = 1 on timeout, CF = 0 on successful write.
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_dsp_write_busy      PROC    NEAR
                MOV     CX, 800H
                MOV     AH, AL
dwb_1546:       IN      AL, DX
                OR      AL, AL
                JNS     dwb_1550
                LOOP    dwb_1546
                STC     
                JMP     dwb_1554
dwb_1550:       MOV     AL, AH
                OUT     DX, AL
                CLC     
dwb_1554:       RETF    
asb_dsp_write_busy      ENDP

; ----------------------------------------------------------------------------
; 0x1555  --  asb_dsp_read_byte  (31 bytes)
;
;   Read one byte from the DSP, with a 2048-iteration timeout. Polls bit
;   7 of base+0x0E ("data available"); when set, reads from base+0x0A
;   (read-data port) and returns the byte in AL. Used by asb_dsp_reset
;   and asb_probe_1516 to receive the DSP's response bytes.
;
;   Type:        Internal helper (bounded DSP read)
;   Category:    DSP I/O
;   Callers:     asb_dsp_reset (PUSH CS), asb_probe_1516 (PUSH CS).
;
;   Inputs:      none.
;   Outputs:     AL = byte read; CF = 0 on success, CF = 1 on timeout.
;   Touches:     DX, CX restored by PUSH/POP.
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_dsp_read_byte       PROC    NEAR
                PUSH    DX
                PUSH    CX
                MOV     DX, CS:[72H]
                ADD     DL, 0EH
                MOV     CX, 800H
drb_1562:       IN      AL, DX
                OR      AL, AL
                JS      drb_156c
                LOOP    drb_1562
                STC     
                JMP     drb_1571
drb_156c:       SUB     DL, 4
                IN      AL, DX
                CLC     
drb_1571:       POP     CX
                POP     DX
                RETF    
asb_dsp_read_byte       ENDP

; ----------------------------------------------------------------------------
; 0x1574  --  asb_dsp_get_version  (58 bytes)
;
;   Send DSP command 0xE1 (get version) and read back two bytes: major
;   followed by minor. Stash a "DSP is v2.x or later" flag at CS:[38H]:
;     0 if 1.01 <= ver < 2.00 (DSP supports basic commands)
;     1 if ver >= 2.00          (DSP supports high-speed mode)
;   Bails with AX = 1 if version < 1.01 (DSP too old).
;
;   Type:        Internal helper (DSP version query)
;   Category:    DSP I/O
;   Callers:     asb_probe (PUSH CS).
;   Callees:     asb_dsp_wait_ready, asb_dsp_read_buf (both PUSH CS).
;
;   Inputs:      none.
;   Outputs:     AX = 0 on success, AX = 1 if DSP too old; ZF set on success.
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_dsp_get_version     PROC    NEAR
                MOV     AL, 0E1H
                MOV     DX, CS:[72H]
                ADD     DL, 0CH
                PUSH    CS
                CALL    asb_dsp_wait_ready
                PUSH    CS
                CALL    asb_dsp_read_buf
                MOV     AH, AL
                PUSH    CS
                CALL    asb_dsp_read_buf
                CMP     AX, 101H
                JL      dgv_15a8
                CMP     AX, 200H
                JL      dgv_159e
                MOV     BYTE PTR CS:[38H], 1
                JMP     dgv_15a4
dgv_159e:       MOV     BYTE PTR CS:[38H], 0
dgv_15a4:       XOR     AX, AX
                JMP     dgv_15ab
dgv_15a8:       MOV     AX, 1
dgv_15ab:       OR      AX, AX
                RETF    
asb_dsp_get_version     ENDP

; ----------------------------------------------------------------------------
; 0x15AE  --  asb_dsp_read_buf  (22 bytes)
;
;   Read one byte from the DSP read-data port, with an unbounded wait
;   (no timeout). Used during DSP-version readout where we trust the
;   DSP to be alive and responsive.
;
;   Type:        Internal helper (unbounded DSP read)
;   Category:    DSP I/O
;   Callers:     asb_dsp_get_version (PUSH CS) -- twice.
;
;   Inputs:      none.
;   Outputs:     AL = byte read.
;   Touches:     DX restored.
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_dsp_read_buf        PROC    NEAR
                PUSH    DX
                MOV     DX, CS:[72H]
                ADD     DL, 0EH
                SUB     AL, AL
drbf_15b9:      IN      AL, DX
                OR      AL, AL
                JNS     drbf_15b9
                SUB     DL, 4
                IN      AL, DX
                POP     DX
                RETF    
asb_dsp_read_buf        ENDP

; ----------------------------------------------------------------------------
; 0x15C4  --  asb_dsp_simple  (31 bytes)
;
;   Send DSP command 0xD1 (speaker on) and return. This is the last
;   step of asb_probe -- after a successful version-query and DMA test,
;   we turn the speaker output on so subsequent playback is audible.
;
;   Type:        Internal helper (DSP speaker-on)
;   Category:    DSP I/O
;   Callers:     asb_probe (PUSH CS).
;   Callees:     asb_dsp_wait_ready (PUSH CS).
;
;   Inputs:      none.
;   Outputs:     none.
;
;   Notes:
;     Returns RETF. The 16 zero bytes after the RETF (encoding of
;     `ADD [BX+SI], AL`, whose opcode is 00 00) are inter-PROC filler
;     between this routine and asb_init_setup.
; ----------------------------------------------------------------------------
asb_dsp_simple          PROC    NEAR
                MOV     DX, CS:[72H]
                ADD     DX, 0CH
                MOV     AL, 0D1H
                PUSH    CS
                CALL    asb_dsp_wait_ready
                RETF
                ; 16 bytes of zero filler decoded as ADD [BX+SI], AL.
                ADD     [BX+SI], AL
                ADD     [BX+SI], AL
                ADD     [BX+SI], AL
                ADD     [BX+SI], AL
                ADD     [BX+SI], AL
                ADD     [BX+SI], AL
                ADD     [BX+SI], AL
                ADD     [BX+SI], AL
asb_dsp_simple          ENDP

; ----------------------------------------------------------------------------
; 0x15E3  --  asb_init_setup  (176 bytes)
;
;   At probe time: hook four candidate IRQ lines (2, 3, 5, 7) with the
;   one-shot test ISRs at asb_irq_isr_a..d, program the 8237 DMA to
;   point at our 9Eh-byte scratch buffer, send a "DSP single-cycle DMA
;   playback at minimum sample rate" sequence (cmd 0x40 + 0x64 + 0x14
;   + 0x00 + 0x00 -- two-byte zero count means one sample), wait for
;   one of the candidate IRQs to fire (its ISR writes its line number
;   into asb_dsp_ver / CS:[44H]), then unhook all four candidates and
;   return.
;
;   The asb_irq_isr_a / _b / _c / _d ISRs are how this driver auto-
;   detects which IRQ the SB card is configured for. If asb_dsp_ver
;   remains 0 after the 2048-iteration wait, AX = 3 ("IRQ probe
;   failed"); otherwise asb_dsp_ver holds the detected IRQ line and
;   the rest of the driver will install its real ISR there.
;
;   Type:        Internal helper (IRQ-line autoprobe)
;   Category:    Probe / init
;   Callers:     asb_probe (PUSH CS).
;   Callees:     asb_helper_0c50 / _0c8e (install / uninstall IRQ),
;                asb_helper_segoff, asb_dma_program, asb_dsp_wait_ready
;                (all PUSH CS).
;
;   Inputs:      none.
;   Outputs:     AX = 0 if any candidate IRQ fired; AX = 3 if none did.
;                asb_dsp_ver (CS:[44H]) holds the detected IRQ line on
;                success.
;
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_init_setup          PROC    NEAR
                MOV     AL, 2
                MOV     DX, 16BCH
                MOV     BX, 15D3H
                PUSH    CS
                CALL    asb_helper_0c50
                MOV     AL, 3
                MOV     DX, 16C5H
                MOV     BX, 15D7H
                PUSH    CS
                CALL    asb_helper_0c50
                MOV     AL, 5
                MOV     DX, 16CEH
                MOV     BX, 15DBH
                PUSH    CS
                CALL    asb_helper_0c50
                MOV     AL, 7
                MOV     DX, 16D7H
                MOV     BX, 15DFH
                PUSH    CS
                CALL    asb_helper_0c50
                MOV     DX, CS
                MOV     AX, 9EH
                PUSH    CS
                CALL    asb_helper_segoff
                XOR     CX, CX
                MOV     DH, 49H
                PUSH    CS
                CALL    asb_dma_program
                MOV     DX, CS:[72H]
                ADD     DX, 0CH
                MOV     AL, 40H
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     AL, 64H
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     AL, 14H
                PUSH    CS
                CALL    asb_dsp_wait_ready
                XOR     AL, AL
                PUSH    CS
                CALL    asb_dsp_wait_ready
                XOR     AL, AL
                PUSH    CS
                CALL    asb_dsp_wait_ready
                MOV     CX, 800H
                MOV     BYTE PTR CS:[44H], 0
is__1653:       CMP     BYTE PTR CS:[44H], 0
                LOOPE   is__1653
                CMP     BYTE PTR CS:[44H], 0
                JNE     is__1668
                MOV     AX, 3
                JMP     is__166a
is__1668:       XOR     AX, AX
is__166a:       PUSH    AX
                MOV     AL, 2
                MOV     BX, 15D3H
                PUSH    CS
                CALL    asb_helper_0c8e
                MOV     AL, 3
                MOV     BX, 15D7H
                PUSH    CS
                CALL    asb_helper_0c8e
                MOV     AL, 5
                MOV     BX, 15DBH
                PUSH    CS
                CALL    asb_helper_0c8e
                MOV     AL, 7
                MOV     BX, 15DFH
                PUSH    CS
                CALL    asb_helper_0c8e
                POP     AX
                OR      AX, AX
                RETF    
asb_init_setup          ENDP

; ----------------------------------------------------------------------------
; 0x1693  --  asb_dma_program  (41 bytes)
;
;   Program 8237 DMA channel 1: mask channel, write the mode byte,
;   then the 16-bit address (low/high), the 16-bit count (low/high),
;   the page register (high 8 bits of physical address), and finally
;   unmask. Used by asb_init_setup for the IRQ-probe single-sample
;   DMA setup.
;
;   Type:        Internal helper (8237 DMA primitive)
;   Category:    DMA I/O
;   Callers:     asb_init_setup (PUSH CS).
;
;   Inputs:
;     AX  --  DMA 16-bit base address (low 16 bits of physical addr).
;     CX  --  DMA byte count (samples - 1; 0 means one byte).
;     DH  --  DMA mode-register byte (0x49 = single-cycle / write /
;             increment / channel 1).
;     DL  --  DMA page register byte (high 8 bits of physical addr).
;
;   Outputs:     none.
;   Touches:     AL clobbered; BX preserved via PUSH/POP.
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_dma_program         PROC    NEAR
                PUSH    BX
                MOV     BX, AX
                MOV     AL, 5
                OUT     0AH, AL
                SUB     AL, AL
                OUT     0CH, AL
                MOV     AL, DH
                OUT     0BH, AL
                MOV     AL, BL
                OUT     2, AL
                MOV     AL, BH
                OUT     2, AL
                MOV     AL, CL
                OUT     3, AL
                MOV     AL, CH
                OUT     3, AL
                MOV     AL, DL
                OUT     83H, AL
                MOV     AL, 1
                OUT     0AH, AL
                POP     BX
                RETF    
asb_dma_program         ENDP

; ----------------------------------------------------------------------------
; 0x16BC  --  asb_irq_isr_a  (9 bytes)
;
;   IRQ-probe ISR for IRQ line 2. Installed temporarily by asb_init_setup
;   on candidate-IRQ slot 2; when called, records "the firing IRQ is 2"
;   into DL and tail-calls asb_irq_tail (which stores DL in asb_dsp_ver
;   and EOIs the PIC). Lets the probe loop detect which IRQ the card
;   is configured for.
;
;   Type:        Interrupt service routine (one-shot IRQ probe handler).
;   Category:    IRQ autodetection.
;   Reached by:  CPU hardware vectoring (during asb_init_setup only;
;                uninstalled at end of probe).
; ----------------------------------------------------------------------------
asb_irq_isr_a           PROC    NEAR
                PUSH    DX
                MOV     DL, 2
                PUSH    CS
                CALL    asb_irq_tail
                POP     DX
                IRET    
asb_irq_isr_a           ENDP

; ----------------------------------------------------------------------------
; 0x16C5  --  asb_irq_isr_b  (9 bytes)
;
;   IRQ-probe ISR for IRQ line 3. See asb_irq_isr_a; identical shape,
;   different DL constant.
;
;   Type:        Interrupt service routine (one-shot IRQ probe handler).
; ----------------------------------------------------------------------------
asb_irq_isr_b           PROC    NEAR
                PUSH    DX
                MOV     DL, 3
                PUSH    CS
                CALL    asb_irq_tail
                POP     DX
                IRET    
asb_irq_isr_b           ENDP

; ----------------------------------------------------------------------------
; 0x16CE  --  asb_irq_isr_c  (9 bytes)
;
;   IRQ-probe ISR for IRQ line 5. See asb_irq_isr_a.
;
;   Type:        Interrupt service routine (one-shot IRQ probe handler).
; ----------------------------------------------------------------------------
asb_irq_isr_c           PROC    NEAR
                PUSH    DX
                MOV     DL, 5
                PUSH    CS
                CALL    asb_irq_tail
                POP     DX
                IRET    
asb_irq_isr_c           ENDP

; ----------------------------------------------------------------------------
; 0x16D7  --  asb_irq_isr_d  (9 bytes)
;
;   IRQ-probe ISR for IRQ line 7 (the SB v1.x default). See asb_irq_isr_a.
;
;   Type:        Interrupt service routine (one-shot IRQ probe handler).
; ----------------------------------------------------------------------------
asb_irq_isr_d           PROC    NEAR
                PUSH    DX
                MOV     DL, 7
                PUSH    CS
                CALL    asb_irq_tail
                POP     DX
                IRET    
asb_irq_isr_d           ENDP

; ----------------------------------------------------------------------------
; 0x16E0  --  asb_irq_tail  (27 bytes)
;
;   Tail-call target shared by asb_irq_isr_a..d. Records "this IRQ
;   fired" by writing the caller's DL into asb_dsp_ver (CS:[44H]),
;   reads the DSP buffer-status port (clears the SB IRQ), and writes
;   EOI (0x20) to the master 8259 PIC at port 0x20.
;
;   Type:        Internal helper (IRQ probe completer).
;   Category:    IRQ autodetection
;   Callers:     asb_irq_isr_a / _b / _c / _d (PUSH CS).
;
;   Inputs:
;     DL  --  IRQ line that fired (2, 3, 5, or 7).
;
;   Outputs:     none.
;
;   Side effects:
;     asb_dsp_ver <- DL; DSP-IRQ cleared; PIC EOI sent.
;
;   Notes:       Returns RETF.
; ----------------------------------------------------------------------------
asb_irq_tail            PROC    NEAR
                PUSH    DS
                PUSH    AX
                MOV     AX, CS
                MOV     DS, AX
                MOV     CS:[44H], DL
                MOV     DX, CS:[72H]
                ADD     DX, 0EH
                IN      AL, DX
                MOV     AL, 20H
                OUT     20H, AL
                POP     AX
                POP     DS
                RETF    
asb_irq_tail            ENDP


; ============================================================================
; 0x16FB  --  trailing magic byte (0xDC)
;
; The last byte of the binary. Origin uncertain (compiler tail-padding?
; checksum?).
; ============================================================================
                DB      0DCH

; ============================================================================
; 11.  Glossary
;
; A reader who skipped the preamble can resolve every acronym used in this
; file from this block. Hardware-and-format terms first, then the driver-
; internal vocabulary.
;
;   ---- Sound Blaster hardware ----
;
;   SB         Sound Blaster. The original Creative Labs card from
;              1989-1991 (versions 1.0 / 1.5 / 2.0); this driver targets
;              SB v1.x. The card contains the YM3812 (OPL2) FM-synth
;              chip, the SAA1099 CMS chips (square-wave synth), and the
;              digital DSP described below. This file drives only the
;              DSP; the OPL2 side is in Sx.SSM.ADL.bin.
;
;   DSP        "Digital Signal Processor." Misnomer -- it's actually an
;              Intel 8051-derivative microcontroller running Creative's
;              custom firmware. The DSP is what the host CPU talks to
;              when it wants to play PCM samples. It has its own
;              command set (see below).
;
;   SAA1099    Philips square-wave synthesis chip. The "CMS" in the DUDE
;              device-name field refers to the Creative Music System
;              that bundled two of these. NOT programmed by this driver.
;
;   8237       Intel DMA controller. Two cascaded 4-channel chips on
;              every PC AT and later; this driver uses channel 1 of the
;              first chip to stream PCM bytes from a buffer in system
;              RAM to the DSP without CPU intervention.
;
;   8259       Intel programmable interrupt controller ("PIC"). Two
;              cascaded 8-channel chips on every PC AT and later. The
;              SB asserts a hardware IRQ line on the master PIC when
;              each DMA half-buffer is consumed; the driver's ISR
;              services it.
;
;   8253       Intel programmable interval timer ("PIT"). Three 16-bit
;              countdown channels at I/O ports 0x40..0x43; channel 0
;              drives the system timer interrupt at 18.2 Hz by default.
;              asb_slot_13 reads channel 1 directly to get sub-DMA-tick
;              resolution on the current play position.
;
;   EOI        "End of interrupt." The 1-byte token (value 0x20) the
;              CPU writes to the PIC at port 0x20 (master) or 0xA0
;              (slave) to tell the PIC "I'm done; you may re-enable
;              this IRQ line and others below it." Every ISR in this
;              driver writes EOI before returning.
;
;   IRQ        Interrupt request line. A wire from a hardware device
;              to the PIC; when asserted, the CPU (if interrupts are
;              enabled) vectors through the IVT to the registered ISR
;              for that line. SB cards default to IRQ 7.
;
;   ISR        Interrupt service routine. The piece of code installed
;              in the IVT to handle a given IRQ. Always ends in IRET
;              (not RET / RETF).
;
;   IVT        Interrupt vector table. The 1024-byte table at flat
;              address 0x000:0x0000 holding 256 four-byte (seg:off)
;              far-pointer entries, one per interrupt number. DOS
;              services INT 21h AH=25h (set) and AH=35h (get) read/
;              write these entries.
;
;   IRET       x86 "return from interrupt" instruction (opcode 0xCF).
;              Pops IP, CS, and FLAGS off the stack -- the inverse of
;              the implicit CPU-driven push that happens on interrupt
;              vectoring.
;
;   RETF       "Return far" (opcode 0xCB). Pops IP and CS. Helpers
;              invoked via the pseudo-far-call (PUSH CS / CALL near)
;              return with RETF to match what the caller pushed.
;
;   RET        "Return near" (opcode 0xC3). Pops only IP. Plain helpers
;              called via a same-segment CALL.
;
;   ---- DSP command set used by this driver ----
;
;   0x14       Single-cycle 8-bit DMA playback. Followed by a 16-bit
;              count (low/high) of samples - 1. After the count is
;              consumed, the DSP fires its IRQ once and stops. Used by
;              asb_helper_0a95's 8-bit branch.
;
;   0x1C       Auto-init 8-bit DMA playback. Like 0x14 but loops over
;              the same DMA buffer indefinitely, firing the IRQ at
;              each half-buffer boundary. Used by asb_helper_0a95's
;              auto-init branch (the streaming case).
;
;   0x40       Set time constant. Followed by one byte = 256 -
;              (1000000 / sample_rate_hz). Programs the playback rate.
;              Sent by asb_helper_0bbd.
;
;   0x48       Set DMA block size. Followed by 16-bit count. Used by
;              asb_slot_9's setup; tells the DSP "the next 0x14 / 0x1C
;              command should treat 16-bit block-size as the chunk".
;              Sent by asb_helper_0be4.
;
;   0xD0       Halt 8-bit DMA. Pauses the currently-running DMA cycle
;              without aborting; resumes on 0xD4. Used by
;              asb_helper_0c1b.
;
;   0xD1       Speaker on. Connects the DSP output to the card's
;              audio output stage. Sent by asb_dsp_simple at end of
;              probe.
;
;   0xD4       Continue 8-bit DMA. Resumes a 0xD0-halted cycle. Sent
;              by asb_helper_0c2f.
;
;   0xE0       Echo / identify. Followed by one byte; the DSP responds
;              with the bitwise inverse of the byte. The canonical
;              "is the DSP alive?" handshake. Used by asb_probe_1516
;              with input 0xAA / expected response 0x55.
;
;   0xE1       Get DSP version. The DSP responds with two bytes:
;              major then minor. Read by asb_dsp_get_version.
;
;   ---- Driver internals ----
;
;   DUDE       Dynamix's internal name for the sound-driver container
;              format. This file is one DUDE binary; the project ships
;              14 of them, one per supported sound card / synth.
;
;   Slot       One of 16 (sometimes 18 in other drivers) entry points
;              the game can invoke via the dispatch trampoline. AX
;              selects which slot; SS:SI points at slot-specific args.
;
;   Trampoline The 18-byte dispatch entry point at offset 0x08BF
;              (asb_dispatch). The only far-callable symbol in the file.
;
;   Pseudo-far-call  The PUSH CS / CALL near idiom. Pushes the caller's
;              CS on the stack, then does a near CALL (which pushes only
;              the near IP). The callee can therefore RETF and pop a
;              valid (CS:IP) pair. Cheaper than a real CALL FAR for
;              same-segment calls because the CALL is 3 bytes instead
;              of 5. Used throughout this driver for "helpers that need
;              to return via RETF" (every PUSH-CS site is documented at
;              the call site).
;
;   IRQ chaining  Hooking an interrupt vector by saving the previous
;              (seg:off) entry, writing your own ISR's (seg:off), then
;              having your ISR PUSHF + CALL FAR PTR <saved> the original
;              after doing its own work. The driver chains INT 0x10
;              (BIOS video), INT 0x0D, INT 0x74 via asb_int_hook_a..c.
;              See those functions' headers for details.
;
;   Auto-init mode      A DMA / DSP mode where the 0x1C playback
;              command loops over the same buffer indefinitely, firing
;              an IRQ at each half-buffer boundary. The driver's ISR
;              (asb_isr_dma_complete) refills the just-played half
;              while the other half plays.
;
;   Single-cycle mode   A DMA / DSP mode where the 0x14 playback
;              command consumes the buffer once and stops. Used by the
;              IRQ-line autoprobe in asb_init_setup to fire one IRQ.
;
;   Time constant       The DSP rate-programming byte. Formula:
;              tc = 256 - (1000000 / hz). Range ~0x06 (4 kHz) ..
;              0xD3 (22.05 kHz) on SB 1.x.
;
;   Page register       The 8237 DMA "page" port for channel 1 (port
;              0x83). Holds the upper 8 bits of the 24-bit physical
;              address; combined with the 16-bit channel-1 address
;              port (0x02) gives the full 24-bit DMA address. The
;              buffer must NOT span a 64 KB boundary (the page byte
;              doesn't auto-increment).
;
;   SOL        Dynamix in-game voice-data format. Files in this format
;              begin with the 5-byte magic 8D 53 4F 4C 00 ("." "S" "O"
;              "L" 00); the bytes after the magic are a per-file
;              header containing sample rate, format flags, and the
;              start offset of the raw PCM payload. asb_helper_0ea4
;              parses it.
; ============================================================================

                END     _start
