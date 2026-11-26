/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/* Swap the parent directory of ZSTD_TEST_PARENT_RACE_TARGET for a symlink,
 * so that later operations resolving a pathname through it reach another
 * directory. The swap happens once :
 * - ZSTD_TEST_PARENT_RACE_WHEN=open : right after the stream is opened ;
 * - ZSTD_TEST_PARENT_RACE_WHEN=close (default) : right before it is closed ;
 * - ZSTD_TEST_PARENT_RACE_WHEN=sigint : after the SIGINT handler is installed,
 *   then raise SIGINT ;
 * - ZSTD_TEST_PARENT_RACE_WHEN=stat : right after stat() or fstatat() checks
 *   the target, which need not exist yet. PARENT must be its direct parent.
 * The stream is matched by file identity, so it works for files opened with
 * fopen(), or with open() / openat() then fdopen(). */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef FILE* (*fopen_fn)(const char*, const char*);
typedef FILE* (*fdopen_fn)(int, const char*);
typedef int (*fclose_fn)(FILE*);
typedef int (*stat_fn)(const char*, struct stat*);
typedef int (*fstatat_fn)(int, const char*, struct stat*, int);
typedef void (*signal_handler_fn)(int);
typedef signal_handler_fn (*signal_fn)(int, signal_handler_fn);

static int done = 0;
static FILE* interruptStream = NULL;

static const char* configuredTrigger(void)
{
    const char* const configured = getenv("ZSTD_TEST_PARENT_RACE_WHEN");
    return configured != NULL ? configured : "close";
}

static int originalStat(const char* path, struct stat* statbuf)
{
    static stat_fn realStat = NULL;
    if (realStat == NULL)
        realStat = (stat_fn)dlsym(RTLD_NEXT, "stat");
    if (realStat == NULL) {
        fputs("parent-race: cannot resolve stat\n", stderr);
        _exit(91);
    }
    return realStat(path, statbuf);
}

static int isTarget(FILE* stream)
{
    const char* const target = getenv("ZSTD_TEST_PARENT_RACE_TARGET");
    struct stat streamStat;
    struct stat targetStat;
    int const fd = fileno(stream);
    return target != NULL && fd >= 0
        && fstat(fd, &streamStat) == 0
        && originalStat(target, &targetStat) == 0
        && streamStat.st_dev == targetStat.st_dev
        && streamStat.st_ino == targetStat.st_ino;
}

static void changeParent(const char* when)
{
    const char* const parent = getenv("ZSTD_TEST_PARENT_RACE_PARENT");
    const char* const saved = getenv("ZSTD_TEST_PARENT_RACE_SAVED");
    const char* const replacement = getenv("ZSTD_TEST_PARENT_RACE_REPLACEMENT");
    done = 1;
    if (parent == NULL || saved == NULL || replacement == NULL
     || rename(parent, saved) != 0 || symlink(replacement, parent) != 0) {
        perror("parent-race");
        _exit(91);
    }
    fprintf(stderr, "parent-race: changed parent on %s\n", when);
}

static int swapParent(FILE* stream, const char* when)
{
    const char* const trigger = configuredTrigger();
    if (done) return 0;
    if (strcmp(trigger, "sigint") == 0 && strcmp(when, "open") == 0) {
        if (isTarget(stream)) interruptStream = stream;
        return 0;
    }
    if (strcmp(trigger, when) != 0 || !isTarget(stream)) return 0;
    changeParent(when);
    return 1;
}

static int isTargetPath(int dirfd, const char* path)
{
    const char* const target = getenv("ZSTD_TEST_PARENT_RACE_TARGET");
    const char* const parent = getenv("ZSTD_TEST_PARENT_RACE_PARENT");
    const char* base;
    struct stat dirStat;
    struct stat parentStat;
    if (target == NULL) return 0;
    if (dirfd == AT_FDCWD || path[0] == '/') return !strcmp(path, target);
    base = strrchr(target, '/');
    base = base != NULL ? base + 1 : target;
    return !strcmp(path, base) && parent != NULL
        && fstat(dirfd, &dirStat) == 0
        && originalStat(parent, &parentStat) == 0
        && dirStat.st_dev == parentStat.st_dev
        && dirStat.st_ino == parentStat.st_ino;
}

static void swapAfterStat(int dirfd, const char* path)
{
    int const savedErrno = errno;
    if (!done && !strcmp(configuredTrigger(), "stat") && isTargetPath(dirfd, path))
        changeParent("stat");
    errno = savedErrno;
}

int stat(const char* path, struct stat* statbuf)
{
    int const result = originalStat(path, statbuf);
    swapAfterStat(AT_FDCWD, path);
    return result;
}

int fstatat(int dirfd, const char* path, struct stat* statbuf, int flags)
{
    static fstatat_fn realFstatat = NULL;
    int result;
    if (realFstatat == NULL)
        realFstatat = (fstatat_fn)dlsym(RTLD_NEXT, "fstatat");
    if (realFstatat == NULL) {
        fputs("parent-race: cannot resolve fstatat\n", stderr);
        _exit(91);
    }
    result = realFstatat(dirfd, path, statbuf, flags);
    swapAfterStat(dirfd, path);
    return result;
}

FILE* fopen(const char* path, const char* mode)
{
    static fopen_fn realOpen = NULL;
    FILE* stream;
    if (realOpen == NULL)
        realOpen = (fopen_fn)dlsym(RTLD_NEXT, "fopen");
    stream = realOpen(path, mode);
    if (stream != NULL) swapParent(stream, "open");
    return stream;
}

FILE* fdopen(int fd, const char* mode)
{
    static fdopen_fn realFdopen = NULL;
    FILE* stream;
    if (realFdopen == NULL)
        realFdopen = (fdopen_fn)dlsym(RTLD_NEXT, "fdopen");
    stream = realFdopen(fd, mode);
    if (stream != NULL) swapParent(stream, "open");
    return stream;
}

int fclose(FILE* stream)
{
    static fclose_fn realClose = NULL;
    if (realClose == NULL)
        realClose = (fclose_fn)dlsym(RTLD_NEXT, "fclose");
    swapParent(stream, "close");
    if (stream == interruptStream) interruptStream = NULL;
    return realClose(stream);
}

static signal_handler_fn installHandler(const char* name, int sig,
                                         signal_handler_fn handler)
{
    signal_fn const realSignal = (signal_fn)dlsym(RTLD_NEXT, name);
    signal_handler_fn previous;
    if (realSignal == NULL) {
        fprintf(stderr, "parent-race: cannot resolve %s\n", name);
        _exit(91);
    }
    previous = realSignal(sig, handler);
    if (previous != SIG_ERR && sig == SIGINT
     && handler != SIG_DFL && handler != SIG_IGN
     && interruptStream != NULL && swapParent(interruptStream, "sigint")) {
        raise(SIGINT);
        /* The CLI's handler must exit, not return. */
        fprintf(stderr, "parent-race: SIGINT handler returned\n");
        _exit(92);
    }
    return previous;
}

signal_handler_fn signal(int sig, signal_handler_fn handler)
{
    return installHandler("signal", sig, handler);
}

/* In strict C modes, glibc redirects signal() to this symbol. */
#if defined(__GLIBC__)
signal_handler_fn __sysv_signal(int sig, signal_handler_fn handler)
{
    return installHandler("__sysv_signal", sig, handler);
}
#endif
