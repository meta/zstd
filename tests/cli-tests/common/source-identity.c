/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/* Change one source immediately before zstd's real fopen(), or openat()
 * when zstd opens it relative to its parent directory.
 * The target must be in the current directory. */
#undef _FORTIFY_SOURCE
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef FILE* (*fopen_fn)(const char*, const char*);
typedef int (*openat_fn)(int, const char*, int, ...);

static void changeSource(const char* path)
{
    static int changed = 0;
    const char* const target = getenv("ZSTD_TEST_RACE_TARGET");
    if (!changed && target != NULL && !strcmp(path, target)) {
        const char* const replacement = getenv("ZSTD_TEST_RACE_REPLACEMENT");
        changed = 1;
        if (replacement != NULL ? rename(replacement, path) != 0 : chmod(path, 0600) != 0) {
            perror("source-identity");
            _exit(91);
        }
        fprintf(stderr, "source-identity: changed %s\n", path);
    }
}

static FILE* openSource(const char* symbol, const char* path, const char* mode)
{
    fopen_fn const realOpen = (fopen_fn)dlsym(RTLD_NEXT, symbol);
    if (realOpen == NULL) {
        fputs("source-identity: cannot find real fopen\n", stderr);
        _exit(90);
    }
    if (!strcmp(mode, "rb")) changeSource(path);
    return realOpen(path, mode);
}

int openat(int dirfd, const char* path, int flags, ...)
{
    static openat_fn realOpenat = NULL;
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    if (realOpenat == NULL)
        realOpenat = (openat_fn)dlsym(RTLD_NEXT, "openat");
    if (realOpenat == NULL) {
        fputs("source-identity: cannot find real openat\n", stderr);
        _exit(90);
    }
    if ((flags & O_ACCMODE) == O_RDONLY) changeSource(path);
    return realOpenat(dirfd, path, flags, mode);
}

FILE* fopen(const char* path, const char* mode)
{
    return openSource("fopen", path, mode);
}

#if !defined(fopen64)
FILE* fopen64(const char* path, const char* mode)
{
    return openSource("fopen64", path, mode);
}
#endif
