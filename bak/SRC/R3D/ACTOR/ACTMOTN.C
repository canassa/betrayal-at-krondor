#include <mem.h>
#include <stdlib.h>
#include "structs.h"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/SYS/PANICF.H"

short g_nActorKnockbackColorIdx = 0;
short g_nActorSpriteFlip = 0;
unsigned short g_nActorShakeX = 0x0000;
unsigned short g_nActorShakeY = 0x0000;
unsigned short g_bForceOverlay = 0x0000;

void *actormotion_xzmalloc(unsigned int size) {
    void *p;

    p = malloc(size);
    if (p == NULL) {
        panic("malloc failed");
    }
    memset(p, 0, size);
    return p;
}

void actormotion_xzfree(void *ptr) {
    free(ptr);
}

WorldEntity *actormotion_vec_alloc(unsigned short type_tag) {
    WorldEntity *entity;

    entity = actormotion_xzmalloc(0x24);
    entity->base.shapeId = type_tag;
    return entity;
}

unsigned int *actormotion_alloc_24b_bit800(unsigned int tag) {
    unsigned int *rec;

    rec = actormotion_xzmalloc(0x18);
    rec[1] = tag;
    *rec |= 0x800;
    return rec;
}

void actormotion_integrate(WorldEntity *actor) {
    long t;

    actor->base.orientation.pitch += actor->angularVelocity.pitch;
    actor->base.orientation.roll += actor->angularVelocity.roll;
    actor->base.orientation.yaw += actor->angularVelocity.yaw;
    if ((actor->base.orientation.pitch | actor->base.orientation.roll) != 0) {
        t = (long)actor->forwardVelocity * (long)-r3d_tbl_cos(actor->base.orientation.pitch);
        t = (t >> 0xe) * (long)r3d_tbl_sin(actor->base.orientation.yaw);
        actor->base.pos.xy.nWorld_x += (t >> 0xe);
        t = (long)actor->forwardVelocity * (long)r3d_tbl_cos(actor->base.orientation.pitch);
        t = (t >> 0xe) * (long)r3d_tbl_cos(actor->base.orientation.yaw);
        actor->base.pos.xy.nWorld_y += (t >> 0xe);
        actor->base.pos.nWorld_z +=
            ((long)actor->forwardVelocity * (long)r3d_tbl_sin(actor->base.orientation.pitch) >>
             0xe);
    } else if (actor->base.orientation.yaw != 0) {
        actor->base.pos.xy.nWorld_x +=
            ((long)actor->forwardVelocity * (long)-r3d_tbl_sin(actor->base.orientation.yaw) >> 0xe);
        actor->base.pos.xy.nWorld_y +=
            ((long)actor->forwardVelocity * (long)r3d_tbl_cos(actor->base.orientation.yaw) >> 0xe);
    } else {
        actor->base.pos.xy.nWorld_y += (long)actor->forwardVelocity;
    }
    actor->base.pos.xy.nWorld_x += (long)actor->linearVelocity.nX;
    actor->base.pos.xy.nWorld_y += (long)actor->linearVelocity.nY;
    actor->base.pos.nWorld_z += (long)actor->linearVelocity.nZ;
    return;
}

int actormotion_atan2_long(long y, long x) {
    int angle;
    unsigned char yNeg;
    unsigned char xNeg;

    if (yNeg = y < 0) {
        y = -y;
    }
    if (xNeg = x < 0) {
        x = -x;
    }
    if (y == 0) {
        angle = 0x400;
    } else if (x == 0) {
        angle = 0;
    } else if (y == x) {
        angle = 0x200;
    } else if (y < x) {
        angle = 0x400 - r3d_tbl_atan_lookup_raw((int)((y << 9) / x));
    } else {
        angle = r3d_tbl_atan_lookup_raw((int)((x << 9) / y));
    }
    if (yNeg) {
        angle = 0x800 - angle;
    }
    if (xNeg) {
        angle = 0x1000 - angle;
    }
    angle -= 0x400;
    return angle * 0x10;
}

int actormotion_clamp_signed_delta(int a, int b, int max_abs) {
    int delta;

    delta = a - b;
    max_abs = (((delta < 0) ? ((delta == -0x8000) ? 0x7fff : -delta) : delta) > max_abs)
                  ? max_abs
                  : ((delta < 0) ? ((delta == -0x8000) ? 0x7fff : -delta) : delta);
    return (delta >= 0) ? max_abs : 0 - max_abs;
}
