#!/bin/sh

set -e

# After --, arguments are file names, even when they start with -,
# but - alone still means standard input, as with gzip and xz.

echo "some data" > file
echo "other data" > ./-file
zstd -q file
zstd -q -- -file

zstd -dc -- -file.zst > out
cmp -- -file out

zstd -dc -- - < file.zst > out
cmp file out

zstd -c -- - < file | zstd -dc > out
cmp file out

zstd -dc -- -file.zst - < file.zst > out
cat -- -file file > expected
cmp expected out

# a file named - is given as ./-
echo "dash data" > ./-
zstd -c -- ./- > dash.zst
zstd -dc dash.zst > out
cmp ./- out
