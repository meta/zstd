#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so

# A truncated frame : decompression fails after work/victim was created,
# so zstd removes that partial output.
datagen -g1M > data
zstd -q data -o data.zst
mkdir -p work protected
head -c $(( $(wc -c < data.zst) / 2 )) data.zst > work/victim.zst
printf 'protected content\n' > protected/victim
cp protected/victim sentinel

# fclose() on work/victim (the output) swaps work/ for a symlink to
# protected/ before the failed run removes its partial output.
if LD_PRELOAD="$PWD/parent-race.so" \
    ZSTD_TEST_PARENT_RACE_TARGET="work/victim" \
    ZSTD_TEST_PARENT_RACE_PARENT="work" \
    ZSTD_TEST_PARENT_RACE_SAVED="held" \
    ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
    zstd -q -d work/victim.zst 2> stderr; then
    die 'decompressing a truncated frame should fail'
fi

grep -Fxq 'parent-race: changed parent on close' stderr
[ -L work ] || die 'output parent was not replaced'
# Re-resolving the output pathname would delete the protected file.
cmp sentinel protected/victim
# The partial output was removed, from the directory it was created in.
[ ! -e held/victim ] || die 'partial output was left behind'
