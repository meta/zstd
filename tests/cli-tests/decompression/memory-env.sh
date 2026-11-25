#!/bin/sh

set -e

# ZSTD_MEMORY replaces the default memory limit (128 MiB) of decompression.
# Compressed from stdin, these frames keep their full window size.
datagen -g100K | zstd -q --long=28 > w256M.zst
datagen -g100K | zstd -q -19 > w8M.zst

println "+ default limit"
zstd -q -t w256M.zst && die "a 256 MiB window should exceed the default limit"
zstd -q -t w8M.zst

println "+ raise the limit"
ZSTD_MEMORY=256MB zstd -q -t w256M.zst
ZSTD_MEMORY=1GiB zstd -q -t w256M.zst

println "+ lower the limit"
ZSTD_MEMORY=4MB zstd -q -t w8M.zst && die "an 8 MiB window should exceed ZSTD_MEMORY=4MB"

println "+ the command line wins"
ZSTD_MEMORY=4MB zstd -q -t --memory=8MB w8M.zst
ZSTD_MEMORY=4MB zstd -q -t --long=23 w8M.zst
ZSTD_MEMORY=1GiB zstd -q -t --memory=128MB w256M.zst && die "--memory should override ZSTD_MEMORY"

println "+ invalid values are ignored, 0 means default"
ZSTD_MEMORY=abc zstd -t w8M.zst
ZSTD_MEMORY=4XB zstd -t w8M.zst
ZSTD_MEMORY=5GB zstd -t w8M.zst
ZSTD_MEMORY=0 zstd -t w8M.zst
