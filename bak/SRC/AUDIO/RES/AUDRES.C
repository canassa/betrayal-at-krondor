#include <dos.h>
#include "structs.h"
#include "SRC/AUDIO/RES/AUDRES.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/STREAM/CODEC/STREAM.H"

unsigned char far *audres_load_chunk_by_mode(IoFile *file, unsigned int size_lo, unsigned int size_hi, unsigned int *out_size,
                                     unsigned short allocTag) {
    AudFragNode far *cursor;
    unsigned char ssmRecordTag;
    unsigned long sum;
    unsigned int far *chain;
    unsigned char far *buf;
    int stream;
    unsigned int header_size;

    chain = 0;
    buf = 0;

    switch (g_nSfxDriverMode) {
    case 0:
        ssmRecordTag = 0x12;
        break;
    case 1:
    case 5:
        ssmRecordTag = 0x13;
        break;
    case 2:
    case 6:
        ssmRecordTag = 0x00;
        break;
    case 3:
        ssmRecordTag = 0x0c;
        break;
    case 0x7e:
        ssmRecordTag = g_bAudioLooseTag;
        break;
    case 7:
        ssmRecordTag = 0x07;
        break;
    default:
        return 0;
    }

    if ((stream = stream_open(0, file, "r", ((unsigned long)size_hi << 16) | size_lo)) >= 0) {

        if (audres_stream_find_tagged_record(stream, ssmRecordTag) &&
            (chain = (unsigned int far *)audres_load_sorted_chain(stream)) != 0) {

            cursor = (AudFragNode far *)chain;
            sum = 0;
            header_size = 5;
            while (cursor) {
                sum += cursor->wSize;
                header_size += 6;
                cursor = cursor->next;
            }

            if (header_size & 1)
                header_size++;
            header_size = (header_size >= 0x26) ? header_size : 0x26;

            sum += (unsigned int)header_size;

            if ((buf = (unsigned char far *)pool_acquire_buffer(sum + 1, 4)) != 0 &&
                audres_resource_read_fragmented(stream, (AudFragNode far *)chain, buf, header_size,
                                                ssmRecordTag)) {
                audres_release_buffer_chain((AudFragNode far *)chain);
                if (out_size) {
                    *(unsigned long *)out_size = sum;
                }
                stream_close(stream);
                return buf;
            }
        } else {
            g_nAudioBufLastError = 2;
        }
        stream_close(stream);
    }

    audres_release_buffer_chain((AudFragNode far *)chain);
    return 0;
}

void audres_release_buffer_chain(AudFragNode far *head) {
    AudFragNode far *ptr;

    while (head != 0) {
        ptr = head;
        head = head->next;
        release_buffer(ptr, 9);
    }
}

int audres_stream_find_tagged_record(int stream, unsigned char tag) {
    unsigned char tag_byte;
    unsigned char sub_byte;
    unsigned char magic_byte;

    if (stream_read(stream, &magic_byte, 1) != 1)
        return 0;
    if (magic_byte != 0x84)
        return 0;

    if (stream_read(stream, &magic_byte, 1) != 1)
        return 0;

    if (stream_read(stream, &tag_byte, 1) != 1)
        return 0;

    while (tag_byte != tag) {

        if (tag_byte == 0xff || stream_read(stream, &sub_byte, 1) != 1)
            return 0;

        while (sub_byte != 0xff) {
            stream_seek(stream, 5L, 1);
            if (stream_read(stream, &sub_byte, 1) != 1)
                return 0;
        }

        if (stream_read(stream, &tag_byte, 1) != 1)
            return 0;
    }
    return 1;
}

void far *audres_load_sorted_chain(int stream_id) {
    unsigned char flag;
    void far *head;
    void far *node;

    head = 0;
    stream_read(stream_id, (void far *)&flag, 1u);

    while (flag != 0xffu && (node = pool_acquire_buffer(8UL, 9)) != 0) {

        ((AudFragNode far *)node)->next = 0;

        stream_seek(stream_id, 1L, 1);
        stream_read(stream_id, node, 4u);
        stream_read(stream_id, (void far *)&flag, 1u);

        if (!head) {
            head = node;
        } else {
            head = audres_sorted_list_insert((AudFragNode far *)head, (AudFragNode far *)node);
        }
    }

    if (flag != 0xffu) {
        audres_release_buffer_chain(head);
    }
    return head;
}

AudFragNode far *audres_sorted_list_insert(AudFragNode far *head, AudFragNode far *new_node) {
    AudFragNode far *cur;
    AudFragNode far *prev;

    if (head != 0) {
        if (!(head->wKey < new_node->wKey)) {

            new_node->next = head;
            head = new_node;
        } else {
            cur = head;
            prev = head;
            do {
                prev = cur;
                cur = cur->next;
                if (cur == 0)
                    break;
            } while (cur->wKey < new_node->wKey);
            new_node->next = cur;
            prev->next = new_node;
        }
    }
    return head;
}

int audres_resource_read_fragmented(int stream_id, AudFragNode far *fragment_list,
                                    unsigned char far *out_buf, int header_size, int tag) {
    unsigned char far *data_ptr;
    unsigned char far *hdrp;

    hdrp = (unsigned char far *)out_buf;
    data_ptr = (unsigned char far *)out_buf;
    data_ptr += header_size;

    *hdrp++ = 0x84;
    *hdrp++ = 0;
    *hdrp++ = (unsigned char)tag;

    while (fragment_list != 0) {

        hdrp[0] = 0;
        hdrp[1] = 0;
        *(unsigned int far *)(hdrp + 2) = (unsigned)((long)(data_ptr - out_buf) + (long)0xfffe);
        *(unsigned int far *)(hdrp + 4) = fragment_list->wSize;

        stream_seek(stream_id, (unsigned long)(unsigned short)(fragment_list->wKey + 2), 0);

        if (stream_read(stream_id, data_ptr, fragment_list->wSize) != fragment_list->wSize) {
            return 0;
        }

        data_ptr += fragment_list->wSize;

        fragment_list = fragment_list->next;

        hdrp += 6;
    }

    *(unsigned int far *)hdrp = 0xffff;
    return 1;
}
