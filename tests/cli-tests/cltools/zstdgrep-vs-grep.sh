#!/bin/sh

set -e

# zstdgrep on compressed files must behave like grep on the original files:
# same output, same exit status.
# plain/ holds the original files, compressed/ the same names, compressed.

mkdir plain compressed
printf 'start\nmiddle\nstop\nStart again\n-dash line\nwith space\nit'"'"'s quoted\n' > plain/a
printf 'nothing here\nstop\n' > plain/b
printf 'start\n' > "plain/c d"
awk 'BEGIN { for (i = 0; i < 100000; i++) print "line " i }' > plain/big
for f in a b "c d" big; do zstd -q -c "plain/$f" > "compressed/$f"; done
printf 'start\n' > plain/pats
printf 'start\nstop\n' > "plain/my pats"
cp plain/pats "plain/my pats" compressed/

# compare INPUT ARGS... : INPUT, if not empty, is the standard input
compare() {
    input=$1; shift
    expected_status=0
    actual_status=0
    if [ -n "$input" ]; then
        (cd plain && grep "$@" < "$input") > expected 2>/dev/null || expected_status=$?
        (cd compressed && zstdgrep "$@" < "$input") > actual 2>/dev/null || actual_status=$?
    else
        (cd plain && grep "$@") > expected 2>/dev/null || expected_status=$?
        (cd compressed && zstdgrep "$@") > actual 2>/dev/null || actual_status=$?
    fi
    [ "$actual_status" -eq "$expected_status" ] || die "zstdgrep $*: exit status $actual_status, grep gives $expected_status"
    cmp -s expected actual || die "zstdgrep $*: output differs from grep"
}
check() { compare "" "$@"; }
check_stdin() { compare "$@"; }

println "+ patterns"
check start a
check start a b
check -e start -e stop a b
check --regexp=start --regexp=stop a b
check --regexp start --regexp stop a b
check --regexp start --regexp=stop -e Start a
check --reg start a
check -f pats a b
check -f "my pats" a b
check --file="my pats" a b
check -f pats -e middle a
check -e -dash a
check -- -dash a
check "with space" a "c d"
check "it's" a
check '' b
check -e '' b
check start a -n

println "+ patterns from standard input"
check_stdin pats -f - a b
check_stdin pats --file=- a b
(cd plain && cat pats | grep -f /dev/stdin a b) > expected
(cd compressed && cat pats | zstdgrep -f /dev/stdin a b) > actual
cmp -s expected actual || die "zstdgrep -f /dev/stdin: output differs from grep"

println "+ data from standard input"
check_stdin a start
check_stdin a -H start
check_stdin a start - b

println "+ options taking a value"
check -A1 start a
check -A 1 start a
check -iA1 start a
check -iA 1 START a
check -C 1 middle a
check -1 middle a
# not --context 1 : the BSD grep of macOS reads a value for --context only after '='
check --context=1 middle a
check --cont=1 middle a
check -m1 -e s a
check --max-count 1 -e s a
check -m1 line big
check --label=x start a b

println "+ output options"
check -c start a b
check -l start a b
check -L start a b
check -n start a b
check -h start a b
check -H start a
check -o tar a
check -v start a b
check -w start a
check -x stop a b
check -i start a
check -E 'start|stop' a
check -F 'it'"'"'s' a
check -lZ start a b
check -c line big

println "+ exit status"
check zzz a b
check stop a b
check 'a[' a b
check start a missing
check zzz a missing
check start missing
check -q start a missing
check -q zzz a missing
check -s start a missing
check -q line big a

println "+ unsupported options"
for opt in -r -R -ir --recursive --directories=recurse "--include=*" "--exclude=*"; do
    status=0
    (cd compressed && zstdgrep $opt start a) > /dev/null 2>&1 || status=$?
    [ "$status" -eq 2 ] || die "zstdgrep $opt: exit status $status, expected 2"
done
