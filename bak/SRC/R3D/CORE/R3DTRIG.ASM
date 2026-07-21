; ============================================================================
; R3DTRIG.ASM  --  table trig for the 3-D renderer
;
; sin, cos, asin and atan2 over 16-bit binary angles (a full turn =
; 10000h), returning Q14 values (4000h = 1.0). sin and cos share the Q14
; cosine table (g_awCosTable, in R3DDATA.ASM), sin reading it with a
; quarter-turn phase shift; asin and atan2 use their own tables, which
; are assembled at the end of this file. asin expects a Q14 sine value in
; [-1.0, 1.0] and does not clamp; atan2(y, x) folds the first-octant
; table across all four quadrants.
;
; One of the four source files of segment S233E_TEXT -- see R3D.ASM for
; the segment layout and reading conventions; the link order is fixed by
; KRONDOR.RSP.
; ============================================================================

.286

S233E_TEXT	segment word public use16 'CODE'
	assume cs:S233E_TEXT, ds:S233E_TEXT
	locals			; enable @@-prefixed local labels (scoped per public
				; _name proc). Label names emit no bytes.

; The shared Q14 cosine table lives with the rest of the renderer state
; in R3DDATA.ASM.
	extrn g_awCosTable:word

; ============================================================================
; _r3d_tbl_sin
;
; Table-lookup sine of a 4096-unit angle, returning cos-table entry via quarter-period phase
; shift and half-period folding.
;
; C equivalent:
;   short r3d_tbl_sin(int angle)
;   {
;       unsigned idx;
;
;       idx = (unsigned)(angle + 0xc000) >> 4;
;       if (idx & 0x800)
;           idx = 0x1000 - idx;
;       return g_awCosTable[idx];
;   }
; ============================================================================
@angle equ word ptr ss:[bx+4]
	public _r3d_tbl_sin
_r3d_tbl_sin:
	mov BX,SP
	mov AX, @angle
	add AX, 0c000h
	shr AX,1h
	shr AX,1h
	shr AX,1h
	shr AX,1h
	test AX, 800h
	jz @@lookup
	neg AX
	add AX, 1000h		; idx = 1000h - idx (half-period fold)
@@lookup:
	mov BX,AX
	shl BX,1h
	mov AX,word ptr CS:[BX+g_awCosTable]
	retf

; ============================================================================
; _r3d_tbl_cos
;
; Returns cos(angle) as a Q14 fixed-point short (0x4000 = 1.0) via a lookup into g_awCosTable,
; with the angle scaled to a table index and folded across the half-period.
;
; C equivalent:
;   short r3d_tbl_cos(int angle)
;   {
;       unsigned int idx;
;
;       /* 16-bit angle -> table index: 65536 angle units span 4096 entries */
;       idx = (unsigned int)angle >> 4;
;
;       /* Fold the upper half-period back onto the stored quarter/half. */
;       if (idx & 0x800)
;           idx = 0x1000 - idx;
;
;       return g_awCosTable[idx];
;   }
; ============================================================================
@angle equ word ptr ss:[bx+4]
	public _r3d_tbl_cos
_r3d_tbl_cos:
	mov BX,SP
	mov AX, @angle
	shr AX,1h
	shr AX,1h
	shr AX,1h
	shr AX,1h
	test AX, 800h
	jz @@lookup
	neg AX
	add AX, 1000h		; idx = 1000h - idx (half-period fold)
@@lookup:
	mov BX,AX
	shl BX,1h
	mov AX,word ptr CS:[BX+g_awCosTable]
	retf

; Gap 0x2e9b-0x2e9b: 1B zero-init
	db 0
; In-segment data at 0x2e9c: asin angle LUT [g_awAsinTable]
; Indexed by (Q14 sine >> 5); each entry is a 12-bit angle. Used by r3d_tbl_asin.
g_awAsinTable	dw 00000h, 00001h, 00002h, 00003h, 00005h, 00006h, 00007h, 00008h
	dw 0000ah, 0000bh, 0000ch, 0000eh, 0000fh, 00010h, 00011h, 00013h
	dw 00014h, 00015h, 00016h, 00018h, 00019h, 0001ah, 0001ch, 0001dh
	dw 0001eh, 0001fh, 00021h, 00022h, 00023h, 00024h, 00026h, 00027h
	dw 00028h, 0002ah, 0002bh, 0002ch, 0002dh, 0002fh, 00030h, 00031h
	dw 00032h, 00034h, 00035h, 00036h, 00038h, 00039h, 0003ah, 0003bh
	dw 0003dh, 0003eh, 0003fh, 00041h, 00042h, 00043h, 00044h, 00046h
	dw 00047h, 00048h, 0004ah, 0004bh, 0004ch, 0004dh, 0004fh, 00050h
	dw 00051h, 00052h, 00054h, 00055h, 00056h, 00058h, 00059h, 0005ah
	dw 0005bh, 0005dh, 0005eh, 0005fh, 00061h, 00062h, 00063h, 00064h
	dw 00066h, 00067h, 00068h, 0006ah, 0006bh, 0006ch, 0006eh, 0006fh
	dw 00070h, 00071h, 00073h, 00074h, 00075h, 00077h, 00078h, 00079h
	dw 0007ah, 0007ch, 0007dh, 0007eh, 00080h, 00081h, 00082h, 00084h
	dw 00085h, 00086h, 00087h, 00089h, 0008ah, 0008bh, 0008dh, 0008eh
	dw 0008fh, 00091h, 00092h, 00093h, 00094h, 00096h, 00097h, 00098h
	dw 0009ah, 0009bh, 0009ch, 0009eh, 0009fh, 000a0h, 000a2h, 000a3h
	dw 000a4h, 000a6h, 000a7h, 000a8h, 000a9h, 000abh, 000ach, 000adh
	dw 000afh, 000b0h, 000b1h, 000b3h, 000b4h, 000b5h, 000b7h, 000b8h
	dw 000b9h, 000bbh, 000bch, 000bdh, 000bfh, 000c0h, 000c1h, 000c3h
	dw 000c4h, 000c5h, 000c7h, 000c8h, 000c9h, 000cbh, 000cch, 000cdh
	dw 000cfh, 000d0h, 000d1h, 000d3h, 000d4h, 000d5h, 000d7h, 000d8h
	dw 000d9h, 000dbh, 000dch, 000ddh, 000dfh, 000e0h, 000e2h, 000e3h
	dw 000e4h, 000e6h, 000e7h, 000e8h, 000eah, 000ebh, 000ech, 000eeh
	dw 000efh, 000f1h, 000f2h, 000f3h, 000f5h, 000f6h, 000f7h, 000f9h
	dw 000fah, 000fbh, 000fdh, 000feh, 00100h, 00101h, 00102h, 00104h
	dw 00105h, 00106h, 00108h, 00109h, 0010bh, 0010ch, 0010dh, 0010fh
	dw 00110h, 00112h, 00113h, 00114h, 00116h, 00117h, 00119h, 0011ah
	dw 0011bh, 0011dh, 0011eh, 00120h, 00121h, 00122h, 00124h, 00125h
	dw 00127h, 00128h, 0012ah, 0012bh, 0012ch, 0012eh, 0012fh, 00131h
	dw 00132h, 00133h, 00135h, 00136h, 00138h, 00139h, 0013bh, 0013ch
	dw 0013eh, 0013fh, 00140h, 00142h, 00143h, 00145h, 00146h, 00148h
	dw 00149h, 0014bh, 0014ch, 0014eh, 0014fh, 00150h, 00152h, 00153h
	dw 00155h, 00156h, 00158h, 00159h, 0015bh, 0015ch, 0015eh, 0015fh
	dw 00161h, 00162h, 00164h, 00165h, 00167h, 00168h, 0016ah, 0016bh
	dw 0016dh, 0016eh, 00170h, 00171h, 00173h, 00174h, 00176h, 00177h
	dw 00179h, 0017ah, 0017ch, 0017dh, 0017fh, 00180h, 00182h, 00183h
	dw 00185h, 00186h, 00188h, 0018ah, 0018bh, 0018dh, 0018eh, 00190h
	dw 00191h, 00193h, 00194h, 00196h, 00198h, 00199h, 0019bh, 0019ch
	dw 0019eh, 001a0h, 001a1h, 001a3h, 001a4h, 001a6h, 001a7h, 001a9h
	dw 001abh, 001ach, 001aeh, 001b0h, 001b1h, 001b3h, 001b4h, 001b6h
	dw 001b8h, 001b9h, 001bbh, 001bdh, 001beh, 001c0h, 001c1h, 001c3h
	dw 001c5h, 001c6h, 001c8h, 001cah, 001cbh, 001cdh, 001cfh, 001d0h
	dw 001d2h, 001d4h, 001d6h, 001d7h, 001d9h, 001dbh, 001dch, 001deh
	dw 001e0h, 001e1h, 001e3h, 001e5h, 001e7h, 001e8h, 001eah, 001ech
	dw 001eeh, 001efh, 001f1h, 001f3h, 001f5h, 001f6h, 001f8h, 001fah
	dw 001fch, 001feh, 001ffh, 00201h, 00203h, 00205h, 00207h, 00208h
	dw 0020ah, 0020ch, 0020eh, 00210h, 00212h, 00214h, 00215h, 00217h
	dw 00219h, 0021bh, 0021dh, 0021fh, 00221h, 00223h, 00225h, 00226h
	dw 00228h, 0022ah, 0022ch, 0022eh, 00230h, 00232h, 00234h, 00236h
	dw 00238h, 0023ah, 0023ch, 0023eh, 00240h, 00242h, 00244h, 00246h
	dw 00248h, 0024ah, 0024ch, 0024eh, 00250h, 00252h, 00254h, 00257h
	dw 00259h, 0025bh, 0025dh, 0025fh, 00261h, 00263h, 00265h, 00268h
	dw 0026ah, 0026ch, 0026eh, 00270h, 00273h, 00275h, 00277h, 00279h
	dw 0027ch, 0027eh, 00280h, 00282h, 00285h, 00287h, 00289h, 0028ch
	dw 0028eh, 00291h, 00293h, 00295h, 00298h, 0029ah, 0029dh, 0029fh
	dw 002a2h, 002a4h, 002a7h, 002a9h, 002ach, 002aeh, 002b1h, 002b3h
	dw 002b6h, 002b9h, 002bbh, 002beh, 002c1h, 002c3h, 002c6h, 002c9h
	dw 002cch, 002cfh, 002d1h, 002d4h, 002d7h, 002dah, 002ddh, 002e0h
	dw 002e3h, 002e6h, 002e9h, 002ech, 002efh, 002f2h, 002f6h, 002f9h
	dw 002fch, 002ffh, 00303h, 00306h, 0030ah, 0030dh, 00311h, 00314h
	dw 00318h, 0031bh, 0031fh, 00323h, 00327h, 0032bh, 0032fh, 00333h
	dw 00337h, 0033bh, 00340h, 00344h, 00349h, 0034dh, 00352h, 00357h
	dw 0035ch, 00361h, 00367h, 0036ch, 00372h, 00378h, 0037eh, 00385h
	dw 0038ch, 00394h, 0039ch, 003a4h, 003aeh, 003b9h, 003c6h, 003d7h
	dw 00400h

; ============================================================================
; _r3d_tbl_asin
;
; Table lookup returning a 16-bit fixed-point angle for a signed sine-like input, folding the
; sign into the positive quadrant and rescaling the 12-bit table entry.
;
; C equivalent:
;   int r3d_tbl_asin(int sinValue)
;   {
;       int sign;
;       int angle;
;
;       sign = 1;
;       if (sinValue < 0) {
;           sign = -1;
;           sinValue = -sinValue;
;       }
;
;       angle = g_awAsinTable[sinValue >> 5];
;
;       if (sign <= 0) {
;           angle = 0x1000 - angle;
;       }
;
;       return angle << 4;
;   }
; ============================================================================
@sinValue equ word ptr ss:[bx+4]
	public _r3d_tbl_asin
_r3d_tbl_asin:
	mov BX,SP
	mov AX, @sinValue
	mov DX,1h			; DX = sign (+1)
	cmp AX,0h
	jge @@absValue
	neg DX				; negative input: sign = -1, fold to positive
	neg AX
@@absValue:
	mov CL,5h
	sar AX,CL
	mov BX,AX
	shl BX,1h
	mov AX,word ptr CS:[BX+g_awAsinTable]
	cmp DX,0h
	jg @@scale
	mov BX, 1000h		; idx = 1000h - idx (half-period fold)
	sub BX,AX
	mov AX,BX
@@scale:
	shl AX,1h
	shl AX,1h
	shl AX,1h
	shl AX,1h
	retf

; In-segment data at 0x32d2 [g_awAtanTable]
g_awAtanTable	dw 00000h, 00001h, 00002h, 00003h, 00005h, 00006h, 00007h, 00008h
	dw 0000ah, 0000bh, 0000ch, 0000eh, 0000fh, 00010h, 00011h, 00013h
	dw 00014h, 00015h, 00016h, 00018h, 00019h, 0001ah, 0001bh, 0001dh
	dw 0001eh, 0001fh, 00021h, 00022h, 00023h, 00024h, 00026h, 00027h
	dw 00028h, 00029h, 0002bh, 0002ch, 0002dh, 0002fh, 00030h, 00031h
	dw 00032h, 00034h, 00035h, 00036h, 00037h, 00039h, 0003ah, 0003bh
	dw 0003ch, 0003eh, 0003fh, 00040h, 00041h, 00043h, 00044h, 00045h
	dw 00047h, 00048h, 00049h, 0004ah, 0004ch, 0004dh, 0004eh, 0004fh
	dw 00051h, 00052h, 00053h, 00054h, 00056h, 00057h, 00058h, 00059h
	dw 0005bh, 0005ch, 0005dh, 0005eh, 00060h, 00061h, 00062h, 00063h
	dw 00065h, 00066h, 00067h, 00068h, 0006ah, 0006bh, 0006ch, 0006dh
	dw 0006eh, 00070h, 00071h, 00072h, 00073h, 00075h, 00076h, 00077h
	dw 00078h, 0007ah, 0007bh, 0007ch, 0007dh, 0007eh, 00080h, 00081h
	dw 00082h, 00083h, 00085h, 00086h, 00087h, 00088h, 00089h, 0008bh
	dw 0008ch, 0008dh, 0008eh, 00090h, 00091h, 00092h, 00093h, 00094h
	dw 00096h, 00097h, 00098h, 00099h, 0009ah, 0009ch, 0009dh, 0009eh
	dw 0009fh, 000a0h, 000a2h, 000a3h, 000a4h, 000a5h, 000a6h, 000a8h
	dw 000a9h, 000aah, 000abh, 000ach, 000aeh, 000afh, 000b0h, 000b1h
	dw 000b2h, 000b3h, 000b5h, 000b6h, 000b7h, 000b8h, 000b9h, 000bah
	dw 000bch, 000bdh, 000beh, 000bfh, 000c0h, 000c1h, 000c3h, 000c4h
	dw 000c5h, 000c6h, 000c7h, 000c8h, 000cah, 000cbh, 000cch, 000cdh
	dw 000ceh, 000cfh, 000d0h, 000d2h, 000d3h, 000d4h, 000d5h, 000d6h
	dw 000d7h, 000d8h, 000dah, 000dbh, 000dch, 000ddh, 000deh, 000dfh
	dw 000e0h, 000e2h, 000e3h, 000e4h, 000e5h, 000e6h, 000e7h, 000e8h
	dw 000e9h, 000eah, 000ech, 000edh, 000eeh, 000efh, 000f0h, 000f1h
	dw 000f2h, 000f3h, 000f4h, 000f6h, 000f7h, 000f8h, 000f9h, 000fah
	dw 000fbh, 000fch, 000fdh, 000feh, 000ffh, 00101h, 00102h, 00103h
	dw 00104h, 00105h, 00106h, 00107h, 00108h, 00109h, 0010ah, 0010bh
	dw 0010ch, 0010dh, 0010eh, 00110h, 00111h, 00112h, 00113h, 00114h
	dw 00115h, 00116h, 00117h, 00118h, 00119h, 0011ah, 0011bh, 0011ch
	dw 0011dh, 0011eh, 0011fh, 00120h, 00121h, 00122h, 00123h, 00125h
	dw 00126h, 00127h, 00128h, 00129h, 0012ah, 0012bh, 0012ch, 0012dh
	dw 0012eh, 0012fh, 00130h, 00131h, 00132h, 00133h, 00134h, 00135h
	dw 00136h, 00137h, 00138h, 00139h, 0013ah, 0013bh, 0013ch, 0013dh
	dw 0013eh, 0013fh, 00140h, 00141h, 00142h, 00143h, 00144h, 00145h
	dw 00146h, 00147h, 00148h, 00149h, 0014ah, 0014bh, 0014ch, 0014dh
	dw 0014eh, 0014eh, 0014fh, 00150h, 00151h, 00152h, 00153h, 00154h
	dw 00155h, 00156h, 00157h, 00158h, 00159h, 0015ah, 0015bh, 0015ch
	dw 0015dh, 0015eh, 0015fh, 00160h, 00161h, 00161h, 00162h, 00163h
	dw 00164h, 00165h, 00166h, 00167h, 00168h, 00169h, 0016ah, 0016bh
	dw 0016ch, 0016dh, 0016dh, 0016eh, 0016fh, 00170h, 00171h, 00172h
	dw 00173h, 00174h, 00175h, 00176h, 00177h, 00177h, 00178h, 00179h
	dw 0017ah, 0017bh, 0017ch, 0017dh, 0017eh, 0017fh, 0017fh, 00180h
	dw 00181h, 00182h, 00183h, 00184h, 00185h, 00186h, 00186h, 00187h
	dw 00188h, 00189h, 0018ah, 0018bh, 0018ch, 0018ch, 0018dh, 0018eh
	dw 0018fh, 00190h, 00191h, 00192h, 00192h, 00193h, 00194h, 00195h
	dw 00196h, 00197h, 00197h, 00198h, 00199h, 0019ah, 0019bh, 0019ch
	dw 0019ch, 0019dh, 0019eh, 0019fh, 001a0h, 001a1h, 001a1h, 001a2h
	dw 001a3h, 001a4h, 001a5h, 001a5h, 001a6h, 001a7h, 001a8h, 001a9h
	dw 001a9h, 001aah, 001abh, 001ach, 001adh, 001adh, 001aeh, 001afh
	dw 001b0h, 001b1h, 001b1h, 001b2h, 001b3h, 001b4h, 001b5h, 001b5h
	dw 001b6h, 001b7h, 001b8h, 001b8h, 001b9h, 001bah, 001bbh, 001bch
	dw 001bch, 001bdh, 001beh, 001bfh, 001bfh, 001c0h, 001c1h, 001c2h
	dw 001c2h, 001c3h, 001c4h, 001c5h, 001c5h, 001c6h, 001c7h, 001c8h
	dw 001c8h, 001c9h, 001cah, 001cbh, 001cbh, 001cch, 001cdh, 001ceh
	dw 001ceh, 001cfh, 001d0h, 001d0h, 001d1h, 001d2h, 001d3h, 001d3h
	dw 001d4h, 001d5h, 001d6h, 001d6h, 001d7h, 001d8h, 001d8h, 001d9h
	dw 001dah, 001dbh, 001dbh, 001dch, 001ddh, 001ddh, 001deh, 001dfh
	dw 001dfh, 001e0h, 001e1h, 001e2h, 001e2h, 001e3h, 001e4h, 001e4h
	dw 001e5h, 001e6h, 001e6h, 001e7h, 001e8h, 001e8h, 001e9h, 001eah
	dw 001eah, 001ebh, 001ech, 001edh, 001edh, 001eeh, 001efh, 001efh
	dw 001f0h, 001f1h, 001f1h, 001f2h, 001f3h, 001f3h, 001f4h, 001f4h
	dw 001f5h, 001f6h, 001f6h, 001f7h, 001f8h, 001f8h, 001f9h, 001fah
	dw 001fah, 001fbh, 001fch, 001fch, 001fdh, 001feh, 001feh, 001ffh

; ============================================================================
; _r3d_tbl_atan2
;
; Four-quadrant fixed-point atan2 of y/x, returning a 16-bit binary angle (0x10000 == 2*pi) via
; a CS-resident octant lookup table.
;
; C equivalent:
;   int far r3d_tbl_atan2(int y, int x)
;   {
;       int signY, signX;
;       int angle;
;       unsigned idx;
;
;       signY = 1;
;       if (y < 0) {
;           signY = -1;
;           y = -y;
;       }
;       signX = 1;
;       if (x < 0) {
;           signX = -1;
;           x = -x;
;       }
;
;       if (y == 0) {
;           if (x == 0)
;               return 0;
;           angle = 0x400;                     /* +x axis: 90 degrees */
;       } else if (x == 0) {
;           angle = 0;                         /* +y axis: 0 degrees */
;       } else if (y == x) {
;           angle = 0x200;                     /* exact 45 degrees */
;       } else if ((unsigned)y < (unsigned)x) {
;           /* y < x: use y/x in [0,1), reflect table about the diagonal */
;           idx = (unsigned)(((long)y << 9) / (unsigned)x);
;           angle = 0x400 - g_awAtanTable[idx];
;       } else {
;           /* y > x: use x/y in [0,1) directly */
;           idx = (unsigned)(((long)x << 9) / (unsigned)y);
;           angle = g_awAtanTable[idx];
;       }
;
;       if (signY < 0)
;           angle = 0x800 - angle;             /* fold across the y sign */
;       if (signX < 0)
;           angle = 0x1000 - angle;            /* fold across the x sign */
;
;       return angle << 4;                     /* 0..0x1000 -> full 16-bit angle */
;   }
; ============================================================================
@y equ word ptr [bp+6]
@x equ word ptr [bp+8]
	public _r3d_tbl_atan2
_r3d_tbl_atan2:
	push BP
	mov BP,SP
	push SI
	push DI
	mov AX, @y
	mov BX, @x
	mov SI,1h
	cmp AX,0h
	jge @@yAbs
	neg SI
	neg AX
@@yAbs:
	mov DI,1h
	cmp BX,0h
	jge @@xAbs
	neg DI
	neg BX
@@xAbs:
	cmp AX,0h
	jnz @@yNonzero
	cmp BX,0h
	jnz @@axisX
	mov AX,0h
	jmp short @@done
@@axisX:
	mov AX, 400h		; 90 degrees (x axis zero case)
	jmp short @@applyFolds
@@yNonzero:
	cmp BX,0h
	jnz @@xNonzero
	xor AX,AX
	jmp short @@applyFolds
@@xNonzero:
	cmp AX,BX
	jnz @@ratioSelect
	mov AX, 200h		; 45 degrees (y == x)
	jmp short @@applyFolds
@@ratioSelect:
	jc @@reflect
	xor DH,DH
	mov DL,BH
	mov BH,BL
	xor BL,BL
	xchg AX, BX
	shl AX,1h
	rcl DX,1h
	div BX
	mov BX,AX
	shl BX,1h
	mov AX,word ptr CS:[BX+g_awAtanTable]
	jmp short @@applyFolds
@@reflect:
	xor DH,DH
	mov DL,AH
	mov AH,AL
	xor AL,AL
	shl AX,1h
	rcl DX,1h
	div BX
	mov BX,AX
	shl BX,1h
	mov AX, 400h		; reflect across the 45-degree diagonal
	sub AX,word ptr CS:[BX+g_awAtanTable]
@@applyFolds:
	cmp SI,0h
	jg @@foldX
	mov BX, 800h		; fold across the y sign: angle = 800h - angle
	sub BX,AX
	mov AX,BX
@@foldX:
	cmp DI,0h
	jg @@scale
	mov BX, 1000h		; fold across the x sign: angle = 1000h - angle
	sub BX,AX
	mov AX,BX
@@scale:
	shl AX,1h
	shl AX,1h
	shl AX,1h
	shl AX,1h
@@done:
	pop DI
	pop SI
	pop BP
	retf

; ============================================================================
; _r3d_tbl_atan_lookup_raw
;
; Returns the raw arctangent-table angle for a ratio index: g_awAtanTable[idx].
;
; C equivalent:
;   extern short g_awAtanTable[];
;
;   short r3d_tbl_atan_lookup_raw(int idx)
;   {
;       return g_awAtanTable[idx];
;   }
; ============================================================================
@idx equ word ptr [bp+6]
	public _r3d_tbl_atan_lookup_raw
_r3d_tbl_atan_lookup_raw:
	push BP
	mov BP,SP
	mov BX, @idx
	shl BX,1h
	mov AX,word ptr CS:[BX+g_awAtanTable]
	pop BP
	retf

S233E_TEXT	ends

	end
