#include "globals.h"
#include "structs.h"
#include "SRC/GFX/PALETTE/PALCYC.H"
#include "SRC/GFX/DRIVER/PALDRV.H"

void far palette_cycle_eb_toggle(int enable) {
    if (enable != 0) {
        if (g_bPaletteCycleEbActive == 0) {
            palette_cycle_add(0xeb, 5, -1);
            g_bPaletteCycleEbActive = 1;
        }
    } else {
        g_bPaletteCycleEbActive = 0;
        palette_cycle_add(-1, 0, 0);
    }
}
