#!/bin/sh

set -e

# --raw-dict saves only the content of the dictionary, without its header.
for i in $(seq 100); do
    datagen -s$i -g2K > file$i
done
printf '\067\244\060\354' > magic   # ZSTD_MAGIC_DICTIONARY

for train in --train --train-cover=k=48,d=8 --train-legacy; do
    println "+ $train"
    zstd -q $train file* --maxdict=4KB -o full
    zstd -q $train file* --maxdict=4KB --raw-dict -o raw

    # the full dictionary starts with the magic number, the raw one doesn't
    head -c 4 full | cmp -s - magic || die "full dictionary should start with the magic number"
    head -c 4 raw | cmp -s - magic && die "raw dictionary should not start with the magic number"

    # the raw dictionary is the content at the end of the full dictionary
    rawSize=$(wc -c < raw)
    fullSize=$(wc -c < full)
    [ "$rawSize" -lt "$fullSize" ] || die "raw dictionary should be smaller"
    tail -c "$rawSize" full | cmp -s - raw || die "raw dictionary should be the end of the full dictionary"

    # zstd accepts it with -D
    zstd -q -f -D raw file1 -o file1.zst
    zstd -q -f -d -D raw file1.zst -o file1.out
    cmp file1 file1.out
done
