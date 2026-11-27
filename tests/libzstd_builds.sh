#!/bin/sh -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ECHO=echo
RM="rm -f"
GREP="grep"
INTOVOID="/dev/null"

die() {
    $ECHO "$@" 1>&2
    exit 1
}

isPresent() {
    $GREP $@ tmplog || die "$@" "should be present"
}

mustBeAbsent() {
    $GREP $@ tmplog && die "$@ should not be there !!"
    $ECHO "$@ correctly not present"  # for some reason, this $ECHO must exist, otherwise mustBeAbsent() always fails (??)
}

# default compilation : all features enabled - no zbuff, no legacy
$ECHO "testing default library compilation"
CFLAGS= make -C $DIR/../lib libzstd libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
isPresent "zstd_compress.o"
isPresent "zstd_decompress.o"
isPresent "zdict.o"
mustBeAbsent "zstd_v07.o"
mustBeAbsent "zbuff_compress.o"
$RM tmplog

# Check that the exec-stack bit isn't set
readelf -lW $DIR/../lib/libzstd.so | $GREP "GNU_STACK" > tmplog
mustBeAbsent "RWE"
$RM $DIR/../lib/libzstd.a $DIR/../lib/libzstd.so* tmplog

# compression disabled => also disable zdict
$ECHO "testing with compression disabled"
ZSTD_LIB_COMPRESSION=0 CFLAGS= make -C $DIR/../lib libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
mustBeAbsent "zstd_compress.o"
isPresent "zstd_decompress.o"
mustBeAbsent "zdict.o"
mustBeAbsent "zstd_v07.o"
mustBeAbsent "zbuff_compress.o"
$RM $DIR/../lib/libzstd.a tmplog

# decompression disabled => also disable legacy
$ECHO "testing with decompression disabled"
ZSTD_LIB_DECOMPRESSION=0 CFLAGS= make -C $DIR/../lib libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
isPresent "zstd_compress.o"
mustBeAbsent "zstd_decompress.o"
isPresent "zdict.o"
mustBeAbsent "zstd_v07.o"
mustBeAbsent "zbuff_compress.o"
$RM $DIR/../lib/libzstd.a tmplog

# deprecated function disabled => only remove zbuff
$ECHO "testing with deprecated functions disabled"
ZSTD_LIB_DEPRECATED=0 CFLAGS= make -C $DIR/../lib libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
isPresent "zstd_compress.o"
isPresent "zstd_decompress.o"
isPresent "zdict.o"
mustBeAbsent "zstd_v07.o"
mustBeAbsent "zbuff_compress.o"
$RM $DIR/../lib/libzstd.a tmplog

# deprecated function enabled => zbuff present
$ECHO "testing with deprecated functions enabled"
ZSTD_LIB_DEPRECATED=1 CFLAGS= make -C $DIR/../lib libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
isPresent "zstd_compress.o"
isPresent "zstd_decompress.o"
isPresent "zdict.o"
mustBeAbsent "zstd_v07.o"
isPresent "zbuff_compress.o"
$RM $DIR/../lib/libzstd.a tmplog

# dictionary builder disabled => only remove zdict
$ECHO "testing with dictionary builder disabled"
ZSTD_LIB_DICTBUILDER=0 CFLAGS= make -C $DIR/../lib libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
isPresent "zstd_compress.o"
isPresent "zstd_decompress.o"
mustBeAbsent "zdict.o"
mustBeAbsent "zstd_v07.o"
mustBeAbsent "zbuff_compress.o"
$RM $DIR/../lib/libzstd.a tmplog

# both decompression and dictionary builder disabled => only compression remains
$ECHO "testing with both decompression and dictionary builder disabled (only compression remains)"
ZSTD_LIB_DECOMPRESSION=0 ZSTD_LIB_DICTBUILDER=0 CFLAGS= make -C $DIR/../lib libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
isPresent "zstd_compress.o"
mustBeAbsent "zstd_decompress.o"
mustBeAbsent "zdict.o"
mustBeAbsent "zstd_v07.o"
mustBeAbsent "zbuff_compress.o"
$RM $DIR/../lib/libzstd.a tmplog

# legacy support explicitly enabled
$ECHO "testing with legacy support explicitly enabled"
ZSTD_LEGACY_SUPPORT=5 CFLAGS= make -C $DIR/../lib libzstd.a > $INTOVOID
nm $DIR/../lib/libzstd.a | $GREP "\.o" > tmplog
isPresent "zstd_compress.o"
isPresent "zstd_decompress.o"
isPresent "zdict.o"
isPresent "zstd_v07.o"
mustBeAbsent "zbuff_compress.o"
$RM $DIR/../lib/libzstd.a tmplog

# exported symbols : the whole API by default,
# only the stable API when the experimental API is hidden.
# The API comes from the headers : -aux-info (GCC) lists their function declarations.
$ECHO "testing exported symbols"
printf '#include "zstd.h"\n#include "zdict.h"\n#include "zstd_errors.h"\n' > tmpapi.c
listDeclared() {
    ${CC:-cc} -I$DIR/../lib "$@" -fsyntax-only -aux-info tmpaux tmpapi.c
    sed -n 's/^\/\*[^*]*\*\/ //; s/ (.*//; s/.*[ *]//p' tmpaux | $GREP -E '^(ZSTD|ZDICT)_' | LC_ALL=C sort -u
}
listExported() {
    nm -D --defined-only $DIR/../lib/libzstd.so.*.*.* | awk '{ print $NF }' | LC_ALL=C sort -u
}
listDeclared > tmpstable
listDeclared -DZSTD_STATIC_LINKING_ONLY -DZDICT_STATIC_LINKING_ONLY > tmpall
CFLAGS= make -C $DIR/../lib libzstd > $INTOVOID
listExported > tmpexported
diff tmpall tmpexported || die "libzstd.so should export the whole API"
$RM $DIR/../lib/libzstd.so*
CFLAGS= make -C $DIR/../lib libzstd MOREFLAGS="-DZSTDLIB_STATIC_API=ZSTDLIB_HIDDEN -DZDICTLIB_STATIC_API=ZDICTLIB_HIDDEN" > $INTOVOID
listExported > tmpexported
diff tmpstable tmpexported || die "with the experimental API hidden, libzstd.so should export only the stable API"
$RM $DIR/../lib/libzstd.so* tmpapi.c tmpaux tmpstable tmpall tmpexported
