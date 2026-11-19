#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/source-rm-parent-race.c" -ldl -o source-rm-parent-race.so

printf 'attacker content\n' > work-input
mkdir -p work protected
cp work-input work/victim
printf 'protected content\n' > protected/victim
cp protected/victim sentinel

# fclose() on work/victim swaps work/ for a symlink to protected/ before
# --rm re-resolves the source pathname.
LD_PRELOAD="$PWD/source-rm-parent-race.so" \
    ZSTD_TEST_RM_RACE_TARGET="work/victim" \
    ZSTD_TEST_RM_RACE_PARENT="work" \
    ZSTD_TEST_RM_RACE_SAVED="held" \
    ZSTD_TEST_RM_RACE_REPLACEMENT="$PWD/protected" \
    zstd -q --rm -o out.zst work/victim 2> stderr

grep -Fxq 'source-rm-parent-race: changed source parent' stderr
[ -L work ] || die 'source parent was not replaced'
# Unfixed code deletes the protected file here; fixed code refuses.
cmp sentinel protected/victim
# The processed content was the original input, not the protected file.
zstd -dcq out.zst | cmp - held/victim
