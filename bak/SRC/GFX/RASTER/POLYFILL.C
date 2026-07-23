#include "globals.h"
#include "SRC/GFX/FONT/FONT.H"
#include "structs.h"
#include "SRC/GFX/RASTER/POLYFILL.H"
#include "SRC/GFX/RASTER/POLYGON.H"

void draw_polygon_textured(int vertex_count, int *verts_x, int *verts_y, int texture) {
    Slot27Fn far *saved;
    Slot27Fn far *src;

    saved = g_renderer_vtable.pfn_fill_spans_dithered_modey;
    g_renderer_vtable.pfn_fill_spans_dithered_modey =
        (Slot27Fn far *)g_renderer_vtable.pfn_fill_world_textured_span_modey;
    g_graphics_context.wTextureIdx = texture;
    draw_polygon(vertex_count, verts_x, verts_y);
    g_renderer_vtable.pfn_fill_spans_dithered_modey = saved;
    return;
}
