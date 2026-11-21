#!/bin/sh

set -e

# The interposer requires a native 64-bit Linux binary.
[ -z "${EXEC_PREFIX:-}" ] || exit 0
[ "$(uname -s)" = Linux ] || exit 0
[ "$(getconf LONG_BIT)" = 64 ] || exit 0
zstd --version | grep -Fq '(64-bit)' || exit 0

${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/parent-race.c" -ldl -o parent-race.so
TEST_ROOT=$PWD
SO="$PWD/parent-race.so"
${CC:-cc} -Wall -Wextra -Werror -shared -fPIC \
    "$COMMON/source-identity.c" -ldl -o source-identity.so

printf 'original recursive input\n' > original
printf 'replacement recursive input\n' > replacement
zstd -q original -o original.zst
zstd -q replacement -o replacement.zst

# First confirm that all four ordinary recursive operations work.
mkdir control-cmp control-dec
cp original control-cmp/job
cp original.zst control-dec/job.zst
zstd -qrc control-cmp > control.zst
zstd -dcq control.zst > control.decoded
cmp original control.decoded
zstd -dqrc control-dec > control.decoded
cmp original control.decoded
zstd -qr --rm control-cmp
zstd -dqr --rm control-dec
zstd -dcq control-cmp/job.zst > control.decoded
cmp original control.decoded
cmp original control-dec/job
[ ! -e control-cmp/job ]
[ ! -e control-dec/job.zst ]
zstd -qt -r control-cmp
zstd -ql -r control-cmp > control.list

# Following directory links remains an explicit choice.
mkdir -p follow/tree follow/original
cp original follow/original/job
ln -s "$TEST_ROOT/follow/original" follow/tree/link
zstd -qqrc follow/tree > follow.ignored
[ ! -s follow.ignored ]
zstd -qfrc follow/tree > follow.zst
zstd -dcq follow.zst > follow.decoded
cmp original follow.decoded

# A metadata change on the same inode remains valid; use its current mode.
mkdir metadata
cp original metadata/job
chmod 644 metadata/job
(
    cd metadata
    LD_PRELOAD="$TEST_ROOT/source-identity.so" \
        ZSTD_TEST_RACE_TARGET=job \
        zstd -qr . -o ../metadata.zst 2> ../metadata.stderr
)
grep -Fxq 'source-identity: changed job' metadata.stderr
[ "$(stat -c %a metadata/job)" = 600 ]
[ "$(stat -c %a metadata.zst)" = 600 ]
zstd -dcq metadata.zst > metadata.decoded
cmp original metadata.decoded

fail() {
    printf '%s: %s\n' "$scenario" "$*" >&2
    exit 1
}

# Both successful processing of the original object and explicit rejection
# are safe. Processing the replacement, even just to stdout, is not.
checkOutput() {
    if [ "$operation" = compress ]; then
        zstd -dcq "$1" > decoded || fail 'invalid compressed output'
    else
        cp "$1" decoded || fail 'missing decompressed output'
    fi
    if cmp -s "$TEST_ROOT/replacement" decoded; then
        fail 'processed the replacement contents'
    fi
    cmp -s "$TEST_ROOT/original" decoded || fail 'unexpected output contents'
}

race() (
    operation=$1 layout=$2 destination=$3 trigger=$4
    scenario="$trigger-$operation-$layout-$destination"
    child=
    [ "$layout" != nested ] || child=/nested
    sourceDir="work$child"
    heldDir="held$child"
    replacementDir="protected$child"
    source=job
    output=job.zst
    input="$TEST_ROOT/original"
    replacement="$TEST_ROOT/replacement"
    set -- -q -r
    if [ "$operation" != compress ]; then
        source=job.zst
        output=job
        input="$TEST_ROOT/original.zst"
        replacement="$TEST_ROOT/replacement.zst"
        case "$operation" in
            decompress) set -- "$@" -d ;;
            test) set -- "$@" -t ;;
            list) set -- "$@" --list ;;
        esac
    fi
    if [ "$destination" = stdout ]; then
        set -- "$@" -c
    elif [ "$destination" = file ]; then
        set -- "$@" --rm
    fi

    mkdir -p "$scenario/$sourceDir" "$scenario/$replacementDir" || fail 'mkdir failed'
    cd "$scenario" || fail 'chdir failed'
    cp "$input" "$sourceDir/$source" || fail 'cannot prepare original input'
    cp "$replacement" "$replacementDir/$source" || fail 'cannot prepare replacement input'

    # The tree has only one file, so the ordering of readdir() is irrelevant.
    # For nested/, TARGET is the scanned directory and PARENT its ancestor.
    status=0
    LD_PRELOAD="$SO" \
        ZSTD_TEST_PARENT_RACE_WHEN="$trigger" \
        ZSTD_TEST_PARENT_RACE_TARGET="$sourceDir" \
        ZSTD_TEST_PARENT_RACE_PARENT=work \
        ZSTD_TEST_PARENT_RACE_SAVED=held \
        ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
        zstd "$@" work > stdout 2> stderr || status=$?

    grep -Fxq "parent-race: changed parent on $trigger" stderr || fail 'race did not trigger'
    [ -L work ] && [ -d "$heldDir" ] || fail 'original directory was not retained'
    [ ! -e "$replacementDir/$output" ] && [ ! -L "$replacementDir/$output" ] \
        || fail 'output was created in the replacement tree'
    cmp -s "$replacement" "$replacementDir/$source" || fail 'replacement input was changed or removed'

    if [ "$destination" = check ]; then
        [ "$status" -eq 1 ] || fail "replaced source was not rejected: $status"
        grep -Fq "zstd: $sourceDir/$source changed while opening" stderr || fail 'missing source rejection diagnostic'
        if [ "$operation" = test ]; then
            [ ! -s stdout ] || fail 'test mode produced stdout data'
        else
            if grep -Fq "$sourceDir/$source" stdout; then fail 'listed the replacement input'; fi
        fi
        [ ! -e "$heldDir/$output" ] || fail 'inspection created an output file'
        cmp -s "$input" "$heldDir/$source" || fail 'inspection changed the original input'
        exit 0
    fi

    if [ "$status" -eq 0 ]; then
        if [ "$destination" = stdout ]; then
            checkOutput stdout
            cmp -s "$input" "$heldDir/$source" || fail 'stdout processing changed the original input'
            [ ! -e "$heldDir/$output" ] || fail 'stdout processing created a file'
        else
            [ ! -s stdout ] || fail 'file processing wrote to stdout'
            checkOutput "$heldDir/$output"
            [ ! -e "$heldDir/$source" ] || fail '--rm left the original input behind'
        fi
    else
        [ "$status" -eq 1 ] || fail "unexpected exit status: $status"
        grep -Fq "zstd: $sourceDir/$source" stderr || fail 'missing source rejection diagnostic'
        [ ! -s stdout ] || fail 'rejected source produced stdout data'
        [ ! -e "$heldDir/$output" ] || fail 'rejected source created an output file'
        cmp -s "$input" "$heldDir/$source" || fail 'rejected source was changed or removed'
    fi
)

# A renamed parent that still resolves to the selected inode is accepted.
unchanged() (
    operation=$1
    scenario="unchanged-$operation"
    source=job output=job.zst input="$TEST_ROOT/original"
    set --
    if [ "$operation" = decompress ]; then
        source=job.zst output=job input="$TEST_ROOT/original.zst"
        set -- -d
    fi
    mkdir -p "$scenario/work" || fail 'mkdir failed'
    cd "$scenario" || fail 'chdir failed'
    cp "$input" "work/$source" || fail 'cannot prepare input'
    LD_PRELOAD="$SO" \
        ZSTD_TEST_PARENT_RACE_WHEN=closedir \
        ZSTD_TEST_PARENT_RACE_TARGET=work \
        ZSTD_TEST_PARENT_RACE_PARENT=work \
        ZSTD_TEST_PARENT_RACE_SAVED=held \
        ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/held" \
        zstd -qr --rm "$@" work 2> stderr || fail 'unchanged input was rejected'
    grep -Fxq 'parent-race: changed parent on closedir' stderr || fail 'race did not trigger'
    checkOutput "held/$output"
    [ ! -e "held/$source" ] || fail '--rm left the original input behind'
)

# Replace the child directory itself after classification but before descent.
# Without -f, O_NOFOLLOW rejects the new link. With -f, the directory's saved
# identity must still match the directory actually opened.
changedDirectory() (
    follow=$1
    scenario="directory-$follow"
    mkdir -p "$scenario/work/nested" "$scenario/protected" || fail 'mkdir failed'
    cd "$scenario" || fail 'chdir failed'
    cp "$TEST_ROOT/original" work/nested/job || fail 'cannot prepare original input'
    cp "$TEST_ROOT/replacement" protected/job || fail 'cannot prepare replacement input'
    set --
    [ "$follow" != follow ] || set -- -f
    status=0
    LD_PRELOAD="$SO" \
        ZSTD_TEST_PARENT_RACE_WHEN=stat \
        ZSTD_TEST_PARENT_RACE_TARGET=work/nested \
        ZSTD_TEST_PARENT_RACE_MATCH_PARENT=work \
        ZSTD_TEST_PARENT_RACE_PARENT=work/nested \
        ZSTD_TEST_PARENT_RACE_SAVED=work/held \
        ZSTD_TEST_PARENT_RACE_REPLACEMENT="$PWD/protected" \
        zstd -qrc "$@" work > stdout 2> stderr || status=$?
    grep -Fxq 'parent-race: changed parent on stat' stderr || fail 'race did not trigger'
    [ "$status" -eq 1 ] || fail "changed directory was not rejected: $status"
    grep -Fq "'work/nested'" stderr || fail 'missing directory rejection diagnostic'
    [ ! -s stdout ] || fail 'changed directory produced stdout data'
    cmp -s "$TEST_ROOT/original" work/held/job || fail 'original input was changed'
    cmp -s "$TEST_ROOT/replacement" protected/job || fail 'replacement input was changed'
)

# Run every case, including when the current CLI still has the regression.
failed=0
for trigger in closedir opendir; do
    for layout in direct nested; do
        for operation in compress decompress; do
            for destination in stdout file; do
                if race "$operation" "$layout" "$destination" "$trigger"; then :; else failed=1; fi
            done
        done
        for operation in test list; do
            if race "$operation" "$layout" check "$trigger"; then :; else failed=1; fi
        done
    done
done
for operation in compress decompress; do
    if unchanged "$operation"; then :; else failed=1; fi
done
for follow in nofollow follow; do
    if changedDirectory "$follow"; then :; else failed=1; fi
done
exit "$failed"
