/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * File         : isotopes_bitonic_sort.s
 * Description  : Standalone Autonomous GPU Bitonic Sorter with embedded CUBIN
 * and raw dynamic diagnostic return capabilities.
 * Usage        : ./isotopes_bitonic_sort [-o target_sorted.bin]
 * ============================================================================
 */

.global _start

.section .rodata
    default_bin:  .string "isotopes.bin"
    kernel_name:  .string "bitonic_sort"

    msg_start:    .asciz "[GPU-DRIVER] Loading embedded CUBIN image for bitonic sorting...\n"
    msg_gpu:      .asciz "[GPU-DRIVER] GPU Grid scaling configured to exactly %u records (GridX=%u).\n"
    msg_done:     .asciz "[GPU-DRIVER] Completed! Sorted database saved.\n"
    fmt_err:      .ascii "\033[1;31m[ERROR]\033[0m CUDA Driver API or I/O resource constraint failure.\n"
    fmt_err_l = . - fmt_err

    .align 8
    pad_k_inf:    .double 999999.0

    # ==========================================================================
    # EMBEDDED GPU SILICON IMAGE: INJECT CUBIN DIRECTLY INTO THE ELF SEGMENT
    # ==========================================================================
    .align 8
    gpu_kernel_start:
        .incbin "bitonic_sort.cubin"        # Ingests raw binary directly at compile-time
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
    param_j:      .long 0
    param_k:      .long 0
    param_N:      .long 0

    .align 8
    kernel_args:
        .quad param_db
        .quad param_j
        .quad param_k
        .quad param_N

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
    # Set up safe frame pointer and align stack to 16 bytes (ABI compliant)
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    subq    $128, %rsp                      # Scratch space for fstat struct allocation

    # --- ABI Stack Parser for -o Override Flag ---
    movq    8(%rbp), %r8                    # %r8 = argc
    leaq    24(%rbp), %rcx                  # %rcx = argv[1]
    leaq    default_bin(%rip), %rax
    movq    %rax, bin_target(%rip)

.L_sort_arg:
    movq    (%rcx), %rdi
    testq   %rdi, %rdi
    jz      .L_sort_files_ready

    movb    (%rdi), %al
    cmpb    $45, %al                        # Check for '-' character
    jne     .L_next_s

    movb    1(%rdi), %al
    cmpb    $111, %al                       # Check for 'o' character
    jne     .L_next_s

    addq    $8, %rcx
    movq    (%rcx), %rax
    movq    %rax, bin_target(%rip)

.L_next_s:
    addq    $8, %rcx
    jmp     .L_sort_arg

.L_sort_files_ready:
    # Open target file (O_RDWR = 2)
    movq    $2, %rax
    movq    bin_target(%rip), %rdi
    movq    $2, %rsi
    syscall
    js      error_exit
    movq    %rax, fd_bin(%rip)

    # Fetch file size metrics via native sys_fstat (syscall 5)
    movq    $5, %rax                        # sys_fstat
    movq    fd_bin(%rip), %rdi
    leaq    0(%rsp), %rsi                   # Pass aligned stack pointer for stat struct
    syscall
    js      error_exit
    movq    48(%rsp), %rax                  # st_size resides at offset 48
    movq    %rax, size_in(%rip)

    # Compute genuine record row count = size_in / 24 bytes
    xorq    %rdx, %rdx
    movq    $24, %rcx
    divq    %rcx
    movq    %rax, records_real(%rip)

    # --- BIT-SMEARING ALGORITHM FOR NEXT POWER-OF-2 MATRIX BOUNDARY ---
    decl    %eax

    movl    %eax, %ecx
    shrl    $1, %ecx
    orl     %ecx, %eax

    movl    %eax, %ecx
    shrl    $2, %ecx
    orl     %ecx, %eax

    movl    %eax, %ecx
    shrl    $4, %ecx
    orl     %ecx, %eax

    movl    %eax, %ecx
    shrl    $8, %ecx
    orl     %ecx, %eax

    movl    %eax, %ecx
    shrl    $16, %ecx
    orl     %ecx, %eax

    incl    %eax

    # Store determined power-of-2 dimensions
    movl    %eax, %eax                      # Explicitly zero-extend %eax into %rax
    movq    %rax, records_pow2(%rip)
    movl    %eax, param_N(%rip)

    # Compute padded byte sizing = records_pow2 * 24 bytes
    imulq   $24, %rax, %rcx
    movq    %rcx, size_pow2(%rip)

    # Compute active dynamic grid scaling: GridX = records_pow2 / 256
    shrq    $8, %rax
    movq    %rax, grid_x(%rip)

    # Extend file bounds via ftruncate
    movq    $77, %rax
    movq    fd_bin(%rip), %rdi
    movq    size_pow2(%rip), %rsi
    syscall
    js      error_exit

    # Map the extended binary matrix into shared workspace memory
    movq    $9, %rax                        # sys_mmap
    xorq    %rdi, %rdi
    movq    size_pow2(%rip), %rsi
    movq    $3, %rdx                        # PROT_READ | PROT_WRITE
    movq    $1, %r10                        # MAP_SHARED
    movq    fd_bin(%rip), %r8
    xorq    %r9, %r9
    syscall
    js      error_exit
    movq    %rax, ptr_out(%rip)

    # --- Matrix Opvullen (Pad Missing Gaps to Power-of-2 Grid Bounds) ---
    movq    records_real(%rip), %r12
    movq    ptr_out(%rip), %rdi

.L_pad_l:
    cmpq    records_pow2(%rip), %r12
    jae     .L_sort_gpu_init

    # Compute target structural index pointer: %rdi + %r12 * 24
    imulq   $24, %r12, %rcx
    addq    %rdi, %rcx

    # Zero out data headers
    movq    $0, 0(%rcx)
    movq    $0, 8(%rcx)

    # Inject maximum double floating boundary constraint to push padding to the tail end
    movq    pad_k_inf(%rip), %rax
    movq    %rax, 16(%rcx)

    incq    %r12
    jmp     .L_pad_l

.L_sort_gpu_init:
    leaq    msg_gpu(%rip), %rdi
    movl    param_N(%rip), %esi
    movl    grid_x(%rip), %edx
    xorq    %rax, %rax
    call    printf@PLT

    # --- CUDA API Execution Bootstrap with Strict Verification ---
    xorq    %rdi, %rdi
    call    cuInit@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit                 # Guard against missing GPU hardware lane entirely

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

    # ==========================================================================
    # ZERO-DEPENDENCY DESERIALIZATION: LOAD MODULE STRAIGHT FROM EXPERT .RODATA
    # ==========================================================================
    leaq    cu_module(%rip), %rdi           # Target module destination descriptor
    leaq    gpu_kernel_start(%rip), %rsi    # Pass direct pointer to embedded CUBIN blob
    call    cuModuleLoadData@PLT            # Synchronize raw image data directly into VRAM
    testl   %eax, %eax
    jnz     cuda_error_exit                 # Guard against corrupted internal binary image states

    # Extract function handle using the string symbol anchor
    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    kernel_name(%rip), %rdx
    call    cuModuleGetFunction@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit                 # Guard against symbol mismatch within compiled binary

    # Allocate safe arena inside Device VRAM matching size_pow2
    leaq    d_db_ptr(%rip), %rdi
    movq    size_pow2(%rip), %rsi
    call    cuMemAlloc@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    # Synchronize layout states onto VRAM device memory pipeline
    movq    d_db_ptr(%rip), %rdi
    movq    ptr_out(%rip), %rsi
    movq    size_pow2(%rip), %rdx
    call    cuMemcpyHtoD@PLT
    testl   %eax, %eax
    jnz     cuda_error_exit

    # Configure driver loop boundary variables
    movq    d_db_ptr(%rax), %rax
    movq    %rax, param_db(%rip)
    movl    $2, param_k(%rip)

.L_k_loop:
    movl    param_k(%rip), %eax
    shrl    $1, %eax
    movl    %eax, param_j(%rip)

.L_j_loop:
    # Trigger parallel execution blocks on hardware threads
    movq    cu_function(%rip), %rdi
    movq    grid_x(%rip), %rsi
    movq    $1, %rdx
    movq    $1, %rcx
    movq    $256, %r8                       # BlockX = 256 threads per CTA block
    movq    $1, %r9

    # Structure references dynamically while enforcing safe 16-byte stack boundaries
    subq    $48, %rsp
    movq    $0, 32(%rsp)
    movq    $0, 24(%rsp)
    leaq    kernel_args(%rip), %rax
    movq    %rax, 16(%rsp)                  # Pass target array address pointer
    movq    $0, 8(%rsp)
    movq    $1, 0(%rsp)
    call    cuLaunchKernel@PLT
    addq    $48, %rsp                       # Instantly wipe context frame allocation

    call    cuCtxSynchronize@PLT

    shrl    $1, param_j(%rip)
    jnz     .L_j_loop

    shll    $1, param_k(%rip)
    movl    param_N(%rip), %eax
    cmpl    %eax, param_k(%rip)
    jle     .L_k_loop

    # Download sorted matrix values directly back into shared mmap layout
    movq    ptr_out(%rip), %rdi
    movq    d_db_ptr(%rip), %rsi
    movq    size_pow2(%rip), %rdx
    call    cuMemcpyDtoH@PLT

    # Release memory mappings and close active file descriptors
    movq    $11, %rax                       # sys_munmap
    movq    ptr_out(%rip), %rdi
    movq    size_pow2(%rip), %rsi
    syscall

    movq    $3, %rax                        # sys_close
    movq    fd_bin(%rip), %rdi
    syscall

    # Print clean final completion log
    leaq    msg_done(%rip), %rdi
    xorq    %rax, %rax
    call    printf@PLT

    # Deallocate GPU handlers cleanly
    movq    d_db_ptr(%rip), %rdi
    call    cuMemFree@PLT
    movq    cu_context(%rip), %rdi
    call    cuCtxDestroy@PLT

    # Return stack structure to absolute entry pointer coordinates
    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit Exit(0)
    xorq    %rdi, %rdi
    syscall

cuda_error_exit:
    # --- DIAGNOSTIC MODE: Return the raw CUresult inside the exit code ---
    movl    %eax, %edi                      # Move the raw CUDA error code (CUresult) into %edi

    pushq   %rdi                            # Safeguard our error code over system write
    movq    $1, %rax                        # sys_write
    movq    $2, %rdi                        # stderr
    leaq    fmt_err(%rip), %rsi
    movq    $fmt_err_l, %rdx
    syscall
    popq    %rdi                            # Restore our exact CUDA error code

    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit Exit(CUresult)
    syscall

cuda_error_exit:
    # Handle critical GPU or Driver API infrastructure constraints
    movq    $1, %rax                        # sys_write
    movq    $2, %rdi                        # stderr
    leaq    fmt_err(%rip), %rsi             # Reference the existing error string
    movq    $fmt_err_l, %rdx
    syscall

    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit Exit(1)
    movq    $1, %rdi
    syscall

error_exit:
    # ==========================================================================
    # HOST I/O SAFETY LOCK: PRINT CLEAR EXPLICIT ERROR ON LOCAL PATH FAILURE
    # ==========================================================================
    movq    $1, %rax                        # sys_write
    movq    $2, %rdi                        # stderr
    leaq    fmt_err(%rip), %rsi             # Inform user about file/descriptor constraint
    movq    $fmt_err_l, %rdx
    syscall

    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit Exit(1)
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
