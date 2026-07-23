#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "SRC/GAME/GMAIN.H"
#include "structs.h"
#include "SRC/GAME/GSTATE.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/DIALOG/EVTCOND.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"
#include "SRC/GAME/CFGPARSE.H"

unsigned short g_wLastTempWriteRecordKind = 0xffff;
char g_abChapterEventSlot[9] = {0x00, 0x04, 0x04, 0x01, 0x04, 0x02, 0x04, 0x02, 0x03};
BakFile *g_pTempGamFp = {0};
char g_abSleepStatDelta[6] = {0xfe, 0xff, 0xfe, 0xfe, 0xfe, 0xfd};
char g_abRegenPerChar[6] = {0x01, 0x01, 0x01, 0x01, 0x01, 0x01};

unsigned short far gstate_event_read(unsigned short id) {

    if (id < 0x2134) {
        return (g_gameState.event_bitmap_lo[id >> 3] & (1 << (id & 7))) ? 1 : 0;
    }
    if (id >= 0xc350 && id < 0xc3da) {
        return itemtbl_party_count_by_kind(id + 0x3cb0);
    }
    if (id >= 0xcb20 && id < 0xcb27) {
        unsigned int w = id + 0x34df;
        return spellfx_event_mask_test_bit(w);
    }
    if (id >= 0xcf08 && id <= 0xcf6c) {
        unsigned int w = id + 0x30f8;
        return RND(w);
    }
    if (id >= 0xdac0) {
        unsigned int cx = id + 0x2540;
        unsigned int row = cx / 10;
        unsigned int w = cx % 10 - 1;
        return (g_gameState.event_bitmap_hi[row] & (1 << w)) ? 1 : 0;
    }

    switch (id - 0x7530) {
    case 0:
        return g_gameState.nEvtArgCount;
    case 1: {
        long g = g_gameState.nParty_gold / 10;
        return (g > 0xffffL) ? 0xffff : (unsigned short)g;
    }
    case 2:
        return (g_gameState.nParty_gold > 0xffff) ? 0xffff : (unsigned short)g_gameState.nParty_gold;
    case 7:
        return g_gameState.nChapter;
    case 19:
        return g_gameState.nZoneId;
    case 3:
        return (g_gameState.nParty_gold >= g_gameState.lEvtArgGoldCost) ? 1 : 0;
    case 13:
        return g_gameState.nEvtArgDlgResult;
    case 5:
        return gstate_is_party_member(3) ? 3 : g_abChapterEventSlot[g_gameState.nChapter - 1];
    case 10: {
        short h = (short)(g_gameState.game_time % 0xa8c0 / 0x708);
        return (h >= 4 && h < 0x14) ? 1 : 0;
    }
    case 9: {
        short h = (short)(g_gameState.game_time % 0xa8c0 / 0x708);
        return (h < 4 || h >= 0x14) ? 1 : 0;
    }
    case 12:
        return (unsigned short)(g_gameState.game_time % 0xa8c0 / 0x708);
    case 14:
        return (unsigned short)g_gameState.lEvtArgGoldCost;
    case 15:
        return (unsigned short)g_gameState.lEvtArgValue;
    case 18:
        return (unsigned short)g_gameState.lEvtArgAuxValue;
    case 20:
    case 21:
    case 22:
    case 23:
    case 24:
    case 25:
    case 26:
    case 27:
    case 28:
        return ((id - 0x7544 + 1) == g_gameState.nChapter) ? 1 : 0;
    case 29:
        return (g_gameState.dwPopup_retry_state > 0) ? 1 : 0;
    default:
        return evtcond_range_d_read_handler(id);
    }
}

int far gstate_event_write(unsigned int event_id, unsigned int value) {
    unsigned int idx;
    unsigned int q;
    unsigned int bit;

    if (event_id < 0x2134) {
        if (value != 0) {
            g_gameState.event_bitmap_lo[event_id >> 3] |= (1 << (event_id & 7));
        } else {
            g_gameState.event_bitmap_lo[event_id >> 3] &= ~(1 << (event_id & 7));
        }
    } else if (event_id >= 0xdac0) {
        idx = event_id + 0x2540;
        q = idx / 10;
        bit = idx % 10 - 1;
        if (value != 0) {
            g_gameState.event_bitmap_hi[q] |= (1 << bit);
        } else {
            g_gameState.event_bitmap_hi[q] &= ~(1 << bit);
        }
    } else {
        switch (event_id - 0x7530) {
        case 0:
            g_gameState.nEvtArgCount = value;
            break;
        case 14:
            g_gameState.lEvtArgGoldCost = (long)value;
            break;
        case 15:
            g_gameState.lEvtArgValue = (long)value;
            break;
        case 18:
            g_gameState.lEvtArgAuxValue = (long)value;
            break;
        case 16:
            g_gameState.bCombatExitRequest = value;
            break;
        case 17:
            g_gameState.nWorldLoopExitRequest = value;
            break;
        case 7:
            g_gameState.nChapter = value;
            break;
        case 6:
            g_gameState.dwLastActionTimeSnapshot = 0;
            break;
        default:
            evtcond_range_d_write_stub(event_id, value);
            break;
        }
    }
}

int gstate_temp_file_open(void) {
    char buf[50];

    if (g_cfgTempDrive != 0) {
        sprintf(buf, "%c:%s", g_cfgTempDrive, "TEMP.GAM");
        if ((g_pTempGamFp = bak_fopen(buf, "r+b")) != (BakFile *)0)
            return 1;
        return 0;
    }

    if ((g_pTempGamFp = bak_fopen("TEMP.GAM", "r+b")) != (BakFile *)0)
        return 1;
    return 0;
}

void gstate_temp_file_close(void) {
    bak_fclose(g_pTempGamFp);
    g_pTempGamFp = (BakFile *)0;
    return;
}

int gstate_temp_file_read_at(unsigned char far *dst_far, unsigned long offset, unsigned int bytes) {
    if (bak_fseek(g_pTempGamFp, offset, 0) != 0) {
        bak_fseek(g_pTempGamFp, 0, 0);
        if (bak_fseek(g_pTempGamFp, offset, 0) != 0) {
        }
    }
    if ((unsigned long)bak_ftell(g_pTempGamFp) == offset) {
    }
    bak_fread_chunked(dst_far, 1, (long)bytes, g_pTempGamFp);
    return 1;
}

int gstate_temp_file_write_at(unsigned char far *src_far, unsigned long offset, unsigned int bytes) {
#ifdef V102CD
    unsigned long lo;
    unsigned long hi;
    if (g_pTempGamFp == (BakFile *)0 || offset > 0x51aa9)
        return 0;
    switch (g_wLastTempWriteRecordKind) {
    case 1:
        lo = 0xad7;
        hi = 0x90e7;
        if (offset < lo || offset + bytes > hi)
            return 0;
        break;
    case 2:
        lo = 0x90e7;
        hi = lo + 0x281fe;
        if (offset < lo || offset + bytes > hi)
            return 0;
        break;
    case 3:
        lo = 0x312e5;
        hi = lo + 0x94ac;
        if (offset < lo || offset + bytes > hi)
            return 0;
        break;
    case 4:
        lo = 0x3a791;
        hi = 0x51aa9;
        if (offset < lo || offset + bytes > hi)
            return 0;
        break;
    case 0:
        lo = 0;
        hi = 0xad7;
        if (offset < lo || offset + bytes > hi)
            return 0;
        break;
    }
    g_wLastTempWriteRecordKind = 0xffff;
#endif
    if (bak_fseek(g_pTempGamFp, offset, 0) != 0) {
        bak_fseek(g_pTempGamFp, 0, 0);
        if (bak_fseek(g_pTempGamFp, offset, 0) != 0)
            ;
    }
    if (bak_ftell(g_pTempGamFp) == (long)offset)
        ;
    bak_fwrite_chunked(src_far, 1, (unsigned long)bytes, g_pTempGamFp);
    return 1;
}

static int far gstate_consume_rations_tick(int ctx) {
    int table_loaded;
    int i;
    int event_total;

    table_loaded = itemtbl_load();
    i = event_total = 0;
    for (; i < g_gameState.party_count; i = i + 1) {
        event_total += gstate_member_consume_rations(g_gameState.party_roster[i], ctx);
    }
    if (table_loaded != 0) {
        itemtbl_free();
    }
    return event_total;
}

int far gstate_member_consume_rations(int member_slot, int a) {
    int ret;
    CombatActor *actor;

    actor = &g_gameState.party_members[member_slot];
    ret = 0;
    g_gameState.nEvtArgActor0 = member_slot;

    if (itemtbl_inv_consume_one_by_kind(actor->actor_record, 0x48) != 0) {
        stat_combatant_apply_delta(actor, 5, -100);
    } else if (itemtbl_inv_consume_one_by_kind(actor->actor_record, 0x4a) != 0) {
        stat_combatant_apply_delta(actor, 5, -100);
        stat_combatant_apply_delta(actor, 0, 3);
    } else if (itemtbl_inv_consume_one_by_kind(actor->actor_record, 0x49) != 0) {
        stat_combatant_apply_delta(actor, 2, 4);
    } else {
        stat_combatant_apply_delta(actor, 5, 5);
    }
    return ret;
}

extern ConditionInfo far g_aConditionInfo[7];

static int gstate_30min_tick(int arg0, int arg1, int arg2) {
    int cond;
    int regen;
    int eventFired;
    int allConscious;
    unsigned long elapsed;
    int val;
    /* The two party-regen loop temps (slot = roster index, actor = resolved
       member id) are pinned to SI/DI as a pair — the hot-loop-counter idiom. */
    register int actor;
    register int slot;

    eventFired = 0;
    allConscious = 1;
    elapsed = g_gameState.game_time - g_gameState.dwLastActionTimeSnapshot;
    if ((((arg0 == 0) || (arg1 == 0)) || (elapsed < 0x7788)) || (elapsed >= 0x7e90)) {
        if ((arg1 == 0) || (elapsed < 0x7e90))
            goto party_regen;
        for (slot = 0; slot < g_gameState.party_count; slot = slot + 1) {
            actor = g_gameState.party_roster[slot];
            if (stat_combatant_modify(&g_gameState.party_members[actor], 0x10,
                                      (long)((int)g_abSleepStatDelta[actor] << 8), 100) == 0) {
                allConscious = 0;
            }
        }
        if ((!allConscious) || (arg0 == 0))
            goto party_regen;
    }
    dialog_play_record(0x40, eventFired = 1);
party_regen:
    for (slot = 0; slot < g_gameState.party_count; slot = slot + 1) {
        actor = g_gameState.party_roster[slot];
        if (arg2 != 0) {
            stat_combatant_apply_delta(&g_gameState.party_members[actor], 0, -3);
            val = (arg2 == 100) ? 0x50 : 100;
            regen = (g_abRegenPerChar[actor] * arg2) / 100;
            if (g_gameState.abActorStatusRanks[actor][4] != '\0') {
                regen *= 2;
            }
        } else {
            regen = 0;
            val = 100;
        }
        cond = 0;
        do {
            if (g_gameState.abActorStatusRanks[actor][cond] != '\0') {
                int amount;
                amount = g_aConditionInfo[cond].nStatDelta;
                if ((cond < 4) && (g_gameState.abActorStatusRanks[actor][4] != '\0')) {
                    amount -= (cond == 0) + 2;
                }
                stat_combatant_apply_delta(&g_gameState.party_members[actor], cond, amount);
            }
            if ((g_gameState.abActorStatusRanks[actor][cond] != '\0') &&
                (g_aConditionInfo[cond].nRegenDelta != 0)) {
                regen += g_aConditionInfo[cond].nRegenDelta;
            }
            cond++;
        } while (cond < 7);
        if (regen != 0) {
            stat_combatant_modify(&g_gameState.party_members[actor], 0x10, (long)(regen << 8), val);
        }
    }
    if ((arg0 != 0) && ((g_gameState.bPartyDirtyFlags & 2) != 0)) {
        val = (char)g_gameState.bPartyDirtyFlags;
        g_gameState.bPartyDirtyFlags = '\x02';
        evtcond_pty_dirty_flags_process();
        g_gameState.bPartyDirtyFlags = val & 1;
        eventFired = 1;
    }
    return eventFired;
}

int far gstate_advance_time(long seconds, int flags, int recompute_party, int a, int b) {
    int actor;
    int rank;
    int n;
    int i;
    int old_hd;
    int eventTotal;
    int old_tick;
    CombatActor *member;

    eventTotal = 0;
    old_tick = (int)(g_gameState.game_time % 0xa8c0 / 0x708);
    old_hd = (int)(g_gameState.game_time / 0xa8c0);
    g_gameState.game_time += seconds;
    if (g_gameState.game_time / 0xa8c0 != (long)old_hd) {
        if (old_hd % 0x1e == 0) {
            for (i = 0; i < g_gameState.party_count; i = i + 1) {
                member = &g_gameState.party_members[g_gameState.party_roster[i]];
                member->stats[0].max = member->stats[0].max + (member->stats[0].max < 0xfa);
                member->stats[1].max = member->stats[1].max + (member->stats[1].max < 0xfa);

                n = SKILL_IMPROVED(g_gameState.party_roster[i] * 0x11);
                gstate_event_write(n, 1);
                gstate_event_write(n + 1, 1);
            }
        }
        if (recompute_party != 0) {
            eventTotal += gstate_consume_rations_tick(flags);
        }
        for (i = 0; i < g_gameState.party_count; i = i + 1) {
            actor = g_gameState.party_roster[i];
            rank = (char)g_gameState.abActorStatusRanks[actor][6];
            n = (rank + -100) / 10 + -1;
            if (g_gameState.abActorStatusRanks[actor][4] != '\0') {
                n *= 2;
            }
            if (rank != 0) {
                stat_combatant_apply_delta(&g_gameState.party_members[actor], 6, n);
            }
        }
    }
    if ((g_gameState.game_time % 0xa8c0) / 0x708 != (long)old_tick) {
        eventTotal += gstate_30min_tick(flags, a, b);
    }
    timerpool_tick((int)seconds);
    palette_daylight_tick();
    return eventTotal;
}

int far gstate_advance_half_hours(int half_hours, int pad, int flags) {
    int eventTotal;

    g_gameState.dwLastActionTimeSnapshot = g_gameState.game_time;
    eventTotal = gstate_advance_time((long)half_hours * 0x708, 1, 1, 0, flags);
    g_gameState.dwLastActionTimeSnapshot = g_gameState.game_time;
    return eventTotal;
}

int gstate_is_party_member(int actor_id) {
    int i;

    for (i = 0; g_gameState.party_count > i; i++) {
        if (g_gameState.party_roster[i] == actor_id) {
            return 1;
        }
    }
    return 0;
}

int gstate_actor_is_caster(CombatActor *actor) {
    return actor->stats[SKILL_CASTING].max != 0;
}

CombatActor *gstate_party_member_record(int slot) {
    if (slot >= 0 && slot < g_gameState.party_count) {
        return &g_gameState.party_members[g_gameState.party_roster[slot]];
    }
    return 0;
}

int gstate_find_party_slot(CombatActor *actor) {
    int result_slot;
    int i;

    i = 0;
    result_slot = -1;
    for (; i < g_gameState.party_count; i = i + 1) {
        if (g_gameState.party_members[g_gameState.party_roster[i]].cParty_slot ==
            actor->cParty_slot) {
            result_slot = i;
        }
    }
    return result_slot;
}

void gstate_format_money(char *buf, long gold, int mode) {
    long g = gold / 10;
    long s = gold % 10;

    if (mode == 0) {
        sprintf(buf, "%ld.%ld gold", g, s);
    } else if (mode == 1) {
        if (s != 0) {
            if (g != 0) {
                sprintf(buf, "%ld gold %ld silver", g, s);
            } else {
                sprintf(buf, "%ld silver", s);
            }
        } else {
            sprintf(buf, "%ld gold", g);
        }
    } else {
        if (s != 0) {
            if (g > 1) {
                sprintf(buf, "%ld sovereigns and %ld royal", g, s);
            } else {
                if (g != 0) {
                    sprintf(buf, "%ld sovereign and %ld royal", g, s);
                } else {
                    sprintf(buf, "%ld royal", s);
                }
            }
            if (s > 1) {
                strcat(buf, "s");
            }
        } else {
            sprintf(buf, "%ld sovereign%c", g, g > 1 ? 's' : 0);
        }
    }
}
