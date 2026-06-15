/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * File         : isotopes_bitonic_sort.s
 * Description  : Standalone Autonomous GPU Bitonic Sorter.
 * Usage        : ./isotopes_bitonic_sort [-o target_sorted.bin]
 * ============================================================================
 */

.global _start

.section .rodata
    default_bin:  .string "isotopes.bin"
    kernel_name:  .string "isotopes_bitonic_sort"

    msg_start:    .asciz "[GPU-DRIVER] Loading embedded CUBIN image for bitonic sorting...\n"
    msg_gpu:      .asciz "[GPU-DRIVER] GPU Grid scaling configured to exactly %lu records (GridX=%lu).\n"
    msg_done:     .asciz "[GPU-DRIVER] Completed! Sorted database saved.\n"
    fmt_err:      .ascii "\033[1;31m[ERROR]\033[0m CUDA Driver API or I/O resource constraint failure.\n"
    fmt_err_l = . - fmt_err

    .align 8
    pad_k_inf:    .double 999999.0

    .align 8
gpu_kernel_start:
    .incbin "isotopes_bitonic_sort.cubin"
gpu_kernel_end:

.section .data
    .align 8
    cu_device:    .long 0
    cu_context:   .quad 0
    cu_module:    .quad 0
    cu_function:  .quad 0
    d_db_ptr:     .quad 0

    .align 8
    param_db:     .quad 0
    .align 8
    param_j:      .quad 0
    .align 8
    param_k:      .quad 0
    .align 8
    param_N:      .quad 0

    .align 8
    kernel_args:
        .quad param_db
        .quad param_j
        .quad param_k
        .quad param_N

    .align 8
    stat_buf:     .zero 144

.section .bss
    .align 8
    bin_target:   .quad 0
    fd_bin:       .quad 0
    size_in:      .quad 0
    records_real: .quad 0
    records_pow2: .quad 0
    size_pow2:    .quad 0
    ptr_out:      .quad 0
    grid_x:       .quad 0

.section .text
_start:
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    # --- parse -o ---
    movq    8(%rbp), %r8
    leaq    24(%rbp), %rcx
    leaq    default_bin(%rip), %rax
    movq    %rax, bin_target(%rip)

.L_sort_arg:
    movq    (%rcx), %rdi
    testq   %rdi, %rdi
    jz      .L_sort_files_ready

    movb    (%rdi), %al
    cmpb    $'-', %al
    jne     .L_next_s

    movb    1(%rdi), %al
    cmpb    $'o', %al
    jne     .L_next_s

    addq    $8, %rcx
    movq    (%rcx), %rax
    movq    %rax, bin_target(%rip)

.L_next_s:
    addq    $8, %rcx
    jmp     .L_sort_arg

.L_sort_files_ready:
    # open
    movq    $2, %rax
    movq    bin_target(%rip), %rdi
    movq    $2, %rsi
    syscall
    js      error_exit
    movq    %rax, fd_bin(%rip)

    # fstat into stat_buf
    movq    $5, %rax
    movq    fd_bin(%rip), %rdi
    leaq    stat_buf(%rip), %rsi
    syscall
    js      error_exit
    movq    48(%rsi), %rax
    movq    %rax, size_in(%rip)

    # records_real = size_in / 64
    xorq    %rdx, %rdx
    movq    $64, %rcx
    divq    %rcx
    movq    %rax, records_real(%rip)

    # --- Hacker's Delight: Next Power of 2 (Pure 64-bit Arithmetic) ---
    decq    %rax                  # %rax = records_real - 1
    
    movq    %rax, %rcx
    shrq    $1, %rcx
    orq     %rcx, %rax
    
    movq    %rax, %rcx
    shrq    $2, %rcx
    orq     %rcx, %rax
    
    movq    %rax, %rcx
    shrq    $4, %rcx
    orq     %rcx, %rax
    
    movq    %rax, %rcx
    shrq    $8, %rcx
    orq     %rcx, %rax
    
    movq    %rax, %rcx
    shrq    $16, %rcx
    orq     %rcx, %rax
    
    movq    %rax, %rcx
    shrq    $32, %rcx
    orq     %rcx, %rax
    
    incq    %rax                  # %rax holds exact power of 2 (e.g., 4096)

    movq    %rax, records_pow2(%rip)
    movq    %rax, param_N(%rip)

    # size_pow2 = N * 64
    imulq   $64, %rax, %rcx
    movq    %rcx, size_pow2(%rip)

    # grid_x = N / 256
    shrq    $8, %rax
    movq    %rax, grid_x(%rip)

    # ftruncate
    movq    $77, %rax
    movq    fd_bin(%rip), %rdi
    movq    size_pow2(%rip), %rsi
    syscall
    js      error_exit

    # mmap
    movq    $9, %rax
    xorq    %rdi, %rdi
    movq    size_pow2(%rip), %rsi
    movq    $3, %rdx
    movq    $1, %r10
    movq    fd_bin(%rip), %r8
    xorq    %r9, %r9
    syscall
    js      error_exit
    movq    %rax, ptr_out(%rip)

    # pad to power-of-2
    movq    records_real(%rip), %r12
    movq    ptr_out(%rip), %rdi

.L_pad_l:
    cmpq    records_pow2(%rip), %r12
    jae     .L_sort_gpu_init

    imulq   $64, %r12, %rcx
    addq    %rdi, %rcx

    movq    $0, 0(%rcx)
    movq    $0, 8(%rcx)
    movq    $0, 16(%rcx)
    movq    $0, 24(%rcx)
    movq    $0, 32(%rcx)
    movq    $0, 40(%rcx)
    movq    pad_k_inf(%rip), %rax
    movq    %rax, 48(%rcx)
    movq    $0, 56(%rcx)
    
    incq    %r12
    jmp     .L_pad_l

.L_sort_gpu_init:
    leaq    msg_gpu(%rip), %rdi
    movq    param_N(%rip), %rsi
    movq    grid_x(%rip), %rdx
    xorq    %rax, %rax
    call    printf@PLT

    xorq    %rdi, %rdi
    call    cuInit@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    leaq    cu_device(%rip), %rdi
    xorq    %rsi, %rsi
    call    cuDeviceGet@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    leaq    cu_context(%rip), %rdi
    xorq    %rsi, %rsi
    movl    cu_device(%rip), %edx
    call    cuCtxCreate@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    leaq    cu_module(%rip), %rdi
    leaq    gpu_kernel_start(%rip), %rsi
    call    cuModuleLoadData@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    kernel_name(%rip), %rdx
    call    cuModuleGetFunction@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    leaq    d_db_ptr(%rip), %rdi
    movq    size_pow2(%rip), %rsi
    call    cuMemAlloc@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    movq    d_db_ptr(%rip), %rdi
    movq    ptr_out(%rip), %rsi
    movq    size_pow2(%rip), %rdx
    call    cuMemcpyHtoD@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    movq    d_db_ptr(%rip), %rax
    movq    %rax, param_db(%rip)
    movq    $2, param_k(%rip)

.L_k_loop:
    movq    param_k(%rip), %rax
    shrq    $1, %rax
    movq    %rax, param_j(%rip)
.L_j_loop:
    movq    cu_function(%rip), %rdi
    movq    grid_x(%rip), %rsi
    movq    $1, %rdx              # gridDimY
    movq    $1, %rcx              # gridDimZ
    movq    $256, %r8             # blockDimX
    movq    $1, %r9               # blockDimY

    # Space for exactly 5 remaining stack arguments (ABI Compliant & Aligned)
    subq    $48, %rsp

    movq    $1, 0(%rsp)           # Arg 7:  unsigned int blockDimZ = 1
    movq    $0, 8(%rsp)           # Arg 8:  unsigned int sharedMemBytes = 0
    movq    $0, 16(%rsp)          # Arg 9:  CUstream hStream = NULL
    leaq    kernel_args(%rip), %rax
    movq    %rax, 24(%rsp)        # Arg 10: void** kernelParams = &kernel_args[0]
    movq    $0, 32(%rsp)          # Arg 11: void** extra = NULL

    call    cuLaunchKernel@PLT
    addq    $48, %rsp             # Instantly clean stack frame

    testl   %eax, %eax
    jnz     cuda_error_exit

    call    cuCtxSynchronize@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    shrq    $1, param_j(%rip)
    jnz     .L_j_loop

    shlq    $1, param_k(%rip)
    movq    param_N(%rip), %rax
    cmpq    %rax, param_k(%rip)
    jle     .L_k_loop

    movq    ptr_out(%rip), %rdi
    movq    d_db_ptr(%rip), %rsi
    movq    size_pow2(%rip), %rdx
    call    cuMemcpyDtoH@PLT

    movq    $11, %rax
    movq    ptr_out(%rip), %rdi
    movq    size_pow2(%rip), %rsi
    syscall

    movq    $3, %rax
    movq    fd_bin(%rip), %rdi
    syscall

    leaq    msg_done(%rip), %rdi
    xorq    %rax, %rax
    call    printf@PLT

    movq    d_db_ptr(%rip), %rdi
    call    cuMemFree@PLT
    movq    cu_context(%rip), %rdi
    call    cuCtxDestroy@PLT

    movq    %rbp, %rsp
    popq    %rbp
    movq    $231, %rax            # sys_exit_group
    xorq    %rdi, %rdi
    syscall

cuda_error_exit:
    movl    %eax, %edi
    pushq   %rdi
    movq    $1, %rax
    movq    $2, %rdi
    leaq    fmt_err(%rip), %rsi
    movq    $fmt_err_l, %rdx
    syscall
    popq    %rdi
    movq    %rbp, %rsp
    popq    %rbp
    movq    $231, %rax            # sys_exit_group
    syscall

error_exit:
    movq    $1, %rax
    movq    $2, %rdi
    leaq    fmt_err(%rip), %rsi
    movq    $fmt_err_l, %rdx
    syscall
    movq    %rbp, %rsp
    popq    %rbp
    movq    $231, %rax            # sys_exit_group
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
