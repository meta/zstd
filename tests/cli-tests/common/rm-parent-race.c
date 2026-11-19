/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/* Swap the parent of ZSTD_TEST_RM_RACE_TARGET for a symlink right before the
 * stream open on that file is closed, so a later removal re-resolves the
 * pathname to a different file. The stream is matched by file identity, so
 * it works for files opened with fopen() (source) or open()+fdopen()
 * (destination) alike. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

typedef int (*fclose_fn)(FILE*);

static int done = 0;

static int isTarget(FILE* stream)
{
    const char* const target = getenv("ZSTD_TEST_RM_RACE_TARGET");
    struct stat streamStat;
    struct stat targetStat;
    int const fd = fileno(stream);
    return target != NULL && fd >= 0
        && fstat(fd, &streamStat) == 0
        && stat(target, &targetStat) == 0
        && streamStat.st_dev == targetStat.st_dev
        && streamStat.st_ino == targetStat.st_ino;
}

int fclose(FILE* stream)
{
    static fclose_fn realClose = NULL;
    if (realClose == NULL)
        realClose = (fclose_fn)dlsym(RTLD_NEXT, "fclose");
    if (!done && isTarget(stream)) {
        const char* const parent = getenv("ZSTD_TEST_RM_RACE_PARENT");
        const char* const saved = getenv("ZSTD_TEST_RM_RACE_SAVED");
        const char* const replacement = getenv("ZSTD_TEST_RM_RACE_REPLACEMENT");
        done = 1;
        if (parent == NULL || saved == NULL || replacement == NULL
         || rename(parent, saved) != 0 || symlink(replacement, parent) != 0) {
            perror("rm-parent-race");
            _exit(91);
        }
        fputs("rm-parent-race: changed parent\n", stderr);
    }
    return realClose(stream);
}
