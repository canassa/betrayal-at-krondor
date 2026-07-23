#include "SRC/GAME/GMAIN.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "structs.h"
#include "SRC/R3D/PROJECT/PROJECT.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "r3d.h"

void project_perspective_xy(int x, int depth, int y, int *out_vec3) {
    long tmp;

    out_vec3[1] = 1 << g_active_window->zoom;
    tmp = (long)(y * out_vec3[1]);
    out_vec3[2] = tmp / -depth;
    tmp = (long)(x * out_vec3[2]);
    *out_vec3 = tmp / y;
}

void far project_world_to_screen(int x, int y, int z, int *out_screen_xy, ViewContext *widget) {
    Mat3x3 mtx;
    int in[3];
    int out[3];

    mtx = g_mat3x3ViewRot;
    in[0] = x;
    in[1] = y;
    in[2] = -((int)widget->camera->base.pos.nWorld_z - z);
    r3d_mat3_xform_vec3_wrap(in, &mtx, out);
    if (out[1] < (1 << widget->zoom)) {
        if (out[1] <= 0)
            return;
        if (out[2] <= 0)
            return;
        project_perspective_xy(out[0], out[1], out[2], out);
    }
    *out_screen_xy = g_nViewportCenterX + (int)(((long)out[0] << widget->zoom) / (long)out[1]);
    out_screen_xy[1] = g_nViewportCenterY - (int)(((long)out[2] << widget->zoom) / (long)out[1]);
}

void project_tile_to_screen(int tile_x, int tile_y, int *out_screen) {
    int worldX = tile_x * g_grid_tile_size + (g_grid_tile_size >> 1) - 0x4b0;

    int worldY = tile_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;

    project_world_to_screen(worldX, worldY, 0, out_screen, g_active_window);
}

void project_cursor_to_world_tile(long *out_world_xyz) {
    Mat3x3 mtx;
    int in[3];
    int out[3];
    int cx;
    int cy;

    cx = screen_cursor_get_x() -
         (g_active_window->viewport.x + (g_active_window->viewport.width >> 1));
    cy = (g_active_window->viewport.y + (g_active_window->viewport.height >> 1)) -
         screen_cursor_get_y();
    in[0] = cx;
    in[2] = cy;
    in[1] = 1 << g_active_window->zoom;

    mtx = g_mat3x3ViewRot;
    r3d_matrix3x3_transpose(&mtx);
    r3d_mat3_xform_vec3_wrap(in, &mtx, out);

    *out_world_xyz = (g_render_camera_scratch->base.pos.nWorld_z * (long)out[0]) / (long)-out[2];
    out_world_xyz[1] = (g_render_camera_scratch->base.pos.nWorld_z * (long)out[1]) / (long)-out[2];

    *out_world_xyz -= (*out_world_xyz + 9000) % g_grid_tile_size - (long)(g_grid_tile_size >> 1);
    out_world_xyz[1] -= (out_world_xyz[1] + 100) % g_grid_tile_size - (long)(g_grid_tile_size >> 1);
    out_world_xyz[2] = 0;
    if (*out_world_xyz < -0x41a) {
        *out_world_xyz = -4000;
    }
    if (g_active_window->viewport.y + g_active_window->viewport.height <= screen_cursor_get_y()) {
        out_world_xyz[1] = 0;
    }
}
