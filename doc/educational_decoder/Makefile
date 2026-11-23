# ################################################################
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under both the BSD-style license (found in the
# LICENSE file in the root directory of this source tree) and the GPLv2 (found
# in the COPYING file in the root directory of this source tree).
# You may select, at your option, one of the above-listed licenses.
# ################################################################

ZSTD ?= zstd   # note: requires zstd installation on local system

UNAME?= $(shell sh -c 'MSYSTEM="MSYS" uname') 
ifeq ($(UNAME), SunOS)
DIFF ?= gdiff
else
DIFF ?= diff
endif

HARNESS_FILES=harness.c zstd_decompress.c

MULTITHREAD_LDFLAGS = -pthread
DEBUGFLAGS= -g -DZSTD_DEBUG=1
CPPFLAGS += -I$(ZSTDDIR) -I$(ZSTDDIR)/common -I$(ZSTDDIR)/compress \
            -I$(ZSTDDIR)/dictBuilder -I$(ZSTDDIR)/deprecated -I$(PRGDIR)
CFLAGS   ?= -O2
CFLAGS   += -Wall -Wextra -Wcast-qual -Wcast-align -Wshadow                 \
            -Wstrict-aliasing=1 -Wswitch-enum                               \
            -Wredundant-decls -Wstrict-prototypes -Wundef                   \
            -Wvla -Wformat=2 -Winit-self -Wfloat-equal -Wwrite-strings      \
            -std=c99
CFLAGS   += $(DEBUGFLAGS)
CFLAGS   += $(MOREFLAGS)
FLAGS     = $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(MULTITHREAD_LDFLAGS)

harness: $(HARNESS_FILES)
	$(CC) $(FLAGS) $^ -o $@

.PHONY: clean test test-unit

unit_tests: unit_tests.c zstd_decompress.c zstd_decompress.h
	$(CC) $(FLAGS) $< -o $@

test-unit: unit_tests
	@./unit_tests valid
	# Rejected inputs exit(1) without unwinding their allocations.
	@set -eu; \
	for case in $$(./unit_tests --list); do \
		edu_expected=$$(./unit_tests --expect "$$case"); \
		edu_status=0; \
		edu_actual=$$(ASAN_OPTIONS="$${ASAN_OPTIONS:+$${ASAN_OPTIONS}:}detect_leaks=0" \
			./unit_tests "$$case" 2>&1) || edu_status=$$?; \
		if test "$$edu_status" -ne 1 || test "$$edu_actual" != "$$edu_expected"; then \
			printf '%s\n' "$$case: expected rejection, got status $$edu_status" "$$edu_actual"; \
			exit 1; \
		fi; \
	done; \
	printf '%s\n' 'Educational decoder unit tests passed'

clean:
	@$(RM) harness unit_tests *.o
	@$(RM) -rf harness.dSYM  # MacOS specific

test: harness test-unit
	#
	# Testing single-file decompression with educational decoder
	#
	@$(ZSTD) -f README.md -o tmp.zst
	@./harness tmp.zst tmp
	@$(DIFF) -s tmp README.md
	@$(RM) tmp*
	#
	# Testing dictionary decompression with education decoder
	#
	# note : files are presented multiple for training, to reach minimum threshold
	@$(ZSTD) --train harness.c zstd_decompress.c zstd_decompress.h README.md \
                  harness.c zstd_decompress.c zstd_decompress.h README.md \
                  harness.c zstd_decompress.c zstd_decompress.h README.md \
                  -o dictionary
	@$(ZSTD) -f README.md -D dictionary -o tmp.zst
	@./harness tmp.zst tmp dictionary
	@$(DIFF) -s tmp README.md
	@$(RM) tmp* dictionary
