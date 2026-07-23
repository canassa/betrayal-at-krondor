#include "structs.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/RES/AUDRESLD.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/AUDIO/RES/AUDLOAD.H"
#include "SRC/AUDIO/ENGINE/AUDITER.H"
#include "SRC/AUDIO/ENGINE/AUDSTOP.H"

BakFile *audio_resource_load_chunk(BakFileRef *file, int chunk_id) {
    long found_offset;
    long buf_size;
    MusicChunkEntry far *entry;
    int i;

    if (chunk_id == 0 || file != g_music_archive || g_music_archive == 0) {
        if (g_music_archive != file && g_music_archive_owned != 0) {
            cached_file_close(g_music_archive);
            g_music_archive = 0;
            g_music_archive_owned = 0;
        }
        if (is_file_cached(file) != 0) {
            g_music_archive = file;
        } else {
            if ((g_music_archive = cached_file_open(file)) == 0)
                goto cleanup;
            g_music_archive_owned = 1;
        }
        audio_stop(0);
        bak_fseek(g_music_archive, 0xcL, 0);
        if (bak_fread(&buf_size, 4, 1, g_music_archive) != 1)
            goto cleanup;
        if (g_pMusicChunkBuf != 0)
            release_buffer(g_pMusicChunkBuf, 10);
        if ((g_pMusicChunkBuf =
                 (MusicChunkHeader far *)pool_acquire_buffer((unsigned long)(buf_size + 4), 10)) == 0)
            goto cleanup;
        if (bak_fread_chunked((unsigned char huge *)&g_pMusicChunkBuf->nMagic, buf_size, 1,
                              g_music_archive) != 1)
            goto cleanup;
        if (g_pMusicChunkBuf->nMagic != 2)
            goto cleanup;
        g_pMusicChunkBuf->pEntries = (MusicChunkEntry far *)(&g_pMusicChunkBuf->bFlag + 1);
    }
    if (chunk_id > 0 && audio_iter(chunk_id) != 0)
        return g_music_archive;

    entry = g_pMusicChunkBuf->pEntries;
    if (chunk_id > 0) {
        for (i = 0; i < g_pMusicChunkBuf->nEntries; i++, entry++) {
            if (entry->nId == chunk_id) {
                found_offset = entry->nOffset;
                break;
            }
        }
        if (bak_fseek(g_music_archive, found_offset + 4, 0) != 0 || found_offset == 0)
            goto cleanup;
        if (music_chunk_load_and_link(g_music_archive, g_pMusicChunkBuf->bFlag) == 0)
            return 0;
    } else {
        for (i = 0; i < g_pMusicChunkBuf->nEntries; i++, entry++) {
            if (bak_fseek(g_music_archive, entry->nOffset + 4, 0) != 0 ||
                music_chunk_load_and_link(g_music_archive, g_pMusicChunkBuf->bFlag) == 0)
                goto cleanup;
        }
    }
    return g_music_archive;

cleanup:
    if (g_music_archive != 0 && g_music_archive_owned != 0)
        cached_file_close(g_music_archive);
    if (g_pMusicChunkBuf != 0)
        release_buffer(g_pMusicChunkBuf, 10);
    audio_stop(0);
    g_music_archive = 0;
    g_pMusicChunkBuf = 0;
    return 0;
}
