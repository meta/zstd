/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#include "../common/portability_macros.h"

#if defined(__ELF__) && defined(__GNUC__)
/* Stack marking
 * ref: https://wiki.gentoo.org/wiki/Hardened/GNU_stack_quickstart
 */
.section .note.GNU-stack,"",%progbits

#if defined(__aarch64__)
/* Mark that this assembly supports BTI & PAC, because it is empty for aarch64.
 * See: https://github.com/facebook/zstd/issues/3841
 * See: https://gcc.godbolt.org/z/sqr5T4ffK
 * See: https://lore.kernel.org/linux-arm-kernel/20200429211641.9279-8-broonie@kernel.org/
 * See: https://reviews.llvm.org/D62609
 */
.pushsection .note.gnu.property, "a"
.p2align 3
.long 4                 /* size of the name - "GNU\0" */
.long 0x10              /* size of descriptor */
.long 0x5               /* NT_GNU_PROPERTY_TYPE_0 */
.asciz "GNU"
.long 0xc0000000        /* pr_type - GNU_PROPERTY_AARCH64_FEATURE_1_AND */
.long 4                 /* pr_datasz - 4 bytes */
.long 3                 /* pr_data - GNU_PROPERTY_AARCH64_FEATURE_1_BTI | GNU_PROPERTY_AARCH64_FEATURE_1_PAC */
.p2align 3              /* pr_padding - bring everything to 8 byte alignment */
.popsection
#endif

#endif

// There appears to be an unreconcilable syntax difference between Linux and Darwin assemblers.
// Name of a private label (i.e. not exported to symbol table) on Darwin has to start with "L",
// on Linux has to start with ".". There's no way to have a name start with both "." and "L", so
// we have to use a macro.
#if defined(__APPLE__)
#define LOCAL_LABEL(label) L_ ## label
#else
#define LOCAL_LABEL(label) .L_ ## label
#endif

#if ZSTD_ENABLE_ASM_X86_64_BMI2

/* Calling convention:
 *
 * %rdi (or %rcx on Windows) contains the first argument: HUF_DecompressAsmArgs*.
 * %rbp isn't maintained (no frame pointer).
 * %rsp contains the stack pointer that grows down.
 *      No red-zone is assumed, only addresses >= %rsp are used.
 * All register contents are preserved.
 */

ZSTD_HIDE_ASM_FUNCTION(HUF_decompress4X1_usingDTable_internal_fast_asm_loop)
ZSTD_HIDE_ASM_FUNCTION(HUF_decompress4X2_usingDTable_internal_fast_asm_loop)
ZSTD_HIDE_ASM_FUNCTION(_HUF_decompress4X2_usingDTable_internal_fast_asm_loop)
ZSTD_HIDE_ASM_FUNCTION(_HUF_decompress4X1_usingDTable_internal_fast_asm_loop)
.global HUF_decompress4X1_usingDTable_internal_fast_asm_loop
.global HUF_decompress4X2_usingDTable_internal_fast_asm_loop
.global _HUF_decompress4X1_usingDTable_internal_fast_asm_loop
.global _HUF_decompress4X2_usingDTable_internal_fast_asm_loop
.text

/* Sets up register mappings for clarity.
 * op[], bits[], dtable & ip[0] each get their own register.
 * ip[1,2,3] & olimit alias var[].
 * %rax is a scratch register.
 */

#define op0    rsi
#define op1    rbx
#define op2    rcx
#define op3    rdi

#define ip0    r8
#define ip1    r9
#define ip2    r10
#define ip3    r11

#define bits0  rbp
#define bits1  rdx
#define bits2  r12
#define bits3  r13
#define dtable r14
#define olimit r15

/* var[] aliases ip[1,2,3] & olimit
 * ip[1,2,3] are saved every iteration.
 * olimit is only used in compute_olimit.
 */
#define var0   r15
#define var1   r9
#define var2   r10
#define var3   r11

/* 32-bit var registers */
#define vard0  r15d
#define vard1  r9d
#define vard2  r10d
#define vard3  r11d

/* Calls X(N) for each stream 0, 1, 2, 3. */
#define FOR_EACH_STREAM(X) \
    X(0);                  \
    X(1);                  \
    X(2);                  \
    X(3)

/* Calls X(N, idx) for each stream 0, 1, 2, 3. */
#define FOR_EACH_STREAM_WITH_INDEX(X, idx) \
    X(0, idx);                             \
    X(1, idx);                             \
    X(2, idx);                             \
    X(3, idx)

/* Define both _HUF_* & HUF_* symbols because MacOS
 * C symbols are prefixed with '_' & Linux symbols aren't.
 */
_HUF_decompress4X1_usingDTable_internal_fast_asm_loop:
HUF_decompress4X1_usingDTable_internal_fast_asm_loop:
    ZSTD_CET_ENDBRANCH
    .cfi_startproc
    .cfi_def_cfa_offset 8
    .cfi_offset %rip, -8
    /* Save all registers - even if they are callee saved for simplicity. */
    push %rax
    .cfi_def_cfa_offset 16
    .cfi_offset rax, -16
    push %rbx
    .cfi_def_cfa_offset 24
    .cfi_offset rbx, -24
    push %rcx
    .cfi_def_cfa_offset 32
    .cfi_offset rcx, -32
    push %rdx
    .cfi_def_cfa_offset 40
    .cfi_offset rdx, -40
    push %rbp
    .cfi_def_cfa_offset 48
    .cfi_offset rbp, -48
    push %rsi
    .cfi_def_cfa_offset 56
    .cfi_offset rsi, -56
    push %rdi
    .cfi_def_cfa_offset 64
    .cfi_offset rdi, -64
    push %r8
    .cfi_def_cfa_offset 72
    .cfi_offset r8, -72
    push %r9
    .cfi_def_cfa_offset 80
    .cfi_offset r9, -80
    push %r10
    .cfi_def_cfa_offset 88
    .cfi_offset r10, -88
    push %r11
    .cfi_def_cfa_offset 96
    .cfi_offset r11, -96
    push %r12
    .cfi_def_cfa_offset 104
    .cfi_offset r12, -104
    push %r13
    .cfi_def_cfa_offset 112
    .cfi_offset r13, -112
    push %r14
    .cfi_def_cfa_offset 120
    .cfi_offset r14, -120
    push %r15
    .cfi_def_cfa_offset 128
    .cfi_offset r15, -128

    /* Read HUF_DecompressAsmArgs* args from %rax */
#if defined(_WIN32)
    movq %rcx, %rax
#else
    movq %rdi, %rax
#endif
    movq  0(%rax), %ip0
    movq  8(%rax), %ip1
    movq 16(%rax), %ip2
    movq 24(%rax), %ip3
    movq 32(%rax), %op0
    movq 40(%rax), %op1
    movq 48(%rax), %op2
    movq 56(%rax), %op3
    movq 64(%rax), %bits0
    movq 72(%rax), %bits1
    movq 80(%rax), %bits2
    movq 88(%rax), %bits3
    movq 96(%rax), %dtable
    push %rax      /* argument */
    .cfi_def_cfa_offset 136
    push 104(%rax) /* ilowest */
    .cfi_def_cfa_offset 144
    push 112(%rax) /* oend */
    .cfi_def_cfa_offset 152
    push %olimit   /* olimit space */
    .cfi_def_cfa_offset 160

    subq $24, %rsp
    .cfi_def_cfa_offset 184

LOCAL_LABEL(4X1_compute_olimit):
    /* Computes how many iterations we can do safely
     * %r15, %rax may be clobbered
     * rbx, rdx must be saved
     * op3 & ip0 mustn't be clobbered
     */
    movq %rbx, 0(%rsp)
    movq %rdx, 8(%rsp)

    movq 32(%rsp), %rax /* rax = oend */
    subq %op3,    %rax  /* rax = oend - op3 */

    /* r15 = (oend - op3) / 5 */
    movabsq $-3689348814741910323, %rdx
    mulq %rdx
    movq %rdx, %r15
    shrq $2, %r15

    movq %ip0,     %rax /* rax = ip0 */
    movq 40(%rsp), %rdx /* rdx = ilowest */
    subq %rdx,     %rax /* rax = ip0 - ilowest */
    movq %rax,     %rbx /* rbx = ip0 - ilowest */

    /* rdx = (ip0 - ilowest) / 7 */
    movabsq $2635249153387078803, %rdx
    mulq %rdx
    subq %rdx, %rbx
    shrq %rbx
    addq %rbx, %rdx
    shrq $2, %rdx

    /* r15 = min(%rdx, %r15) */
    cmpq %rdx, %r15
    cmova %rdx, %r15

    /* r15 = r15 * 5 */
    leaq (%r15, %r15, 4), %r15

    /* olimit = op3 + r15 */
    addq %op3, %olimit

    movq 8(%rsp), %rdx
    movq 0(%rsp), %rbx

    /* If (op3 + 20 > olimit) */
    movq %op3, %rax    /* rax = op3 */
    cmpq %rax, %olimit /* op3 == olimit */
    je LOCAL_LABEL(4X1_exit)

    /* If (ip1 < ip0) go to exit */
    cmpq %ip0, %ip1
    jb LOCAL_LABEL(4X1_exit)

    /* If (ip2 < ip1) go to exit */
    cmpq %ip1, %ip2
    jb LOCAL_LABEL(4X1_exit)

    /* If (ip3 < ip2) go to exit */
    cmpq %ip2, %ip3
    jb LOCAL_LABEL(4X1_exit)

/* Reads top 11 bits from bits[n]
 * Loads dt[bits[n]] into var[n]
 */
#define GET_NEXT_DELT(n)                \
    movq $53, %var##n;                  \
    shrxq %var##n, %bits##n, %var##n;   \
    movzwl (%dtable,%var##n,2),%vard##n

/* var[n] must contain the DTable entry computed with GET_NEXT_DELT
 * Moves var[n] to %rax
 * bits[n] <<= var[n] & 63
 * op[n][idx] = %rax >> 8
 * %ah is a way to access bits [8, 16) of %rax
 */
#define DECODE_FROM_DELT(n, idx)       \
    movq %var##n, %rax;                \
    shlxq %var##n, %bits##n, %bits##n; \
    movb %ah, idx(%op##n)

/* Assumes GET_NEXT_DELT has been called.
 * Calls DECODE_FROM_DELT then GET_NEXT_DELT
 */
#define DECODE_AND_GET_NEXT(n, idx) \
    DECODE_FROM_DELT(n, idx);       \
    GET_NEXT_DELT(n)                \

/* // ctz & nbBytes is stored in bits[n]
 * // nbBits is stored in %rax
 * ctz  = CTZ[bits[n]]
 * nbBits  = ctz & 7
 * nbBytes = ctz >> 3
 * op[n]  += 5
 * ip[n]  -= nbBytes
 * // Note: x86-64 is little-endian ==> no bswap
 * bits[n] = MEM_readST(ip[n]) | 1
 * bits[n] <<= nbBits
 */
#define RELOAD_BITS(n)             \
    bsfq %bits##n, %bits##n;       \
    movq %bits##n, %rax;           \
    andq $7, %rax;                 \
    shrq $3, %bits##n;             \
    leaq 5(%op##n), %op##n;        \
    subq %bits##n, %ip##n;         \
    movq (%ip##n), %bits##n;       \
    orq $1, %bits##n;              \
    shlx %rax, %bits##n, %bits##n

    /* Store clobbered variables on the stack */
    movq %olimit, 24(%rsp)
    movq %ip1, 0(%rsp)
    movq %ip2, 8(%rsp)
    movq %ip3, 16(%rsp)

    /* Call GET_NEXT_DELT for each stream */
    FOR_EACH_STREAM(GET_NEXT_DELT)

    .p2align 6

LOCAL_LABEL(4X1_loop_body):
    /* Decode 5 symbols in each of the 4 streams (20 total)
     * Must have called GET_NEXT_DELT for each stream
     */
    FOR_EACH_STREAM_WITH_INDEX(DECODE_AND_GET_NEXT, 0)
    FOR_EACH_STREAM_WITH_INDEX(DECODE_AND_GET_NEXT, 1)
    FOR_EACH_STREAM_WITH_INDEX(DECODE_AND_GET_NEXT, 2)
    FOR_EACH_STREAM_WITH_INDEX(DECODE_AND_GET_NEXT, 3)
    FOR_EACH_STREAM_WITH_INDEX(DECODE_FROM_DELT, 4)

    /* Load ip[1,2,3] from stack (var[] aliases them)
     * ip[] is needed for RELOAD_BITS
     * Each will be stored back to the stack after RELOAD
     */
    movq 0(%rsp), %ip1
    movq 8(%rsp), %ip2
    movq 16(%rsp), %ip3

    /* Reload each stream & fetch the next table entry
     * to prepare for the next iteration
     */
    RELOAD_BITS(0)
    GET_NEXT_DELT(0)

    RELOAD_BITS(1)
    movq %ip1, 0(%rsp)
    GET_NEXT_DELT(1)

    RELOAD_BITS(2)
    movq %ip2, 8(%rsp)
    GET_NEXT_DELT(2)

    RELOAD_BITS(3)
    movq %ip3, 16(%rsp)
    GET_NEXT_DELT(3)

    /* If op3 < olimit: continue the loop */
    cmp %op3, 24(%rsp)
    ja LOCAL_LABEL(4X1_loop_body)

    /* Reload ip[1,2,3] from stack */
    movq 0(%rsp), %ip1
    movq 8(%rsp), %ip2
    movq 16(%rsp), %ip3

    /* Re-compute olimit */
    jmp LOCAL_LABEL(4X1_compute_olimit)

#undef GET_NEXT_DELT
#undef DECODE_FROM_DELT
#undef DECODE
#undef RELOAD_BITS
LOCAL_LABEL(4X1_exit):
    addq $24, %rsp
    .cfi_def_cfa_offset 160

    /* Restore stack (oend & olimit) */
    pop %rax /* olimit */
    .cfi_def_cfa_offset 152
    pop %rax /* oend */
    .cfi_def_cfa_offset 144
    pop %rax /* ilowest */
    .cfi_def_cfa_offset 136
    pop %rax /* arg */
    .cfi_def_cfa_offset 128

    /* Save ip / op / bits */
    movq %ip0,  0(%rax)
    movq %ip1,  8(%rax)
    movq %ip2, 16(%rax)
    movq %ip3, 24(%rax)
    movq %op0, 32(%rax)
    movq %op1, 40(%rax)
    movq %op2, 48(%rax)
    movq %op3, 56(%rax)
    movq %bits0, 64(%rax)
    movq %bits1, 72(%rax)
    movq %bits2, 80(%rax)
    movq %bits3, 88(%rax)

    /* Restore registers */
    pop %r15
    .cfi_restore r15
    .cfi_def_cfa_offset 120
    pop %r14
    .cfi_restore r14
    .cfi_def_cfa_offset 112
    pop %r13
    .cfi_restore r13
    .cfi_def_cfa_offset 104
    pop %r12
    .cfi_restore r12
    .cfi_def_cfa_offset 96
    pop %r11
    .cfi_restore r11
    .cfi_def_cfa_offset 88
    pop %r10
    .cfi_restore r10
    .cfi_def_cfa_offset 80
    pop %r9
    .cfi_restore r9
    .cfi_def_cfa_offset 72
    pop %r8
    .cfi_restore r8
    .cfi_def_cfa_offset 64
    pop %rdi
    .cfi_restore rdi
    .cfi_def_cfa_offset 56
    pop %rsi
    .cfi_restore rsi
    .cfi_def_cfa_offset 48
    pop %rbp
    .cfi_restore rbp
    .cfi_def_cfa_offset 40
    pop %rdx
    .cfi_restore rdx
    .cfi_def_cfa_offset 32
    pop %rcx
    .cfi_restore rcx
    .cfi_def_cfa_offset 24
    pop %rbx
    .cfi_restore rbx
    .cfi_def_cfa_offset 16
    pop %rax
    .cfi_restore rax
    .cfi_def_cfa_offset 8
    ret
    .cfi_endproc

_HUF_decompress4X2_usingDTable_internal_fast_asm_loop:
HUF_decompress4X2_usingDTable_internal_fast_asm_loop:
    ZSTD_CET_ENDBRANCH
    .cfi_startproc
    .cfi_def_cfa_offset 8
    .cfi_offset %rip, -8
    /* Save all registers - even if they are callee saved for simplicity. */
    push %rax
    .cfi_def_cfa_offset 16
    .cfi_offset rax, -16
    push %rbx
    .cfi_def_cfa_offset 24
    .cfi_offset rbx, -24
    push %rcx
    .cfi_def_cfa_offset 32
    .cfi_offset rcx, -32
    push %rdx
    .cfi_def_cfa_offset 40
    .cfi_offset rdx, -40
    push %rbp
    .cfi_def_cfa_offset 48
    .cfi_offset rbp, -48
    push %rsi
    .cfi_def_cfa_offset 56
    .cfi_offset rsi, -56
    push %rdi
    .cfi_def_cfa_offset 64
    .cfi_offset rdi, -64
    push %r8
    .cfi_def_cfa_offset 72
    .cfi_offset r8, -72
    push %r9
    .cfi_def_cfa_offset 80
    .cfi_offset r9, -80
    push %r10
    .cfi_def_cfa_offset 88
    .cfi_offset r10, -88
    push %r11
    .cfi_def_cfa_offset 96
    .cfi_offset r11, -96
    push %r12
    .cfi_def_cfa_offset 104
    .cfi_offset r12, -104
    push %r13
    .cfi_def_cfa_offset 112
    .cfi_offset r13, -112
    push %r14
    .cfi_def_cfa_offset 120
    .cfi_offset r14, -120
    push %r15
    .cfi_def_cfa_offset 128
    .cfi_offset r15, -128

    /* Read HUF_DecompressAsmArgs* args from %rax */
#if defined(_WIN32)
    movq %rcx, %rax
#else
    movq %rdi, %rax
#endif
    movq  0(%rax), %ip0
    movq  8(%rax), %ip1
    movq 16(%rax), %ip2
    movq 24(%rax), %ip3
    movq 32(%rax), %op0
    movq 40(%rax), %op1
    movq 48(%rax), %op2
    movq 56(%rax), %op3
    movq 64(%rax), %bits0
    movq 72(%rax), %bits1
    movq 80(%rax), %bits2
    movq 88(%rax), %bits3
    movq 96(%rax), %dtable
    push %rax      /* argument */
    .cfi_def_cfa_offset 136
    push %rax      /* olimit */
    .cfi_def_cfa_offset 144
    push 104(%rax) /* ilowest */
    .cfi_def_cfa_offset 152

    movq 112(%rax), %rax
    push %rax /* oend3 */
    .cfi_def_cfa_offset 160

    movq %op3, %rax
    push %rax /* oend2 */
    .cfi_def_cfa_offset 168

    movq %op2, %rax
    push %rax /* oend1 */
    .cfi_def_cfa_offset 176

    movq %op1, %rax
    push %rax /* oend0 */
    .cfi_def_cfa_offset 184

    /* Scratch space */
    subq $8, %rsp
    .cfi_def_cfa_offset 192

LOCAL_LABEL(4X2_compute_olimit):
    /* Computes how many iterations we can do safely
     * %r15, %rax may be clobbered
     * rdx must be saved
     * op[1,2,3,4] & ip0 mustn't be clobbered
     */
    movq %rdx, 0(%rsp)

    /* We can consume up to 7 input bytes each iteration. */
    movq %ip0,     %rax  /* rax = ip0 */
    movq 40(%rsp), %rdx  /* rdx = ilowest */
    subq %rdx,     %rax  /* rax = ip0 - ilowest */
    movq %rax,    %r15   /* r15 = ip0 - ilowest */

    /* rdx = rax / 7 */
    movabsq $2635249153387078803, %rdx
    mulq %rdx
    subq %rdx, %r15
    shrq %r15
    addq %r15, %rdx
    shrq $2, %rdx

    /* r15 = (ip0 - ilowest) / 7 */
    movq %rdx, %r15

    /* r15 = min(r15, min(oend0 - op0, oend1 - op1, oend2 - op2, oend3 - op3) / 10) */
    movq 8(%rsp),  %rax /* rax = oend0 */
    subq %op0,     %rax /* rax = oend0 - op0 */
    movq 16(%rsp), %rdx /* rdx = oend1 */
    subq %op1,     %rdx /* rdx = oend1 - op1 */

    cmpq  %rax,    %rdx
    cmova %rax,    %rdx /* rdx = min(%rdx, %rax) */

    movq 24(%rsp), %rax /* rax = oend2 */
    subq %op2,     %rax /* rax = oend2 - op2 */

    cmpq  %rax,    %rdx
    cmova %rax,    %rdx /* rdx = min(%rdx, %rax) */

    movq 32(%rsp), %rax /* rax = oend3 */
    subq %op3,     %rax /* rax = oend3 - op3 */

    cmpq  %rax,    %rdx
    cmova %rax,    %rdx /* rdx = min(%rdx, %rax) */

    movabsq $-3689348814741910323, %rax
    mulq %rdx
    shrq $3,       %rdx /* rdx = rdx / 10 */

    /* r15 = min(%rdx, %r15) */
    cmpq  %rdx, %r15
    cmova %rdx, %r15

    /* olimit = op3 + 5 * r15 */
    movq %r15, %rax
    leaq (%op3, %rax, 4), %olimit
    addq %rax, %olimit

    movq 0(%rsp), %rdx

    /* If (op3 + 10 > olimit) */
    movq %op3, %rax    /* rax = op3 */
    cmpq %rax, %olimit /* op3 == olimit */
    je LOCAL_LABEL(4X2_exit)

    /* If (ip1 < ip0) go to exit */
    cmpq %ip0, %ip1
    jb LOCAL_LABEL(4X2_exit)

    /* If (ip2 < ip1) go to exit */
    cmpq %ip1, %ip2
    jb LOCAL_LABEL(4X2_exit)

    /* If (ip3 < ip2) go to exit */
    cmpq %ip2, %ip3
    jb LOCAL_LABEL(4X2_exit)

#define DECODE(n, idx)              \
    movq %bits##n, %rax;            \
    shrq $53, %rax;                 \
    movzwl 0(%dtable,%rax,4),%r8d;  \
    movzbl 2(%dtable,%rax,4),%r15d; \
    movzbl 3(%dtable,%rax,4),%eax;  \
    movw %r8w, (%op##n);            \
    shlxq %r15, %bits##n, %bits##n; \
    addq %rax, %op##n

#define RELOAD_BITS(n)              \
    bsfq %bits##n, %bits##n;        \
    movq %bits##n, %rax;            \
    shrq $3, %bits##n;              \
    andq $7, %rax;                  \
    subq %bits##n, %ip##n;          \
    movq (%ip##n), %bits##n;        \
    orq $1, %bits##n;               \
    shlxq %rax, %bits##n, %bits##n


    movq %olimit, 48(%rsp)

    .p2align 6

LOCAL_LABEL(4X2_loop_body):
    /* We clobber r8, so store it on the stack */
    movq %r8, 0(%rsp)

    /* Decode 5 symbols from each of the 4 streams (20 symbols total). */
    FOR_EACH_STREAM_WITH_INDEX(DECODE, 0)
    FOR_EACH_STREAM_WITH_INDEX(DECODE, 1)
    FOR_EACH_STREAM_WITH_INDEX(DECODE, 2)
    FOR_EACH_STREAM_WITH_INDEX(DECODE, 3)
    FOR_EACH_STREAM_WITH_INDEX(DECODE, 4)

    /* Reload r8 */
    movq 0(%rsp), %r8

    FOR_EACH_STREAM(RELOAD_BITS)

    cmp %op3, 48(%rsp)
    ja LOCAL_LABEL(4X2_loop_body)
    jmp LOCAL_LABEL(4X2_compute_olimit)

#undef DECODE
#undef RELOAD_BITS
LOCAL_LABEL(4X2_exit):
    addq $8, %rsp
    .cfi_def_cfa_offset 184
    /* Restore stack (oend & olimit) */
    pop %rax /* oend0 */
    .cfi_def_cfa_offset 176
    pop %rax /* oend1 */
    .cfi_def_cfa_offset 168
    pop %rax /* oend2 */
    .cfi_def_cfa_offset 160
    pop %rax /* oend3 */
    .cfi_def_cfa_offset 152
    pop %rax /* ilowest */
    .cfi_def_cfa_offset 144
    pop %rax /* olimit */
    .cfi_def_cfa_offset 136
    pop %rax /* arg */
    .cfi_def_cfa_offset 128

    /* Save ip / op / bits */
    movq %ip0,  0(%rax)
    movq %ip1,  8(%rax)
    movq %ip2, 16(%rax)
    movq %ip3, 24(%rax)
    movq %op0, 32(%rax)
    movq %op1, 40(%rax)
    movq %op2, 48(%rax)
    movq %op3, 56(%rax)
    movq %bits0, 64(%rax)
    movq %bits1, 72(%rax)
    movq %bits2, 80(%rax)
    movq %bits3, 88(%rax)

    /* Restore registers */
    pop %r15
    .cfi_restore r15
    .cfi_def_cfa_offset 120
    pop %r14
    .cfi_restore r14
    .cfi_def_cfa_offset 112
    pop %r13
    .cfi_restore r13
    .cfi_def_cfa_offset 104
    pop %r12
    .cfi_restore r12
    .cfi_def_cfa_offset 96
    pop %r11
    .cfi_restore r11
    .cfi_def_cfa_offset 88
    pop %r10
    .cfi_restore r10
    .cfi_def_cfa_offset 80
    pop %r9
    .cfi_restore r9
    .cfi_def_cfa_offset 72
    pop %r8
    .cfi_restore r8
    .cfi_def_cfa_offset 64
    pop %rdi
    .cfi_restore rdi
    .cfi_def_cfa_offset 56
    pop %rsi
    .cfi_restore rsi
    .cfi_def_cfa_offset 48
    pop %rbp
    .cfi_restore rbp
    .cfi_def_cfa_offset 40
    pop %rdx
    .cfi_restore rdx
    .cfi_def_cfa_offset 32
    pop %rcx
    .cfi_restore rcx
    .cfi_def_cfa_offset 24
    pop %rbx
    .cfi_restore rbx
    .cfi_def_cfa_offset 16
    pop %rax
    .cfi_restore rax
    .cfi_def_cfa_offset 8
    ret
    .cfi_endproc


/* Undefine the register mappings of the BMI2 version */
#undef op0
#undef op1
#undef op2
#undef op3
#undef ip0
#undef ip1
#undef ip2
#undef ip3
#undef bits0
#undef bits1
#undef bits2
#undef bits3
#undef dtable
#undef olimit
#undef var0
#undef var1
#undef var2
#undef var3
#undef vard0
#undef vard1
#undef vard2
#undef vard3
#undef FOR_EACH_STREAM
#undef FOR_EACH_STREAM_WITH_INDEX

#if ZSTD_ENABLE_ASM_X86_64_APX

/* The APX loops below are self-contained: they define every register alias
 * they use and undefine all of them at the end. */

ZSTD_HIDE_ASM_FUNCTION(HUF_decompress4X1_usingDTable_internal_fast_asm_loop_apx)
ZSTD_HIDE_ASM_FUNCTION(HUF_decompress4X2_usingDTable_internal_fast_asm_loop_apx)
ZSTD_HIDE_ASM_FUNCTION(_HUF_decompress4X1_usingDTable_internal_fast_asm_loop_apx)
ZSTD_HIDE_ASM_FUNCTION(_HUF_decompress4X2_usingDTable_internal_fast_asm_loop_apx)
.global HUF_decompress4X1_usingDTable_internal_fast_asm_loop_apx
.global HUF_decompress4X2_usingDTable_internal_fast_asm_loop_apx
.global _HUF_decompress4X1_usingDTable_internal_fast_asm_loop_apx
.global _HUF_decompress4X2_usingDTable_internal_fast_asm_loop_apx

/* APX (Intel Advanced Performance Extensions) versions of the decoding loops.
 *
 * They use the extended GPRs (EGPR), the new data destination (NDD) forms,
 * PUSH2 / POP2 and the PPX hint for the register saves, and, when the
 * assembler supports it, the conditional compare (CCMP) for the loop exit
 * conditions. These functions are selected at runtime when the CPU supports
 * APX and the OS has enabled the APX register state, or always when the C
 * code is compiled for APX (STATIC_APXF). See ZSTD_ENABLE_ASM_X86_64_APX.
 *
 * Compared with the BMI2 versions, the 16 extra registers (r16-r31) allow to:
 * - keep the loop state in registers (no stack spills of ip[]). Only olimit
 *   is kept on the stack: it is read once per iteration, by the loop exit
 *   check, which leaves %rbp free for the frame pointer.
 * - use NDD shifts instead of a constant load followed by SHRX,
 * - track the number of consumed bits per stream in a register (cnt[n]).
 *   cnt[n] equals CTZ(bits[n]) at reload time, which takes the BSF off the
 *   critical path of the bit reload.
 * - compute the next DTable index before the sentinel bit is set with BTS,
 *   instead of setting it with OR before the shift.
 *
 * Calling convention:
 * %rdi (or %rcx on Windows) contains the first argument: HUF_DecompressAsmArgs*.
 * Only the callee-saved registers of the ABI are preserved:
 * - SysV:    %rbx, %rbp, %r12-%r15
 * - Windows: %rbx, %rbp, %rsi, %rdi, %r12-%r15
 * All other registers, including r16-r31 (volatile in both APX ABIs), are
 * clobbered.
 *
 * Frame pointer:
 * Both functions set up a standard frame (push %rbp; mov %rsp, %rbp) and
 * don't modify %rbp otherwise, so profilers and debuggers can unwind through
 * them with frame pointers. The CFA is defined relative to %rbp once the
 * frame is set up.
 */

/* Use the APX conditional compare (CCMP) when the assembler supports it.
 * CCMP is part of APX_F, which the runtime CPU check requires, but older
 * assemblers that support EGPR and NDD (e.g. GNU as 2.42, Clang 18) don't
 * support it. The build system defines ZSTD_ASM_APX_CCMP_SUPPORTED=1.
 */
#if defined(ZSTD_ASM_APX_CCMP_SUPPORTED) && ZSTD_ASM_APX_CCMP_SUPPORTED
# define APX_USE_CCMP 1
#else
# define APX_USE_CCMP 0
#endif

/* Sets up the frame and saves the callee-saved registers, two at a time with
 * PUSH2 / POP2 where possible. PUSH2 / POP2 require a 16-byte aligned %rsp:
 * on entry %rsp is 8 (mod 16), so pushing %rbp aligns it. In AT&T syntax,
 * "push2 %a, %b" stores %a at the lower address, and "pop2 %b, %a" restores
 * them. The stack layout is the same as with single pushes.
 * After APX_SAVE_REGS, %rsp is 8 (mod 16).
 *
 * The callee-saved registers and the argument pointer are saved and restored
 * with the PPX hint (PUSH2P / POP2P, PUSHP / POPP): each push is matched by a
 * pop of the same slot and the slot isn't otherwise accessed, which allows
 * the processor to forward the value from the push to the pop (memory
 * renaming). The stack slots of ilowest, oend and olimit are read by loads
 * in the loops, so they don't use the hint. %rbp uses plain PUSH / POP.
 */
#define APX_SETUP_FRAME            \
    push %rbp;                     \
    .cfi_def_cfa_offset 16;        \
    .cfi_offset rbp, -16;          \
    movq %rsp, %rbp;               \
    .cfi_def_cfa_register rbp

#define APX_LEAVE_FRAME            \
    pop %rbp;                      \
    .cfi_def_cfa rsp, 8;           \
    .cfi_restore rbp

#if defined(_WIN32)
#define APX_SAVE_REGS              \
    APX_SETUP_FRAME;               \
    push2p %r12, %rbx;             \
    .cfi_offset rbx, -24;          \
    .cfi_offset r12, -32;          \
    push2p %r14, %r13;             \
    .cfi_offset r13, -40;          \
    .cfi_offset r14, -48;          \
    push2p %rsi, %r15;             \
    .cfi_offset r15, -56;          \
    .cfi_offset rsi, -64;          \
    pushp %rdi;                    \
    .cfi_offset rdi, -72

#define APX_RESTORE_REGS           \
    popp %rdi;                     \
    .cfi_restore rdi;              \
    pop2p %r15, %rsi;              \
    .cfi_restore r15;              \
    .cfi_restore rsi;              \
    pop2p %r13, %r14;              \
    .cfi_restore r13;              \
    .cfi_restore r14;              \
    pop2p %rbx, %r12;              \
    .cfi_restore rbx;              \
    .cfi_restore r12;              \
    APX_LEAVE_FRAME
#else
#define APX_SAVE_REGS              \
    APX_SETUP_FRAME;               \
    push2p %r12, %rbx;             \
    .cfi_offset rbx, -24;          \
    .cfi_offset r12, -32;          \
    push2p %r14, %r13;             \
    .cfi_offset r13, -40;          \
    .cfi_offset r14, -48;          \
    pushp %r15;                    \
    .cfi_offset r15, -56

#define APX_RESTORE_REGS           \
    popp %r15;                     \
    .cfi_restore r15;              \
    pop2p %r13, %r14;              \
    .cfi_restore r13;              \
    .cfi_restore r14;              \
    pop2p %rbx, %r12;              \
    .cfi_restore rbx;              \
    .cfi_restore r12;              \
    APX_LEAVE_FRAME
#endif

/* Loads ip / op / bits / dtable from HUF_DecompressAsmArgs* in %rax */
#define APX_LOAD_ARGS              \
    movq  0(%rax), %ip0;           \
    movq  8(%rax), %ip1;           \
    movq 16(%rax), %ip2;           \
    movq 24(%rax), %ip3;           \
    movq 32(%rax), %op0;           \
    movq 40(%rax), %op1;           \
    movq 48(%rax), %op2;           \
    movq 56(%rax), %op3;           \
    movq 64(%rax), %bits0;         \
    movq 72(%rax), %bits1;         \
    movq 80(%rax), %bits2;         \
    movq 88(%rax), %bits3;         \
    movq 96(%rax), %dtable

/* Saves ip / op / bits to HUF_DecompressAsmArgs* in %rax */
#define APX_STORE_ARGS             \
    movq %ip0,  0(%rax);           \
    movq %ip1,  8(%rax);           \
    movq %ip2, 16(%rax);           \
    movq %ip3, 24(%rax);           \
    movq %op0, 32(%rax);           \
    movq %op1, 40(%rax);           \
    movq %op2, 48(%rax);           \
    movq %op3, 56(%rax);           \
    movq %bits0, 64(%rax);         \
    movq %bits1, 72(%rax);         \
    movq %bits2, 80(%rax);         \
    movq %bits3, 88(%rax)

/* Register mappings shared by both loops.
 * op[] must stay in rsi/rbx/rcx/rdi: the 4X1 loop stores %ah, which can't be
 * encoded together with a REX/REX2 prefix.
 * %rax is a scratch register. %rbp is the frame pointer and is not used.
 * olimit is kept on the stack, at 0(%rsp).
 */
#define op0    rsi
#define op1    rbx
#define op2    rcx
#define op3    rdi

#define ip0    r8
#define ip1    r9
#define ip2    r10
#define ip3    r11

#define bits0  r15
#define bits1  rdx
#define bits2  r12
#define bits3  r13
#define dtable r14

/* 4X1 registers:
 * var[n]: DTable entry of the next symbol (symbol << 8 | nbBits)
 * cnt[n]: number of bits consumed from bits[n] (low byte, see the loop body)
 * tmp[n]: scratch
 */
#define var0   r16
#define var1   r17
#define var2   r18
#define var3   r19
#define vard0  r16d
#define vard1  r17d
#define vard2  r18d
#define vard3  r19d

#define cnt0   r20
#define cnt1   r21
#define cnt2   r22
#define cnt3   r23
#define cntd0  r20d
#define cntd1  r21d
#define cntd2  r22d
#define cntd3  r23d
#define cntb0  r20b
#define cntb1  r21b
#define cntb2  r22b
#define cntb3  r23b

#define tmp0   r24
#define tmp1   r25
#define tmp2   r26
#define tmp3   r27
#define tmpd0  r24d
#define tmpd1  r25d
#define tmpd2  r26d
#define tmpd3  r27d

/* nb[n]: nbBits of the 5th symbol, loaded without the symbol byte so that
 * the total number of consumed bits stays exact in a 32-bit register
 */
#define nb0    r28
#define nb1    r29
#define nb2    r30
#define nb3    r31
#define nbd0   r28d
#define nbd1   r29d
#define nbd2   r30d
#define nbd3   r31d

/* Define both _HUF_* & HUF_* symbols because MacOS
 * C symbols are prefixed with '_' & Linux symbols aren't.
 */
	.p2align 6
_HUF_decompress4X1_usingDTable_internal_fast_asm_loop_apx:
HUF_decompress4X1_usingDTable_internal_fast_asm_loop_apx:
    ZSTD_CET_ENDBRANCH
    .cfi_startproc
    .cfi_def_cfa_offset 8
    .cfi_offset %rip, -8
    /* Save the callee-saved registers */
    APX_SAVE_REGS

    /* Read HUF_DecompressAsmArgs* args from %rax */
#if defined(_WIN32)
    movq %rcx, %rax
#else
    movq %rdi, %rax
#endif
    APX_LOAD_ARGS
    pushp %rax     /* argument */
    movq 104(%rax), %r16 /* ilowest */
    movq 112(%rax), %r17 /* oend */
    push2 %r17, %r16 /* oend, ilowest: %rsp is 16-byte aligned here */
    subq $8, %rsp  /* olimit, set by 4X1_apx_compute_olimit */

    /* Stack: 0 = olimit, 8 = oend, 16 = ilowest, 24 = argument */

    /* cnt[n] = CTZ(bits[n]) */
    tzcntq %bits0, %cnt0
    tzcntq %bits1, %cnt1
    tzcntq %bits2, %cnt2
    tzcntq %bits3, %cnt3

LOCAL_LABEL(4X1_apx_compute_olimit):
    /* Computes how many iterations we can do safely
     * %rax, %tmp[0,1,2] may be clobbered
     * %rdx (bits1) is saved in %tmp0
     * olimit is computed in %tmp2 and stored to 0(%rsp)
     */
    movq %rdx, %tmp0

    subq %op3, 8(%rsp), %rax  /* rax = oend - op3 */

    /* olimit = (oend - op3) / 5 */
    movabsq $-3689348814741910323, %rdx
    mulq %rdx
    shrq $2, %rdx, %tmp2

    subq 16(%rsp), %ip0, %rax /* rax = ip0 - ilowest */
    movq %rax, %tmp1          /* tmp1 = ip0 - ilowest */

    /* rdx = (ip0 - ilowest) / 7 */
    movabsq $2635249153387078803, %rdx
    mulq %rdx
    subq %rdx, %tmp1
    shrq %tmp1
    addq %tmp1, %rdx
    shrq $2, %rdx

    /* olimit = min(%rdx, olimit) */
    cmpq %rdx, %tmp2
    cmova %rdx, %tmp2

    /* olimit = op3 + olimit * 5 */
    leaq (%tmp2, %tmp2, 4), %tmp2
    addq %op3, %tmp2
    movq %tmp2, 0(%rsp)

    movq %tmp0, %rdx

#if APX_USE_CCMP
    /* Go to exit if any of these is true, using a single branch:
     * - op3 + 20 > olimit (op3 == olimit)
     * - ip1 < ip0
     * - ip2 < ip1
     * - ip3 < ip2
     * Each CCMP only compares if no exit condition was found so far,
     * otherwise it sets CF (dfv=cf), which keeps the exit condition (CF) set.
     */
    cmpq %op3, %tmp2                    /* ZF = (op3 == olimit) */
    ccmpne {dfv=cf} %ip0, %ip1          /* CF = (ip1 < ip0) */
    ccmpae {dfv=cf} %ip1, %ip2          /* CF = (ip2 < ip1) */
    ccmpae {dfv=cf} %ip2, %ip3          /* CF = (ip3 < ip2) */
    jb LOCAL_LABEL(4X1_apx_exit)
#else
    /* If (op3 + 20 > olimit) */
    cmpq %op3, %tmp2 /* op3 == olimit */
    je LOCAL_LABEL(4X1_apx_exit)

    /* If (ip1 < ip0) go to exit */
    cmpq %ip0, %ip1
    jb LOCAL_LABEL(4X1_apx_exit)

    /* If (ip2 < ip1) go to exit */
    cmpq %ip1, %ip2
    jb LOCAL_LABEL(4X1_apx_exit)

    /* If (ip3 < ip2) go to exit */
    cmpq %ip2, %ip3
    jb LOCAL_LABEL(4X1_apx_exit)
#endif

    /* Get the DTable entry of the first symbol of each stream:
     * var[n] = dt[bits[n] >> 53] (top 11 bits)
     */
    shrq $53, %bits0, %var0
    movzwl (%dtable,%var0,2), %vard0
    shrq $53, %bits1, %var1
    movzwl (%dtable,%var1,2), %vard1
    shrq $53, %bits2, %var2
    movzwl (%dtable,%var2,2), %vard2
    shrq $53, %bits3, %var3
    movzwl (%dtable,%var3,2), %vard3

    .p2align 5

LOCAL_LABEL(4X1_apx_loop_body):
    /* Decode 5 symbols in each of the 4 streams (20 total).
     * var[n] holds the DTable entry of the next symbol of stream n.
     *
     * Decoding a symbol of stream n:
     *   rax = var[n]               %ah is the symbol: bits [8, 16) of var[n]
     *   bits[n] <<= var[n] & 63    the low byte of var[n] is nbBits
     *   op[n][idx] = %ah
     *   cnt[n] += var[n]           cnt[n] < 64 before the reload, so its low
     *                              byte is the exact number of bits consumed
     * Getting the DTable entry of the next symbol (symbols 0 to 3):
     *   var[n] = dt[bits[n] >> 53] (top 11 bits)
     *
     * The symbol bytes accumulated in cnt[n] must be stripped before the
     * reload can use the bit count. Instead of doing it in the reload, where
     * it sits on the critical path, symbol 3 extracts the partial count into
     * tmp[n] and separately loads the nbBits of symbol 4 into nb[n], so that
     * symbol 4 only has to add nb[n] to the already clean tmp[n].
     */

    /* Symbol 0 of each stream */
    movq %var0, %rax
    shlxq %var0, %bits0, %bits0
    movb %ah, 0(%op0)
    addl %vard0, %cntd0
    shrq $53, %bits0, %var0
    movzwl (%dtable,%var0,2), %vard0
    movq %var1, %rax
    shlxq %var1, %bits1, %bits1
    movb %ah, 0(%op1)
    addl %vard1, %cntd1
    shrq $53, %bits1, %var1
    movzwl (%dtable,%var1,2), %vard1
    movq %var2, %rax
    shlxq %var2, %bits2, %bits2
    movb %ah, 0(%op2)
    addl %vard2, %cntd2
    shrq $53, %bits2, %var2
    movzwl (%dtable,%var2,2), %vard2
    movq %var3, %rax
    shlxq %var3, %bits3, %bits3
    movb %ah, 0(%op3)
    addl %vard3, %cntd3
    shrq $53, %bits3, %var3
    movzwl (%dtable,%var3,2), %vard3

    /* Symbol 1 of each stream */
    movq %var0, %rax
    shlxq %var0, %bits0, %bits0
    movb %ah, 1(%op0)
    addl %vard0, %cntd0
    shrq $53, %bits0, %var0
    movzwl (%dtable,%var0,2), %vard0
    movq %var1, %rax
    shlxq %var1, %bits1, %bits1
    movb %ah, 1(%op1)
    addl %vard1, %cntd1
    shrq $53, %bits1, %var1
    movzwl (%dtable,%var1,2), %vard1
    movq %var2, %rax
    shlxq %var2, %bits2, %bits2
    movb %ah, 1(%op2)
    addl %vard2, %cntd2
    shrq $53, %bits2, %var2
    movzwl (%dtable,%var2,2), %vard2
    movq %var3, %rax
    shlxq %var3, %bits3, %bits3
    movb %ah, 1(%op3)
    addl %vard3, %cntd3
    shrq $53, %bits3, %var3
    movzwl (%dtable,%var3,2), %vard3

    /* Symbol 2 of each stream */
    movq %var0, %rax
    shlxq %var0, %bits0, %bits0
    movb %ah, 2(%op0)
    addl %vard0, %cntd0
    shrq $53, %bits0, %var0
    movzwl (%dtable,%var0,2), %vard0
    movq %var1, %rax
    shlxq %var1, %bits1, %bits1
    movb %ah, 2(%op1)
    addl %vard1, %cntd1
    shrq $53, %bits1, %var1
    movzwl (%dtable,%var1,2), %vard1
    movq %var2, %rax
    shlxq %var2, %bits2, %bits2
    movb %ah, 2(%op2)
    addl %vard2, %cntd2
    shrq $53, %bits2, %var2
    movzwl (%dtable,%var2,2), %vard2
    movq %var3, %rax
    shlxq %var3, %bits3, %bits3
    movb %ah, 2(%op3)
    addl %vard3, %cntd3
    shrq $53, %bits3, %var3
    movzwl (%dtable,%var3,2), %vard3

    /* Symbol 3 of each stream */
    movq %var0, %rax
    shlxq %var0, %bits0, %bits0
    movb %ah, 3(%op0)
    addl %vard0, %cntd0
    movzbl %cntb0, %tmpd0
    shrq $53, %bits0, %var0
    movzbl (%dtable,%var0,2), %nbd0
    movzwl (%dtable,%var0,2), %vard0
    movq %var1, %rax
    shlxq %var1, %bits1, %bits1
    movb %ah, 3(%op1)
    addl %vard1, %cntd1
    movzbl %cntb1, %tmpd1
    shrq $53, %bits1, %var1
    movzbl (%dtable,%var1,2), %nbd1
    movzwl (%dtable,%var1,2), %vard1
    movq %var2, %rax
    shlxq %var2, %bits2, %bits2
    movb %ah, 3(%op2)
    addl %vard2, %cntd2
    movzbl %cntb2, %tmpd2
    shrq $53, %bits2, %var2
    movzbl (%dtable,%var2,2), %nbd2
    movzwl (%dtable,%var2,2), %vard2
    movq %var3, %rax
    shlxq %var3, %bits3, %bits3
    movb %ah, 3(%op3)
    addl %vard3, %cntd3
    movzbl %cntb3, %tmpd3
    shrq $53, %bits3, %var3
    movzbl (%dtable,%var3,2), %nbd3
    movzwl (%dtable,%var3,2), %vard3

    /* Symbol 4 of each stream */
    movq %var0, %rax
    shlxq %var0, %bits0, %bits0
    movb %ah, 4(%op0)
    addl %nbd0, %tmpd0
    movq %var1, %rax
    shlxq %var1, %bits1, %bits1
    movb %ah, 4(%op1)
    addl %nbd1, %tmpd1
    movq %var2, %rax
    shlxq %var2, %bits2, %bits2
    movb %ah, 4(%op2)
    addl %nbd2, %tmpd2
    movq %var3, %rax
    shlxq %var3, %bits3, %bits3
    movb %ah, 4(%op3)
    addl %nbd3, %tmpd3

    /* Reload each stream & get the DTable entry of its next symbol
     * to prepare for the next iteration:
     *   ctz     = low byte of cnt[n] (same as CTZ(bits[n]))
     *   nbBits  = ctz & 7
     *   nbBytes = ctz >> 3
     *   op[n]  += 5
     *   ip[n]  -= nbBytes
     *   // Note: x86-64 is little-endian ==> no bswap
     *   bits[n] = MEM_readST(ip[n]) << nbBits
     *   var[n]  = dt[bits[n] >> 53], the sentinel bit doesn't affect the top 11 bits
     *   bits[n] |= 1 << nbBits, same as (MEM_readST(ip[n]) | 1) << nbBits
     *   cnt[n]  = nbBits
     */

    /* Stream 0 */
    andl $7, %tmpd0, %cntd0
    shrl $3, %tmpd0
    leaq 5(%op0), %op0
    subq %tmp0, %ip0
    movq (%ip0), %bits0
    shlxq %cnt0, %bits0, %bits0
    shrq $53, %bits0, %var0
    btsq %cnt0, %bits0
    movzwl (%dtable,%var0,2), %vard0

    /* Stream 1 */
    andl $7, %tmpd1, %cntd1
    shrl $3, %tmpd1
    leaq 5(%op1), %op1
    subq %tmp1, %ip1
    movq (%ip1), %bits1
    shlxq %cnt1, %bits1, %bits1
    shrq $53, %bits1, %var1
    btsq %cnt1, %bits1
    movzwl (%dtable,%var1,2), %vard1

    /* Stream 2 */
    andl $7, %tmpd2, %cntd2
    shrl $3, %tmpd2
    leaq 5(%op2), %op2
    subq %tmp2, %ip2
    movq (%ip2), %bits2
    shlxq %cnt2, %bits2, %bits2
    shrq $53, %bits2, %var2
    btsq %cnt2, %bits2
    movzwl (%dtable,%var2,2), %vard2

    /* Stream 3 */
    andl $7, %tmpd3, %cntd3
    shrl $3, %tmpd3
    leaq 5(%op3), %op3
    subq %tmp3, %ip3
    movq (%ip3), %bits3
    shlxq %cnt3, %bits3, %bits3
    shrq $53, %bits3, %var3
    btsq %cnt3, %bits3
    movzwl (%dtable,%var3,2), %vard3

    /* If op3 < olimit: continue the loop */
    cmpq %op3, 0(%rsp)
    ja LOCAL_LABEL(4X1_apx_loop_body)

    /* Re-compute olimit */
    jmp LOCAL_LABEL(4X1_apx_compute_olimit)

LOCAL_LABEL(4X1_apx_exit):
    /* Restore stack (olimit, oend & ilowest) */
    pop %rax /* olimit */
    /* ilowest, oend: %rsp is 16-byte aligned here, %r16 is no longer used */
    pop2 %r16, %rax
    popp %rax /* arg */

    /* Save ip / op / bits */
    APX_STORE_ARGS

    /* Restore the callee-saved registers */
    APX_RESTORE_REGS
    ret
    .cfi_endproc

#undef var0
#undef var1
#undef var2
#undef var3
#undef vard0
#undef vard1
#undef vard2
#undef vard3
#undef cnt0
#undef cnt1
#undef cnt2
#undef cnt3
#undef cntd0
#undef cntd1
#undef cntd2
#undef cntd3
#undef cntb0
#undef cntb1
#undef cntb2
#undef cntb3
#undef tmp0
#undef tmp1
#undef tmp2
#undef tmp3
#undef tmpd0
#undef tmpd1
#undef tmpd2
#undef tmpd3
#undef nb0
#undef nb1
#undef nb2
#undef nb3
#undef nbd0
#undef nbd1
#undef nbd2
#undef nbd3

/* 4X2 registers:
 * ent[n]: DTable index, then the length of the decoded sequence
 * seq[n]: decoded sequence (2 bytes)
 * nb[n]:  nbBits of the decoded sequence, then nbBytes during the reload
 * cnt[n]: number of bits consumed from bits[n]
 */
#define ent0   r16
#define ent1   r17
#define ent2   r18
#define ent3   r19
#define entd0  r16d
#define entd1  r17d
#define entd2  r18d
#define entd3  r19d

#define seq0   r20
#define seq1   r21
#define seq2   r22
#define seq3   r23
#define seqd0  r20d
#define seqd1  r21d
#define seqd2  r22d
#define seqd3  r23d
#define seqw0  r20w
#define seqw1  r21w
#define seqw2  r22w
#define seqw3  r23w

#define nb0    r24
#define nb1    r25
#define nb2    r26
#define nb3    r27
#define nbd0   r24d
#define nbd1   r25d
#define nbd2   r26d
#define nbd3   r27d

#define cnt0   r28
#define cnt1   r29
#define cnt2   r30
#define cnt3   r31
#define cntd0  r28d
#define cntd1  r29d
#define cntd2  r30d
#define cntd3  r31d

	.p2align 6
_HUF_decompress4X2_usingDTable_internal_fast_asm_loop_apx:
HUF_decompress4X2_usingDTable_internal_fast_asm_loop_apx:
    ZSTD_CET_ENDBRANCH
    .cfi_startproc
    .cfi_def_cfa_offset 8
    .cfi_offset %rip, -8
    /* Save the callee-saved registers */
    APX_SAVE_REGS

    /* Read HUF_DecompressAsmArgs* args from %rax */
#if defined(_WIN32)
    movq %rcx, %rax
#else
    movq %rdi, %rax
#endif
    APX_LOAD_ARGS
    pushp %rax     /* argument */
    movq 104(%rax), %r16 /* ilowest */
    movq 112(%rax), %r17 /* oend3 */
    push2 %r17, %r16 /* oend3, ilowest: %rsp is 16-byte aligned here */
    push2 %op2, %op3 /* oend1, oend2 */
    /* olimit (set by 4X2_apx_compute_olimit), oend0 */
    push2 %rax, %op1

    /* Stack: 0 = olimit, 8 = oend0, 16 = oend1, 24 = oend2, 32 = oend3,
     *        40 = ilowest, 48 = argument
     */

    /* cnt[n] = CTZ(bits[n]) */
    tzcntq %bits0, %cnt0
    tzcntq %bits1, %cnt1
    tzcntq %bits2, %cnt2
    tzcntq %bits3, %cnt3

LOCAL_LABEL(4X2_apx_compute_olimit):
    /* Computes how many iterations we can do safely
     * %rax, %seq0, %seq1 may be clobbered
     * %rdx (bits1) is saved in %seq0
     * olimit is computed in %seq1 and stored to 0(%rsp)
     */
    movq %rdx, %seq0

    /* We can consume up to 7 input bytes each iteration. */
    subq 40(%rsp), %ip0, %rax  /* rax = ip0 - ilowest */
    movq %rax, %seq1           /* olimit = ip0 - ilowest */

    /* olimit = (ip0 - ilowest) / 7 */
    movabsq $2635249153387078803, %rdx
    mulq %rdx
    subq %rdx, %seq1
    shrq %seq1
    addq %seq1, %rdx
    shrq $2, %rdx, %seq1

    /* olimit = min(olimit, min(oend0 - op0, oend1 - op1, oend2 - op2, oend3 - op3) / 10) */
    subq %op0, 8(%rsp),  %rax /* rax = oend0 - op0 */
    subq %op1, 16(%rsp), %rdx /* rdx = oend1 - op1 */

    cmpq  %rax,    %rdx
    cmova %rax,    %rdx /* rdx = min(%rdx, %rax) */

    subq %op2, 24(%rsp), %rax /* rax = oend2 - op2 */

    cmpq  %rax,    %rdx
    cmova %rax,    %rdx /* rdx = min(%rdx, %rax) */

    subq %op3, 32(%rsp), %rax /* rax = oend3 - op3 */

    cmpq  %rax,    %rdx
    cmova %rax,    %rdx /* rdx = min(%rdx, %rax) */

    movabsq $-3689348814741910323, %rax
    mulq %rdx
    shrq $3,       %rdx /* rdx = rdx / 10 */

    /* olimit = min(%rdx, olimit) */
    cmpq  %rdx, %seq1
    cmova %rdx, %seq1

    /* olimit = op3 + 5 * olimit */
    leaq (%seq1, %seq1, 4), %seq1
    addq %op3, %seq1
    movq %seq1, 0(%rsp)

    movq %seq0, %rdx

#if APX_USE_CCMP
    /* Go to exit if any of these is true, using a single branch:
     * - op3 + 10 > olimit (op3 == olimit)
     * - ip1 < ip0
     * - ip2 < ip1
     * - ip3 < ip2
     * Each CCMP only compares if no exit condition was found so far,
     * otherwise it sets CF (dfv=cf), which keeps the exit condition (CF) set.
     */
    cmpq %op3, %seq1                    /* ZF = (op3 == olimit) */
    ccmpne {dfv=cf} %ip0, %ip1          /* CF = (ip1 < ip0) */
    ccmpae {dfv=cf} %ip1, %ip2          /* CF = (ip2 < ip1) */
    ccmpae {dfv=cf} %ip2, %ip3          /* CF = (ip3 < ip2) */
    jb LOCAL_LABEL(4X2_apx_exit)
#else
    /* If (op3 + 10 > olimit) */
    cmpq %op3, %seq1 /* op3 == olimit */
    je LOCAL_LABEL(4X2_apx_exit)

    /* If (ip1 < ip0) go to exit */
    cmpq %ip0, %ip1
    jb LOCAL_LABEL(4X2_apx_exit)

    /* If (ip2 < ip1) go to exit */
    cmpq %ip1, %ip2
    jb LOCAL_LABEL(4X2_apx_exit)

    /* If (ip3 < ip2) go to exit */
    cmpq %ip2, %ip3
    jb LOCAL_LABEL(4X2_apx_exit)
#endif

    /* Get the DTable index of the first symbol of each stream:
     * ent[n] = bits[n] >> 53 (top 11 bits)
     */
    shrq $53, %bits0, %ent0
    shrq $53, %bits1, %ent1
    shrq $53, %bits2, %ent2
    shrq $53, %bits3, %ent3

    .p2align 5

LOCAL_LABEL(4X2_apx_loop_body):
    /* Decode 5 sequences of 1 or 2 symbols from each of the 4 streams
     * (20 sequences total).
     *
     * Getting the DTable index (sequences 1 to 4, sequence 0 got it in the reload):
     *   ent[n] = bits[n] >> 53 (top 11 bits)
     * Decoding a sequence of stream n:
     *   seq[n] = dt[ent[n]]        the whole 4-byte entry: the 2-byte sequence
     *                              in bits [0, 16) and the length in [24, 32)
     *   nb[n]  = dt[ent[n]].nbBits loaded separately to keep the latency of
     *                              the bits[n] -> ent[n] -> bits[n] chain
     *                              down to a single DTable load
     *   ent[n] = seq[n] >> 24      the length, off the critical path
     *   op[n][0,1] = seq[n]
     *   bits[n] <<= nb[n]
     *   op[n]   += ent[n]
     *   cnt[n]  += nb[n]
     */

    /* Sequence 0 of each stream */
    movl   0(%dtable,%ent0,4), %seqd0
    movzbl 2(%dtable,%ent0,4), %nbd0
    movw %seqw0, (%op0)
    shlxq %nb0, %bits0, %bits0
    shrl $24, %seqd0, %entd0
    addq %ent0, %op0
    addl %nbd0, %cntd0
    movl   0(%dtable,%ent1,4), %seqd1
    movzbl 2(%dtable,%ent1,4), %nbd1
    movw %seqw1, (%op1)
    shlxq %nb1, %bits1, %bits1
    shrl $24, %seqd1, %entd1
    addq %ent1, %op1
    addl %nbd1, %cntd1
    movl   0(%dtable,%ent2,4), %seqd2
    movzbl 2(%dtable,%ent2,4), %nbd2
    movw %seqw2, (%op2)
    shlxq %nb2, %bits2, %bits2
    shrl $24, %seqd2, %entd2
    addq %ent2, %op2
    addl %nbd2, %cntd2
    movl   0(%dtable,%ent3,4), %seqd3
    movzbl 2(%dtable,%ent3,4), %nbd3
    movw %seqw3, (%op3)
    shlxq %nb3, %bits3, %bits3
    shrl $24, %seqd3, %entd3
    addq %ent3, %op3
    addl %nbd3, %cntd3

    /* Sequence 1 of each stream */
    shrq $53, %bits0, %ent0
    movl   0(%dtable,%ent0,4), %seqd0
    movzbl 2(%dtable,%ent0,4), %nbd0
    movw %seqw0, (%op0)
    shlxq %nb0, %bits0, %bits0
    shrl $24, %seqd0, %entd0
    addq %ent0, %op0
    addl %nbd0, %cntd0
    shrq $53, %bits1, %ent1
    movl   0(%dtable,%ent1,4), %seqd1
    movzbl 2(%dtable,%ent1,4), %nbd1
    movw %seqw1, (%op1)
    shlxq %nb1, %bits1, %bits1
    shrl $24, %seqd1, %entd1
    addq %ent1, %op1
    addl %nbd1, %cntd1
    shrq $53, %bits2, %ent2
    movl   0(%dtable,%ent2,4), %seqd2
    movzbl 2(%dtable,%ent2,4), %nbd2
    movw %seqw2, (%op2)
    shlxq %nb2, %bits2, %bits2
    shrl $24, %seqd2, %entd2
    addq %ent2, %op2
    addl %nbd2, %cntd2
    shrq $53, %bits3, %ent3
    movl   0(%dtable,%ent3,4), %seqd3
    movzbl 2(%dtable,%ent3,4), %nbd3
    movw %seqw3, (%op3)
    shlxq %nb3, %bits3, %bits3
    shrl $24, %seqd3, %entd3
    addq %ent3, %op3
    addl %nbd3, %cntd3

    /* Sequence 2 of each stream */
    shrq $53, %bits0, %ent0
    movl   0(%dtable,%ent0,4), %seqd0
    movzbl 2(%dtable,%ent0,4), %nbd0
    movw %seqw0, (%op0)
    shlxq %nb0, %bits0, %bits0
    shrl $24, %seqd0, %entd0
    addq %ent0, %op0
    addl %nbd0, %cntd0
    shrq $53, %bits1, %ent1
    movl   0(%dtable,%ent1,4), %seqd1
    movzbl 2(%dtable,%ent1,4), %nbd1
    movw %seqw1, (%op1)
    shlxq %nb1, %bits1, %bits1
    shrl $24, %seqd1, %entd1
    addq %ent1, %op1
    addl %nbd1, %cntd1
    shrq $53, %bits2, %ent2
    movl   0(%dtable,%ent2,4), %seqd2
    movzbl 2(%dtable,%ent2,4), %nbd2
    movw %seqw2, (%op2)
    shlxq %nb2, %bits2, %bits2
    shrl $24, %seqd2, %entd2
    addq %ent2, %op2
    addl %nbd2, %cntd2
    shrq $53, %bits3, %ent3
    movl   0(%dtable,%ent3,4), %seqd3
    movzbl 2(%dtable,%ent3,4), %nbd3
    movw %seqw3, (%op3)
    shlxq %nb3, %bits3, %bits3
    shrl $24, %seqd3, %entd3
    addq %ent3, %op3
    addl %nbd3, %cntd3

    /* Sequence 3 of each stream */
    shrq $53, %bits0, %ent0
    movl   0(%dtable,%ent0,4), %seqd0
    movzbl 2(%dtable,%ent0,4), %nbd0
    movw %seqw0, (%op0)
    shlxq %nb0, %bits0, %bits0
    shrl $24, %seqd0, %entd0
    addq %ent0, %op0
    addl %nbd0, %cntd0
    shrq $53, %bits1, %ent1
    movl   0(%dtable,%ent1,4), %seqd1
    movzbl 2(%dtable,%ent1,4), %nbd1
    movw %seqw1, (%op1)
    shlxq %nb1, %bits1, %bits1
    shrl $24, %seqd1, %entd1
    addq %ent1, %op1
    addl %nbd1, %cntd1
    shrq $53, %bits2, %ent2
    movl   0(%dtable,%ent2,4), %seqd2
    movzbl 2(%dtable,%ent2,4), %nbd2
    movw %seqw2, (%op2)
    shlxq %nb2, %bits2, %bits2
    shrl $24, %seqd2, %entd2
    addq %ent2, %op2
    addl %nbd2, %cntd2
    shrq $53, %bits3, %ent3
    movl   0(%dtable,%ent3,4), %seqd3
    movzbl 2(%dtable,%ent3,4), %nbd3
    movw %seqw3, (%op3)
    shlxq %nb3, %bits3, %bits3
    shrl $24, %seqd3, %entd3
    addq %ent3, %op3
    addl %nbd3, %cntd3

    /* Sequence 4 of each stream */
    shrq $53, %bits0, %ent0
    movl   0(%dtable,%ent0,4), %seqd0
    movzbl 2(%dtable,%ent0,4), %nbd0
    movw %seqw0, (%op0)
    shlxq %nb0, %bits0, %bits0
    shrl $24, %seqd0, %entd0
    addq %ent0, %op0
    addl %nbd0, %cntd0
    shrq $53, %bits1, %ent1
    movl   0(%dtable,%ent1,4), %seqd1
    movzbl 2(%dtable,%ent1,4), %nbd1
    movw %seqw1, (%op1)
    shlxq %nb1, %bits1, %bits1
    shrl $24, %seqd1, %entd1
    addq %ent1, %op1
    addl %nbd1, %cntd1
    shrq $53, %bits2, %ent2
    movl   0(%dtable,%ent2,4), %seqd2
    movzbl 2(%dtable,%ent2,4), %nbd2
    movw %seqw2, (%op2)
    shlxq %nb2, %bits2, %bits2
    shrl $24, %seqd2, %entd2
    addq %ent2, %op2
    addl %nbd2, %cntd2
    shrq $53, %bits3, %ent3
    movl   0(%dtable,%ent3,4), %seqd3
    movzbl 2(%dtable,%ent3,4), %nbd3
    movw %seqw3, (%op3)
    shlxq %nb3, %bits3, %bits3
    shrl $24, %seqd3, %entd3
    addq %ent3, %op3
    addl %nbd3, %cntd3

    /* Reload each stream & get the DTable index of its next sequence
     * to prepare for the next iteration:
     *   // cnt[n] is the same as CTZ(bits[n])
     *   nbBits  = cnt[n] & 7
     *   nbBytes = cnt[n] >> 3
     *   ip[n]  -= nbBytes
     *   // Note: x86-64 is little-endian ==> no bswap
     *   bits[n] = MEM_readST(ip[n]) << nbBits
     *   ent[n]  = bits[n] >> 53, the sentinel bit doesn't affect the top 11 bits
     *   bits[n] |= 1 << nbBits, same as (MEM_readST(ip[n]) | 1) << nbBits
     *   cnt[n]  = nbBits
     */

    /* Stream 0 */
    shrl $3, %cntd0, %nbd0
    andl $7, %cntd0
    subq %nb0, %ip0
    movq (%ip0), %bits0
    shlxq %cnt0, %bits0, %bits0
    shrq $53, %bits0, %ent0
    btsq %cnt0, %bits0

    /* Stream 1 */
    shrl $3, %cntd1, %nbd1
    andl $7, %cntd1
    subq %nb1, %ip1
    movq (%ip1), %bits1
    shlxq %cnt1, %bits1, %bits1
    shrq $53, %bits1, %ent1
    btsq %cnt1, %bits1

    /* Stream 2 */
    shrl $3, %cntd2, %nbd2
    andl $7, %cntd2
    subq %nb2, %ip2
    movq (%ip2), %bits2
    shlxq %cnt2, %bits2, %bits2
    shrq $53, %bits2, %ent2
    btsq %cnt2, %bits2

    /* Stream 3 */
    shrl $3, %cntd3, %nbd3
    andl $7, %cntd3
    subq %nb3, %ip3
    movq (%ip3), %bits3
    shlxq %cnt3, %bits3, %bits3
    shrq $53, %bits3, %ent3
    btsq %cnt3, %bits3

    /* If op3 < olimit: continue the loop */
    cmpq %op3, 0(%rsp)
    ja LOCAL_LABEL(4X2_apx_loop_body)
    jmp LOCAL_LABEL(4X2_apx_compute_olimit)

LOCAL_LABEL(4X2_apx_exit):
    /* Restore stack (olimit, oend & ilowest)
     * %rsp is 16-byte aligned here, %r16 is no longer used
     */
    pop2 %r16, %rax /* oend0, olimit */
    pop2 %r16, %rax /* oend2, oend1 */
    pop2 %r16, %rax /* ilowest, oend3 */
    popp %rax /* arg */

    /* Save ip / op / bits */
    APX_STORE_ARGS

    /* Restore the callee-saved registers */
    APX_RESTORE_REGS
    ret
    .cfi_endproc

#undef ent0
#undef ent1
#undef ent2
#undef ent3
#undef entd0
#undef entd1
#undef entd2
#undef entd3
#undef seq0
#undef seq1
#undef seq2
#undef seq3
#undef seqd0
#undef seqd1
#undef seqd2
#undef seqd3
#undef seqw0
#undef seqw1
#undef seqw2
#undef seqw3
#undef nb0
#undef nb1
#undef nb2
#undef nb3
#undef nbd0
#undef nbd1
#undef nbd2
#undef nbd3
#undef cnt0
#undef cnt1
#undef cnt2
#undef cnt3
#undef cntd0
#undef cntd1
#undef cntd2
#undef cntd3

#undef op0
#undef op1
#undef op2
#undef op3
#undef ip0
#undef ip1
#undef ip2
#undef ip3
#undef bits0
#undef bits1
#undef bits2
#undef bits3
#undef dtable

#undef APX_SETUP_FRAME
#undef APX_LEAVE_FRAME
#undef APX_SAVE_REGS
#undef APX_RESTORE_REGS
#undef APX_LOAD_ARGS
#undef APX_STORE_ARGS
#undef APX_USE_CCMP

#endif /* ZSTD_ENABLE_ASM_X86_64_APX */

#endif
