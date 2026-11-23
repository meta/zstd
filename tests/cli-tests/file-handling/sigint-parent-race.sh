#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so
SIGINT_TEST_ROOT=$PWD
SIGINT_TEST_SO="$PWD/parent-race.so"

printf 'interrupted payload\n' > payload
zstd -q payload -o payload.zst
printf 'protected output\n' > sentinel

for operation in compress decompress; do
    for layout in shared independent; do
        scenario="$operation-$layout"
        mkdir -p "$scenario/work" "$scenario/protected"
        (
            cd "$scenario"
            case "$operation" in
                compress)
                    source=job output=job.zst
                    input="$SIGINT_TEST_ROOT/payload"
                    set --
                    ;;
                decompress)
                    source=job.zst output=job
                    input="$SIGINT_TEST_ROOT/payload.zst"
                    set -- -d
                    ;;
            esac
            case "$layout" in
                shared) sourceDir=work savedSourceDir=held ;;
                independent)
                    sourceDir=source savedSourceDir=source
                    mkdir source
                    ;;
            esac
            cp "$input" "$sourceDir/$source"
            cp "$SIGINT_TEST_ROOT/sentinel" "protected/$output"

            # Interrupt only after the output is open and its cleanup handler
            # is installed. No sleeps or timing-dependent external kill.
            status=0
            LD_PRELOAD="$SIGINT_TEST_SO" \
                ZSTD_TEST_PARENT_RACE_WHEN=sigint \
                ZSTD_TEST_PARENT_RACE_TARGET="work/$output" \
                ZSTD_TEST_PARENT_RACE_PARENT=work \
                ZSTD_TEST_PARENT_RACE_SAVED=held \
                ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
                zstd -q --rm "$@" "$sourceDir/$source" -o "work/$output" \
                2> stderr || status=$?

            [ "$status" -eq 2 ] || die "$scenario: SIGINT should exit with status 2"
            grep -Fxq 'parent-race: changed parent on sigint' stderr
            [ -L work ] || die "$scenario: output parent was not replaced"
            [ -d held ] || die "$scenario: original output parent is missing"
            [ ! -e "held/$output" ] && [ ! -L "held/$output" ] \
                || die "$scenario: interrupted output was not removed"
            cmp "$input" "$savedSourceDir/$source"
            cmp "$SIGINT_TEST_ROOT/sentinel" "protected/$output"
        )
    done
done
