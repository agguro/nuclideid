/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * File         : create_isotopes_db.s
 * Description  : Token-Based Offline SSE CSV-to-Binary Matrix Transformer.
 * Design       : Stack-alignment proof, ABI compliant, fully isolated wrappers.
 * ============================================================================
 */

.global _start
.extern printf, strtod

.section .rodata
    csv_file:     .string "isotopes.csv"
    bin_file:     .string "isotopes.bin"
    msg_start:    .string "[PARSER] Token-based conversion starting: isotopes.csv -> isotopes.bin\n"
    msg_done:     .string "[PARSER] Binary master database successfully generated.\n"
    msg_error:    .string "[ERROR] Critical failure in database compiler pipeline.\n"

    .align 8
    pad_k_inf:    .double 999999.0
    ln2_val:      .double 0.693147180559945309417  # Pre-calculated ln(2) for SSE64

.section .data
    fd_in:        .quad 0
    fd_out:       .quad 0
    size_in:      .quad 0
    ptr_in:       .quad 0
    ptr_end:      .quad 0
    hl_ptr:       .quad 0

.section .bss
    .align 8
    stat_buf:     .space 144

    .align 16
    ascii_hl:     .space 64

    # Internal 64-byte matrix record buffer (Standard Stride)
    .align 64
    db_record:    .space 64

.section .text
_start:
    # Strict SysV ABI 16-byte stack frame alignment
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    # Safe isolated call to print start message
    leaq    msg_start(%rip), %rdi
    call    safe_printf

    # --- 1. Open Input CSV via sys_open (syscall 2) ---
    movq    $2, %rax
    leaq    csv_file(%rip), %rdi
    xorq    %rsi, %rsi                      # O_RDONLY = 0
    syscall
    cmpl    $0, %eax
    js      .L_error_pipeline
    movq    %rax, fd_in(%rip)

    # --- 2. Open Output Binary via sys_open ---
    movq    $2, %rax
    leaq    bin_file(%rip), %rdi
    movq    $577, %rsi                      # O_WRONLY(1) | O_CREAT(64) | O_TRUNC(512)
    movq    $420, %rdx                      # Permissions 0644
    syscall
    cmpl    $0, %eax
    js      .L_error_pipeline
    movq    %rax, fd_out(%rip)

    # --- 3. Get file size via sys_fstat (syscall 5) ---
    movq    $5, %rax
    movq    fd_in(%rip), %rdi
    leaq    stat_buf(%rip), %rsi
    syscall
    cmpl    $0, %eax
    js      .L_error_pipeline
    
    leaq    stat_buf(%rip), %rax
    movq    48(%rax), %rcx                  # st_size is located at offset 48
    movq    %rcx, size_in(%rip)

    testq   %rcx, %rcx                      # Guard against empty files
    jz      .L_error_pipeline

    # --- 4. Map CSV into virtual memory via sys_mmap (syscall 9) ---
    movq    $9, %rax
    xorq    %rdi, %rdi
    movq    size_in(%rip), %rsi
    movq    $1, %rdx                        # PROT_READ = 1
    movq    $2, %r10                        # MAP_PRIVATE = 2
    movq    fd_in(%rip), %r8
    xorq    %r9, %r9
    syscall
    cmpq    $-1, %rax
    je      .L_error_pipeline
    movq    %rax, ptr_in(%rip)

    # Anchor the end pointer of the mapped memory
    addq    size_in(%rip), %rax
    movq    %rax, ptr_end(%rip)

    # --- 5. Unconditionally skip the CSV Header row ---
    movq    ptr_in(%rip), %rsi              # %rsi = active stream cursor
.L_skip_header_loop:
    movq    ptr_end(%rip), %rax
    cmpq    %rax, %rsi
    jae     .L_compiler_done
    movb    (%rsi), %cl                     # Load byte into %cl to protect %rax
    incq    %rsi
    cmpb    $10, %cl                        # Look for the first newline (\n)
    jne     .L_skip_header_loop

    # --- 6. Initialize Live Status Registers for Token-Parsing ---
    xorq    %r13, %r13                      # %r13 = Field index within current row (starts at 0)
    leaq    ascii_hl(%rip), %r14            # %r14 = Base address of the active field buffer

    # --- 7. Main Parsing Loop (Field by Field) ---
.L_parse_byte:
    movq    ptr_end(%rip), %rax
    cmpq    %rax, %rsi                      # Reached EOF / mmap boundary?
    jae     .L_eof_flush                    # <<< CHANGED: handle pending last line at EOF

    movzbq  (%rsi), %rax                    # Consume current byte
    incq    %rsi

    cmpb    $13, %al                        # Skip Carriage Return (\r) for Windows files
    je      .L_parse_byte
    cmpb    $10, %al                        # EOL (\n)? -> Process field, close row
    je      .L_field_end_newline
    cmpb    $44, %al                        # Comma (,)? -> Process field, increment index
    je      .L_field_end_comma

    # --- Store character in the active field buffer ---
    movq    hl_ptr(%rip), %rdx
    cmpq    $63, %rdx                       # Buffer guard: max 64 bytes per field
    jae     .L_parse_byte
    movb    %al, (%r14,%rdx)
    incq    %rdx
    movq    %rdx, hl_ptr(%rip)
    jmp     .L_parse_byte

.L_field_end_comma:
    call    .L_process_field                # Field is complete: evaluate data
    incq    %r13                            # Increment local field index for this row
    jmp     .L_parse_byte

.L_field_end_newline:
    call    .L_process_field                # Process the very last field of the row

    # --- END OF ROW EVALUATION & MATRIX COMMIT ---
    # Check if valid nuclide data was read (Z or N must be > 0)
    movq    (db_record+0)(%rip), %rax       
    movq    (db_record+8)(%rip), %rdx       
    orq     %rdx, %rax                      # Filters out empty trailing lines/whitespace
    jz      .L_reset_line

    # Calculate Mass Number A = Z + N
    movq    (db_record+0)(%rip), %rax
    addq    %rdx, %rax                      # %rax = Z + N
    movq    %rax, (db_record+16)(%rip)      # Store at offset 16

    # Write the validated 64-byte matrix record to disk via sys_write (syscall 1)
    movq    $1, %rax                        
    movq    fd_out(%rip), %rdi
    leaq    db_record(%rip), %rdx
    pushq   %rsi                            # Safe preserve around syscall
    movq    %rdx, %rsi
    movq    $64, %rdx                       # Exact 64 bytes structure stride
    syscall
    popq    %rsi
    cmpq    $0, %rax
    js      .L_error_pipeline

.L_reset_line:
    # Clear the entire matrix record buffer for the next row
    pushq   %rdi
    pushq   %rcx
    pushq   %rax
    leaq    db_record(%rip), %rdi
    movq    $8, %rcx                        # 8 quads = 64 bytes
    xorq    %rax, %rax
    rep     stosq                           # Wipe clean with zeros
    popq    %rax
    popq    %rcx
    popq    %rdi

    # Unconditionally reset row-linked state registers
    xorq    %r13, %r13                      # Field index returns to 0
    movq    $0, hl_ptr(%rip)
    movb    $0, ascii_hl(%rip)
    jmp     .L_parse_byte

# ============================================================================
# NEW: EOF FLUSH FOR LAST LINE WITHOUT NEWLINE
# ============================================================================
.L_eof_flush:
    # If no pending field bytes, nothing to flush -> normal exit
    movq    hl_ptr(%rip), %rax
    testq   %rax, %rax
    jz      .L_compiler_done

    # Process the last field as if we just saw a newline
    call    .L_process_field

    # Same row validation as in .L_field_end_newline
    movq    (db_record+0)(%rip), %rax
    movq    (db_record+8)(%rip), %rdx
    orq     %rdx, %rax
    jz      .L_compiler_done

    # A = Z + N
    movq    (db_record+0)(%rip), %rax
    addq    %rdx, %rax
    movq    %rax, (db_record+16)(%rip)

    # Write final 64-byte record
    movq    $1, %rax
    movq    fd_out(%rip), %rdi
    leaq    db_record(%rip), %rsi
    movq    $64, %rdx
    syscall
    cmpq    $0, %rax
    js      .L_error_pipeline

    jmp     .L_compiler_done

# ============================================================================
# SUBROUTINE: PROCESS LOCAL FIELD BASED ON CURRENT INDEX
# ============================================================================
.L_process_field:
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp                      # Local stack alignment safeguard

    movq    hl_ptr(%rip), %rdx              # Length of the constructed field
    leaq    ascii_hl(%rip), %rcx            # %rcx points to string data
    movb    $0, (%rcx,%rdx)                 # Null-terminate active field buffer
    
    testq   %rdx, %rdx                      # Is field empty?
    jz      .L_clear_field_ptr              # Yes: jump straight to cleanup

    cmpq    $0, %r13                        # Field 0: Protons (Z)
    je      .L_parse_z_field
    cmpq    $1, %r13                        # Field 1: Neutrons (N)
    je      .L_parse_n_field
    cmpq    $2, %r13                        # Field 2: Chemical Symbol
    je      .L_parse_sym_field
    cmpq    $16, %r13                       # Field 16: Half-life in seconds
    je      .L_parse_hl_field
    jmp     .L_clear_field_ptr

.L_parse_z_field:
    xorq    %rax, %rax
    xorq    %rbx, %rbx
.L_z_loop:
    movb    (%rcx,%rbx), %al
    testb   %al, %al
    jz      .L_clear_field_ptr
    subb    $48, %al                        
    movzbq  %al, %rax                       
    movq    (db_record+0)(%rip), %r11       
    imulq   $10, %r11                       
    addq    %rax, %r11                      
    movq    %r11, (db_record+0)(%rip)       
    incq    %rbx
    jmp     .L_z_loop

.L_parse_n_field:
    xorq    %rax, %rax
    xorq    %rbx, %rbx
.L_n_loop:
    movb    (%rcx,%rbx), %al
    testb   %al, %al
    jz      .L_clear_field_ptr
    subb    $48, %al                        
    movzbq  %al, %rax                       
    movq    (db_record+8)(%rip), %r11       
    imulq   $10, %r11                       
    addq    %rax, %r11                      
    movq    %r11, (db_record+8)(%rip)       
    incq    %rbx
    jmp     .L_n_loop

.L_parse_sym_field:
    movq    $0, (db_record+24)(%rip)
    movq    (%rcx), %rax                    
    movq    %rax, (db_record+24)(%rip)
    jmp     .L_clear_field_ptr

.L_parse_hl_field:
    movb    (%rcx), %al
    cmpb    $83, %al                        # 'S' = STABLE?
    je      .L_hl_stable

    # Safe isolated call to our strtod wrapper
    movq    %rcx, %rdi                      # Pass string address
    call    safe_strtod                     # Out: %xmm0 = double value (All registers preserved!)

    movsd   %xmm0, (db_record+32)(%rip)     # Store T_1/2

    # --- Modern SSE K-calculation: k = ln(2) / T_1/2 ---
    movsd   ln2_val(%rip), %xmm1            # Load pre-calculated ln(2)
    divsd   %xmm0, %xmm1                    # %xmm1 = ln(2) / T_1/2

    movsd   %xmm1, (db_record+40)(%rip)     # K_Value
    movsd   %xmm1, (db_record+48)(%rip)     # Sort_Key (For Bitonic Sort)
    jmp     .L_clear_field_ptr

.L_hl_stable:
    movq    $0, (db_record+32)(%rip)        
    movq    $0, (db_record+40)(%rip)        
    movq    pad_k_inf(%rip), %rax           # Inf key for sorting sinks
    movq    %rax, (db_record+48)(%rip)

.L_clear_field_ptr:
    movq    $0, hl_ptr(%rip)                

.L_field_done:
    movq    %rbp, %rsp                      
    popq    %rbp
    ret

# --- Wrapper voor strtod ---
safe_strtod:
    pushq   %rsi
    pushq   %rdi
    pushq   %rcx
    pushq   %rdx
    pushq   %rbx
    pushq   %r11
    pushq   %r13
    pushq   %r14

    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    xorq    %rsi, %rsi
    xorq    %rax, %rax
    call    strtod@PLT

    movq    %rbp, %rsp
    popq    %rbp

    popq    %r14
    popq    %r13
    popq    %r11
    popq    %rbx
    popq    %rdx
    popq    %rcx
    popq    %rdi
    popq    %rsi
    ret

# --- Wrapper voor printf ---
safe_printf:
    pushq   %rsi
    pushq   %rdi
    pushq   %rcx
    pushq   %rdx
    pushq   %r11

    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    xorq    %rax, %rax
    call    printf@PLT

    movq    %rbp, %rsp
    popq    %rbp

    popq    %r11
    popq    %rdx
    popq    %rcx
    popq    %rdi
    popq    %rsi
    ret

# ============================================================================
# PIPELINE EXIT MECHANISMS
# ============================================================================
.L_compiler_done:
    movq    $3, %rax                        # sys_close fd_in
    movq    fd_in(%rip), %rdi
    syscall
    movq    $3, %rax                        # sys_close fd_out
    movq    fd_out(%rip), %rdi
    syscall

    movq    $11, %rax                       # sys_munmap
    movq    ptr_in(%rip), %rdi
    movq    size_in(%rip), %rsi
    syscall

    leaq    msg_done(%rip), %rdi
    call    safe_printf

    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit(0)
    xorq    %rdi, %rdi
    syscall

.L_error_pipeline:
    leaq    msg_error(%rip), %rdi
    call    safe_printf
    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit(1)
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
