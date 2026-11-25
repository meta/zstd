// Uses the static-only API of zstd.h and zdict.h through the libzstd module.
import libzstd

let src = Array(repeating: UInt8(ascii: "z"), count: 1000)
var dst = [UInt8](repeating: 0, count: ZSTD_compressBound(src.count))
let cSize = ZSTD_compress(&dst, dst.count, src, src.count, 1)
precondition(ZSTD_isError(cSize) == 0)

// zstd.h
precondition(ZSTD_isFrame(dst, cSize) == 1)
precondition(ZSTD_findDecompressedSize(dst, cSize) == UInt64(src.count))

// zdict.h: a single sample is not enough to train
var params = ZDICT_cover_params_t()
params.k = 64
params.d = 8
var dict = [UInt8](repeating: 0, count: 1024)
let dictSize = ZDICT_trainFromBuffer_cover(&dict, dict.count, src, [src.count], 1, params)
precondition(ZDICT_isError(dictSize) != 0)

print("static-only API: ok")
