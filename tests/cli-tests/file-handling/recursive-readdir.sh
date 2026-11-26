#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/readdir-error.c" -ldl -o readdir-error.so

printf 'recursive directory reading\n' > payload
mkdir -p tree/nested
cp payload tree/nested/job
ln -s nested/job tree/ignored-link

zstd -qrc tree > control.zst
zstd -dcq control.zst | cmp payload -

failed=0
for target in tree tree/nested; do
    status=0
    LD_PRELOAD="$PWD/readdir-error.so" \
        ZSTD_TEST_READDIR_TARGET="$PWD/$target" \
        ZSTD_TEST_READDIR_MODE=stale \
        zstd -qrc tree > stale.zst 2> stale.stderr || status=$?
    grep -Fxq 'readdir-error: stale' stale.stderr
    if [ "$status" -eq 0 ]; then
        zstd -dcq stale.zst | cmp payload -
    else
        printf 'stale errno rejected %s\n' "$target" >&2
        failed=1
    fi

    status=0
    LD_PRELOAD="$PWD/readdir-error.so" \
        ZSTD_TEST_READDIR_TARGET="$PWD/$target" \
        ZSTD_TEST_READDIR_MODE=error \
        zstd -qrc tree > error.zst 2> error.stderr || status=$?
    grep -Fxq 'readdir-error: error' error.stderr
    if [ "$status" -eq 0 ]; then
        printf 'read error accepted for %s\n' "$target" >&2
        failed=1
    else
        grep -Fq "readdir($target) error:" error.stderr
        [ ! -s error.zst ] || die 'read error did not discard the partial file list'
    fi
done
[ "$failed" -eq 0 ] || die 'recursive directory reading failed'
