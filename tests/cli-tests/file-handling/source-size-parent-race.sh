#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so
SO="$PWD/parent-race.so"

datagen -g256K > payload

# The smaller replacement ends exactly at a compression input-buffer boundary.
# Using its size silently truncates the original, and --rm then deletes it.
# A larger replacement instead used to cause a pledged-source-size error.
for size in 128K 384K; do
    mkdir -p "$size/work" "$size/protected"
    cp payload "$size/work/job"
    datagen -g"$size" > "$size/sentinel"
    cp "$size/sentinel" "$size/protected/job"
    (
        cd "$size"
        LD_PRELOAD="$SO" \
            ZSTD_TEST_PARENT_RACE_WHEN=open \
            ZSTD_TEST_PARENT_RACE_TARGET=work/job \
            ZSTD_TEST_PARENT_RACE_PARENT=work \
            ZSTD_TEST_PARENT_RACE_SAVED=held \
            ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
            zstd -q --rm work/job 2> stderr
        grep -Fxq 'parent-race: changed parent on open' stderr
        [ -L work ] || die 'source parent was not replaced'
        [ ! -e protected/job.zst ] || die 'output escaped into the replacement directory'
        cmp sentinel protected/job
        zstd -dcq held/job.zst > decoded
        cmp -s ../payload decoded || die "replacement size $size changed the compressed content"
        [ ! -e held/job ] || die 'successfully compressed source was not removed'
    )
done
