/* PACKOVL.C -- Dynamix "RES" resource-archive packer (reconstruction).
 *
 * WHAT THIS IS
 *   A reconstruction of Dynamix's in-house resource packer -- the tool that, at
 *   build time in 1993, wove the loadable driver overlays VMCODE.OVL (per-adapter
 *   video drivers) and SX.OVL (sound & music drivers) out of their individually-
 *   built chunk images.  Written in the era's dialect (Borland C++ 3.1, C89,
 *   real-mode DOS, medium model).
 *
 * USAGE
 *   PACKOVL <specfile> <out.ovl>
 *
 *   <specfile> is a small text "pack spec" (a *.PAK file):
 *       line 1        : the 4-byte root container tag, e.g. "OVL:" or "SSM:"
 *       lines 2..n    : one chunk per line, in emit order:  "TAG: <inputpath>"
 *   Blank lines and lines beginning with ';' are comments and are skipped.
 *
 * THE CONTAINER FORMAT (Dynamix "RES")
 *   A tree of length-prefixed named chunks.  These two archives are exactly two
 *   levels: one root *container* chunk whose body is a flat run of *leaf* chunks.
 *
 *   Chunk header (8 bytes, every chunk):
 *       +0  4  tag        3 printable ASCII chars + ':'  (0x3A)
 *       +4  4  sizefield  UINT32 LE:  size  = sizefield & 0x7FFFFFFF  (body len)
 *                                     isctr = sizefield & 0x80000000  (MSB flag)
 *   The body immediately follows the header; the next sibling starts at
 *   header_offset + 8 + size.  `size` is the BODY length only (no header).
 *   No padding, no alignment, no trailer: chunks butt directly against each
 *   other and the root body ends exactly at EOF, so the root sizefield is
 *       0x80000000 | (total_file_size - 8).
 *
 *   Leaf body (the `size` bytes after a leaf's header):
 *       +0      1       method             compression code (table below)
 *       +1      4       uncompressed_size  UINT32 LE  (= raw input byte count)
 *       +5    size-5    payload            compressed (or raw) bytes
 *   so  size = 5 + payload_len.
 *
 *   method codes:  0x00 raw (verbatim)   0x01 RLE   0x02 LZW   0x03 LH1
 *   Every leaf in both shipped archives uses 0x02 (LZW); that is the only method
 *   PACKOVL emits.  The others are documented here for the format's sake; if a
 *   future archive mixed methods the spec line would need to carry a per-chunk
 *   method, but as it stands method is a constant and is kept out of the spec.
 *
 * INPUT PREPARATION (done INSIDE PACKOVL, per chunk)
 *   - If the input begins with "MZ" or "ZM" it is a linked DOS .EXE load module;
 *     PACKOVL strips the MZ header + relocation table and packs the flat image
 *     (the game loads a headerless flat image -- see mz_image_bounds()).  This is
 *     how the 8 video drivers (linked as .EXE) become their chunk bytes.
 *   - Otherwise the file is packed verbatim.  The 11 sound drivers are headerless
 *     ORG-0 .COM images and the 3 data blobs are raw data files; all are fed as-is.
 *   PACKOVL needs no knowledge of which archive is which -- the MZ signature test
 *   alone decides strip-vs-raw, so one code path packs both archives.
 *
 * MEMORY / MODEL
 *   Medium model (bcc -mm): far code, near data (64 KB DGROUP).  PACKOVL is
 *   STREAMING: it never holds a whole input or output in memory.  It reads input
 *   bytes sequentially and writes payload bytes as they are produced, then
 *   fseek()s back to patch each leaf's stored-size field and finally the root's.
 *   The only large resident structure is the LZW string table (~22 KB near data).
 *   Every file is opened in BINARY mode ("rb"/"wb"): DOS text mode would translate
 *   0x0A<->0x0D0A and treat 0x1A as EOF, instantly corrupting binary chunk data
 *   and the LZW bitstream.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------------- */
/* LZW encoder (method 0x02) -- the Sierra/Dynamix "RES" variant.
 *
 * Dictionary: codes 0..255 are the single-byte literals (implicit, never stored);
 * code 256 is the reserved clear marker (NEVER emitted here); code 257 is the
 * first multi-byte codeword.  The table grows to a hard ceiling of 4096 (12-bit
 * codes) and then FREEZES -- no mid-stream clear is ever emitted.
 *
 * Codes are packed LSB-first into a 32-bit bit accumulator and flushed a byte at
 * a time in ascending file order.  The code width starts at 9 bits and widens
 * 9->10->11->12 as the table fills.  The widening TIMING is the classic
 * off-by-one killer (see the encode loop): widen one slot LATE, when
 * next_code > table_max (NOT ==), because the decoder builds each entry one
 * iteration behind the encoder and must stay in lock-step.
 */

#define TABLE_CEIL 4096 /* hard code ceiling (12-bit); table freezes here   */
#define FIRST_CODE 257  /* codes 0..255 literals, 256 = reserved clear      */
#define HASH_SIZE 5003  /* prime > TABLE_CEIL: open-addressed string table   */

/* Dictionary entry (multi-byte codes 257..4095): a code == prefix code + one
 * suffix byte.  Represent the current match by its code number, never by a
 * growing byte buffer -- extend = look up (prefix, next_byte); a hit advances
 * the prefix code, a miss emits it and inserts a new entry.  This is behaviourally
 * identical to a dict-of-byte-strings because greedy longest match + the
 * prefix-closure of the dictionary force the same code choices. */
static int g_prefix[TABLE_CEIL];           /* prefix code of entry `code`      */
static unsigned char g_suffix[TABLE_CEIL]; /* last byte of entry `code`        */
static int g_hash[HASH_SIZE];              /* (prefix,byte) -> code, -1 = empty */

/* Bit-packing accumulator + the streaming payload sink. */
static unsigned long g_bitbuf; /* MUST be 32-bit: up to a 12-bit code + 7 bits */
static int g_bitcnt;
static FILE *g_out;
static long g_payload; /* bytes written for the current chunk payload   */

static void emit_code(int code, int code_size) {
    g_bitbuf |= (unsigned long)code << g_bitcnt;
    g_bitcnt += code_size;
    while (g_bitcnt >= 8) {
        putc((int)(g_bitbuf & 0xFFU), g_out);
        g_payload++;
        g_bitbuf >>= 8;
        g_bitcnt -= 8;
    }
}

static void flush_bits(void) {
    if (g_bitcnt > 0) { /* pad the final partial byte with zero bits */
        putc((int)(g_bitbuf & 0xFFU), g_out);
        g_payload++;
        g_bitbuf = 0;
        g_bitcnt = 0;
    }
}

/* Open-addressed lookup of (prefix, ch).  Returns the code on a hit; on a miss
 * returns -1 and stores the free slot index in *slot for the caller to fill.
 * The particular hash used does NOT affect which codes are assigned (that is
 * fixed by greedy longest-match + insertion order) -- it only affects speed. */
static int hash_find(int prefix, unsigned char ch, int *slot) {
    long key = ((long)prefix << 8) | ch;
    int h = (int)(key % HASH_SIZE);
    int step = 1 + (int)(key % (HASH_SIZE - 2)); /* nonzero; coprime to prime */
    for (;;) {
        int code = g_hash[h];
        if (code < 0) {
            *slot = h;
            return -1;
        }
        if (g_prefix[code] == prefix && g_suffix[code] == ch)
            return code;
        h += step;
        if (h >= HASH_SIZE)
            h -= HASH_SIZE;
    }
}

/* One input byte from `in`, honouring `*remaining` (the exact packable length).
 * Returns 0..255, or -1 at the requested end.  A short read (EOF before the
 * count is exhausted) also returns -1; the caller has pre-checked the length. */
static int next_byte(FILE *in, long *remaining) {
    int c;
    if (*remaining <= 0)
        return -1;
    c = getc(in);
    if (c == EOF)
        return -1;
    (*remaining)--;
    return c & 0xFF;
}

/* LZW-encode `inlen` bytes read from `in` (already positioned) into g_out.
 * Returns the payload byte count.  Empty input emits nothing. */
static long lzw_encode(FILE *in, long inlen) {
    int code_size = 9;
    int table_max = 512; /* exclusive ceiling for the current width */
    int next_code = FIRST_CODE;
    int table_full = 0;
    long remaining = inlen;
    int prefix, c, i;

    for (i = 0; i < HASH_SIZE; i++)
        g_hash[i] = -1;
    g_bitbuf = 0;
    g_bitcnt = 0;
    g_payload = 0;

    if (inlen <= 0)
        return 0;

    prefix = next_byte(in, &remaining); /* first literal 0..255 */

    while ((c = next_byte(in, &remaining)) != -1) {
        unsigned char ch = (unsigned char)c;
        int slot;
        int hit = hash_find(prefix, ch, &slot);
        if (hit >= 0) {
            prefix = hit; /* extend the current match */
            continue;
        }
        emit_code(prefix, code_size); /* emit the OLD code first... */
        if (!table_full) {
            /* ...THEN add the new string...  the `|| code_size < 12` clause lets
             * a slot equal to table_max be added at the narrower width (the slot
             * that then triggers the widen), and blocks slot 4096 at width 12. */
            if (next_code < table_max || code_size < 12) {
                g_hash[slot] = next_code;
                g_prefix[next_code] = prefix;
                g_suffix[next_code] = ch;
                next_code++;
                /* ...THEN maybe widen -- LATE, at `>` not `==` (decoder lock-step). */
                if (next_code > table_max && code_size < 12) {
                    code_size++;
                    table_max <<= 1;
                }
            } else {
                table_full = 1; /* width 12 AND full: freeze */
            }
        }
        prefix = ch; /* restart match at this byte */
    }
    emit_code(prefix, code_size); /* flush the final pending code */
    flush_bits();
    return g_payload;
}

/* ------------------------------------------------------------------------- */
/* Container writer. */

static void die(const char *msg, const char *arg) {
    /* Errors go to stdout (not stderr): this is a build tool whose console is
     * captured to a log by the driver, so a stdout message is the visible,
     * "fail loudly" record.  Nonzero exit still aborts the MAKE. */
    if (arg)
        printf("PACKOVL: ERROR: %s: %s\n", msg, arg);
    else
        printf("PACKOVL: ERROR: %s\n", msg);
    exit(1);
}

static void put_u32(FILE *f, unsigned long v) /* explicit little-endian */
{
    putc((int)(v & 0xFFU), f);
    putc((int)((v >> 8) & 0xFFU), f);
    putc((int)((v >> 16) & 0xFFU), f);
    putc((int)((v >> 24) & 0xFFU), f);
}

static unsigned int rd_u16(FILE *f, long off) /* little-endian u16 at `off` */
{
    int lo, hi;
    fseek(f, off, SEEK_SET);
    lo = getc(f);
    hi = getc(f);
    return (unsigned int)((lo & 0xFF) | ((hi & 0xFF) << 8));
}

/* Determine the packable byte range [*start, *start+*len) of `in`.  For an MZ/ZM
 * load module: strip the header + relocation table (paragraph-aligned) and trim
 * to the true load-module end; e_cp/e_cblp give the exact byte length so any
 * trailing reloc/padding past it is dropped.  Otherwise: the whole file. */
static void mz_image_bounds(FILE *in, long filelen, long *start, long *len) {
    int b0 = getc(in);
    int b1 = getc(in);
    if ((b0 == 'M' && b1 == 'Z') || (b0 == 'Z' && b1 == 'M')) {
        unsigned int e_cblp = rd_u16(in, 0x02);    /* bytes used in last 512 page */
        unsigned int e_cp = rd_u16(in, 0x04);      /* count of 512-byte pages     */
        unsigned int e_cparhdr = rd_u16(in, 0x08); /* header size in 16-byte paras */
        long header_size = (long)e_cparhdr * 16L;
        long total_size = (long)e_cp * 512L - (e_cblp ? (512L - (long)e_cblp) : 0L);
        *start = header_size;
        *len = total_size - header_size;
    } else {
        *start = 0;
        *len = filelen;
    }
}

/* Pack one leaf chunk (tag + method 0x02 LZW payload) into g_out. */
static void pack_chunk(const char *tag, const char *inpath) {
    FILE *in;
    long filelen, start, inlen, sizefield_pos, payload_len;

    in = fopen(inpath, "rb");
    if (!in)
        die("cannot open input", inpath);

    fseek(in, 0, SEEK_END);
    filelen = ftell(in);
    fseek(in, 0, SEEK_SET);

    mz_image_bounds(in, filelen, &start, &inlen);
    if (inlen < 0 || start < 0 || start + inlen > filelen)
        die("malformed input (bad length/header)", inpath);

    /* leaf header: tag(4) + placeholder sizefield(4) to backpatch */
    fwrite(tag, 1, 4, g_out);
    sizefield_pos = ftell(g_out);
    put_u32(g_out, 0);

    /* leaf body: method byte + uncompressed size + LZW payload */
    putc(0x02, g_out); /* method 0x02 = LZW */
    put_u32(g_out, (unsigned long)inlen);
    fseek(in, start, SEEK_SET);
    payload_len = lzw_encode(in, inlen);
    fclose(in);

    /* backpatch the leaf sizefield (leaf: container bit clear) = 5 + payload */
    fseek(g_out, sizefield_pos, SEEK_SET);
    put_u32(g_out, (unsigned long)(5L + payload_len));
    fseek(g_out, 0, SEEK_END);

    printf("  %.4s  uncmp %6ld  payload %6ld\n", tag, inlen, payload_len);
}

/* Trim leading blanks and trailing whitespace/CR/LF/EOF in place; return first
 * non-blank char.  0x1A (Ctrl-Z) is DOS's soft end-of-file marker: a text tool
 * may append one, and in binary read mode it arrives as data -- treat it as
 * trailing whitespace so a lone-0x1A tail line trims to empty and is skipped. */
static char *trim(char *s) {
    char *p = s;
    char *e;
    while (*p == ' ' || *p == '\t' || *p == 0x1A)
        p++;
    e = p + strlen(p);
    while (e > p &&
           (e[-1] == '\n' || e[-1] == '\r' || e[-1] == 0x1A || e[-1] == ' ' || e[-1] == '\t'))
        *--e = '\0';
    return p;
}

static void build_archive(const char *specpath, const char *outpath) {
    FILE *spec;
    char line[256];
    char root_tag[4];
    int have_root = 0;
    long root_pos, total;

    spec = fopen(specpath, "rb"); /* text spec, but read raw + trim CR/LF */
    if (!spec)
        die("cannot open spec", specpath);
    g_out = fopen(outpath, "wb");
    if (!g_out)
        die("cannot open output", outpath);

    root_pos = 0;
    while (fgets(line, sizeof(line), spec)) {
        char *p = trim(line);
        if (*p == '\0' || *p == ';') /* blank or comment */
            continue;
        if (!have_root) {
            if ((int)strlen(p) < 4)
                die("bad root tag line", p);
            memcpy(root_tag, p, 4);
            fwrite(root_tag, 1, 4, g_out);
            root_pos = ftell(g_out); /* sizefield offset (== 4) */
            put_u32(g_out, 0);       /* placeholder, backpatched at EOF */
            have_root = 1;
        } else {
            /* "TAG: <inputpath>"  -- tag is 4 chars, path is the rest */
            char tag[4];
            char *path;
            if ((int)strlen(p) < 5)
                die("bad chunk line", p);
            memcpy(tag, p, 4);
            path = trim(p + 4);
            if (*path == '\0')
                die("chunk line missing input path", p);
            pack_chunk(tag, path);
        }
    }
    fclose(spec);
    if (!have_root)
        die("empty spec (no root tag)", specpath);

    /* backpatch the root container sizefield = 0x80000000 | (total - 8) */
    fseek(g_out, 0, SEEK_END);
    total = ftell(g_out);
    printf("  root total %ld bytes\n", total);
    fseek(g_out, root_pos, SEEK_SET);
    put_u32(g_out, 0x80000000UL | (unsigned long)(total - 8L));
    if (fclose(g_out) != 0)
        die("write error closing output", outpath);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: PACKOVL <specfile> <out.ovl>\n");
        return 1;
    }
    printf("PACKOVL %s -> %s\n", argv[1], argv[2]);
    build_archive(argv[1], argv[2]);
    printf("PACKOVL: wrote %s\n", argv[2]);
    return 0;
}
