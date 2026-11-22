/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/* Include the real implementation to test the small entropy primitives too.
 * Malformed-input tests use its normal exit(1) error path. */
#include "zstd_decompress.c"

#define CHECK(condition)                                                       \
    do {                                                                       \
        if (!(condition)) {                                                    \
            fprintf(stderr, "Check failed at line %d: %s\n", __LINE__,         \
                    #condition);                                               \
            exit(4);                                                           \
        }                                                                      \
    } while (0)

#if defined(ZDEC_NO_MESSAGE)
#define CORRUPTION_MESSAGE ""
#define DICTIONARY_MESSAGE ""
#else
#define CORRUPTION_MESSAGE "Error: Corruption detected while decompressing"
#define DICTIONARY_MESSAGE "Error: Dictionary corrupted"
#endif

static void decode_input(const u8* src, size_t size)
{
    u8 dst[64];
    memset(dst, 0xa5, sizeof(dst));
    (void)ZSTD_decompress(dst, sizeof(dst), src, size);
}

static void zero_offset(unsigned unused)
{
    /* One sequence: LL=0, OF=1, ML=0. The extra offset bit selects
     * Repeated_Offset1 - 1, which is initially 1 - 1. */
    static const u8 frame[] = {
        0x28,0xb5,0x2f,0xfd,0x20,3,0x3d,0,0,
        0,1,0x54,0,1,0,3
    };
    (void)unused;
    decode_input(frame, sizeof(frame));
}

static void oversized_offset(unsigned code)
{
    u8 frame[] = {
        0x28,0xb5,0x2f,0xfd,0x20,16,0x4d,0,0,
        0,1,0x54,0,0,0,0,0,0x80
    };
    frame[13] = (u8)code;
    decode_input(frame, sizeof(frame));
}

static void invalid_sequence_bits(unsigned length)
{
    u8 frame[] = {
        0x28,0xb5,0x2f,0xfd,0x20,16,0x3d,0,0,
        0,1,0x54,0,1,0,0
    };
    CHECK(length <= 1);
    frame[6] = length ? 0x3d : 0x35;  /* seven- or six-byte block */
    decode_input(frame, sizeof(frame) - 1 + length);
}

static void invalid_entropy_bits(unsigned which)
{
    static const u8 zero = 0;
    u8 dst[8];
    istream_t in = IO_make_istream(&zero, which & 1);
    ostream_t out = IO_make_ostream(dst, sizeof(dst));
    if (which < 2) {
        static const u8 lengths[] = {1, 1};
        HUF_dtable table = {0};
        HUF_init_dtable(&table, lengths, 2);
        (void)HUF_decompress_1stream(&table, &out, &in);
        HUF_free_dtable(&table);
    } else {
        static const i16 frequencies[] = {16, 16};
        FSE_dtable table = {0};
        FSE_init_dtable(&table, frequencies, 2, 5);
        (void)FSE_decompress_interleaved2(&table, &out, &in);
        FSE_free_dtable(&table);
    }
}

#if !defined(ZDEC_NO_DICTIONARY)
static void make_dictionary(u8 dict[44])
{
    static const u8 header[28] = {
        0x37,0xa4,0x30,0xec, 1,0,0,0,
        128,0x10, 0xf0,0x03, 0xf0,0x03, 0xf0,0x03,
        4,0,0,0, 4,0,0,0, 4,0,0,0
    };
    memcpy(dict, header, sizeof(header));
    memset(dict + sizeof(header), 'A', 16);
}

static void invalid_dictionary_offset(unsigned which)
{
    u8 bytes[44];
    dictionary_t* dict = create_dictionary();
    make_dictionary(bytes);
    /* The upper-bound cases are within the whole dictionary allocation, but
     * outside its sixteen-byte content. */
    bytes[16 + 4 * (which % 3)] = which < 3 ? 0 : 17;
    parse_dictionary(dict, bytes, sizeof(bytes));
    free_dictionary(dict);
}
#endif

static void valid_tests(void)
{
    static const u8 raw[] = {
        0x28,0xb5,0x2f,0xfd,0x20,3,0x19,0,0,'A','B','C'
    };
    static const u8 bits[] = {0xff,0xff,0xff,0x7f};
    static const u8 stop_bits[] = {0xff,1};
    u8 dst[8] = {0};
    u64 history[] = {2,4,8};
    sequence_command_t command = {0,3,3};
    sequence_states_t states = {0};
    i64 offset;
    CHECK(ZSTD_decompress(dst, sizeof(dst), raw, sizeof(raw)) == 3);
    CHECK(memcmp(dst, "ABC", 3) == 0);
    CHECK(compute_offset(command, history) == 1);
    CHECK(history[0] == 1 && history[1] == 2 && history[2] == 4);

    CHECK(STREAM_init(stop_bits + 1, 1) == 0);
    CHECK(STREAM_init(stop_bits, sizeof(stop_bits)) == 8);
    offset = 4;
    CHECK(STREAM_read_bits(bits, 8, &offset) == 0xf0 && offset == -4);
    offset = 1;
    CHECK(STREAM_read_bits(bits, 64, &offset) == ((u64)1 << 63) && offset == -63);
    offset = 0;
    CHECK(STREAM_read_bits(bits, 64, &offset) == 0 && offset == -64);
    offset = -1;
    CHECK(STREAM_read_bits(bits, 0, &offset) == 0 && offset == -1);
    offset = -65;
    CHECK(STREAM_read_bits(bits, 1, &offset) == 0 && offset == -66);

    /* Code 31 and all its additional bits must still fit in Offset_Value. */
    FSE_init_dtable_rle(&states.ll_table, 0);
    FSE_init_dtable_rle(&states.of_table, 31);
    FSE_init_dtable_rle(&states.ml_table, 0);
    offset = 31;
    command = decode_sequence(&states, bits, &offset, 1);
    CHECK(command.offset == UINT32_MAX && offset == 0);
    FSE_free_dtable(&states.ll_table);
    FSE_free_dtable(&states.of_table);
    FSE_free_dtable(&states.ml_table);

    {   static const u8 lengths[] = {1,1};
        static const u8 encoded[] = {2};
        HUF_dtable table = {0};
        istream_t in = IO_make_istream(encoded, sizeof(encoded));
        ostream_t out = IO_make_ostream(dst, sizeof(dst));
        HUF_init_dtable(&table, lengths, 2);
        CHECK(HUF_decompress_1stream(&table, &out, &in) == 1 && dst[0] == 0);
        HUF_free_dtable(&table);
    }
    {   static const i16 frequencies[] = {16,16};
        static const u8 encoded[] = {0,4};
        FSE_dtable table = {0};
        istream_t in = IO_make_istream(encoded, sizeof(encoded));
        ostream_t out = IO_make_ostream(dst, sizeof(dst));
        FSE_init_dtable(&table, frequencies, 2, 5);
        CHECK(FSE_decompress_interleaved2(&table, &out, &in) == 2);
        CHECK(dst[0] == 0 && dst[1] == 0);
        FSE_free_dtable(&table);
    }

#if !defined(ZDEC_NO_DICTIONARY)
    {   static const u8 frame[] = {
            0x28,0xb5,0x2f,0xfd,0x20,3,0x3d,0,0,
            0,1,0x54,0,0,0,1
        };
        u8 bytes[44];
        dictionary_t* dict = create_dictionary();
        make_dictionary(bytes);
        for (int i = 0; i < 3; ++i) bytes[16 + 4 * i] = 16;
        parse_dictionary(dict, bytes, sizeof(bytes));
        CHECK(ZSTD_decompress_with_dict(dst, sizeof(dst), frame, sizeof(frame), dict) == 3);
        CHECK(memcmp(dst, "AAA", 3) == 0);
        free_dictionary(dict);
    }
#endif
}

static const struct {
    const char* name;
    void (*run)(unsigned);
    unsigned argument;
    const char* expected;
} cases[] = {
    {"zero-offset", zero_offset, 0, CORRUPTION_MESSAGE},
    {"offset32", oversized_offset, 32, CORRUPTION_MESSAGE},
    {"offset35", oversized_offset, 35, CORRUPTION_MESSAGE},
    {"offset255", oversized_offset, 255, CORRUPTION_MESSAGE},
    {"empty-sequence-bits", invalid_sequence_bits, 0, CORRUPTION_MESSAGE},
    {"zero-sequence-stop-bit", invalid_sequence_bits, 1, CORRUPTION_MESSAGE},
    {"empty-huffman-bits", invalid_entropy_bits, 0, CORRUPTION_MESSAGE},
    {"zero-huffman-stop-bit", invalid_entropy_bits, 1, CORRUPTION_MESSAGE},
    {"empty-fse-bits", invalid_entropy_bits, 2, CORRUPTION_MESSAGE},
    {"zero-fse-stop-bit", invalid_entropy_bits, 3, CORRUPTION_MESSAGE},
#if !defined(ZDEC_NO_DICTIONARY)
    {"dictionary-zero-offset1", invalid_dictionary_offset, 0, DICTIONARY_MESSAGE},
    {"dictionary-zero-offset2", invalid_dictionary_offset, 1, DICTIONARY_MESSAGE},
    {"dictionary-zero-offset3", invalid_dictionary_offset, 2, DICTIONARY_MESSAGE},
    {"dictionary-large-offset1", invalid_dictionary_offset, 3, DICTIONARY_MESSAGE},
    {"dictionary-large-offset2", invalid_dictionary_offset, 4, DICTIONARY_MESSAGE},
    {"dictionary-large-offset3", invalid_dictionary_offset, 5, DICTIONARY_MESSAGE},
#endif
};

int main(int argc, char** argv)
{
    const size_t count = sizeof(cases) / sizeof(cases[0]);
    if (argc == 2 && strcmp(argv[1], "valid") == 0) {
        valid_tests();
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "--list") == 0) {
        for (size_t i = 0; i < count; ++i) puts(cases[i].name);
        return 0;
    }
    if (argc != 2 && !(argc == 3 && strcmp(argv[1], "--expect") == 0)) return 2;
    for (size_t i = 0; i < count; ++i) {
        if (strcmp(argv[argc - 1], cases[i].name) != 0) continue;
        if (argc == 3) {
            puts(cases[i].expected);
            return 0;
        }
        cases[i].run(cases[i].argument);
        return 3;  /* A malformed input returned normally. */
    }
    return 2;
}
