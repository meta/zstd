#!/bin/sh

set -e

# More inputs than the descriptor limit expose leaks in one CLI invocation.
(ulimit -n 32) 2>/dev/null || exit 0
ulimit -n 32

printf 'directory descriptor lifetime\n' > payload
mkdir same src packed decoded reject-in reject-out
i=1
while [ "$i" -le 64 ]; do
    name=$(printf 'file%03d' "$i")
    cp payload "same/$name"
    cp payload "src/$name"
    cp payload "reject-in/$name"
    printf 'existing output\n' > "reject-out/$name.zst"
    i=$((i + 1))
done

# Source and destination share their parent descriptor. Closing the output
# must leave it available for --rm, and the next input must not inherit it.
zstd -q --rm same/*
for source in src/*; do
    name=${source##*/}
    [ ! -e "same/$name" ] || die 'source remained in the shared directory'
done
zstd -q -d --rm same/*.zst

# Independently opened source and output directories must both be released.
zstd -q --rm --output-dir-flat packed src/*
zstd -q -d --rm --output-dir-flat decoded packed/*.zst
for source in same/*; do
    name=${source##*/}
    cmp payload "$source"
    cmp payload "decoded/$name"
    [ ! -e "src/$name" ] || die 'source remained after compression'
    [ ! -e "packed/$name.zst" ] || die 'source remained after decompression'
done

# Rejected destinations must release both directories too. The last input
# must still succeed after all of the preceding overwrite refusals.
cp payload reject-in/z-good
status=0
zstd -q --output-dir-flat reject-out reject-in/* 2> rejected.stderr || status=$?
[ "$status" -eq 1 ] || die 'existing destinations should have been rejected'
zstd -dcq reject-out/z-good.zst | cmp payload -
for source in reject-in/file*; do
    name=${source##*/}
    cmp payload "$source"
    [ "$(cat "reject-out/$name.zst")" = 'existing output' ] || die 'rejected output was modified'
done
