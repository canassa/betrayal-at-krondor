#include "globals.h"
#include "structs.h"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/WORLD/ENC/RGNENC.H"

unsigned short g_bWorldCrossing = 0x0000;
unsigned short g_nWorldCrossingKind = 0x0000;
unsigned long g_dwWorldCrossingCoord = 0x00000000UL;

short g_nWorldStepSpeed;
short g_nWorldGridStride;
long g_lWorldTimePerStep;

void worldmove_dat_load(void) {
    BakFile *stream;
    long seek_off;
    int time_raw;

    stream = bak_fopen("movement.dat", "rb");
    if (g_engine_prefs != (EnginePrefs *)0 && g_engine_prefs->step_speed != '\0') {
        bak_fseek(stream, (ulong)(uint)((int)g_engine_prefs->step_speed << 1), 1);
    }
    bak_fread(&g_nWorldStepSpeed, 2, 1, stream);
    if (g_engine_prefs != (EnginePrefs *)0) {
        seek_off = (long)(int)(uint)g_engine_prefs->combat_step_speed;
    } else {
        seek_off = 0;
    }
    seek_off = (seek_off + 3) * 2;
    bak_fseek(stream, seek_off, 0);
    bak_fread(&g_nWorldGridStride, 2, 1, stream);
    if (g_engine_prefs != (EnginePrefs *)0) {
        seek_off = (long)(int)(uint)g_engine_prefs->step_speed;
    } else {
        seek_off = 0;
    }
    seek_off = (seek_off + 6) * 2;
    bak_fseek(stream, seek_off, 0);
    bak_fread(&time_raw, 2, 1, stream);
    bak_fclose(stream);
    g_lWorldTimePerStep = (long)time_raw * 30;
}

void worldmove_combat_zone_snap_pos(void) {
    g_gameState.nLastSeenStepSpeed = g_nWorldStepSpeed;
    g_gameState.nLastSeenGridStride = g_nWorldGridStride;
}

void worldmove_rgn_chap_trans_apply(void) {
    if (g_gameState.nLastSeenStepSpeed != g_nWorldStepSpeed) {
        if (g_nWorldStepSpeed > g_gameState.nLastSeenStepSpeed) {
            worldmove_step_tick_reset();
            if (g_gameState.nWorldStepPending != 0) {
                if (worldmove_try_step_along_axis() == 0) {
                    g_gameState.nWorldStepPending = 0;
                }
            }
            rgnenc_reset_and_save();
        }
        g_gameState.nLastSeenStepSpeed = g_nWorldStepSpeed;
    }
    if (g_gameState.nLastSeenGridStride != g_nWorldGridStride) {
        if (g_nWorldGridStride > g_gameState.nLastSeenGridStride) {
            worldmove_plr_hdg_align_grid();
        }
        g_gameState.nLastSeenGridStride = g_nWorldGridStride;
    }
}

int far worldmove_party_attempt_move(int mode) {
    int out_target;
    unsigned short saved_crossing_kind;
    unsigned long saved_crossing_coord;
    int out_dir;
    WorldPos pos_save;
    short step;
    int result;

    step = g_nWorldStepSpeed;
    saved_crossing_kind = g_nWorldCrossingKind;
    saved_crossing_coord = g_dwWorldCrossingCoord;
    pos_save = g_world_camera->base.pos;

    if (g_game_mode == 2) {
        step = step >> 2;
    }
    g_bWorldCrossing = 1;

    if (g_gameState.nWorldStepPending != 0) {
        result = worldmove_crossing_check_8dir(&g_world_camera->base.pos,
                                               g_world_camera->base.orientation.yaw, (long)step,
                                               mode, &out_dir, &out_target);
    } else {
        result = worldmove_step_free_move(&g_world_camera->base.pos,
                                          g_world_camera->base.orientation.yaw, (long)step, mode);
        out_dir = 0;
    }
    g_bWorldCrossing = 0;

    if (result == 0)
        goto L_fail;

    if (g_full_redraw_needed != 0) {
        g_world_camera->base.pos.nWorld_z = pos_save.nWorld_z;
    } else {
        g_world_camera->base.pos.nWorld_z += g_lZoneDefaultZ;
    }
    czone_resync_on_world_move();
    if (hotspotevt_activate_at_player() != 0) {
        if ((out_dir == 2) || (out_dir == 3)) {
            worldmove_animate_hdg_tgt(out_dir, out_target);
        }
        g_nWorldRenderJitter = RND2(0x10);
        worldmove_step_tick_advance();
        return 1;
    }

    g_world_camera->base.pos = pos_save;
    g_nWorldCrossingKind = saved_crossing_kind;
    g_dwWorldCrossingCoord = saved_crossing_coord;
    czone_resync_on_world_move();
    return 1;

L_fail:
    hotspotevt_flags_clear();
    if (mode == 1) {
        if (worldmove_sweep_alt_headings(&g_world_camera->base.pos,
                                         g_world_camera->base.orientation.yaw, (long)step, mode,
                                         &out_dir, &out_target) != 0) {
            worldmove_apply_turn_step(out_dir);
            worldmove_animate_hdg_tgt(out_dir, out_target);
            return 1;
        }
    }
    audio_play(0x31);
    return 0;
}

void worldmove_apply_turn_step(short direction) {
    worldmove_heading_step(&g_world_camera->base.orientation.yaw, g_nWorldGridStride, direction);
    g_nWorldRenderJitter = RND2(0x10);
}

void worldmove_animate_hdg_tgt(int hdg_step, int hdg_target) {
    while (g_world_camera->base.orientation.yaw != hdg_target) {
        g_nWorldRenderJitter = RND2(0x10);
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        world_render_scene_dispatch(0);
        uiwidget_compass_draw();
        screen_frame_present();
        worldmove_heading_step(&g_world_camera->base.orientation.yaw, g_nWorldGridStride, hdg_step);
    }
}

void worldmove_plr_hdg_align_grid(void) {
    worldmove_align_to_grid_stride((uint *)&g_world_camera->base.orientation.yaw);
}

void worldmove_camera_crossing_apply(void) {
    ProximityScanHit scan_hit_tag;

    if ((char)proximity_scan_list(&scan_hit_tag, &g_world_camera->base.pos.xy,
                                  g_wVisibleEntrySegment, g_pwVisibleEntryOffsets,
                                  g_nVisibleEntryCount) != '\0') {
        g_nWorldCrossingKind = ts_get_shape((scan_hit_tag.pRecord)->wRecord_id)->kind;
        g_dwWorldCrossingCoord = scan_hit_tag.nZ_delta;
        if (g_full_redraw_needed == 0) {
            g_world_camera->base.pos.nWorld_z = g_lZoneDefaultZ + scan_hit_tag.nZ_delta;
        }
    }
    return;
}

int far worldmove_aabb_outcode_rotated(uchar *tile_rect) {
    uchar tile_x;
    uchar tile_y;
    long unused;
    WorldPos2 cornerPos;

    (void)unused;
    czone_get_party_tile_xy(&tile_x, &tile_y);
    czone_world_pos_from_tile(tile_x, tile_y, *tile_rect + 1, tile_rect[1], &cornerPos);
    if (cornerPos.nWorld_y < g_world_camera->base.pos.xy.nWorld_y) {
        return 1;
    } else if (g_world_camera->base.pos.xy.nWorld_x < cornerPos.nWorld_x) {
        return 2;
    } else {
        czone_world_pos_from_tile(tile_x, tile_y, tile_rect[2], tile_rect[3] + 1, &cornerPos);
        if (g_world_camera->base.pos.xy.nWorld_y < cornerPos.nWorld_y) {
            return 4;
        } else {
            return 8;
        }
    }
}

int far worldmove_sweep_alt_headings(WorldPos *pos, int heading, long step, int mode, int *out_dir,
                                     int *out_heading) {
    int iter;
    int max_iters;
    int cw_heading;
    int ccw_heading;
    int cw_hit;
    int ccw_hit;
    uint hit_kind;
    ulong hit_coord;
    int pos_x_mod;
    int pos_y_mod;
    uchar tile_x;
    uchar tile_y;
    uchar sub_x;
    uchar sub_y;
    WorldPos work_pos;
    int blocked_angles[8];
    int n_blocked;
    int i;

    max_iters = 0x4000 / (int)g_nWorldGridStride;
    cw_heading = heading + g_nWorldGridStride;
    ccw_heading = heading - g_nWorldGridStride;
    n_blocked = 0;
    if (mode == 1) {
        if (g_gameState.nWorldStepPending != 0) {

            pos_x_mod = (int)(pos->xy.nWorld_x % 0x640);
            pos_y_mod = (int)(pos->xy.nWorld_y % 0x640);
            if (pos_x_mod == 800) {
                blocked_angles[n_blocked] = 0;
                n_blocked++;

                blocked_angles[n_blocked] = R3D_DEG(180);
                n_blocked++;
            }
            if (pos_y_mod == 800) {
                blocked_angles[n_blocked] = R3D_DEG(-90);
                n_blocked++;
                blocked_angles[n_blocked] = R3D_DEG(90);
                n_blocked++;
            }
            if (pos_x_mod == pos_y_mod) {
                blocked_angles[n_blocked] = R3D_DEG(-45);
                n_blocked++;
                blocked_angles[n_blocked] = R3D_DEG(135);
                n_blocked++;
            }
            if ((pos_x_mod + pos_y_mod == 0x640) || ((pos_x_mod == 0) && (pos_y_mod == 0))) {
                blocked_angles[n_blocked] = R3D_DEG(45);
                n_blocked++;
                blocked_angles[n_blocked] = R3D_DEG(-135);
                n_blocked++;
            }
        }
        for (iter = 0; iter < max_iters; iter++) {
            if (g_gameState.nWorldStepPending != 0) {
                cw_hit = ccw_hit = 0;
                i = 0;
                while (i < n_blocked) {
                    if (blocked_angles[i] == cw_heading) {
                        cw_hit = 1;
                    }
                    if (blocked_angles[i] == ccw_heading) {
                        ccw_hit = 1;
                    }
                    i++;
                }
                if (cw_hit != 0) {
                    work_pos = *pos;
                    if ((pos_x_mod != 800) || (pos_y_mod != 800)) {
                        worldmove_crossing_apply_offset(
                            &work_pos, (int)((unsigned)cw_heading + R3D_DEG(180)), 0x320);
                        tile_x = (uchar)(work_pos.xy.nWorld_x / 64000);
                        tile_y = (uchar)(work_pos.xy.nWorld_y / 64000);
                        sub_x = (uchar)((work_pos.xy.nWorld_x / 0x640) % 0x28);
                        sub_y = (uchar)((work_pos.xy.nWorld_y / 0x640) % 0x28);
                        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x, sub_y, &work_pos.xy);
                    }
                    cw_hit = worldmove_probe_adjacent_cell(&work_pos, cw_heading, &hit_kind,
                                                           (long *)&hit_coord);
                }
                if (ccw_hit != 0) {
                    work_pos = *pos;
                    if ((pos_x_mod != 800) || (pos_y_mod != 800)) {
                        worldmove_crossing_apply_offset(
                            &work_pos, (int)((unsigned)ccw_heading + R3D_DEG(180)), 0x320);
                        tile_x = (uchar)(work_pos.xy.nWorld_x / 64000);
                        tile_y = (uchar)(work_pos.xy.nWorld_y / 64000);
                        sub_x = (uchar)((work_pos.xy.nWorld_x / 0x640) % 0x28);
                        sub_y = (uchar)((work_pos.xy.nWorld_y / 0x640) % 0x28);
                        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x, sub_y, &work_pos.xy);
                    }
                    ccw_hit = worldmove_probe_adjacent_cell(&work_pos, ccw_heading, &hit_kind,
                                                            (long *)&hit_coord);
                }
            } else {
                cw_hit = worldmove_probe_walkable_at(pos, cw_heading, step, &hit_kind,
                                                     (long *)&hit_coord);
                ccw_hit = worldmove_probe_walkable_at(pos, ccw_heading, step, &hit_kind,
                                                      (long *)&hit_coord);
            }
            if (cw_hit != 0) {
                if (ccw_hit != 0) {
                    return 0;
                }
                *out_dir = 2;
                *out_heading = cw_heading;
                return 1;
            }
            if (ccw_hit != 0) {
                *out_dir = 3;
                *out_heading = ccw_heading;
                return 1;
            }
            cw_heading += g_nWorldGridStride;
            ccw_heading -= g_nWorldGridStride;
        }
    }
    return 0;
}

int far worldmove_step_free_move(WorldPos *pos, int heading, long step, int mode) {
    uint kind;
    long coord;

    if (mode == 4) {
        heading = heading + R3D_DEG(-180);
    }
    if (worldmove_probe_walkable_at(pos, heading, step, &kind, &coord) != 0) {
        worldmove_vec2_rotate_add_q14(&pos->xy.nWorld_x, heading, step);
        pos->nWorld_z = coord;
        if (g_bWorldCrossing != 0) {
            g_nWorldCrossingKind = kind;
            g_dwWorldCrossingCoord = coord;
        }
        return 1;
    }
    return 0;
}

int far worldmove_crossing_check_8dir(WorldPos *pos, int heading, long step, int mode, int *out_dir,
                                      int *out_target) {
    int x_in_tile;
    int y_in_tile;
    int probe_heading;
    uint hit_kind;
    uchar tile_x;
    uchar tile_y;
    uchar sub_x;
    uchar sub_y;
    ulong hit_coord;
    WorldPos work_pos;

    probe_heading = heading;
    x_in_tile = (int)(pos->xy.nWorld_x % 0x640);
    y_in_tile = (int)(pos->xy.nWorld_y % 0x640);
    switch (heading) {
    case R3D_DEG(0):
    case R3D_DEG(180):
        if (x_in_tile != 0x320)
            goto bail;
        break;
    case R3D_DEG(90):
    case R3D_DEG(270):
        if (y_in_tile != 0x320)
            goto bail;
        break;
    case R3D_DEG(135):
    case R3D_DEG(315):
        if (x_in_tile != y_in_tile)
            goto bail;
        break;
    case R3D_DEG(45):
    case R3D_DEG(225):
        if (x_in_tile + y_in_tile != 0x640) {
            if (x_in_tile != 0)
                goto bail;
            if (y_in_tile != 0)
                goto bail;
        }
        break;
    default:
        return 0;
    }
    if (mode == 4) {
        probe_heading = probe_heading + R3D_DEG(-180);
    }
    work_pos = *pos;
    if ((x_in_tile != 0x320) || (y_in_tile != 0x320)) {
        worldmove_crossing_apply_offset(&work_pos, probe_heading + R3D_DEG(180), 0x320);
        tile_x = (uchar)(work_pos.xy.nWorld_x / 64000);
        tile_y = (uchar)(work_pos.xy.nWorld_y / 64000);
        sub_x = (uchar)((work_pos.xy.nWorld_x / 0x640) % 0x28);
        sub_y = (uchar)((work_pos.xy.nWorld_y / 0x640) % 0x28);
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x, sub_y, &work_pos.xy);
    }
    if (worldmove_probe_adjacent_cell(&work_pos, probe_heading, &hit_kind, (long *)&hit_coord) == 0)
        goto bail;
    worldmove_crossing_apply_offset(pos, probe_heading, (int)step);
    pos->nWorld_z = hit_coord;
    if ((pos->xy.nWorld_x % 0x640 == 0x320) && (pos->xy.nWorld_y % 0x640 == 0x320)) {
        *out_dir = worldmove_sweep_adjacent_cells(pos, heading, mode, out_target);
    } else {
        *out_dir = 0;
    }
    if (g_bWorldCrossing != 0) {
        g_nWorldCrossingKind = hit_kind;
        g_dwWorldCrossingCoord = hit_coord;
    }
    return 1;
bail:
    return 0;
}

void worldmove_heading_step(short *heading, short step, short direction) {
    if (direction == 3) {
        step = -step;
    }
    *heading += step;
}

int far worldmove_align_to_grid_stride(uint *value) {
    ulong target;
    ulong candidate;
    int steps;
    int i;

    target = (ulong)*value;
    candidate = 0;
    steps = (int)(0x10000L / (long)g_nWorldGridStride) + 1;
    for (i = 0; i < steps; i++) {
        if (candidate == target) {
            return 0;
        }
        if ((long)target < (long)candidate) {
            *value = (uint)candidate;
            if ((long)target < (long)(candidate - (uint)(g_nWorldGridStride >> 1))) {
                *value -= g_nWorldGridStride;
            }
            return 1;
        }
        candidate += (uint)g_nWorldGridStride;
    }
    return 0;
}

void far worldmove_vec2_rotate_add_q14(long *out, int angle, long scale) {
    int a;

    a = angle + R3D_DEG(90);
    *out += scale * r3d_tbl_cos(a) >> 0xe;
    out[1] += scale * r3d_tbl_sin(a) >> 0xe;
}

void far worldmove_crossing_apply_offset(WorldPos *pPos, int wDir, int delta) {

    switch (wDir) {
    case R3D_DEG(315):
    case R3D_DEG(0):
    case R3D_DEG(45):
        pPos->xy.nWorld_y += (long)delta;
        break;
    case R3D_DEG(180):
    case R3D_DEG(225):
    case R3D_DEG(135):
        pPos->xy.nWorld_y -= (long)delta;
        break;
    }

    switch (wDir) {
    case R3D_DEG(225):
    case R3D_DEG(270):
    case R3D_DEG(315):
        pPos->xy.nWorld_x += (long)delta;
        break;
    case R3D_DEG(45):
    case R3D_DEG(90):
    case R3D_DEG(135):
        pPos->xy.nWorld_x -= (long)delta;
        break;
    }
}

int far worldmove_probe_walkable_at(WorldPos *pos, int angle, long scale, uint *out_kind,
                                    long *out_coord) {
    WorldPos probe_pos;
    ProximityScanHit hit;

    probe_pos = *pos;
    worldmove_vec2_rotate_add_q14(&probe_pos.xy.nWorld_x, angle, scale);
    if ((char)proximity_scan_list(&hit, &probe_pos.xy, g_wVisibleEntrySegment,
                                  g_pwVisibleEntryOffsets, g_nVisibleEntryCount) != '\0') {
        *out_kind = ts_get_shape((hit.pRecord)->wRecord_id)->kind;
        *out_coord = hit.nZ_delta;
        switch (*out_kind) {
        case 0:
        case 1:
        case 2:
        case 14:
        case 15:
        case 23:
            return 1;
        }
    }
    return 0;
}

int worldmove_prox_query_at_cell(WorldPos *pos, uint *out_type, long *out_coord) {
    ProximityScanHit hit;

    if ((char)proximity_scan_list(&hit, &pos->xy, g_wVisibleEntrySegment, g_pwVisibleEntryOffsets,
                                  g_nVisibleEntryCount)) {
        *out_type = ts_get_shape((hit.pRecord)->wRecord_id)->kind;
        *out_coord = hit.nZ_delta;
        if ((*out_type == 1) || (*out_type == 2)) {
            return 1;
        }
    }
    return 0;
}

int far worldmove_probe_adjacent_cell(WorldPos *pos, int dir, uint *out_type, long *out_coord) {
    WorldPos local_pos;

    local_pos = *pos;
    worldmove_crossing_apply_offset(&local_pos, dir, 0x640);
    if (worldmove_prox_query_at_cell(&local_pos, out_type, out_coord) != 0) {
        local_pos = *pos;
        switch (dir) {
        case R3D_DEG(315):
            local_pos.xy.nWorld_x += 0x32a;
            local_pos.xy.nWorld_y += 0x316;
            break;
        case R3D_DEG(45):
            local_pos.xy.nWorld_x += -0x32a;
            local_pos.xy.nWorld_y += 0x316;
            break;
        case R3D_DEG(225):
            local_pos.xy.nWorld_x += 0x32a;
            local_pos.xy.nWorld_y += -0x316;
            break;
        case R3D_DEG(135):
            local_pos.xy.nWorld_x += -0x32a;
            local_pos.xy.nWorld_y += -0x316;
            break;
        default:
            return 1;
        }
        if (worldmove_prox_query_at_cell(&local_pos, out_type, out_coord) == 0)
            return 0;
        switch (dir) {
        case R3D_DEG(315):
            local_pos.xy.nWorld_x -= 0x14;
            local_pos.xy.nWorld_y += 0x14;
            break;
        case R3D_DEG(45):
            local_pos.xy.nWorld_x += 0x14;
            local_pos.xy.nWorld_y += 0x14;
            break;
        case R3D_DEG(225):
            local_pos.xy.nWorld_x -= 0x14;
            local_pos.xy.nWorld_y -= 0x14;
            break;
        case R3D_DEG(135):
            local_pos.xy.nWorld_x += 0x14;
            local_pos.xy.nWorld_y -= 0x14;
        }
        return worldmove_prox_query_at_cell(&local_pos, out_type, out_coord);
    }
    return 0;
}

int far worldmove_sweep_adjacent_cells(WorldPos *pos, uint dir, int mode, int *out_result) {
    uint sweep_end;
    int heading_offset;
    uint hit_kind;
    ulong hit_coord;
    int hit_code;
    uint dir_00;
    uint dir_01;

    sweep_end = dir + R3D_DEG(180);
    dir_00 = dir;
    dir_01 = dir;
    heading_offset = 0;
    hit_code = 0;
    if (mode == 4) {
        sweep_end = dir;
        dir_00 = dir_00 + R3D_DEG(180);
        dir_01 = dir_01 + R3D_DEG(180);
        heading_offset = R3D_DEG(180);
    }
    if ((dir >> 0xd) << 0xd == dir) {
        for (; dir_00 != sweep_end; dir_00 = dir_00 + R3D_DEG(45), dir_01 = dir_01 - R3D_DEG(45)) {
            if (worldmove_probe_adjacent_cell(pos, dir_00, &hit_kind, (long *)&hit_coord) != 0) {
                if (hit_code != 0) {
                    return 0;
                }
                *out_result = dir_00 + heading_offset;
                if (dir_00 == dir_01) {
                    hit_code = mode;
                    break;
                }
                hit_code = 2;
            }
            if (worldmove_probe_adjacent_cell(pos, dir_01, &hit_kind, (long *)&hit_coord) != 0) {
                if (hit_code != 0) {
                    return 0;
                }
                *out_result = dir_01 + heading_offset;
                hit_code = 3;
            }
        }
    }
    return hit_code;
}

int worldmove_prox_find_near_pos(WorldPos *pos) {
    long x_off;
    long y_off;
    long out_coord;
    byte mask;
    byte tile_x;
    byte tile_y;
    char sub_x;
    char sub_y;
    uint out_type;
    WorldPos save_buf;

    save_buf = *pos;
    mask = 0xf;
    x_off = pos->xy.nWorld_x % 0x640;
    y_off = pos->xy.nWorld_y % 0x640;
    if (x_off < 800) {
        mask &= 6;
    } else {
        mask &= 9;
    }
    if (y_off < 800) {
        mask &= 0xc;
    } else {
        mask &= 3;
    }
    czone_get_party_tile_xy(&tile_x, &tile_y);
    czone_world_pos_to_grid_xy(&sub_x, &sub_y);

    czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x, sub_y, &pos->xy);
    if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
        pos->nWorld_z = out_coord;
        return 1;
    }
    if (mask == 2) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x - 1, sub_y + 1, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    if ((mask == 1) || (mask == 2)) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x, sub_y + 1, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    if (mask == 1) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x + 1, sub_y + 1, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    if ((mask == 2) || (mask == 4)) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x - 1, sub_y, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    if ((mask == 1) || (mask == 8)) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x + 1, sub_y, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    if (mask == 4) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x - 1, sub_y - 1, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    if ((mask == 4) || (mask == 8)) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x, sub_y - 1, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    if (mask == 8) {
        czone_world_pos_tile_sub_ctr(tile_x, tile_y, sub_x + 1, sub_y - 1, &pos->xy);
        if (worldmove_prox_query_at_cell(pos, &out_type, &out_coord) != 0) {
            pos->nWorld_z = out_coord;
            return 1;
        }
    }
    *pos = save_buf;
    return 0;
}

void worldmove_cross_get_probe_result(ushort *out_kind, ulong *out_coord) {
    if (out_kind != (ushort *)0x0) {
        *out_kind = g_nWorldCrossingKind;
    }
    if (out_coord != (ulong *)0x0) {
        *out_coord = g_dwWorldCrossingCoord;
    }
}

int worldmove_cross_walkable_kind(void) {
    return (g_nWorldCrossingKind == 1 || g_nWorldCrossingKind == 2) ? 1 : 0;
}

void worldmove_step_pending_clear(void) {
    g_gameState.nWorldStepPending = 0;
}

int worldmove_step_once_along_axis(void) {
    if (g_gameState.nWorldStepPending == 0) {
        if (worldmove_try_step_along_axis() == 0) {
            return 0;
        }
        g_gameState.nWorldStepPending = 1;
    }
    return 1;
}

short worldmove_step_pending_get(void) {
    return g_gameState.nWorldStepPending;
}

int worldmove_try_step_along_axis(void) {
    long lSavedZ;

    lSavedZ = g_world_camera->base.pos.nWorld_z;
    if (worldmove_prox_find_near_pos(&g_world_camera->base.pos) != 0) {
        if (g_full_redraw_needed != 0) {
            g_world_camera->base.pos.nWorld_z = lSavedZ;
        } else {
            g_world_camera->base.pos.nWorld_z += g_lZoneDefaultZ;
        }
        czone_resync_on_world_move();
        return 1;
    }
    return 0;
}

void worldmove_step_tick_reset(void) {
    g_gameState.nWorldStepTickCount = 0;
    g_gameState.world_step_tick = 1;
}

ushort worldmove_step_tick_get(void) {
    return g_gameState.world_step_tick;
}

void worldmove_step_tick_advance(void) {
    g_gameState.nWorldStepTickCount = g_gameState.nWorldStepTickCount + 1;
    if ((uint)g_gameState.nWorldStepTickCount == (uint)(0x640 / g_nWorldStepSpeed)) {
        worldmove_step_tick_reset();
    } else {
        g_gameState.world_step_tick = 0;
    }
}

ushort worldmove_step_ticks_per_step(void) {
    return (ushort)(0x640 / g_nWorldStepSpeed);
}
