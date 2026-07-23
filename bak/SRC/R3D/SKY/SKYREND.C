#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/UI/UIWIDGET.H"
#include "structs.h"
#include "SRC/R3D/SKY/SKYREND.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/VGAFILL.H"
#include "SRC/R3D/SKY/SKY.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/SYS/EMSIMG.H"
#include "r3d.h"

short g_nHorizonScratchW;
unsigned char g_bCurSkyColorR;
unsigned char g_bCurSkyColorG;
unsigned char g_bCurSkyColorB;
unsigned char g_bSkyBandSelectB;
unsigned char g_bSkyBandSelectA;
unsigned short g_wHorizonCamYaw;
unsigned short g_wHorizonCamPitch;
short g_nClipLineX0;
short g_nClipLineY0;
short g_nClipLineX1;
short g_nClipLineY1;
short g_nHorizonRowY;

static unsigned char skyrender_clip_outcode(int x, int y) {
    unsigned char outcode;

    outcode = 0;
    if (x < g_graphics_context.clip.xmin) {
        outcode |= 1;
    } else if (x > g_graphics_context.clip.xmax) {
        outcode |= 2;
    }
    if (y < g_graphics_context.clip.ymin) {
        outcode |= 4;
    } else if (y > g_graphics_context.clip.ymax) {
        outcode |= 8;
    }
    return outcode;
}

static unsigned char skyrender_clip_line_cohen_suth(void) {
    short swapTmp;
    unsigned char outcode1;
    unsigned char outcode0;

    while (1) {
        outcode0 = skyrender_clip_outcode(g_nClipLineX0, g_nClipLineY0);
        outcode1 = skyrender_clip_outcode(g_nClipLineX1, g_nClipLineY1);
        if ((outcode0 & outcode1) != 0) {
            return outcode0 & outcode1;
        }
        if (!(outcode0 | outcode1)) {
            return 0;
        }
        if (!outcode0) {
            outcode0 = outcode1;
            swapTmp = g_nClipLineX0;
            g_nClipLineX0 = g_nClipLineX1;
            g_nClipLineX1 = swapTmp;
            swapTmp = g_nClipLineY0;
            g_nClipLineY0 = g_nClipLineY1;
            g_nClipLineY1 = swapTmp;
        }
        if ((outcode0 & 1) != 0) {
            g_nClipLineY0 = g_nClipLineY0 +
                            (int)(r3d_imul_full32(g_nClipLineY1 - g_nClipLineY0,
                                                  g_graphics_context.clip.xmin - g_nClipLineX0) /
                                  (long)(g_nClipLineX1 - g_nClipLineX0));
            g_nClipLineX0 = g_graphics_context.clip.xmin;
        } else if ((outcode0 & 2) != 0) {
            g_nClipLineY0 = g_nClipLineY0 +
                            (int)(r3d_imul_full32(g_nClipLineY1 - g_nClipLineY0,
                                                  g_graphics_context.clip.xmax - g_nClipLineX0) /
                                  (long)(g_nClipLineX1 - g_nClipLineX0));
            g_nClipLineX0 = g_graphics_context.clip.xmax;
        } else if ((outcode0 & 4) != 0) {
            g_nClipLineX0 = g_nClipLineX0 +
                            (int)(r3d_imul_full32(g_nClipLineX1 - g_nClipLineX0,
                                                  g_graphics_context.clip.ymin - g_nClipLineY0) /
                                  (long)(g_nClipLineY1 - g_nClipLineY0));
            g_nClipLineY0 = g_graphics_context.clip.ymin;
        } else if ((outcode0 & 8) != 0) {
            g_nClipLineX0 = g_nClipLineX0 +
                            (int)(r3d_imul_full32(g_nClipLineX1 - g_nClipLineX0,
                                                  g_graphics_context.clip.ymax - g_nClipLineY0) /
                                  (long)(g_nClipLineY1 - g_nClipLineY0));
            g_nClipLineY0 = g_graphics_context.clip.ymax;
        }
        skyrender_clip_outcode(g_nClipLineX0, g_nClipLineY0);
        skyrender_clip_outcode(g_nClipLineX1, g_nClipLineY1);
    }
}

static void skyrender_horizon_fill_clip_rect(unsigned char reject_mask) {
    if (reject_mask & 1) {
        g_graphics_context.bGfx_fill_color =
            (g_wHorizonCamPitch < R3D_UDEG(180)) ? g_bCurSkyColorG : g_bCurSkyColorR;
    } else if (reject_mask & 2) {
        g_graphics_context.bGfx_fill_color =
            (g_wHorizonCamPitch < R3D_UDEG(180)) ? g_bCurSkyColorR : g_bCurSkyColorG;
    } else if (reject_mask & 4) {
        g_graphics_context.bGfx_fill_color = g_bCurSkyColorG;
    } else if (reject_mask & 8) {
        g_graphics_context.bGfx_fill_color = g_bCurSkyColorR;
    }

    draw_rect_filled(g_graphics_context.clip.xmin, g_graphics_context.clip.ymin,
                     (g_graphics_context.clip.xmax - g_graphics_context.clip.xmin) + 1,
                     (g_graphics_context.clip.ymax - g_graphics_context.clip.ymin) + 1);
    return;
}

static void skyrender_sky_ground_bands(void) {
    short sSaveY0;
    short sSaveY1;
    int iTmp;
    unsigned int uScroll;
    unsigned int uQuad;

    if ((g_game_mode == 2) && (g_wInCombatMode == 0) && (g_engine_prefs->detail_level < 2)) {
        g_bTexturedPolyEnabled = 0;
    } else {
        g_bTexturedPolyEnabled = 1;
    }

    sSaveY0 = g_nClipLineY0;
    sSaveY1 = g_nClipLineY1;

    if (g_game_mode == 1) {
        g_nClipLineY0 -= 0x1b;
    } else {
        g_nClipLineY0 -= 0x1d;
    }

    if (g_nClipLineX0 > g_nClipLineX1) {
        iTmp = g_nClipLineX0;
        g_nClipLineX0 = g_nClipLineX1;
        g_nClipLineX1 = iTmp;
        iTmp = g_nClipLineY0;
        g_nClipLineY0 = g_nClipLineY1;
        g_nClipLineY1 = iTmp;
    }

    g_bSkyBandSelectB = g_bCurSkyColorG;
    g_bSkyBandSelectA = g_bCurSkyColorR;

    if (g_nClipLineY0 > g_nClipLineY1) {
        iTmp = g_nClipLineY0;
        g_nClipLineY0 = g_nClipLineY1;
        g_nClipLineY1 = iTmp;
        iTmp = g_bSkyBandSelectB;
        g_bSkyBandSelectB = g_bSkyBandSelectA;
        g_bSkyBandSelectA = iTmp;
    }

    if (g_nClipLineY0 > g_graphics_context.clip.ymin) {

        if (g_wZoneFlags & 1) {
            g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color =
                g_bZoneSkyColor;
        } else {
            g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color =
                g_bCurSkyColorR;
        }
        vgaplanar_fill_band(g_graphics_context.clip.ymin,
                            g_nClipLineY0 - g_graphics_context.clip.ymin,
                            (char)g_graphics_context.bGfx_outline_color);
        screen_cur_refr_during_long_op();
    }

    g_nHorizonRowY = g_nClipLineY1;
    if (g_nClipLineY1 < g_graphics_context.clip.ymax) {
        if ((g_wZoneFlags & 2) != 0) {
            vgaplanar_fill_band(g_nClipLineY1, (g_graphics_context.clip.ymax - g_nClipLineY1) + 1,
                                (unsigned int)g_bZoneGroundColor);
        } else {
            sky_draw_ground_band();
        }
    }

    g_graphics_context.bClip_enabled = 1;

    if ((g_wZoneFlags & 1) != 0) {
        vgaplanar_fill_band(g_nClipLineY0, g_nClipLineY1 - g_nClipLineY0, (unsigned int)g_bZoneSkyColor);
    } else if (g_engine_prefs->detail_level != 0) {

        uScroll = g_world_camera->base.orientation.yaw >> 6 & 0xff;
        uQuad = -g_world_camera->base.orientation.yaw - 1 >> 0xe & 3;
        emsimg_putsprite_ems_swap((unsigned int *)g_pSkyPanoAssetTable[uQuad], uScroll, g_nClipLineY0);
        screen_cur_refr_during_long_op();
        emsimg_putsprite_ems_swap((unsigned int *)g_pSkyPanoAssetTable[uQuad + 1 & 3], uScroll + 0x100,
                                  g_nClipLineY0);
        screen_cur_refr_during_long_op();
        emsimg_putsprite_ems_swap((unsigned int *)g_pSkyPanoAssetTable[uQuad - 1 & 3], uScroll + 0xff00,
                                  g_nClipLineY0);
        screen_cur_refr_during_long_op();
    } else {
        vgaplanar_clear_column_strip(g_nClipLineY1 * 0x50 - 0x50, g_nClipLineY1 - g_nClipLineY0);
    }

    g_nClipLineY0 = sSaveY0;
    g_nClipLineY1 = sSaveY1;
    return;
}

static void skyrender_compute_horizon_line(void) {
    int yOff;
    short sinYaw;
    int iTmp;
    short sinPitch;
    short cosPitch;

    if ((R3D_DEG(90) < g_wHorizonCamYaw) && (g_wHorizonCamYaw <= R3D_UDEG(270))) {
        g_nHorizonScratchW = g_bCurSkyColorR;
        g_bCurSkyColorR = g_bCurSkyColorG;
        g_bCurSkyColorG = g_nHorizonScratchW;
        g_wHorizonCamYaw += R3D_UDEG(180);
    }
    if ((R3D_DEG(90) < g_wHorizonCamPitch) && (g_wHorizonCamPitch <= R3D_UDEG(270))) {
        g_nHorizonScratchW = g_bCurSkyColorR;
        g_bCurSkyColorR = g_bCurSkyColorG;
        g_bCurSkyColorG = g_nHorizonScratchW;
        g_wHorizonCamYaw += R3D_UDEG(180);
        g_wHorizonCamPitch += R3D_UDEG(180);
    }
    sinYaw = r3d_tbl_sin(g_wHorizonCamYaw);
    iTmp = r3d_tbl_cos(g_wHorizonCamYaw);
    if (iTmp == 0) {
        iTmp = r3d_tbl_cos(0x3fff);
    }
    iTmp = (iTmp < 0) ? -iTmp : iTmp;
    sinPitch = r3d_tbl_sin(g_wHorizonCamPitch);
    cosPitch = r3d_tbl_cos(g_wHorizonCamPitch);
    g_nClipLineX0 = cosPitch >> 6;
    g_nClipLineX1 = -g_nClipLineX0;
    g_nClipLineY0 = sinPitch >> 6;
    g_nClipLineY1 = -g_nClipLineY0;
    g_nHorizonScratchW = ((long)sinYaw << g_nScreenShift) / (long)iTmp;
    iTmp = r3d_imul_full32(g_nHorizonScratchW, g_nClipLineY0) >> 8;
    yOff = r3d_imul_full32(g_nHorizonScratchW, g_nClipLineX1) >> 8;
    g_nClipLineX0 += iTmp;
    g_nClipLineX1 += iTmp;
    g_nClipLineY0 += yOff;
    g_nClipLineY1 += yOff;
    g_nClipLineX0 = g_nViewportCenterX + g_nClipLineX0;
    g_nClipLineX1 = g_nViewportCenterX + g_nClipLineX1;
    g_nClipLineY0 = g_nViewportCenterY - g_nClipLineY0;
    g_nClipLineY1 = g_nViewportCenterY - g_nClipLineY1;
    return;
}

void far skyrender_sky_and_ground(unsigned short sky_r, unsigned short sky_g, unsigned short sky_b, unsigned short cam_yaw,
                                  unsigned short cam_pitch) {
    unsigned char rejectMask;

    g_bCurSkyColorR = sky_r;
    g_bCurSkyColorG = sky_g;
    g_bCurSkyColorB = sky_b;
    g_wHorizonCamYaw = cam_yaw;
    g_wHorizonCamPitch = cam_pitch;
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bClip_enabled = 0;
    skyrender_compute_horizon_line();
    screen_cur_refr_during_long_op();
    rejectMask = skyrender_clip_line_cohen_suth();
    g_nHorizonRowY = g_nClipLineY1;
    if (g_nClipLineY1 != g_nSkyHorizonRowCached) {
        g_nSkyHorizonRowCached = g_nClipLineY1;
        sky_horizon_strips_init(1);
    }
    screen_cur_refr_during_long_op();
    if (rejectMask != 0) {
        skyrender_horizon_fill_clip_rect(rejectMask);
    } else {
        skyrender_sky_ground_bands();
    }
}
