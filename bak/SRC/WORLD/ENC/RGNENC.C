#include "SRC/GAME/GMAIN.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "structs.h"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/ACTOR/ACTRENDR.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "defines.h"

EncounterRecordTemplate *g_pEncounterRecordTemplates;
long g_anEncounterRecordIds[5];
WorldObject far *g_pFixed_object_entries;
WorldObject far *g_pVisible_entry_pool;
EncounterObjectState *g_pEncounterObjectState;
int g_nCombatTempZoneEncounterCount;
unsigned char g_bCombatTempZoneRefPair;

short g_nEncounter_record_count = 0;
short g_nFixed_object_count = 0;
short g_nVisible_entry_count = 0;
unsigned short *g_pZoneShapeIndex = {0};
unsigned short *g_pChapterShapeIds = {0};

void far rgnenc_alloc_3bufs_init(void) {
    WorldObject far *p;
    EncounterActorAux *pBuf;
    int i;

    p = g_pFixed_object_entries;

    g_pEncounterRecordTemplates = galloc_safe_zcalloc(0x69f);
    pBuf = galloc_safe_zcalloc(0x15e);
    i = 0;
    do {
        p->state.encounterAux = pBuf;
        pBuf = pBuf + 1;
        i = i + 1;
        p++;
    } while (i < 0x23);

    g_pEncounterObjectState = galloc_safe_zcalloc(0x1a4);
    g_nEncounter_record_count = g_nFixed_object_count = g_nVisible_entry_count = 0;
    rgnenc_world_objects_reset_spawn();
}

void rgnenc_free_3bufs_clear(void) {
    galloc_zfree(g_pEncounterObjectState);
    galloc_zfree(g_pFixed_object_entries->state.encounterAux);
    galloc_zfree(g_pEncounterRecordTemplates);
    g_nEncounter_record_count = g_nFixed_object_count = g_nVisible_entry_count = 0;
    return;
}

int far rgnenc_load_zone_shape_index(char *filename) {
    BakFile *fp;
    int i;

    if (g_pZoneShapeIndex != 0) {
        return 0;
    }

    g_pZoneShapeIndex = (unsigned short *)galloc_safe_zcalloc(0xa);
    fp = bak_fopen(filename, "rb");
    bak_fseek(fp, (long)(((unsigned)g_gameState.nChapter - 1) << 3), 1);
    bak_fread(g_pZoneShapeIndex, 2, 4, fp);
    bak_fclose(fp);

    for (i = 4; i < 5; i++) {
        g_pZoneShapeIndex[i] = 0xffff;
    }

    for (i = 0; i < 4; i++) {
        if ((short)g_pZoneShapeIndex[i] != -1) {
            combat_actor_bnames_load_cached(g_pZoneShapeIndex[i], 0);
        }
    }
    return 1;
}

int far rgnenc_rel_object_state_group(void) {
    int i;

    if (g_pZoneShapeIndex != (unsigned short *)0x0) {
        for (i = 3; i >= 0; i--) {
            if (g_pZoneShapeIndex[i] != 0xffff) {
                combat_actor_release_anim_images(g_pZoneShapeIndex[i]);
            }
        }
        galloc_zfree(g_pZoneShapeIndex);
        g_pZoneShapeIndex = (unsigned short *)0x0;
        return 1;
    }
    return 0;
}

void far rgnenc_savefile_init_35slot_tbl(void) {
    EncounterObjectState tbl[35];
    EncounterObjectState *p;
    int i;

    p = tbl;
    for (i = 0; i < 0x23; i++, p++) {
        if (i != 0)
            p->wKind_state = 0x100;
        else
            p->wKind_state = 0;
        p->pose.nWorld_x_offset = p->pose.nWorld_y_offset = 0;
        p->pose.nFacing = 0;
    }
    for (i = 0; i < 0x28; i++) {
        g_wLastTempWriteRecordKind = 1;
        gstate_temp_file_write_at((unsigned char far *)tbl,
                                  (unsigned long)(unsigned)GAM_ENC_OBJ_STATE((unsigned)(i * 0x23)), 0x1a4);
    }
}

struct Type1BakRec {
    unsigned char hdr[2];
    long recId;
    unsigned char body[52];
    EncounterRecordTemplate tmpl;
    unsigned int flags;
};

struct Type7BakRec {
    unsigned char hdr[2];
    long recId;
    unsigned char body[62];
    EncounterRecordTemplate tmpl;
    unsigned int flags;
};

void far rgnenc_load_encounter_actors(void) {
    ZoneHotspot *pEvt;
    EncounterRecordTemplate *pTmpl;
    EncounterRecordTemplate *pTmplSrc;
    short *pActorDelta;
    EncounterObjectState *pObjState;
    WorldObject far *pSlot;
    long nRecordId;
    long nOriginX;
    long nOriginY;
    int nEncIdx;
    int nFlags;
    int bPlace;
    unsigned short nShapeCount;
    unsigned short aShapeIds[1];
    unsigned char bZoneY;
    unsigned char bZoneX;
    struct Type1BakRec type1_rec;
    struct Type7BakRec type7_rec;
    short aActorSlots[7];
    CombatActorInner inner;
    int j;
    EncounterActorAux *pAux;
    int v;
    int i;
    int k1;
    int k2;
    int k3;
    int k4;

    pEvt = hotspotevt_next_entry_19byte(1);
    pObjState = g_pEncounterObjectState;
    nEncIdx = (unsigned int)g_apCombat_zone_actor_lists[0]->bRef_pair_index * 0x23;
    nShapeCount = 0;
    g_nEncounter_record_count = g_nFixed_object_count = 0;
    czone_get_party_tile_xy(&bZoneY, &bZoneX);
    nOriginX = (long)(int)(unsigned int)bZoneY * 64000;
    nOriginY = (long)(int)(unsigned int)bZoneX * 64000;
    gstate_temp_file_read_at((unsigned char far *)g_pEncounterObjectState,
                             (unsigned long)(unsigned)GAM_ENC_OBJ_STATE(nEncIdx), 0x1a4);
    if ((g_pEncounterObjectState->wKind_state & 0xff08) >> 8 == 0) {
        g_pEncounterObjectState->wKind_state = 0x100;
        while (pEvt != (ZoneHotspot *)0) {
            if (pEvt->wKind == 1 || pEvt->wKind == 7) {
                if (pEvt->wKind == 1) {
                    hotspotevt_bak_load_indexed_rec(1, &type1_rec, pEvt->dwDef_record_offset);
                    nRecordId = type1_rec.recId;
                } else {
                    hotspotevt_bak_load_indexed_rec(7, &type7_rec, pEvt->dwDef_record_offset);
                    nRecordId = type7_rec.recId;
                }
                gstate_temp_file_read_at((unsigned char far *)aActorSlots, GAM_ENC_ROSTER(nRecordId), 0xe);
                j = 0;
                while (j < 7) {
                    if (aActorSlots[j] != -1) {
                        gstate_temp_file_read_at(
                            (unsigned char far *)&inner, GAM_COMBAT_ACTOR_INNER((long)aActorSlots[j]), 0x16);
                        /* The flags byte is read through (int)(signed char)
                           so the compiler sign-extends it (MOV AL;CWDE) and TESTs
                           the word, rather than folding to a byte-ptr TEST. The
                           result is never used beyond the mask; v is a scratch.
                           See rgnenc_mark_defended for the same idiom. */
                        if (((v = (int)(signed char)inner.flags) & CAF_DEAD) == 0) {
                            pObjState->wKind_state = 0x200;
                        }
                    }
                    j++;
                    pObjState++;
                }
            }
            pEvt = hotspotevt_next_entry_19byte(2);
        }
    }

    for (pEvt = hotspotevt_next_entry_19byte(1); pEvt != (ZoneHotspot *)0;
         pEvt = hotspotevt_next_entry_19byte(2)) {
        if (pEvt->wKind == 1 || pEvt->wKind == 7) {
            if (pEvt->wKind == 1) {
                hotspotevt_bak_load_indexed_rec(1, &type1_rec, pEvt->dwDef_record_offset);
                pTmplSrc = &type1_rec.tmpl;
                nRecordId = type1_rec.recId;
                nFlags = type1_rec.flags & 1;
            } else {
                hotspotevt_bak_load_indexed_rec(7, &type7_rec, pEvt->dwDef_record_offset);
                pTmplSrc = &type7_rec.tmpl;
                nRecordId = type7_rec.recId;
                nFlags = type7_rec.flags & 1;
            }
            if (g_nEncounter_record_count < 5) {
                nEncIdx = g_nEncounter_record_count;
                g_anEncounterRecordIds[g_nEncounter_record_count] = nRecordId;

                pTmpl = g_pEncounterRecordTemplates + g_nEncounter_record_count;
                *pTmpl = *pTmplSrc;
                pActorDelta = &pTmpl->pActors[0].nPaged_record_delta;
                pSlot = g_pFixed_object_entries + g_nFixed_object_count;
                pObjState = g_pEncounterObjectState + nEncIdx * 7;
                for (j = 0;
                     g_nFixed_object_count < 0x23 && j < (int)(unsigned int)pTmpl->pActors[0].kind && j < 7;
                     pActorDelta += 0x18, pObjState++) {
                    unsigned int uKind = (pObjState->wKind_state & 0xff08) >> 8;
                    if (uKind == 4 || nFlags == 0) {
                        bPlace = 1;
                        switch (uKind) {
                        case 2:
                            pSlot->pos.xy.nWorld_x = nOriginX + *(long *)((char *)pActorDelta + 4);
                            pSlot->pos.xy.nWorld_y = nOriginY + *(long *)((char *)pActorDelta + 8);
                            pSlot->orientation.yaw = *(short *)((char *)pActorDelta + 12);
                            pObjState->wKind_state = 0x300;
                            pObjState->wKind_state |= RND(3);
                            if (RND2(2))
                                pObjState->wKind_state |= 4;
                            break;
                        case 3:
                        case 4:
                            pSlot->pos.xy.nWorld_x = nOriginX + pObjState->pose.nWorld_x_offset;
                            pSlot->pos.xy.nWorld_y = nOriginY + pObjState->pose.nWorld_y_offset;
                            pSlot->orientation.yaw = pObjState->pose.nFacing;
                            break;
                        default:
                            bPlace = 0;
                            break;
                        }
                        if (bPlace) {
                            pSlot->shapeId = g_nProximityTableCount;
                            pSlot->pos.nWorld_z = 0;
                            pSlot->orientation.pitch = pSlot->orientation.roll = 0;
                            pAux = pSlot->state.encounterAux;
                            k1 = 0;
                            while (k1 < 10) {
                                *(unsigned char *)pAux = 0xff;
                                k1++;
                                pAux = (EncounterActorAux *)((unsigned char *)pAux + 1);
                            }
                            pSlot->state.encounterAux->nRecord_idx = g_nEncounter_record_count;
                            pSlot->state.encounterAux->nSlot_idx = j;
                            pSlot->state.encounterAux->nEncounter_idx = nEncIdx * 7 + j;
                            for (k2 = 0; k2 < 4; k2++) {
                                *(long *)((char *)pActorDelta + k2 * 4 + 14) += nOriginX;
                                *(long *)((char *)pActorDelta + k2 * 4 + 30) += nOriginY;
                            }
                            if (*pActorDelta != 0) {
                                for (k3 = 0; k3 < 4; k3++) {
                                    if (g_pZoneShapeIndex[k3] == *pActorDelta)
                                        break;
                                }
                                if (k3 == 4) {
                                    for (k4 = 0; k4 < (int)nShapeCount; k4++) {
                                        if (aShapeIds[k4] == *pActorDelta)
                                            break;
                                    }
                                    if (k4 == (int)nShapeCount && (int)nShapeCount < 1) {
                                        aShapeIds[nShapeCount] = *pActorDelta;
                                        nShapeCount++;
                                    }
                                }
                            }
                            g_nFixed_object_count++;
                            pSlot++;
                        }
                    }
                    j++;
                }
                g_nEncounter_record_count++;
            }
        }
    }

    for (j = 4; j >= 4; j--) {
        if (*(short *)&g_pZoneShapeIndex[j] != -1) {
            combat_actor_release_anim_images(g_pZoneShapeIndex[j]);
        }
    }
    for (j = 0; j < 1; j++) {
        if (j < (int)nShapeCount) {
            g_pZoneShapeIndex[j + 4] = aShapeIds[j];
            combat_actor_bnames_load_cached(aShapeIds[j], 0);
        } else {
            g_pZoneShapeIndex[j + 4] = 0xffff;
        }
    }
}

void far rgnenc_release_anim_images_slot4(void) {
    int i;

    for (i = 4; i >= 4; i--) {
        if (g_pZoneShapeIndex[i] != 0xffff) {
            combat_actor_release_anim_images(g_pZoneShapeIndex[i]);
            g_pZoneShapeIndex[i] = 0xffff;
        }
    }
    return;
}

void far rgnenc_zone_rectr_save_objects(void) {
    int zone_rec;
    EncounterObjectState *pState_w;
    WorldObject far *pObj;
    long dx;
    long dy;
    EncounterObjectState empty1;
    EncounterObjectState empty3;
    EncounterObjectState table[35];
    EncounterObjectState *p;
    int i;
    unsigned int kind;

    zone_rec = g_apCombat_zone_actor_lists[0]->bRef_pair_index * 0x23;
    pState_w = g_pEncounterObjectState;
    pObj = g_pFixed_object_entries;
    dx = (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_x * 0xfa00;
    dy = (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_y * 0xfa00;
    for (i = 0; i < g_nFixed_object_count; i++, pObj++) {
        p = g_pEncounterObjectState + pObj->state.encounterAux->nEncounter_idx;
        if (((p->wKind_state & 0xff08) >> 8) == 4) {
            p->pose.nWorld_x_offset = pObj->pos.xy.nWorld_x - dx;
            p->pose.nWorld_y_offset = pObj->pos.xy.nWorld_y - dy;
            p->pose.nFacing = pObj->orientation.yaw;
        }
    }
    empty1.pose.nWorld_x_offset = empty1.pose.nWorld_y_offset = 0;
    empty1.pose.nFacing = 0;
    empty1.wKind_state = 0x100;
    empty3.pose.nWorld_x_offset = empty3.pose.nWorld_y_offset = 0;
    empty3.pose.nFacing = 0;
    empty3.wKind_state = 0x200;
    p = table;
    for (i = 0; i < 0x23; i++, pState_w++, p++) {
        kind = (pState_w->wKind_state & 0xff08) >> 8;
        if (kind == 3)
            *p = empty3;
        else if (kind == 4)
            *p = *pState_w;
        else
            *p = empty1;
    }
    g_wLastTempWriteRecordKind = 1;
    gstate_temp_file_write_at((unsigned char far *)table, (unsigned long)(unsigned)GAM_ENC_OBJ_STATE(zone_rec),
                              0x1a4);
}

void far rgnenc_persist_zone_snapshot(void) {
    int record_base;
    WorldObject far *pCurEntry;
    long party_x_off;
    long party_y_off;
    int nFixedIdx;
    EncounterObjectState *pState;
    unsigned int kind;

    record_base = g_apCombat_zone_actor_lists[0]->bRef_pair_index * 0x23;
    pCurEntry = g_pFixed_object_entries;
    party_x_off = (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_x * 0xfa00;
    party_y_off = (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_y * 0xfa00;
    for (nFixedIdx = 0; nFixedIdx < g_nFixed_object_count; nFixedIdx++, pCurEntry++) {
        pState = g_pEncounterObjectState + pCurEntry->state.encounterAux->nEncounter_idx;
        kind = (pState->wKind_state & 0xff08) >> 8;
        if (kind == 3 || kind == 4) {
            pState->pose.nWorld_x_offset = pCurEntry->pos.xy.nWorld_x - party_x_off;
            pState->pose.nWorld_y_offset = pCurEntry->pos.xy.nWorld_y - party_y_off;
            pState->pose.nFacing = pCurEntry->orientation.yaw;
        }
    }
    g_wLastTempWriteRecordKind = 1;
    gstate_temp_file_write_at((unsigned char far *)g_pEncounterObjectState,
                              (unsigned long)(unsigned)GAM_ENC_OBJ_STATE(record_base), 0x1a4);
    g_nCombatTempZoneEncounterCount = g_nEncounter_record_count;
    g_bCombatTempZoneRefPair = g_apCombat_zone_actor_lists[0]->bRef_pair_index;
}

int far rgnenc_persist_actor_placed(long record_id, int slot_index,
                                    EncounterObjectState *src_partial) {
    int nRecordIdx;
    int nFileIdx;
    EncounterObjectState record;

    for (nRecordIdx = 0; nRecordIdx < g_nCombatTempZoneEncounterCount; nRecordIdx++) {
        if (g_anEncounterRecordIds[nRecordIdx] == record_id) {
            nFileIdx = (unsigned int)g_bCombatTempZoneRefPair * 0x23 + nRecordIdx * 7 + slot_index;
            if (g_game_mode == 2)
                gstate_temp_file_read_at((unsigned char far *)&record,
                                         (unsigned long)(unsigned)GAM_ENC_OBJ_STATE(nFileIdx), 0xc);
            else
                record.pose = src_partial->pose;
            record.wKind_state = 0x400;
            g_wLastTempWriteRecordKind = 1;
            gstate_temp_file_write_at((unsigned char far *)&record,
                                      (unsigned long)(unsigned)GAM_ENC_OBJ_STATE(nFileIdx), 0xc);
            return 1;
        }
    }
    return 0;
}

int far rgnenc_persist_actor_removed(long record_id, int slot_index) {
    int nRecordIdx;
    int nFileIdx;
    EncounterObjectState removalRecord;

    for (nRecordIdx = 0; nRecordIdx < g_nCombatTempZoneEncounterCount; nRecordIdx++) {
        if (g_anEncounterRecordIds[nRecordIdx] == record_id) {
            nFileIdx = (unsigned int)g_bCombatTempZoneRefPair * 0x23 + nRecordIdx * 7 + slot_index;
            removalRecord.pose.nWorld_x_offset = removalRecord.pose.nWorld_y_offset = 0;
            removalRecord.pose.nFacing = 0;
            removalRecord.wKind_state = 0x100;
            g_wLastTempWriteRecordKind = 1;
            gstate_temp_file_write_at((unsigned char far *)&removalRecord,
                                      (unsigned long)(unsigned)GAM_ENC_OBJ_STATE(nFileIdx), 0xc);
            return 1;
        }
    }
    return 0;
}

void far rgnenc_reset_and_save(void) {
    int record_base;
    WorldObject far *pCurEntry;
    int nFixedIdx;
    EncounterObjectState *pState;

    record_base = g_apCombat_zone_actor_lists[0]->bRef_pair_index * 0x23;
    pCurEntry = g_pFixed_object_entries;
    for (nFixedIdx = 0; nFixedIdx < g_nFixed_object_count; nFixedIdx++, pCurEntry++) {
        pState = g_pEncounterObjectState + pCurEntry->state.encounterAux->nEncounter_idx;
        if ((pState->wKind_state & 0xff08) >> 8 == 3) {
            pState->pose.nWorld_x_offset = pState->pose.nWorld_y_offset = 0;
            pState->pose.nFacing = 0;
            pState->wKind_state = 0x200;
        }
    }
    g_wLastTempWriteRecordKind = 1;
    gstate_temp_file_write_at((unsigned char far *)g_pEncounterObjectState,
                              (unsigned long)(unsigned)GAM_ENC_OBJ_STATE(record_base), 0x1a4);
    rgnenc_load_encounter_actors();
}

void far rgnenc_mark_defended(unsigned long filter_encounter_id) {
    int i, j, base;
    unsigned long enc_id;
    unsigned int kind_hi;
    int v;
    short actor_ids[7];
    CombatActorInner inner;

    for (i = 0; i < g_nEncounter_record_count; i++) {
        enc_id = g_anEncounterRecordIds[i];
        if (filter_encounter_id != 0 && filter_encounter_id != enc_id)
            continue;

        hotspotevt_enc_fought_set(enc_id);

        base = i * 7;
        for (j = 0; j < 7; j++) {
            kind_hi = (g_pEncounterObjectState[base + j].wKind_state & 0xff08) >> 8;
            if (kind_hi == 3)
                g_pEncounterObjectState[base + j].wKind_state = 0x400;
        }

        gstate_temp_file_read_at((unsigned char far *)actor_ids, GAM_ENC_ROSTER(enc_id), 0xe);

        for (j = 0; j < 7; j++) {
            if (actor_ids[j] == -1)
                continue;
            gstate_temp_file_read_at((unsigned char far *)&inner, GAM_COMBAT_ACTOR_INNER((long)actor_ids[j]),
                                     0x16);
            /* The flags byte is read through (int)(signed char)
               so the compiler sign-extends it (MOV AL;CWDE) and TESTs
               the word, rather than folding to a byte-ptr TEST. The
               result is never used beyond the mask; v is a scratch.
               See rgnenc_load_encounter_actors for the same idiom. */
            if ((v = (int)(signed char)inner.flags) & CAF_DEAD)
                continue;
            inner.flags |= CAF_DEAD;
            g_wLastTempWriteRecordKind = 3;
            gstate_temp_file_write_at((unsigned char far *)&inner,
                                      GAM_COMBAT_ACTOR_INNER((long)actor_ids[j]), 0x16);
        }
    }
}

void far rgnenc_complete_consume(unsigned long encounter_id) {
    int hit_count;
    int bSearching;
    unsigned short saved_match_idx;
    ZoneHotspot *sub_entry;
    int key_index;

    hit_count = 0;
    bSearching = 1;
    for (key_index = 0; bSearching && key_index < g_nEncounter_record_count; key_index++) {
        if (g_anEncounterRecordIds[key_index] == encounter_id) {
            sub_entry = hotspotevt_next_entry_19byte(1);
            while (bSearching && sub_entry != (ZoneHotspot *)0) {
                if (sub_entry->wKind == 1 || sub_entry->wKind == 7) {
                    if (hit_count == key_index) {
                        saved_match_idx = g_wHotspotMatchIdx;
                        g_wHotspotMatchIdx = g_wHotspotIterCursor - 1;
                        hotspotevt_done_clear();
                        hotspotevt_scout_tried_clear();
                        hotspotevt_scouted_clear();
                        g_wHotspotMatchIdx = saved_match_idx;
                        hotspotevt_enc_fought_clear(encounter_id);
                        combatenc_chap_load_party_grn((int)encounter_id);
                        bSearching = 0;
                    } else {
                        hit_count++;
                    }
                }
                sub_entry = hotspotevt_next_entry_19byte(2);
            }
        }
    }
}

void far rgnenc_render_object(WorldObject far *entry, int bAnimTick) {
    int record_idx;
    int actor_idx;
    int state_idx;
    int dx;
    int dy;
    unsigned char animFrame;
    unsigned char animToggle;
    char entityKind;
    ImageRecord **sprite_table;
    EncounterObjectState *pState;
    unsigned char spriteDir;
    int i;
    unsigned char *state_bytes;
    short *pRecordDelta;
    ImageRecord **saved_table;

    record_idx = *(int *)(entry->state.stateBits + 2);
    actor_idx = *(int *)(entry->state.stateBits + 4);
    state_idx = *(int *)(entry->state.stateBits + 6);
    pState = g_pEncounterObjectState + state_idx;
    state_bytes = (unsigned char *)entry->state.stateBits;
    animFrame = (unsigned char)pState->wKind_state & 3;
    animToggle = (unsigned char)pState->wKind_state & 4;
    entityKind = (char)((pState->wKind_state & 0xff08) >> 8);
    if (entityKind != 3 && entityKind != 4)
        return;
    i = 0;
    do {
        *state_bytes = 0xff;
        i++;
        state_bytes++;
    } while (i < 10);

    g_nActorSpriteFlip = 0;
    dx = g_world_camera->base.pos.xy.nWorld_x - entry->pos.xy.nWorld_x;
    dy = g_world_camera->base.pos.xy.nWorld_y - entry->pos.xy.nWorld_y;
    spriteDir =
        (unsigned char)(~((r3d_tbl_atan2(dx, dy) - 0x4000) - entry->orientation.yaw) + 0x1000U >>
                        0xd);
    if (entityKind == 3) {
        switch (spriteDir) {
        case 1:
            spriteDir = 3;
            break;
        case 2:
            spriteDir = 6;
            break;
        case 3:
            spriteDir = 9;
            break;
        case 4:
            spriteDir = 0xc;
            break;
        case 5:
            g_nActorSpriteFlip = 2;
            spriteDir = 9;
            break;
        case 6:
            g_nActorSpriteFlip = 2;
            break;
        case 7:
            g_nActorSpriteFlip = 2;
            spriteDir = 3;
            break;
        }
        if (bAnimTick != 0) {
            if (animToggle != 0) {
                if (animFrame < 2) {
                    animFrame++;
                } else {
                    animToggle = 0;
                    animFrame--;
                }
            } else {
                if (animFrame != 0) {
                    animFrame--;
                } else {
                    animToggle = 1;
                    animFrame++;
                }
            }
            pState->wKind_state = (unsigned char)entityKind << 8;
            pState->wKind_state |= animFrame;
            if (animToggle != 0)
                pState->wKind_state |= 4;
        }
        *(char *)entry->state.stateBits = spriteDir + animFrame;
    } else {
        switch ((int)(unsigned)spriteDir >> 1) {
        case 0:
            spriteDir = 3;
            break;
        case 1:
            spriteDir = 7;
            break;
        case 2:
            spriteDir = 0xb;
            break;
        case 3:
            g_nActorSpriteFlip = 2;
            spriteDir = 7;
            break;
        }
        *(unsigned char *)(entry->state.stateBits + 1) = spriteDir;
    }
    pRecordDelta = &g_pEncounterRecordTemplates[record_idx].pActors[actor_idx].nPaged_record_delta;
    sprite_table = combat_actor_rsrc_cache_val(*pRecordDelta, 0);
    if (sprite_table != 0) {
        saved_table = worldrender_table_swap(0, sprite_table);
        entry->shapeId = entry->shapeId + *pRecordDelta;
        actorrender_entity(entry);
        entry->shapeId = entry->shapeId - *pRecordDelta;
        worldrender_table_swap(0, saved_table);
    }
    g_nActorSpriteFlip = 0;
    *(int *)(entry->state.stateBits + 2) = record_idx;
    *(int *)(entry->state.stateBits + 4) = actor_idx;
    *(int *)(entry->state.stateBits + 6) = state_idx;
}

void far rgnenc_corpse_tbl_iterate_22byte(void) {
    WorldObject far *slot;
    int nRecord_idx;
    int nSlot_idx;
    int nEncounter_idx;
    int i;
    int facing_delta;
    int out_target;
    int nTemplate_off;
    EncounterObjectState *pState;
    int out_dir;
    WorldPos pos_buf;
    char *pActorPoly;
    int vertex_count;

    slot = g_pFixed_object_entries;
    for (i = 0; i < g_nFixed_object_count; i++, slot++) {
        nRecord_idx = slot->state.encounterAux->nRecord_idx;
        nSlot_idx = slot->state.encounterAux->nSlot_idx;
        nEncounter_idx = slot->state.encounterAux->nEncounter_idx;

        nTemplate_off = (int)(g_pEncounterRecordTemplates + nRecord_idx);
        pActorPoly = (char *)nTemplate_off + nSlot_idx * 48 + 1;

        pState = g_pEncounterObjectState + nEncounter_idx;

        if ((pState->wKind_state & 0xff08) >> 8 == 3) {

            switch (*(int *)(pActorPoly + 2)) {
            case 1:
                vertex_count = 2;
                facing_delta = R3D_UDEG(180);
                break;
            case 2:
                vertex_count = 4;
                facing_delta = R3D_UDEG(270);
                break;
            case 3:
                vertex_count = 4;
                facing_delta = R3D_DEG(90);
                break;
            }

            switch (*(int *)(pActorPoly + 2)) {
            case 1:
            case 2:
            case 3:
                pos_buf = *(WorldPos far *)&slot->pos.xy.nWorld_x;
                worldmove_crossing_apply_offset(&pos_buf, slot->orientation.yaw, 0x190);
                *(WorldPos far *)&slot->pos.xy.nWorld_x = pos_buf;
                {
                    int dx;
                    for (dx = 0; dx < vertex_count; dx++) {
                        if (*(long *)(pActorPoly + 0xe + dx * 4) == pos_buf.xy.nWorld_x &&
                            *(long *)(pActorPoly + 0x1e + dx * 4) == pos_buf.xy.nWorld_y) {
                            slot->orientation.yaw += (short)facing_delta;
                            break;
                        }
                    }
                }
                continue;
            case 4:
                pos_buf = *(WorldPos far *)&slot->pos.xy.nWorld_x;
                if (worldmove_crossing_check_8dir(&pos_buf, slot->orientation.yaw, 0x190L, 1,
                                                  &out_dir, &out_target)) {
                    int dx;
                    *(WorldPos far *)&slot->pos.xy.nWorld_x = pos_buf;
                    for (dx = 0; dx < 2; dx++) {
                        if (*(long *)(pActorPoly + 0xe + dx * 4) == pos_buf.xy.nWorld_x &&
                            *(long *)(pActorPoly + 0x1e + dx * 4) == pos_buf.xy.nWorld_y) {
                            slot->orientation.yaw =
                                (short)((unsigned)slot->orientation.yaw + R3D_UDEG(180));
                            break;
                        }
                    }
                    if (dx == 2) {
                        if (out_dir == 2 || out_dir == 3) {
                            slot->orientation.yaw = (short)out_target;
                        }
                    }
                } else {
                    slot->orientation.yaw =
                        (short)((unsigned)slot->orientation.yaw + R3D_UDEG(180));
                }
                continue;
            }
        }
    }
}

int far rgnenc_slot_actor_kind_eq_placed(WorldObject far *pSlot) {
    short idx = pSlot->state.encounterAux->nEncounter_idx;
    short state = (g_pEncounterObjectState[idx].wKind_state & 0xff08) >> 8;
    return state == 3;
}

void far rgnenc_world_objects_reset_spawn(void) {
    g_nVisible_entry_count = 0;
    actorspawn_for_location_by_time((unsigned)g_gameState.nZoneId);
}

int far rgnenc_visible_pool_append_spawn(unsigned char far *pEntry) {
    WorldObject far *cursor;

    if (g_nVisible_entry_count < 0x5d) {
        if (g_gameState.nZoneId != 7 || *(int far *)(pEntry + 2) != 0xdd ||
            g_gameState.nChapter == 7) {
            cursor = (WorldObject far *)g_pVisible_entry_pool + g_nVisible_entry_count;
            g_nVisible_entry_count++;
            cursor->shapeId = *(int far *)(pEntry + 2);
            cursor->pos.xy.nWorld_x = *(long far *)(pEntry + 4);
            cursor->pos.xy.nWorld_y = *(long far *)(pEntry + 8);
            cursor->pos.nWorld_z = 0;
            cursor->orientation.pitch = cursor->orientation.roll = cursor->orientation.yaw = 0;
            cursor->state.stateBits = 0;
            if (g_gameState.nZoneId == 7 && *(int far *)(pEntry + 2) == 0xdd)
                cursor->orientation.yaw = 0xc200;
            return 1;
        }
    }
    return 0;
}

void far rgnenc_vis_pool_remove_matching(unsigned char far *pKey) {
    int i;
    WorldObject far *cursor;
    WorldObject far *last;

    cursor = (WorldObject far *)g_pVisible_entry_pool;
    if (*pKey != g_gameState.nZoneId)
        return;
    for (i = 0; i < g_nVisible_entry_count; i++, cursor++) {
        if (cursor->shapeId == *(int far *)(pKey + 2) &&
            cursor->pos.xy.nWorld_x == *(long far *)(pKey + 4) &&
            cursor->pos.xy.nWorld_y == *(long far *)(pKey + 8))
            break;
    }
    if (i < g_nVisible_entry_count) {
        g_nVisible_entry_count--;
        last = (WorldObject far *)g_pVisible_entry_pool + g_nVisible_entry_count;
        cursor->shapeId = last->shapeId;
        cursor->pos = last->pos;
        cursor->orientation = last->orientation;
        cursor->state.stateBits = last->state.stateBits;
    }
}

int far rgnenc_chap_shp_init(void) {
    BakFile *stream;
    int i;
    int j;

    if (g_pChapterShapeIds != (unsigned short *)0) {
        return 0;
    }
    g_pChapterShapeIds = galloc_safe_zcalloc(6);
    stream = bak_fopen("chap_shp.dat", "rb");
    bak_fseek(stream, (unsigned long)((g_gameState.nChapter - 1) * 6), 1);
    bak_fread(g_pChapterShapeIds, 2, 3, stream);
    bak_fclose(stream);
    i = 0;
    do {
        if (g_pChapterShapeIds[i] != -1) {
            j = 0;
            do {
                combat_actor_bnames_load_cached(g_pChapterShapeIds[i], j);
                j = j + 1;
            } while (j < 3);
        }
        i = i + 1;
    } while (i < 3);
    return 1;
}

int far rgnenc_release_sfx_slot_table(void) {
    int i;

    if (g_pChapterShapeIds != (unsigned short *)0x0) {
        for (i = 2; i >= 0; i--) {
            if (g_pChapterShapeIds[i] != 0xffff) {
                combat_actor_release_anim_images(g_pChapterShapeIds[i]);
            }
        }
        galloc_zfree(g_pChapterShapeIds);
        g_pChapterShapeIds = (unsigned short *)0x0;
        return 1;
    }
    return 0;
}

int far rgnenc_global_flag_tbl_contains(unsigned short id) {
    int i;

    i = 0;
    do {
        if (g_pChapterShapeIds[i] == id) {
            return 1;
        }
        i = i + 1;
    } while (i < 3);
    return 0;
}
