#ifndef V102_H
#define V102_H

#ifdef V102CD

extern int g_bNonRotatingMap;

extern int far v102_cdaudio_mscdex_request(void);
extern void far v102_cdaudio_set_track_msf(int track, long msf_bias, long frame_offset);
extern void far v102_cdaudio_play(void);
extern void far v102_cdaudio_stop(void);
extern int far v102_cddrive_detect(char drive_letter);

extern char *g_base_dir;
extern char g_cd_drive_letter;

extern int g_cd_present;

#endif

#endif
