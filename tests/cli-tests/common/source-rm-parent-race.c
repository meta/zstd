/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/* Swap the source parent for a symlink right before its fclose, so --rm
 * re-resolves the pathname to a different file. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef FILE* (*fopen_fn)(const char*, const char*);
typedef int (*fclose_fn)(FILE*);

static FILE* watched = NULL;
static int done = 0;

FILE* fopen(const char* path, const char* mode)
{
    static fopen_fn realFopen = NULL;
    FILE* f;
    if (realFopen == NULL)
        realFopen = (fopen_fn)dlsym(RTLD_NEXT, "fopen");
    f = realFopen(path, mode);
    if (f != NULL && !done) {
        const char* const target = getenv("ZSTD_TEST_RM_RACE_TARGET");
        if (target != NULL && !strcmp(path, target))
            watched = f;
    }
    return f;
}

int fclose(FILE* stream)
{
    static fclose_fn realClose = NULL;
    if (realClose == NULL)
        realClose = (fclose_fn)dlsym(RTLD_NEXT, "fclose");
    if (!done && watched != NULL && stream == watched) {
        const char* const parent = getenv("ZSTD_TEST_RM_RACE_PARENT");
        const char* const saved = getenv("ZSTD_TEST_RM_RACE_SAVED");
        const char* const replacement = getenv("ZSTD_TEST_RM_RACE_REPLACEMENT");
        done = 1;
        watched = NULL;
        if (parent == NULL || saved == NULL || replacement == NULL
         || rename(parent, saved) != 0 || symlink(replacement, parent) != 0) {
            perror("source-rm-parent-race");
            _exit(91);
        }
        fputs("source-rm-parent-race: changed source parent\n", stderr);
    }
    return realClose(stream);
}
