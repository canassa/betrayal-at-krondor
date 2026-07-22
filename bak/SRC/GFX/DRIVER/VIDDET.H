#ifndef BAK_VIDDET_H
#define BAK_VIDDET_H

#include "structs.h"

extern int video_shutdown(void);
extern int near video_detect_adapter(void);
extern unsigned char near crtc_probe_data_register(void);

#endif
