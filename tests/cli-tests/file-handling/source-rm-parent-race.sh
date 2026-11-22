#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so

printf 'attacker content\n' > work-input
mkdir -p work protected
cp work-input work/victim
printf 'protected content\n' > protected/victim
cp protected/victim sentinel

# fclose() on work/victim swaps work/ for a symlink to protected/ before
# --rm removes the source.
LD_PRELOAD="$PWD/parent-race.so" \
    ZSTD_TEST_PARENT_RACE_TARGET="work/victim" \
    ZSTD_TEST_PARENT_RACE_PARENT="work" \
    ZSTD_TEST_PARENT_RACE_SAVED="held" \
    ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
    zstd -q --rm -o out.zst work/victim 2> stderr

grep -Fxq 'parent-race: changed parent on close' stderr
[ -L work ] || die 'source parent was not replaced'
# Re-resolving the source pathname would delete the protected file.
cmp sentinel protected/victim
# --rm removed the source itself, from the directory it was opened in.
[ ! -e held/victim ] || die 'source was not removed'
# The processed content was the original input, not the protected file.
zstd -dcq out.zst | cmp - work-input
