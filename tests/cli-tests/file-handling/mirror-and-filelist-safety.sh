#!/bin/sh
set -e

# 1. Root mirror output directory must not underflow when computing output filename
zstd -q --output-dir-mirror=/ nonexistent_zstd_mirror_input 2>/dev/null && die "nonexistent input with root mirror dir should fail"

# 2. Empty line in --filelist with --output-dir-mirror must not abort
printf "\n" > empty_line.list
zstd -q --output-dir-mirror=mirror_empty --filelist=empty_line.list 2>/dev/null && die "empty filename in filelist should fail"

# 3. Entries longer than 2 * LIST_SIZE_INCREASE (16 KB) must not be silently dropped under -r
awk "BEGIN { for (i = 0; i < 17000; i++) printf \"a\"; printf \"\n\" }" > long_name.list
zstd -q -r --filelist=long_name.list -t 2>/dev/null && die "overlong entry in recursive filelist must not silently succeed"

# 4. Recursive expansion exceeding initial 8 KB buffer must preserve all files
mkdir -p deep_src/sub_directory_alpha_beta_gamma_delta_epsilon_zeta_eta_theta
i=1
while [ "$i" -le 220 ]; do
    printf "payload_%d\n" "$i" > "deep_src/sub_directory_alpha_beta_gamma_delta_epsilon_zeta_eta_theta/sample_file_number_${i}_extra_padding_chars.txt"
    i=$((i + 1))
done
zstd -q -r --output-dir-mirror mirror_out deep_src
zstd -q -d -r --output-dir-mirror mirror_dec mirror_out/deep_src
diff --brief --recursive --new-file deep_src mirror_dec/mirror_out/deep_src

# 5. Repeated leading "./" normalization works and ".." traversal is rejected
mkdir -p norm_src norm_out
printf "ok\n" > norm_src/sample.txt
zstd -q --output-dir-mirror norm_out ././norm_src/sample.txt
test -f norm_out/norm_src/sample.txt.zst
zstd -q --output-dir-mirror norm_reject ../norm_src/sample.txt 2>/dev/null && die "parent traversal should be rejected"
test ! -d norm_reject

exit 0
