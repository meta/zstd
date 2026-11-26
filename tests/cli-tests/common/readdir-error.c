/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/* Reorder the selected directory's "." entry to the end, leaving errno set
 * after that successful read, or inject a real read error at the end.
 * Both cases must preserve the distinction between EOF and an error. */
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int done = 0;

static int isTarget(DIR* dir)
{
    const char* const target = getenv("ZSTD_TEST_READDIR_TARGET");
    struct stat actual;
    struct stat expected;
    return target != NULL
        && fstat(dirfd(dir), &actual) == 0
        && stat(target, &expected) == 0
        && actual.st_dev == expected.st_dev
        && actual.st_ino == expected.st_ino;
}

#define DEFINE_READDIR(name, entry_t)                                      \
    typedef entry_t* (*name##_fn)(DIR*);                                   \
    entry_t* name(DIR* dir)                                                \
    {                                                                     \
        static name##_fn realRead = NULL;                                  \
        static entry_t dot;                                               \
        static int haveDot = 0;                                           \
        int const savedErrno = errno;                                     \
        const char* const mode = getenv("ZSTD_TEST_READDIR_MODE");          \
        int const selected = !done && mode != NULL && isTarget(dir);       \
        entry_t* entry;                                                   \
        if (realRead == NULL)                                             \
            realRead = (name##_fn)dlsym(RTLD_NEXT, #name);                  \
        if (realRead == NULL) {                                           \
            fputs("readdir-error: cannot resolve " #name "\n", stderr);   \
            _exit(90);                                                    \
        }                                                                 \
        errno = savedErrno;                                               \
        if (!selected) return realRead(dir);                              \
        for (;;) {                                                        \
            errno = 0;                                                    \
            entry = realRead(dir);                                        \
            if (entry == NULL || strcmp(mode, "stale") != 0               \
                || strcmp(entry->d_name, ".") != 0) break;                \
            memcpy(&dot, entry, entry->d_reclen < sizeof(dot)              \
                              ? entry->d_reclen : sizeof(dot));           \
            haveDot = 1;                                                  \
        }                                                                 \
        if (entry != NULL || errno != 0) return entry;                     \
        done = 1;                                                         \
        fprintf(stderr, "readdir-error: %s\n", mode);                      \
        if (!strcmp(mode, "stale") && haveDot) {                           \
            errno = EIO;                                                  \
            return &dot;                                                  \
        }                                                                 \
        if (!strcmp(mode, "error")) {                                     \
            errno = EIO;                                                  \
            return NULL;                                                  \
        }                                                                 \
        fputs("readdir-error: invalid mode or missing dot entry\n", stderr); \
        _exit(91);                                                        \
    }

DEFINE_READDIR(readdir, struct dirent)
#if defined(__GLIBC__) && !defined(readdir64)
DEFINE_READDIR(readdir64, struct dirent64)
#endif
