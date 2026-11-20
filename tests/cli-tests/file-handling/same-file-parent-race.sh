#!/bin/sh

set -e

printf 'source must survive\n' > payload
zstd -q payload -o payload.zst

# This basic check also runs on platforms without the Linux interposer.
for operation in compress decompress; do
    case "$operation" in
        compress) cp payload "portable-$operation"; set -- ;;
        decompress) cp payload.zst "portable-$operation"; set -- -d ;;
    esac
    cp "portable-$operation" "portable-$operation.sentinel"
    status=0
    zstd -q -f "$@" -o "./portable-$operation" "portable-$operation" \
        2> "portable-$operation.stderr" || status=$?
    [ "$status" -eq 1 ] || die "$operation: output alias was not rejected"
    grep -Fq 'Refusing to open an output file which will overwrite the input file' \
        "portable-$operation.stderr"
    cmp "portable-$operation.sentinel" "portable-$operation"
done

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so
SO="$PWD/parent-race.so"

# Check the same pathname, a hard link, and a different spelling of the parent.
# The last case opens the destination directory separately from the source.
for operation in compress decompress; do
    for alias in same hardlink renamed-parent; do
        scenario="$operation-$alias"
        mkdir -p "$scenario/work" "$scenario/protected"
        case "$operation" in
            compress) cp payload "$scenario/work/job" ;;
            decompress) cp payload.zst "$scenario/work/job" ;;
        esac
        cp "$scenario/work/job" "$scenario/sentinel"
        case "$alias" in
            same) destination=work/job ;;
            hardlink)
                ln "$scenario/work/job" "$scenario/work/alias"
                destination=work/alias
                ;;
            renamed-parent) destination=held/job ;;
        esac
        (
            cd "$scenario"
            if [ "$operation" = decompress ]; then
                set -- -d
            else
                set --
            fi
            status=0
            LD_PRELOAD="$SO" \
                ZSTD_TEST_PARENT_RACE_WHEN=open \
                ZSTD_TEST_PARENT_RACE_TARGET=work/job \
                ZSTD_TEST_PARENT_RACE_PARENT=work \
                ZSTD_TEST_PARENT_RACE_SAVED=held \
                ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
                zstd -q -f "$@" -o "$destination" work/job 2> stderr || status=$?
            grep -Fxq 'parent-race: changed parent on open' stderr
            [ -L work ] || die 'source parent was not replaced'
            [ "$status" -eq 1 ] || die "$scenario: output alias was not rejected"
            grep -Fq 'Refusing to open an output file which will overwrite the input file' stderr
            cmp sentinel held/job
            [ ! -e protected/job ] || die 'replacement directory was modified'
            if [ "$alias" = hardlink ]; then
                cmp sentinel held/alias
            fi
        )
    done
done

# Conversely, aliases in the replacement directory must not cause a false
# positive when the actual source and output are distinct files.
mkdir -p unrelated/work unrelated/protected
cp payload unrelated/work/job
printf 'protected sentinel\n' > unrelated/sentinel
cp unrelated/sentinel unrelated/protected/job
ln unrelated/protected/job unrelated/protected/job.zst
(
    cd unrelated
    LD_PRELOAD="$SO" \
        ZSTD_TEST_PARENT_RACE_WHEN=open \
        ZSTD_TEST_PARENT_RACE_TARGET=work/job \
        ZSTD_TEST_PARENT_RACE_PARENT=work \
        ZSTD_TEST_PARENT_RACE_SAVED=held \
        ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
        zstd -q -f work/job 2> stderr
    grep -Fxq 'parent-race: changed parent on open' stderr
    cmp sentinel protected/job
    cmp sentinel protected/job.zst
    zstd -dcq held/job.zst | cmp ../payload -
)
