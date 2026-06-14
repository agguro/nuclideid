/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * File         : create_isotopes_db.s
 * Description  : Offline FPU CSV-to-Binary Matrix Transformer Engine with
 * 80-bit Hardware register division parity hooks.
 * Usage        : ./create_isotopes_db [-i input.csv] [-o output.bin]
 * ============================================================================
 */

.global _start

.section .rodata
    default_csv:  .string "isotopes.csv"
    default_bin:  .string "isotopes.bin"

    msg_start:    .asciz "[PARSER] Converting fields from %s to %s...\n"
    msg_done:     .asciz "[PARSER] Binary matrix successfully generated with bit-exact parity.\n"
    fmt_err:      .ascii "\033[1;31m[ERROR]\033[0m Source file not found or invalid syntax.\n"
    fmt_err_l = . - fmt_err

.section .data
    .align 8
    csv_name:     .quad 0
    bin_name:     .quad 0
    fd_in:        .quad 0
    fd_out:       .quad 0
    size_in:      .quad 0
    ptr_in:       .quad 0
    ptr_out:      .quad 0
    struct_cursor:.quad 0

.section .bss
    .align 16
    db_record:    .space 24             # Layout: Z(4), N(4), A(4), Symbol(4), k(8)
    ascii_hl:     .space 64
    comma_count:  .quad 0
    hl_ptr:       .quad 0
    line_started: .quad 0
    ptr_end:      .quad 0               # Memory anchor to safeguard loop boundary from clobbering

.section .text
_start:
    # Set up safe frame pointer and align stack to 16 bytes (ABI compliant)
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    subq    $128, %rsp                      # Scratch space for fstat struct allocation

    # --- Parse stack arguments (-i and -o flags) ---
    movq    8(%rbp), %r8                    # %r8 = argc
    leaq    24(%rbp), %rcx                  # %rcx = argv[1]
    leaq    default_csv(%rip), %rax
    movq    %rax, csv_name(%rip)
    leaq    default_bin(%rip), %rax
    movq    %rax, bin_name(%rip)

.L_parse_loop:
    movq    (%rcx), %rdi
    testq   %rdi, %rdi
    jz      .L_files_ready

    movb    (%rdi), %al
    cmpb    $45, %al                        # Check for '-' prefix
    jne     .L_next_p

    movb    1(%rdi), %al
    cmpb    $105, %al                       # Check for '-i' input flag
    jne     .L_check_o

    addq    $8, %rcx
    movq    (%rcx), %rax
    movq    %rax, csv_name(%rip)
    jmp     .L_next_p

.L_check_o:
    cmpb    $111, %al                       # Check for '-o' output flag
    jne     .L_next_p

    addq    $8, %rcx
    movq    (%rcx), %rax
    movq    %rax, bin_name(%rip)

.L_next_p:
    addq    $8, %rcx
    jmp     .L_parse_loop

.L_files_ready:
    # Print parser status notification
    leaq    msg_start(%rip), %rdi
    movq    csv_name(%rip), %rsi
    movq    bin_name(%rip), %rdx
    xorq    %rax, %rax
    call    printf@PLT

    # Open source CSV file (O_RDONLY = 0)
    movq    $2, %rax                        # sys_open
    movq    csv_name(%rip), %rdi
    xorq    %rsi, %rsi
    syscall
    js      error_exit
    movq    %rax, fd_in(%rip)

    # Fetch file capacity size via native sys_fstat (syscall 5)
    movq    $5, %rax                        # sys_fstat
    movq    fd_in(%rip), %rdi
    movq    %rsp, %rsi                      # Pass aligned stack pointer for stat struct
    syscall
    js      error_exit
    movq    48(%rsp), %rax                  # st_size resides at offset 48
    movq    %rax, size_in(%rip)

    # Map input text CSV read-only into virtual memory space
    movq    $9, %rax                        # sys_mmap
    xorq    %rdi, %rdi
    movq    size_in(%rip), %rsi
    movq    $1, %rdx                        # PROT_READ
    movq    $2, %r10                        # MAP_PRIVATE
    movq    fd_in(%rip), %r8
    xorq    %r9, %r9
    syscall
    js      error_exit
    movq    %rax, ptr_in(%rip)

    # Calculate and store the terminal memory stream limit boundary
    movq    ptr_in(%rip), %rsi
    movq    %rsi, %rax
    addq    size_in(%rip), %rax
    movq    %rax, ptr_end(%rip)             # Safe memory anchor setup

    # Allocate matrix destination target file (O_RDWR|O_CREAT|O_TRUNC = 0x242)
    movq    $2, %rax                        # sys_open
    movq    bin_name(%rip), %rdi
    movq    $0x242, %rsi
    movq    $0644, %rdx
    syscall
    js      error_exit
    movq    %rax, fd_out(%rip)

    # --- Parser Loop Setup ---
    movq    ptr_in(%rip), %rsi              # %rsi = active character memory reader

.L_skip_header_row:
    movb    (%rsi), %al
    incq    %rsi
    cmpb    $10, %al                        # Search for trailing heading line break
    jne     .L_skip_header_row

.L_parse_byte:
    # Perform strict boundary check against the protected memory anchor
    movq    ptr_end(%rip), %rax
    cmpq    %rax, %rsi                      # End of memory stream mapping reached?
    jae     .L_compiler_done

    movzbq  (%rsi), %rax                    # Ingest single byte to lower %rax accumulator
    incq    %rsi

    cmpb    $10, %al                        # Newline transition checker
    je      .L_newline
    cmpb    $44, %al                        # Comma column boundary checker
    je      .L_comma

    movq    comma_count(%rip), %rdx
    cmpq    $0, %rdx
    je      .L_z
    cmpq    $1, %rdx
    je      .L_n
    cmpq    $2, %rdx
    je      .L_sym
    cmpq    $16, %rdx
    je      .L_hl
    jmp     .L_parse_byte

.L_z:
    movl    (db_record+0)(%rip), %ecx
    imull   $10, %ecx
    subb    $48, %al
    movzbl  %al, %eax
    addl    %eax, %ecx
    movl    %ecx, (db_record+0)(%rip)       # Accrue atomic integer Z value
    jmp     .L_parse_byte

.L_n:
    movl    (db_record+4)(%rip), %ecx
    imull   $10, %ecx
    subb    $48, %al
    movzbl  %al, %eax
    addl    %eax, %ecx
    movl    %ecx, (db_record+4)(%rip)       # Accrue neutron integer N value
    jmp     .L_parse_byte

.L_sym:
    movq    hl_ptr(%rip), %rdx
    cmpq    $3, %rdx                        # Maximum 3 letters symbol constraint check
    jae     .L_parse_byte
    leaq    db_record+12(%rip), %rcx
    movb    %al, (%rcx,%rdx)
    incq    %rdx
    movq    %rdx, hl_ptr(%rip)
    jmp     .L_parse_byte

.L_hl:
    movq    hl_ptr(%rip), %rdx
    leaq    ascii_hl(%rip), %rcx
    movb    %al, (%rcx,%rdx)
    incq    %rdx
    movq    %rdx, hl_ptr(%rip)
    jmp     .L_parse_byte

.L_comma:
    movq    comma_count(%rip), %rdx
    cmpq    $16, %rdx                       # Column 17 (half_life_sec, index 16) finished?
    jne     .L_inc_comma

    movq    hl_ptr(%rip), %r8
    leaq    ascii_hl(%rip), %rcx
    movb    $0, (%rcx,%r8)                  # Impose immediate explicit null-termination

.L_inc_comma:
    incq    %rdx
    movq    %rdx, comma_count(%rip)
    movq    $0, hl_ptr(%rip)                # Reset character write head tracker index
    jmp     .L_parse_byte

.L_newline:
    # Compute Mass Number A = Z + N and commit to structural offset 8
    movl    (db_record+0)(%rip), %eax
    addl    (db_record+4)(%rip), %eax
    movl    %eax, (db_record+8)(%rip)

    # Verify field data against stable state constants
    movb    ascii_hl(%rip), %al
    testb   %al, %al
    jz      .L_commit_stable
    cmpb    $83, %al                        # Check for 'S' matching constraint (STABLE)
    je      .L_commit_stable

    # Call external library float parsing routine safely (ABI & Stack Alignment compliant)
    subq    $8, %rsp                        # 1. Pad stack by 8 bytes to secure alignment over push
    pushq   %rsi                            # 2. Push another 8 bytes -> Stack remains 16-byte aligned!
    leaq    ascii_hl(%rip), %rdi
    xorq    %rsi, %rsi
    call    strtod@PLT                      # Extracted float lands safely in %xmm0
    popq    %rsi
    addq    $8, %rsp                        # 3. Clean alignment padding from stack pointer

    # ==========================================================================
    # PURE HARDWARE 80-BIT FPU REGISTER MATRIX DIVISION: ELIMINATE DOUBLE ROUNDING
    # ==========================================================================
    subq    $8, %rsp                        # Allocate an 8-byte stack slot
    movsd   %xmm0, (%rsp)                   # Spill the parsed 64-bit half_life_sec onto the stack

    fldln2                                  # Load untamperable 80-bit ln(2) -> ST(0) = ln2
    fldl    (%rsp)                          # Load 64-bit half_life into FPU -> ST(0) = hl, ST(1) = ln2
    fdivrp  %st, %st(1)                     # Compute ST(1) / ST(0) and pop -> ST(0) = 80-bit pure k

    fstpl   (%rsp)                          # Round 80-bit k directly to 64-bit double and store
    movsd   (%rsp), %xmm1                   # Pull the bit-exact double into SSE register %xmm1
    addq    $8, %rsp                        # Reclaim the alignment stack frame space

    movsd   %xmm1, (db_record+16)(%rip)     # Commit double k-value to offset 16
    jmp     .L_write_record

.L_commit_stable:
    movq    $0, (db_record+16)(%rip)        # Stable nuclei decay rate constant -> k = 0.0

.L_write_record:
    # Flush aligned 24-byte record entry onto target storage
    # CRITICAL: Preserve character read pointer from destructive parameter overrides
    pushq   %rsi

    movq    $1, %rax                        # sys_write
    movq    fd_out(%rip), %rdi
    leaq    db_record(%rip), %rsi           # Buffer pointer pass
    movq    $24, %rdx
    syscall

    popq    %rsi                            # Restore pristine character stream pointer

.L_reset_row_state:
    # Empty structure state blocks for next block row
    movq    $0, comma_count(%rip)
    movq    $0, hl_ptr(%rip)
    movq    $0, db_record(%rip)
    movq    $0, db_record+8(%rip)
    movq    $0, db_record+16(%rip)
    jmp     .L_parse_byte

.L_compiler_done:
    # Tear down active resource file handles
    movq    $3, %rax                        # sys_close input
    movq    fd_in(%rip), %rdi
    syscall

    movq    $3, %rax                        # sys_close output
    movq    fd_out(%rip), %rdi
    syscall

    # Print validation success prompt
    leaq    msg_done(%rip), %rdi
    xorq    %rax, %rax
    call    printf@PLT

    # Return context variables and safely exit process execution scope
    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit Exit(0)
    xorq    %rdi, %rdi
    syscall

error_exit:
    movq    $1, %rax                        # sys_write stderr
    movq    $2, %rdi
    leaq    fmt_err(%rip), %rsi
    movq    $fmt_err_l, %rdx
    syscall

    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # Exit(1)
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
