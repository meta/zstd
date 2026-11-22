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

printf 'chosen content\n' > payload
zstd -q payload -o payload.zst

# race <scenario> <source> <zstd options...> :
# right after zstd opens <scenario>/work/<source>, work/ is swapped for a
# symlink to protected/. The output must still go next to the source,
# into what is now held/, never into protected/.
race() {
    scenario=$1 src=$2
    shift 2
    (
        cd "$scenario"
        LD_PRELOAD="$SO" \
            ZSTD_TEST_PARENT_RACE_WHEN=open \
            ZSTD_TEST_PARENT_RACE_TARGET="work/$src" \
            ZSTD_TEST_PARENT_RACE_PARENT=work \
            ZSTD_TEST_PARENT_RACE_SAVED=held \
            ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
            zstd -q "$@" "work/$src" 2> stderr
        grep -Fxq 'parent-race: changed parent on open' stderr
        [ -L work ] || die "$scenario: source parent was not replaced"
    )
}

# Decompression
mkdir -p dec/work dec/protected
cp payload.zst dec/work/job.zst
race dec job.zst -d
[ ! -e dec/protected/job ] || die 'decompressed output created in the swapped-in directory'
cmp payload dec/held/job

# Compression
mkdir -p cmp/work cmp/protected
cp payload cmp/work/job
race cmp job
[ ! -e cmp/protected/job.zst ] || die 'compressed output created in the swapped-in directory'
zstd -dcq cmp/held/job.zst | cmp payload -

# --force : the existing output is checked and removed next to the source
mkdir -p force/work force/protected
cp payload.zst force/work/job.zst
printf 'stale output\n' > force/work/job
printf 'protected content\n' > force/protected/job
cp force/protected/job force/sentinel
race force job.zst -d -f
cmp force/sentinel force/protected/job
cmp payload force/held/job
