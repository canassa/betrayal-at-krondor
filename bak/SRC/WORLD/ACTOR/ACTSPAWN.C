#include <stdlib.h>
#include "globals.h"
#include "structs.h"
#include "SRC/SYS/RAND.H"

#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/R3D/CORE/DISTDIR.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/WORLD/ACTOR/ACTORREC.H"
#include "SRC/WORLD/ENC/RGNENC.H"

/**
 * @brief Allocate a live heap @ref Actor for a template record and copy the
 *        template's header into it.
 *
 * Only the fixed @ref Actor header is copied; the variable-length payload
 * (item array and optional subrecords) is left zero-filled for the caller to
 * read in. Free the result with @ref _freemem (directly, or via
 * @ref actorspawn_destroy_and_persist).
 *
 * @param actor    Template record; supplies the copied header and, through
 *                 @ref actorrec_payload_size, the payload size to allocate.
 * @param canFlush Initial @ref Actor::canFlush: @ref TRUE if the clone owns a
 *                 temp-file write-back slot and so may be persisted.
 * @return Far pointer to the new @ref Actor; header copied, payload zeroed.
 */
static Actor far *actor_alloc_from_template(Actor far *actor, bool16 canFlush) {
    Actor far *dst;

    dst = alloc_far(actorrec_payload_size(actor) + sizeof(Actor), ALLOC_FAR_ZERO_FILL);
    *dst = *actor;
    dst->needsFlush = FALSE;
    dst->canFlush = canFlush;
    return dst;
}

long far actorspawn_location_lookup(int location_id) {
    register int i;
    ObjFixedLocationCacheEntry rec;

    if (location_id == g_gameState.objfixed_location_cache.location_id) {
        return g_gameState.objfixed_location_cache.temp_gam_offset;
    }
    for (i = 0; i < 20; i++) {

        gstate_temp_file_read_at((unsigned char far *)&rec, (unsigned)GAM_OBJFIXED_LOCATION(i), 0x16);
        if (location_id == rec.location_id) {
            g_gameState.objfixed_location_cache = rec;
            return rec.temp_gam_offset;
        }
    }
    return 0;
}

int actorspawn_for_location_by_time(int location_id) {
    int hi_nibble;
    int lo_nibble;
    int count;
    long offset;
    register int spawned;
    register int i;
    Actor hdr;

    if ((offset = actorspawn_location_lookup(location_id)) == 0) {
        return 0;
    }
    bak_fseek(g_pTempGamFp, offset, 0);
    bak_fread(&count, 2, 1, g_pTempGamFp);
    i = spawned = 0;
    if (i < count) {
        do {
            bak_fread(&hdr.kind, 0x10, 1, g_pTempGamFp);
            bak_fseek(g_pTempGamFp, actorrec_payload_size(&hdr), 1);
            hi_nibble = hdr.chap_band >> 4 & 0xf;
            lo_nibble = hdr.chap_band & 0xf;
            if (((hdr.flags & 0x80) != 0 || hdr.bResidence == RES_SELF_SPAWN) &&
                (g_gameState.nChapter >= (unsigned int)hi_nibble) &&
                (g_gameState.nChapter <= lo_nibble && hdr.bResidence != RES_FREE)) {
                rgnenc_visible_pool_append_spawn(&hdr.kind);
                spawned++;
            }
            i++;
        } while (i < count);
    }
    return spawned;
}

Actor far *actorspawn_objfixed(int kind, long world_x, long world_y) {
    register BakFile *stream;
    register int ipass;
    int rec_idx;
    unsigned int chap_min;
    unsigned int chap_max;
    int record_count;
    long offset;
    Actor far *spawned;
    ObjFixedTemplateBuffer tmpl;

    spawned = NULL;
    if (actorspawn_location_lookup(kind) == 0) {
        return NULL;
    }
    for (ipass = 0; spawned == NULL && ipass < 2; ipass++) {
        if (ipass != 0) {
            if (g_gameState.objfixed_location_cache.objfixed_offset == 0) {
                return NULL;
            }
            stream = bak_fopen("OBJFIXED.DAT", "rb");
            bak_fseek(stream, g_gameState.objfixed_location_cache.objfixed_offset, 0);
        } else {
            if (g_gameState.objfixed_location_cache.temp_gam_offset == 0) {
                return NULL;
            }
            stream = g_pTempGamFp;
            bak_fseek(stream, g_gameState.objfixed_location_cache.temp_gam_offset, 0);
        }
        bak_fread(&record_count, 2, 1, stream);
        for (rec_idx = 0; spawned == NULL && rec_idx < record_count; rec_idx++) {
            offset = bak_ftell(stream);
            bak_fread(&tmpl.header, 0x10, 1, stream);
            chap_min = (int)(unsigned int)tmpl.header.chap_band >> 4 & 0xf;
            chap_max = tmpl.header.chap_band & 0xf;
            if (tmpl.header.kind == kind && tmpl.header.nWorld_x == world_x &&
                tmpl.header.nWorld_y == world_y && g_gameState.nChapter >= chap_min &&
                g_gameState.nChapter <= chap_max) {
                spawned = actor_alloc_from_template((Actor far *)&tmpl, ipass == 0);
                *(long far *)spawned->temp_file_off = offset;
                bak_fread_chunked((unsigned char huge *)((char far *)spawned + sizeof(Actor)), 1,
                                  actorrec_payload_size((Actor far *)&tmpl), stream);
            } else {
                bak_fseek(stream, actorrec_payload_size((Actor far *)&tmpl), 1);
            }
        }
        if (ipass != 0) {
            bak_fclose(stream);
        }
    }
    return spawned;
}

void far actorspawn_persist_to_temp(Actor far *actor) {
    ActorSubrec10_LastTouch far *sub;

    if (actor->needsFlush && actor->canFlush) {
        sub = (ActorSubrec10_LastTouch far *)actorrec_get_subrecord(actor, SUBREC_LAST_TOUCH);
        if (sub != (ActorSubrec10_LastTouch far *)0) {
            sub->dwLast_touch_time = g_gameState.game_time;
        }
        g_wLastTempWriteRecordKind = 4;
        gstate_temp_file_write_at(&actor->kind, *(unsigned long far *)actor->temp_file_off,
                                  actorrec_payload_size(actor) + sizeof(Actor) - 6);
    }
    actor->needsFlush = FALSE;
}

void far actorspawn_destroy_and_persist(Actor far *actor) {
    if (actor != NULL) {
        if ((actor->flags & 0x80) != 0 && actor->itemCount == '\0') {
            actor->bResidence = RES_FREE;
            rgnenc_vis_pool_remove_matching(&actor->kind);
        }
        actorspawn_persist_to_temp(actor);
        _freemem(actor);
    }
}

Actor far *actorspawn_enc_location(int kind, long world_x, long world_y) {
    register int i;
    register int found;
    long spawn_loc;
    long cur_off;
    unsigned long cur_time;
    long best_off;
    unsigned long best_time;
    int count;
    Actor far *result;
    ActorSubrec10_LastTouch far *p_touch;
    Actor far *tmp_clone;
    Actor best_hdr;
    Actor actor_hdr;

    best_off = 0;
    best_time = 0xffffffff;
    result = NULL;
    if ((spawn_loc = actorspawn_location_lookup(kind)) == 0) {
        return NULL;
    }
    bak_fseek(g_pTempGamFp, spawn_loc, 0);
    bak_fread(&count, 2, 1, g_pTempGamFp);
    found = 0;
    i = found;
    while (!found && i < count) {
        cur_off = bak_ftell(g_pTempGamFp);
        bak_fread(&actor_hdr.kind, 0x10, 1, g_pTempGamFp);
        if (actor_hdr.bResidence == RES_FREE) {
            found = 1;
        } else {
            bak_fseek(g_pTempGamFp, actorrec_payload_size(&actor_hdr), 1);
        }
        i++;
    }
    if (!found) {
        bak_fseek(g_pTempGamFp, spawn_loc + 2, 0);
        i = 0;
        while (!found && i < count) {
            cur_off = bak_ftell(g_pTempGamFp);
            bak_fread(&actor_hdr.kind, 0x10, 1, g_pTempGamFp);
            if (actor_hdr.flags & 0x80) {
                tmp_clone = actor_alloc_from_template(&actor_hdr, FALSE);
                bak_fread_chunked((unsigned char far *)((char far *)tmp_clone + sizeof(Actor)), 1L,
                                  actorrec_payload_size(&actor_hdr), g_pTempGamFp);
                p_touch = (ActorSubrec10_LastTouch far *)actorrec_get_subrecord(tmp_clone,
                                                                                SUBREC_LAST_TOUCH);
                cur_time = (actor_hdr.flags & 0x40) ? (p_touch->dwLast_touch_time | 0x80000000ul)
                                                    : p_touch->dwLast_touch_time;
                if (cur_time < best_time) {
                    best_hdr = actor_hdr;
                    best_time = cur_time;
                    best_off = cur_off;
                }
                _freemem(tmp_clone);
            } else {
                bak_fseek(g_pTempGamFp, actorrec_payload_size(&actor_hdr), 1);
            }
            i++;
        }
        actor_hdr = best_hdr;
        cur_off = best_off;
        rgnenc_vis_pool_remove_matching(&best_hdr.kind);
    }
    actor_hdr.kind = (unsigned char)kind;
    actor_hdr.chap_band = '\n';
    actor_hdr.loc.world.nWorld_x = world_x;
    actor_hdr.loc.world.nWorld_y = world_y;
    if (g_game_mode == 2) {
        actor_hdr.world_item_id = 0x89;
    } else {
        actor_hdr.world_item_id = 0xa6;
    }
    if (g_wInCombatMode == 0) {
        rgnenc_visible_pool_append_spawn(&actor_hdr.kind);
    }
    result = actor_alloc_from_template(&actor_hdr, TRUE);
    result->itemCount = '\0';
    result->bResidence = RES_ENCOUNTER;
    result->flags |= 0x80;
    *(long far *)result->temp_file_off = cur_off;
    result->needsFlush = TRUE;
    actorspawn_persist_to_temp(result);
    return result;
}

void far actorspawn_npc_prox_periodic(Actor far *actor) {
    register int iZone;
    register int kind;
    int iEntry;
    int coverWeight;
    int trafficWeight;
    long dist;
    long score;
    ActorSubrec01_Proximity far *pProx;
    ActorSubrec10_LastTouch far *pTouch;
    VisibleEntryList *pList;
    WorldObject far *pEnt;
    Shape far *pRec;
    Vec3Long npc_pos;
    Vec3Long actor_pos;

    coverWeight = 1;
    trafficWeight = 1;
    score = 1000;

    pProx = (ActorSubrec01_Proximity far *)actorrec_get_subrecord(actor, SUBREC_PARAMS);
    pTouch = (ActorSubrec10_LastTouch far *)actorrec_get_subrecord(actor, SUBREC_LAST_TOUCH);

    if (pTouch == NULL)
        return;
    if (pTouch->dwLast_touch_time == 0)
        return;
    if (g_wInCombatMode != 0)
        return;
    if (actor->itemCount == 0 || (actor->flags & 0x40))
        return;

    if (actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) != NULL ||
        actor->bResidence == RES_PARTY_SLOT || actor->bResidence == RES_COMBAT) {
        score = 0;
    }

    if (pProx != NULL) {
        if (pProx->bIntensity != 0) {
            score /= pProx->bIntensity / 2 + 1;
        }
        if (pProx->bHundred_flag != 0) {
            score /= 100;
        }
        if (pProx->bFlags & 4) {
            score /= 0x32;
        }
    }

    actor_pos.nX = actor->loc.world.nWorld_x;
    actor_pos.nY = actor->loc.world.nWorld_y;
    actor_pos.nZ = 0;

    for (iZone = 0; iZone < g_nCombat_zone_count; iZone++) {
        pList = g_apCombat_zone_actor_lists[iZone];
        pEnt = pList->pEntries;
        for (iEntry = 0; iEntry < (int)pList->wEntry_count; iEntry++, pEnt++) {
            npc_pos = *(Vec3Long far *)&pEnt->pos.xy.nWorld_x;
            pRec = ts_get_shape(pEnt->shapeId);
            kind = pRec->kind;
            dist = distdir_octagonal_distance((long *)&actor_pos, (long *)&npc_pos);
            if (kind == 5 || kind == 0x1e || kind == 0x15 || kind == 0x16 || kind == 0x12) {
                if (dist < 6000) {
                    coverWeight += (dist < 1000) + 1;
                }
            } else if (kind != 1 && kind != 2 && (kind == 10 || kind == 0x1f || kind == 0xd) &&
                       dist < 30000) {
                trafficWeight += (dist < 15000 ? 12 : 6);
            }
        }
    }

    score = score * (long)trafficWeight / (long)coverWeight;
    score = score * (long)((g_gameState.game_time - pTouch->dwLast_touch_time) / 0xa8c0ul);

    if ((long)RND(10000u) < score || gstate_event_read(0xdc54)) {
        actor->itemCount = 0;
        actor->needsFlush = TRUE;
    }
}
