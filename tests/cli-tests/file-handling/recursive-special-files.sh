#!/bin/sh

set -e

. "$COMMON/platform.sh"

# mkfifo is POSIX-only; the Windows recursion branch already filters to regular files.
$isWindows && exit 0

# Regression: a special file (fifo/socket/device) discovered via -r used to be
# enqueued like a regular input; FIO then opened it and blocked forever waiting
# for a writer. Recursion must only enqueue regular files, matching the
# Windows branch (which only adds NORMAL/ARCHIVE/COMPRESSED entries).
mkdir -p src/sub
echo "payload" > src/file.txt
echo "nested" > src/sub/nested.txt
mkfifo src/pipe
ln -s pipe src/pipe-link   # under -f links are followed; a link to a fifo must also be skipped

# A continuous writer keeps fifo opens unblocking so the buggy build completes
# (and reveals itself by creating pipe.zst/pipe-link.zst) instead of hanging.
( while :; do echo x > src/pipe; done ) & writer=$!

zstd -r -f src 2>stderr.log

kill -9 "$writer" 2>/dev/null || true   # writer stays blocked on fixed builds

test -f src/file.txt.zst
test -f src/sub/nested.txt.zst
test ! -e src/pipe.zst                # fifo must not be compressed
test ! -e src/pipe-link.zst           # symlink to fifo must not be compressed
grep -q "not a regular file" stderr.log
