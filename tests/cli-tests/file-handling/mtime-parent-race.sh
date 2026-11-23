#!/bin/sh

set -e
. "$COMMON/mtime.sh"

# These checks also exercise the portable path without directory descriptors.
printf 'timestamp payload\n' > payload
touch -m -t 200001010000.00 payload
zstd -q payload -o payload.zst
assertSameMTime payload payload.zst > "$INTOVOID"
zstd -dq payload.zst -o decoded
assertSameMTime payload.zst decoded > "$INTOVOID"
cmp payload decoded

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$UNAME" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so
MTIME_TEST_ROOT=$PWD
MTIME_TEST_SO="$PWD/parent-race.so"

printf 'protected timestamp\n' > sentinel
touch -m -t 200101010000.00 sentinel

for operation in compress decompress; do
    for swapped in parent leaf; do
        scenario="$operation-$swapped"
        mkdir -p "$scenario/work" "$scenario/protected"
        (
            cd "$scenario"
            case "$operation" in
                compress) source=job output=job.zst; set -- ;;
                decompress) source=job.zst output=job; set -- -d ;;
            esac
            if [ "$operation" = compress ]; then
                cp -p "$MTIME_TEST_ROOT/payload" "work/$source"
            else
                cp -p "$MTIME_TEST_ROOT/payload.zst" "work/$source"
            fi
            cp -p "$MTIME_TEST_ROOT/sentinel" "protected/$output"

            case "$swapped" in
                parent)
                    changed=work saved=held replacement="$PWD/protected"
                    dataOutput="held/$output"
                    timestamped="$dataOutput"
                    ;;
                leaf)
                    # The same interposer can replace the output itself. The
                    # timestamp update must affect the link, not its target.
                    changed="work/$output" saved=work/saved-output
                    replacement="$PWD/protected/$output"
                    dataOutput="$saved"
                    timestamped="work/$output"
                    ;;
            esac

            LD_PRELOAD="$MTIME_TEST_SO" \
                ZSTD_TEST_PARENT_RACE_WHEN=close \
                ZSTD_TEST_PARENT_RACE_TARGET="work/$output" \
                ZSTD_TEST_PARENT_RACE_PARENT="$changed" \
                ZSTD_TEST_PARENT_RACE_SAVED="$saved" \
                ZSTD_TEST_PARENT_RACE_REPLACEMENT="$replacement" \
                zstd -q "$@" "work/$source" -o "work/$output" 2> stderr

            grep -Fxq 'parent-race: changed parent on close' stderr
            [ -L "$changed" ] || die "$scenario: pathname was not replaced"
            cmp "$MTIME_TEST_ROOT/sentinel" "protected/$output"
            assertSameMTime "$MTIME_TEST_ROOT/sentinel" "protected/$output" > "$INTOVOID"
            assertSameMTime "$MTIME_TEST_ROOT/payload" "$timestamped" > "$INTOVOID"
            if [ "$operation" = compress ]; then
                zstd -dcq "$dataOutput" | cmp "$MTIME_TEST_ROOT/payload" -
            else
                cmp "$MTIME_TEST_ROOT/payload" "$dataOutput"
            fi
        )
    done
done
