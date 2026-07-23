#include <dos.h>
#include "globals.h"
#include "SRC/SYS/EMS.H"
#include "SRC/SYS/EMSDET.H"

int ems_detect_driver(void) {
    asm {
        mov     ax, 3567h
        int     21h
        mov     di, 0ah
        mov     si, offset s_ems_driver_signature
        mov     cx, 8
        repe    cmpsb
    }
    L_check_zf : asm jnz L_no_ems;

    _AH = 0x40;
    geninterrupt(0x67);
    if (_AH)
        goto L_no_ems;

    _AH = 0x41;
    geninterrupt(0x67);
    if (_AH)
        goto L_no_ems;
    g_ems_free_pages = _BX;

    _AH = 0x46;
    geninterrupt(0x67);
    if (_AH)
        goto L_no_ems;
    asm { cmp al, 32h; jc L_check_zf }

    _AH = 0x42;
    geninterrupt(0x67);
    if (_AH)
        goto L_no_ems;
    g_ems_total_pages = _BX;
    if (_BX == 0)
        goto L_no_ems;

    _AH = 0x43;
    geninterrupt(0x67);
    if (_AH)
        goto L_no_ems;
    g_ems_frame_segment = _DX;

    g_ems_present = _AX = 1;
    asm jmp short L_ret;
L_no_ems:
    g_ems_present = _AX = 0;
L_ret:
    return _AX;
}
