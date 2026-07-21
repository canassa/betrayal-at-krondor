#include "globals.h"
#include "structs.h"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"

TimerEventEntry *far timerpool_upsert(ushort kind, ushort sub_id, ushort mode, long value) {
    int i;
    TimerEventEntry *p;

    if ((mode & 0x80) || (mode & 0x40)) {
        i = 0;
        p = g_gameState.aTimerEventPool;
        while (i < g_gameState.nTimerEventPoolCount) {
            if ((p->bKind == kind) && (p->wSub_id == sub_id)) {
                if (mode & 0x80) {
                    p->nValue += value;
                } else {
                    p->nValue = value;
                }
                return p;
            }
            i++;
            p++;
        }
    }
    if (g_gameState.nTimerEventPoolCount < 0x14) {
        p = &g_gameState.aTimerEventPool[g_gameState.nTimerEventPoolCount];
        g_gameState.nTimerEventPoolCount++;
        p->bKind = (unsigned char)kind;
        p->bMode_at_insert = (unsigned char)mode;
        p->wSub_id = sub_id;
        p->nValue = value;
        return p;
    }
    return (TimerEventEntry *)0;
}

void timerpool_tick(int delta_ticks) {
    TimerEventEntry *entry;
    int i;

    entry = g_gameState.aTimerEventPool;
    i = 0;
    while (i < g_gameState.nTimerEventPoolCount) {
        entry->nValue -= (long)delta_ticks;
        if (entry->nValue <= 0) {
            entry->nValue = 0;
        }
        switch (entry->bKind) {
        case 1:
            palette_fade_run_scheduled(entry);
            break;
        case 2:
            spellfx_pal_event_mask_upd(entry);
            break;
        }
        if (entry->nValue != 0) {
            i++;
            entry++;
        } else {
            if (entry->bKind == 3) {
                gstate_event_write(entry->wSub_id, 1);
            } else if (entry->bKind == 4) {
                gstate_event_write(entry->wSub_id, 0);
            }
            g_gameState.nTimerEventPoolCount--;
            *entry = g_gameState.aTimerEventPool[g_gameState.nTimerEventPoolCount];
        }
    }
}

int far timerpool_contains(ushort kind, ushort sub_id) {
    int i;
    TimerEventEntry *p;

    i = 0;
    p = g_gameState.aTimerEventPool;
    while (i < g_gameState.nTimerEventPoolCount) {
        if ((p->bKind == kind) && (p->wSub_id == sub_id)) {
            return 1;
        }
        i = i + 1;
        p++;
    }
    return 0;
}
