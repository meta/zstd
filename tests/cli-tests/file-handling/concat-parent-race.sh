#!/bin/sh

set -e

CONCAT_TEST_ROOT=$PWD
CONCAT_TEST_SO="$PWD/parent-race.so"

printf 'first input\n' > first
printf 'second input\n' > second
cat first second > expected
zstd -q first -o first.zst
zstd -q second -o second.zst
printf 'protected output\n' > sentinel

checkOutput() {
    if [ "$1" = compress ]; then
        zstd -dcq "$2" | cmp "$CONCAT_TEST_ROOT/expected" -
    else
        cmp "$CONCAT_TEST_ROOT/expected" "$2"
    fi
}

runCases() {
    mode=$1
    for operation in compress decompress; do
        for state in create overwrite; do
            scenario="$mode-$operation-$state"
            mkdir -p "$scenario/source" "$scenario/work" "$scenario/protected"
            (
                cd "$scenario"
                set -- env
                if [ "$mode" = race ]; then
                    set -- "$@" \
                        "LD_PRELOAD=$CONCAT_TEST_SO" \
                        ZSTD_TEST_PARENT_RACE_WHEN=stat \
                        ZSTD_TEST_PARENT_RACE_TARGET=work/combined \
                        ZSTD_TEST_PARENT_RACE_PARENT=work \
                        ZSTD_TEST_PARENT_RACE_SAVED=held \
                        "ZSTD_TEST_PARENT_RACE_REPLACEMENT=$PWD/protected"
                fi
                set -- "$@" zstd -q -f --rm
                case "$operation" in
                    compress) first=first second=second ;;
                    decompress)
                        first=first.zst second=second.zst
                        set -- "$@" -d
                        ;;
                esac
                cp "$CONCAT_TEST_ROOT/$first" "source/$first"
                cp "$CONCAT_TEST_ROOT/$second" "source/$second"
                cp "$CONCAT_TEST_ROOT/sentinel" protected/combined
                if [ "$state" = overwrite ]; then
                    printf 'stale output\n' > work/combined
                fi

                "$@" "source/$first" "source/$second" -o work/combined 2> stderr

                case "$mode" in
                    portable) output=work/combined ;;
                    race)
                        grep -Fxq 'parent-race: changed parent on stat' stderr
                        [ -L work ] || die "$scenario: output parent was not replaced"
                        output=held/combined
                        ;;
                esac
                checkOutput "$operation" "$output"
                cmp "$CONCAT_TEST_ROOT/sentinel" protected/combined
                # --rm must remain disabled for concatenated inputs.
                cmp "$CONCAT_TEST_ROOT/$first" "source/$first"
                cmp "$CONCAT_TEST_ROOT/$second" "source/$second"
            )
        done
    done
}

# These checks also exercise the portable path without directory descriptors.
runCases portable
zstd -qc first second | zstd -dcq | cmp expected -
zstd -dcq first.zst second.zst | cmp expected -
zstd -tq first.zst second.zst

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so
runCases race
