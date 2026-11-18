#!/bin/sh

. "$COMMON/platform.sh"

set -e

# zstd -lv reports DictID 0 once frames disagree on their dictionary ID,
# whatever the frame order, and keeps reporting 0 for the rest of the file.

zstd -q -f files/0 -D dicts/0 -o a.zst
zstd -q -f files/0 -D dicts/1 -o b.zst
zstd -q -f files/0 -o none.zst

dict_id() {
    zstd -lv "$1" 2> /dev/null | sed -n 's/^DictID: //p'
}

check_dict_id() {
    file=$1
    expected=$2
    actual=$(dict_id "$file")
    [ "$actual" = "$expected" ] || die "$file: expected DictID $expected, got $actual"
}

id_a=$(dict_id a.zst)
id_b=$(dict_id b.zst)
[ "$id_a" != 0 ] || die "dicts/0 must have a non-zero dictID"
[ "$id_b" != 0 ] || die "dicts/1 must have a non-zero dictID"
[ "$id_a" != "$id_b" ] || die "dictionaries must have different dictIDs"

cat a.zst a.zst > aa.zst
check_dict_id aa.zst "$id_a"

for order in "a b" "a b a" "none a" "a none" "a a none"; do
    rm -f multi.zst
    for part in $order; do cat "$part.zst" >> multi.zst; done
    check_dict_id multi.zst 0
    zstd -lv multi.zst > list.out 2>&1
    [ "$(grep -c 'different dictionary IDs' list.out)" = 1 ] || die "$order: expected one warning"
    grep -qx 'WARNING: File contains multiple frames with different dictionary IDs. Showing dictID 0 instead' list.out \
        || die "$order: warning must be on its own line"
done
