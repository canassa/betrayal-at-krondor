#include <dos.h>
#include "globals.h"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "structs.h"
#include "SRC/R3D/FX/WORLDFX.H"
#include "SRC/SYS/RAND.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/RASTER/PIXEL.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/ACTOR/ACTRENDR.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/R3D/PROJECT/PROJECT.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "gfx169d.h"

unsigned short g_nVfxParticleColor;
VfxRec *g_pVfxVelocityPool;
unsigned short g_wVfxActiveParticleCount;
unsigned short g_nVfxParticleBurstOriginY;
SavedClipRect g_savedClip;

VfxRec *g_pVfxSparkleScratch = {0};
VfxRec *g_pVfxParticlePool = {0};

#define VFX_PARTICLE_COUNT 25
#define VFX_SPARKLE_COUNT 6

void worldfx_sparkle_burst(CombatActor *actor, int color) {
    int scr[3];
    int base_x;
    int base_y;
    int i;

    g_graphics_context.bClip_enabled = 1;

    g_pVfxSparkleScratch = galloc_safe_zcalloc(VFX_SPARKLE_COUNT * sizeof(VfxRec));

    base_x = actor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) - 0x546;

    base_y = actor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;

    for (i = 0; i < VFX_SPARKLE_COUNT; i++) {

        g_pVfxSparkleScratch[i].nW0 = base_x + RND(300);
        g_pVfxSparkleScratch[i].nW1 = base_y + RND(150);

        g_pVfxSparkleScratch[i].nW2 = RND(350);

        project_world_to_screen(g_pVfxSparkleScratch[i].nW0, g_pVfxSparkleScratch[i].nW1,
                                g_pVfxSparkleScratch[i].nW2, scr, g_active_window);
        putpixel(scr[0], scr[1], color);

        if (RND(4) == 0) {
            putpixel(scr[0] - 1, scr[1], color);
            putpixel(scr[0] + 1, scr[1], color);
            putpixel(scr[0], scr[1] - 1, color);
            putpixel(scr[0], scr[1] + 1, color);
        }
    }

    galloc_zfree(g_pVfxSparkleScratch);
    g_pVfxSparkleScratch = 0;
}

void far worldfx_flux_vortex_step_particle(int slot, int base_ang_step) {
    if (g_pVfxParticlePool == 0)
        return;
    if (g_pVfxParticlePool[slot].nW0 <= 0x4b)
        return;

    g_pVfxParticlePool[slot].nW0 -= RNDR(1, 5);

    g_pVfxParticlePool[slot].nW1 += base_ang_step + ((0xfa - g_pVfxParticlePool[slot].nW0) << 4);

    g_pVfxParticlePool[slot].nW2 += 0x14 - RND(0x28);
    if (g_pVfxParticlePool[slot].nW2 > 0x15e)
        g_pVfxParticlePool[slot].nW2 = 0x15e;
    if (g_pVfxParticlePool[slot].nW2 < 0x64)
        g_pVfxParticlePool[slot].nW2 = 0x64;

    g_wVfxActiveParticleCount++;
}

void far worldfx_render_particle_blast(CombatActor *actor, int color) {
    int radius;
    short saved_status;
    int i;

    radius = 1;
    saved_status = actor->inner->status_head;
    actor->inner->status_head = 0x13;
    i = RNDR(10, 24);
    while (i != 0) {
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
        i--;
    }
    actor->inner->status_head = saved_status;
    g_pVfxParticlePool = galloc_safe_zcalloc(VFX_PARTICLE_COUNT * sizeof(VfxRec));
    i = 0;
    do {
        g_pVfxParticlePool[i].nW0 = radius + 0x4b;
        if (i != 0) {

            g_pVfxParticlePool[i].nW1 = RND(4000) + g_pVfxParticlePool[(i - 1)].nW1;
        } else {

            g_pVfxParticlePool[i].nW1 = RND(0x640);
        }
        g_pVfxParticlePool[i].nW2 = 300;
        i++;
    } while (i < VFX_PARTICLE_COUNT);
    g_nVfxParticleColor = color;

    while (radius < 600) {
        radius = radius * 2;
        i = 0;
        do {
            g_pVfxParticlePool[i].nW0 = radius + 0x4b;
            i++;
        } while (i < VFX_PARTICLE_COUNT);
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
    }
    galloc_zfree(g_pVfxParticlePool);
    g_pVfxParticlePool = 0;
}

void worldfx_flux_vortex_play(int color) {
    int i;

    g_nSnowParticleSeedX = 0;
    g_pVfxParticlePool = galloc_safe_zcalloc(VFX_PARTICLE_COUNT * sizeof(VfxRec));

    i = 0;
    while (i < VFX_PARTICLE_COUNT) {
        g_pVfxParticlePool[i].nW0 = RNDR(250, 399);
        if (i != 0) {
            g_pVfxParticlePool[i].nW1 = RND(4000) + g_pVfxParticlePool[(i - 1)].nW1;
        } else {
            g_pVfxParticlePool[i].nW1 = RND(1600);
        }

        g_pVfxParticlePool[i].nW2 = RND(355);
        i++;
    }

    g_nVfxParticleColor = color;
    g_wVfxActiveParticleCount = 1;

    while (g_wVfxActiveParticleCount != 0) {
        g_wVfxActiveParticleCount = 0;
        for (i = 0; i < VFX_PARTICLE_COUNT; i++) {

            worldfx_flux_vortex_step_particle(i, RNDR(1300, 1599));
        }
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
    }

    galloc_zfree(g_pVfxParticlePool);
    g_pVfxParticlePool = 0;
}

void far worldfx_ptcl_overlay_step_back(CombatActor *pActor) {
    int scr[3];
    int scr2[3];
    int base_x;
    int base_y;
    int dx;
    int dy;
    int index;

    if (g_pVfxParticlePool != 0) {
        world_rndr_apply_window_vport();
        base_x = pActor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
        base_y = pActor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
        index = 0;
        do {
            if ((g_pVfxParticlePool[index].nW0 > 0x4b) && (g_pVfxParticlePool[index].nW1 > 0)) {
                dx = (int)(r3d_imul_full32(g_pVfxParticlePool[index].nW0,
                                           r3d_tbl_cos(g_pVfxParticlePool[index].nW1)) >>
                           14);
                dy = (int)(r3d_imul_full32(g_pVfxParticlePool[index].nW0,
                                           r3d_tbl_sin(g_pVfxParticlePool[index].nW1)) >>
                           14);
                project_world_to_screen(base_x + dx, base_y + dy, g_pVfxParticlePool[index].nW2,
                                        scr, g_active_window);
                if (g_pVfxParticlePool[index].nW0 < 200) {
                    if (RND(50) == 0) {
                        project_world_to_screen(base_x, base_y, RNDR(0x96, 0xc7), scr2,
                                                g_active_window);
                        combat_arena_actor_set_anim_pose(pActor, 1);
                        audio_play(4);
                        g_nSnowParticleSeedX = RND2(4) + g_nSnowParticleSeedX + 2;
                        index++;
                        continue;
                    }
                }
                putpixel(scr[0], scr[1], g_nVfxParticleColor);
            }
            index++;
        } while (index < VFX_PARTICLE_COUNT);
    }
}

void worldfx_ptcl_overlay_render_front(CombatActor *pActor) {
    int scr[3];
    int scr2[3];
    int x_base;
    int y_base;
    int i;

    if (g_pVfxParticlePool != 0) {
        world_rndr_apply_window_vport();

        x_base = pActor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) - 0x546;
        y_base = pActor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
        x_base += 0x96;

        for (i = 0; i < VFX_PARTICLE_COUNT; i++) {
            if (g_pVfxParticlePool[i].nW0 > 0x4b && g_pVfxParticlePool[i].nW1 < 0) {
                int cos_shift = (int)(r3d_imul_full32(g_pVfxParticlePool[i].nW0,
                                                      r3d_tbl_cos(g_pVfxParticlePool[i].nW1)) >>
                                      14);
                int sin_shift = (int)(r3d_imul_full32(g_pVfxParticlePool[i].nW0,
                                                      r3d_tbl_sin(g_pVfxParticlePool[i].nW1)) >>
                                      14);

                project_world_to_screen(x_base + cos_shift, y_base + sin_shift,
                                        g_pVfxParticlePool[i].nW2, scr, g_active_window);

                if (g_pVfxParticlePool[i].nW0 < 200 && RND(50) == 0) {
                    project_world_to_screen(x_base, y_base, RNDR(0x96, 0xc7), scr2,
                                            g_active_window);
                    combat_arena_actor_set_anim_pose(pActor, 1);
                    audio_play(4);
                    g_nSnowParticleSeedX = RND2(4) + g_nSnowParticleSeedX + 2;
                    continue;
                }

                putpixel(scr[0], scr[1], g_nVfxParticleColor);
            }
        }
    }
}

void far worldfx_rndr_rand_flash_at_actor(CombatActor *actor) {
    short scr_buf[7];
    WorldObject entry;
    (void)scr_buf;
    entry.shapeId = 4;
    entry.state.stateBits = 0;
    entry.pos.xy.nWorld_x =
        (long)(actor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + (-0x4b0));
    entry.pos.xy.nWorld_y =
        (long)(actor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    entry.pos.nWorld_z = 0;
    entry.orientation.pitch = entry.orientation.roll = entry.orientation.yaw = 0;
    g_nActorSpriteFlip = RND2(2) << 1;
    actorrender_entity(&entry);
}

void far worldfx_render_world_100_frames(void) {
    int i;

    for (i = 0; i < 100; i++) {
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
    }
}

void far worldfx_combat_damage_ptcl_burst(CombatActor *actor, int spread) {
    int x;
    int i;

    g_pVfxParticlePool = galloc_safe_zcalloc(VFX_PARTICLE_COUNT * sizeof(VfxRec));
    g_pVfxVelocityPool = galloc_safe_zcalloc(VFX_PARTICLE_COUNT * sizeof(VfxRec));
    x = actor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
    g_nVfxParticleBurstOriginY =
        actor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
    i = 0;
    do {
        g_pVfxParticlePool[i].nW0 = x;
        g_pVfxParticlePool[i].nW1 = g_nVfxParticleBurstOriginY;
        g_pVfxParticlePool[i].nW2 = 0xfa;
        g_pVfxVelocityPool[i].nW0 = RND(spread) - (spread >> 1);
        g_pVfxVelocityPool[i].nW1 = RND(spread) - (spread >> 1);
        g_pVfxVelocityPool[i].nW2 = RNDR(10, 69);
        i++;
    } while (i < VFX_PARTICLE_COUNT);
    g_wVfxActiveParticleCount = 1;
    while (g_wVfxActiveParticleCount != 0) {
        g_wVfxActiveParticleCount = 0;
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
    }
    galloc_zfree(g_pVfxVelocityPool);
    galloc_zfree(g_pVfxParticlePool);
    g_pVfxParticlePool = 0;
}

void worldfx_render_star(int index) {
    int out[3];
    int color;

    if (g_pVfxParticlePool != 0) {
        project_world_to_screen(g_pVfxParticlePool[index].nW0, g_pVfxParticlePool[index].nW1, 0,
                                out, g_active_window);
        putpixel(out[0], out[1], 0x18);
        if (g_nVfxParticleColor == 0) {
            color = RND2(0x100);
        } else {
            color = g_nVfxParticleColor;
        }
        project_world_to_screen(g_pVfxParticlePool[index].nW0, g_pVfxParticlePool[index].nW1,
                                g_pVfxParticlePool[index].nW2, out, g_active_window);
        putpixel(out[0], out[1], color);
    }
}

void far worldfx_sparkle_update_particles(int y_max, int y_min) {
    int index;

    if (g_pVfxParticlePool != 0) {
        world_rndr_apply_window_vport();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        index = 0;
        do {
            if ((g_pVfxParticlePool[index].nW2 > -1) && (y_min <= g_pVfxParticlePool[index].nW1) &&
                (g_pVfxParticlePool[index].nW1 < y_max)) {
                worldfx_render_star(index);
                g_pVfxParticlePool[index].nW0 += g_pVfxVelocityPool[index].nW0;
                g_pVfxParticlePool[index].nW1 += g_pVfxVelocityPool[index].nW1;
                g_pVfxParticlePool[index].nW2 += g_pVfxVelocityPool[index].nW2;
                g_pVfxVelocityPool[index].nW2 -= 6;
                if (g_pVfxParticlePool[index].nW2 > 0) {
                    g_wVfxActiveParticleCount++;
                } else {
                    if (g_pVfxVelocityPool[index].nW2 > -0x48) {
                        g_pVfxParticlePool[index].nW2 = -1;
                    } else {
                        g_pVfxParticlePool[index].nW2 = 0;
                        g_pVfxVelocityPool[index].nW2 = -(g_pVfxVelocityPool[index].nW2) >> 1;
                    }
                    g_wVfxActiveParticleCount++;
                }
            }
            index++;
        } while (index < VFX_PARTICLE_COUNT);
    }
    return;
}

void far worldfx_sparkle_tick(void) {
    if (g_pVfxParticlePool != 0) {
        worldfx_sparkle_update_particles(32000, g_nVfxParticleBurstOriginY);
    }
}

void far worldfx_sparkle_render(void) {
    if (g_pVfxParticlePool != 0) {
        worldfx_sparkle_update_particles(g_nVfxParticleBurstOriginY, 0);
    }
    return;
}

void worldfx_render_flame_at_actor(CombatActor *actor) {
    int scr[3];
    int z;
    int c1, c2;
    int x_off1, x_off2;
    register int scr_x;
    int scr_y;

    world_rndr_apply_window_vport();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;

    scr_x = actor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
    scr_y = actor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
    z = 0xfa;
    project_world_to_screen(scr_x, scr_y, z, scr, g_active_window);

    scr_x = scr[0];
    scr_y = scr[1];

    g_graphics_context.bGfx_outline_color = 0xaf;

    c1 = 10;
    c2 = c1 * 2;

    x_off1 = 10 - RND(20);
    x_off2 = 3 - RND(6);

    draw_line(scr_x + x_off2, scr_y + RND(3), scr_x + x_off1, scr_y - c1);
    scr_y -= c1;

    while (scr_y > -c1) {
        x_off2 = 10 - RND(20);
        draw_line(scr_x + x_off1, scr_y, scr_x + x_off2, scr_y - c1);

        x_off1 = 10 - RND(20);
        draw_line(scr_x + x_off2, scr_y - c1, scr_x + x_off1, scr_y - c2);

        scr_y -= c2;
    }
}

static int actor_box_verts[8][3] = {
    {-140, 140, 0},    {140, 140, 0},   {140, 140, 400}, {-140, 140, 400},
    {-140, -140, 400}, {-140, -140, 0}, {140, -140, 0},  {140, -140, 400},
};
short g_nVfxTickCountdown = 0;

void worldfx_actor_box_scr_verts(Vec3Short *vertex_buf, CombatActor *actor) {
    int out[3];
    int x_base;
    int tx;
    int y_base;
    int ty;
    int z_base;
    int tz;
    int i;

    world_rndr_apply_window_vport();
    x_base = actor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) - 0x4b0;
    y_base = actor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
    z_base = 0;
    i = 0;
    do {
        tx = x_base + actor_box_verts[i][0];
        ty = y_base + actor_box_verts[i][1];
        tz = z_base + actor_box_verts[i][2];
        project_world_to_screen(tx, ty, tz, out, g_active_window);
        vertex_buf[i].nX = out[0];
        vertex_buf[i].nY = out[1];
        i++;
    } while (i < 8);
}

void worldfx_draw_actor_box_wireframe(CombatActor *actor, int color_idx) {
    Vec3Short v[8];

    worldfx_actor_box_scr_verts(v, actor);
    g_graphics_context.bGfx_outline_color = (char)(color_idx % 7) + 0xd0;
    if (actor->inner->grid_x > 4) {
        draw_line(v[6].nX, v[6].nY, v[1].nX, v[1].nY);
        draw_line(v[2].nX, v[2].nY, v[7].nX, v[7].nY);
    } else {
        draw_line(v[0].nX, v[0].nY, v[5].nX, v[5].nY);
        draw_line(v[3].nX, v[3].nY, v[4].nX, v[4].nY);
    }
    draw_line(v[0].nX, v[0].nY, v[1].nX, v[1].nY);
    draw_line(v[0].nX, v[0].nY, v[3].nX, v[3].nY);
    draw_line(v[2].nX, v[2].nY, v[3].nX, v[3].nY);
    draw_line(v[2].nX, v[2].nY, v[1].nX, v[1].nY);
}

void worldfx_draw_actor_box_wireframe_front(CombatActor *entity, int color_mod) {
    Vec3Short v[8];

    worldfx_actor_box_scr_verts(v, entity);
    g_graphics_context.bGfx_outline_color = (char)(color_mod % 7) + 0xd1;
    if (entity->inner->grid_x <= 4) {
        draw_line(v[6].nX, v[6].nY, v[1].nX, v[1].nY);
        draw_line(v[2].nX, v[2].nY, v[7].nX, v[7].nY);
    } else {
        draw_line(v[0].nX, v[0].nY, v[5].nX, v[5].nY);
        draw_line(v[3].nX, v[3].nY, v[4].nX, v[4].nY);
    }
    draw_line(v[4].nX, v[4].nY, v[5].nX, v[5].nY);
    draw_line(v[4].nX, v[4].nY, v[7].nX, v[7].nY);
    draw_line(v[6].nX, v[6].nY, v[7].nX, v[7].nY);
    draw_line(v[6].nX, v[6].nY, v[5].nX, v[5].nY);
}

void worldfx_state_arm_minus2(void) {
    g_nVfxTickCountdown = -2;
    return;
}

void worldfx_depth_clip_actor_scr_y(CombatActor *actor) {
    int out[3];
    int wx, wy;

    g_savedClip.ymin = g_graphics_context.clip.ymin;
    g_savedClip.ymax = g_graphics_context.clip.ymax;
    g_savedClip.xmax = g_graphics_context.clip.xmax;
    g_savedClip.xmin = g_graphics_context.clip.xmin;
    wx = actor->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
    wy = actor->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
    project_world_to_screen(wx, wy, 0, out, g_active_window);
    world_rndr_apply_window_vport();
    g_graphics_context.clip.ymax = out[1];
    g_nActorShakeY = g_nVfxTickCountdown;
}

void worldfx_clip_rect_restore(void) {
    if (g_nBillboardScrY > g_graphics_context.clip.ymax) {
        g_nVfxTickCountdown = 0;
    } else {
        g_nVfxTickCountdown -= 2;
    }
    g_graphics_context.clip.ymin = g_savedClip.ymin;
    g_graphics_context.clip.ymax = g_savedClip.ymax;
    g_graphics_context.clip.xmax = g_savedClip.xmax;
    g_graphics_context.clip.xmin = g_savedClip.xmin;
    return;
}

void far worldfx_rndr_spr_shadow(short shadow_palette_idx) {
    int x, y, w, h;

    world_rndr_apply_window_vport();
    x = g_nBillboardScrX - 2;
    y = g_nBillboardScrY - 1;
    w = g_nBillboardW + 3;
    h = g_nBillboardH + 2;

    g_polyRasterState.nRemapTableOff = shadow_palette_idx * 0x100 + CURSOR_REMAP_TAB_OFF;
    emsimg_sprite_blit_scaled_paged(g_pBillboardSpriteImg, x, y, g_nActorSpriteFlip, w, h);
    if (g_nActorKnockbackColorIdx != 0) {
        g_polyRasterState.nRemapTableOff = g_nActorKnockbackColorIdx * 0x100 + CURSOR_REMAP_TAB_OFF;
    } else {
        g_polyRasterState.nRemapTableOff = FOG_REMAP_TAB_OFF;
    }
    emsimg_sprite_blit_scaled_paged(g_pBillboardSpriteImg, g_nBillboardScrX, g_nBillboardScrY,
                                    g_nActorSpriteFlip, g_nBillboardW, g_nBillboardH);
}

void far worldfx_draw_path_segment(int grid_x, int grid_y) {
    int scr[3];
    int p2y;
    int p1y;
    int p0y;
    int p2x;
    int p1x;
    int p0x;
    int jitter;
    int dx;
    int dy;
    int shape;
    int wx;
    int wy;

    g_graphics_context.bClip_enabled = 1;
    combatgrid_find_adj_pass_tile(grid_x, grid_y, 4, &dx, &dy);
    if (combatgrid_tile_terrain_field((char)grid_x - (char)dx, (char)grid_y - (char)dy) != 4) {
        shape = 1;
    } else if (combatgrid_tile_terrain_field((char)grid_x + (char)dx, (char)grid_y + (char)dy) !=
               4) {
        shape = 2;
    } else {
        shape = 0;
    }
    wx = grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
    wy = grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
    wx = wx - (g_grid_tile_size >> 1) * dx;
    wy = wy - (g_grid_tile_size >> 1) * dy;
    project_world_to_screen(wx, wy, 0xeb, scr, g_active_window);
    p0y = scr[0];
    p0x = scr[1];
    wx = wx + (g_grid_tile_size >> 1) * dx;
    wy = wy + (g_grid_tile_size >> 1) * dy;
    if (shape == 0) {

        jitter = RND(0x190) - 0xc8;
    } else {
        jitter = 0;
    }
    wy = wy + jitter;
    project_world_to_screen(wx, wy, 0xeb, scr, g_active_window);
    p1y = scr[0];
    p1x = scr[1];
    wx = wx + (g_grid_tile_size >> 1) * dx;
    wy = (wy + (g_grid_tile_size >> 1) * dy) - jitter;
    project_world_to_screen(wx, wy, 0xeb, scr, g_active_window);
    p2y = scr[0];
    p2x = scr[1];
    g_graphics_context.bGfx_outline_color = 0xaf;
    if (shape != 1) {
        draw_line(p0y, p0x, p1y, p1x);
    }
    if (shape != 2) {
        draw_line(p1y, p1x, p2y, p2x);
    }
    return;
}

void worldfx_draw_world_line(int x1, int y1, int x2, int y2) {
    int out[3];
    int sx2, sx1, sy2, sy1;
    int wx, wy;

    g_graphics_context.bClip_enabled = 1;
    wx = x1 * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
    wy = y1 * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
    project_world_to_screen(wx, wy, 0, out, g_active_window);
    sx1 = out[0];
    sy1 = out[1];
    wx = x2 * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
    wy = y2 * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
    project_world_to_screen(wx, wy, 0, out, g_active_window);
    sx2 = out[0];
    sy2 = out[1];
    g_graphics_context.bGfx_outline_color = 0xaf;
    draw_line(sx1, sy1, sx2, sy2);
}

void worldfx_draw_world_line_color(int x1, int y1, int x2, int y2, int color) {
    int out[3];
    int sx2, sx1, sy2, sy1;
    int wx, wy;

    g_graphics_context.bClip_enabled = 1;
    wx = x1 * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0 - (g_grid_tile_size >> 1);
    wy = y1 * g_grid_tile_size + (g_grid_tile_size >> 1) + (g_grid_tile_size >> 1) + 0xc80;
    project_world_to_screen(wx, wy, 0, out, g_active_window);
    sx1 = out[0];
    sy1 = out[1];
    wx = x2 * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0 - (g_grid_tile_size >> 1);
    wy = y2 * g_grid_tile_size + (g_grid_tile_size >> 1) + (g_grid_tile_size >> 1) + 0xc80;
    project_world_to_screen(wx, wy, 0, out, g_active_window);
    sx2 = out[0];
    sy2 = out[1];
    g_graphics_context.bGfx_outline_color = color;
    draw_line(sx1, sy1, sx2, sy2);
}
