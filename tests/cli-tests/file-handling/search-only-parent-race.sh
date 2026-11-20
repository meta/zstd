#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary. Root can bypass the
# directory's read permissions, so it cannot exercise this regression.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
[ "$(id -u)" -ne 0 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so
SO="$PWD/parent-race.so"

printf 'search permission is sufficient\n' > payload
zstd -q payload -o payload.zst

for operation in compress decompress; do
    mkdir -p "$operation/work" "$operation/protected"
    case "$operation" in
        compress) cp payload "$operation/work/job" ;;
        decompress) cp payload.zst "$operation/work/job.zst" ;;
    esac
    (
        cd "$operation"
        # Restore permissions even if an assertion fails, so the test runner
        # can remove its scratch directory.
        trap 'chmod u+rwx held 2>/dev/null || :; [ -L work ] || chmod u+rwx work' 0
        chmod 300 work
        [ ! -r work ] || die 'test directory is unexpectedly readable'
        case "$operation" in
            compress) source=job output=job.zst; set -- ;;
            decompress) source=job.zst output=job; set -- -d ;;
        esac
        LD_PRELOAD="$SO" \
            ZSTD_TEST_PARENT_RACE_WHEN=open \
            ZSTD_TEST_PARENT_RACE_TARGET="work/$source" \
            ZSTD_TEST_PARENT_RACE_PARENT=work \
            ZSTD_TEST_PARENT_RACE_SAVED=held \
            ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
            zstd -q --rm "$@" "work/$source" 2> stderr
        grep -Fxq 'parent-race: changed parent on open' stderr
        [ -L work ] || die 'source parent was not replaced'
        [ ! -e "protected/$output" ] || die 'output escaped the search-only directory'
        [ ! -e "held/$source" ] || die 'source was not removed from the search-only directory'
        if [ "$operation" = compress ]; then
            zstd -dcq "held/$output" | cmp ../payload -
        else
            cmp ../payload "held/$output"
        fi
    )
done

# Also bind an independently selected, search-only output directory. A failed
# decompression must remove its own partial output after that parent is swapped.
mkdir -p dst-error/work dst-error/protected
head -c 8 payload.zst > dst-error/input.zst
printf 'protected output\n' > dst-error/sentinel
cp dst-error/sentinel dst-error/protected/job
(
    cd dst-error
    trap 'chmod u+rwx held 2>/dev/null || :; [ -L work ] || chmod u+rwx work' 0
    chmod 300 work
    if LD_PRELOAD="$SO" \
        ZSTD_TEST_PARENT_RACE_TARGET=work/job \
        ZSTD_TEST_PARENT_RACE_PARENT=work \
        ZSTD_TEST_PARENT_RACE_SAVED=held \
        ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
        zstd -q -d input.zst -o work/job 2> stderr; then
        die 'decompressing a truncated frame should fail'
    fi
    grep -Fxq 'parent-race: changed parent on close' stderr
    [ -L work ] || die 'output parent was not replaced'
    cmp sentinel protected/job
    [ ! -e held/job ] || die 'partial output was left in the search-only directory'
)
