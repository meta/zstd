#!/bin/sh

set -e

# Test --adapt
zstd -f file --adapt -c | zstd -t

# Out-of-range bounds are clamped to the supported levels, as with -# and --fast=#
zstd -f file --adapt=min=-200000 -c | zstd -t
zstd -f file --adapt=max=-200000 -c | zstd -t
zstd -f file --adapt=min=200000 -c | zstd -t
zstd -f file --adapt=min=-200000,max=-200000 -c | zstd -t
zstd -f file --adapt=min=1,max=200000 -c | zstd -t
zstd -f file --adapt=min=200000,max=200000 -c | zstd -t

# Values beyond int are rejected, instead of wrapping into negative levels
zstd -f file --adapt=max=3000000000 -c > /dev/null && die "--adapt=max=3000000000 should be rejected"

datagen -g100M > file100M

# Pick parameters to force fast adaptation, even on slow systems
zstd --adapt -vvvv -19 --zstd=wlog=10 file100M -o /dev/null 2>&1 | grep -q "faster speed , lighter compression"

# Adaption still happens with --no-progress
zstd --no-progress --adapt -vvvv -19 --zstd=wlog=10 file100M -o /dev/null 2>&1 | grep -q "faster speed , lighter compression"
