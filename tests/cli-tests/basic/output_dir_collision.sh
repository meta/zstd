#!/bin/sh

set -e

mkdir d1 d2 out
printf 'first\n' > d1/x
printf 'second\n' > d2/x

println "+ zstd -f --rm --output-dir-flat out d1/x d2/x" >&2
zstd -f --rm --output-dir-flat out d1/x d2/x && die "Collision with --rm should fail!"
test -f d1/x
test -f d2/x
test ! -e out/x.zst

println "+ zstd -f --output-dir-flat out d1/x d2/x" >&2
zstd -f --output-dir-flat out d1/x d2/x && die "Collision should fail!"
test ! -e out/x.zst

mkdir dz1 dz2 dout
printf 'first\n' | zstd -q > dz1/x.zst
printf 'second\n' | zstd -q > dz2/x.zst

println "+ zstd -d -f --rm --output-dir-flat dout dz1/x.zst dz2/x.zst" >&2
zstd -d -f --rm --output-dir-flat dout dz1/x.zst dz2/x.zst && die "Decompression collision with --rm should fail!"
test -f dz1/x.zst
test -f dz2/x.zst
test ! -e dout/x

println "+ zstd -d -f --output-dir-flat dout dz1/x.zst dz2/x.zst" >&2
zstd -d -f --output-dir-flat dout dz1/x.zst dz2/x.zst && die "Decompression collision should fail!"
test ! -e dout/x

mkdir dt1 dt2 dtout
printf 'first\n' | zstd -q > dt1/a.tar.zst
printf 'second\n' | zstd -q > dt2/a.tzst

println "+ zstd -d -f --rm --output-dir-flat dtout dt1/a.tar.zst dt2/a.tzst" >&2
zstd -d -f --rm --output-dir-flat dtout dt1/a.tar.zst dt2/a.tzst && die "Suffix collision with --rm should fail!"
test -f dt1/a.tar.zst
test -f dt2/a.tzst
test ! -e dtout/a.tar

mkdir de1 de2 deout
printf 'first\n' | zstd -q > de1/x.zst
printf 'second\n' | zstd -q > de2/x.zst
printf 'third\n' > de1/y

println "+ zstd --exclude-compressed --output-dir-flat deout de1/x.zst de2/x.zst de1/y" >&2
zstd --exclude-compressed --output-dir-flat deout de1/x.zst de2/x.zst de1/y
test -f deout/y.zst
test ! -e deout/x.zst.zst
exit 0
