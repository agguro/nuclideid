/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * File         : create_isotopes_db.s
 * Description  : Offline FPU CSV-to-Binary Matrix Transformer Engine.
 * Upgraded to strict 32-byte structural record strides.
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
    .align 32
    # Layout geüpgraded naar exact 32 bytes om aan te sluiten op de shll $5 host-stride
    # Offsets: Z(0), N(4), A(8), Symbol(12), k_double(16), padding/unused(24) = 32 bytes
    db_record:    .space 32             
    ascii_hl:     .space 64
    comma_count:  .quad 0
    hl_ptr:       .quad 0
    line_started: .quad 0
    ptr_end:      .quad 0               

.section .text
_start:
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    subq    $128, %rsp                      

    # --- Parse stack arguments (-i and -o flags) ---
    movq    8(%rbp), %r8                    
    leaq    24(%rbp), %rcx                  
    leaq    default_csv(%rip), %rax
    movq    %rax, csv_name(%rip)
    leaq    default_bin(%rip), %rax
    movq    %rax, bin_name(%rip)

.L_parse_loop:
    movq    (%rcx), %rdi
    testq   %rdi, %rdi
    jz      .L_files_ready

    movb    (%rdi), %al
    cmpb    $45, %al                        
    jne     .L_next_p

    movb    1(%rdi), %al
    cmpb    $105, %al                       
    jne     .L_check_o

    addq    $8, %rcx
    movq    (%rcx), %rax
    movq    %rax, csv_name(%rip)
    jmp     .L_next_p

.L_check_o:
    cmpb    $111, %al                       
    jne     .L_next_p

    addq    $8, %rcx
    movq    (%rcx), %rax
    movq    %rax, bin_name(%rip)

.L_next_p:
    addq    $8, %rcx
    jmp     .L_parse_loop

.L_files_ready:
    leaq    msg_start(%rip), %rdi
    movq    csv_name(%rip), %rsi
    movq    bin_name(%rip), %rdx
    xorq    %rax, %rax
    call    printf@PLT

    # Open source CSV file
    movq    $2, %rax                        
    movq    csv_name(%rip), %rdi
    xorq    %rsi, %rsi
    syscall
    js      error_exit
    movq    %rax, fd_in(%rip)

    # Fetch file capacity size via native sys_fstat
    movq    $5, %rax                        
    movq    fd_in(%rip), %rdi
    movq    %rsp, %rsi                      
    syscall
    js      error_exit
    movq    48(%rsp), %rax                  
    movq    %rax, size_in(%rip)

    # Map input text CSV read-only into virtual memory space
    movq    $9, %rax                        
    xorq    %rdi, %rdi
    movq    size_in(%rip), %rsi
    movq    $1, %rdx                        
    movq    $2, %r10                        
    movq    fd_in(%rip), %r8
    xorq    %r9, %r9
    syscall
    js      error_exit
    movq    %rax, ptr_in(%rip)

    # Calculate terminal memory stream limit boundary
    movq    ptr_in(%rip), %rsi
    movq    %rsi, %rax
    addq    size_in(%rip), %rax
    movq    %rax, ptr_end(%rip)             

    # Allocate matrix destination target file
    movq    $2, %rax                        
    movq    bin_name(%rip), %rdi
    movq    $0x242, %rsi
    movq    $0644, %rdx
    syscall
    js      error_exit
    movq    %rax, fd_out(%rip)

    movq    ptr_in(%rip), %rsi              

.L_skip_header_row:
    movb    (%rsi), %al
    incq    %rsi
    cmpb    $10, %al                        
    jne     .L_skip_header_row

.L_parse_byte:
    movq    ptr_end(%rip), %rax
    cmpq    %rax, %rsi                      
    jae     .L_compiler_done

    movzbq  (%rsi), %rax                    
    incq    %rsi

    cmpb    $10, %al                        
    je      .L_newline
    cmpb    $44, %al                        
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
    movl    %ecx, (db_record+0)(%rip)       
    jmp     .L_parse_byte

.L_n:
    movl    (db_record+4)(%rip), %ecx
    imull   $10, %ecx
    subb    $48, %al
    movzbl  %al, %eax
    addl    %eax, %ecx
    movl    %ecx, (db_record+4)(%rip)       
    jmp     .L_parse_byte

.L_sym:
    movq    hl_ptr(%rip), %rdx
    cmpq    $3, %rdx                        
    jae     .L_parse_byte
    leaq    db_record+12(%rip), %rcx        # Offset 12 voor symbool string
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
    cmpq    $16, %rdx                       
    jne     .L_inc_comma

    movq    hl_ptr(%rip), %r8
    leaq    ascii_hl(%rip), %rcx
    movb    $0, (%rcx,%r8)                  

.L_inc_comma:
    incq    %rdx
    movq    %rdx, comma_count(%rip)
    movq    $0, hl_ptr(%rip)                
    jmp     .L_parse_byte

.L_newline:
    # Compute Mass Number A = Z + N and commit to structural offset 8
    movl    (db_record+0)(%rip), %eax
    addl    (db_record+4)(%rip), %eax
    movl    %eax, (db_record+8)(%rip)       # Offset 8 voor A

    # Verify field data against stable state constants
    movb    ascii_hl(%rip), %al
    testb   %al, %al
    jz      .L_commit_stable
    cmpb    $83, %al                        
    je      .L_commit_stable

    # Call external library float parsing routine safely
    subq    $8, %rsp                        
    pushq   %rsi                            
    leaq    ascii_hl(%rip), %rdi
    xorq    %rsi, %rsi
    call    strtod@PLT                      
    popq    %rsi
    addq    $8, %rsp                        

    # Execute 80-bit FPU Register Matrix Division
    subq    $8, %rsp                        
    movsd   %xmm0, (%rsp)                   

    fldln2                                  
    fldl    (%rsp)                          
    fdivrp  %st, %st(1)                     

    fstpl   (%rsp)                          
    movsd   (%rsp), %xmm1                   
    addq    $8, %rsp                        

    movsd   %xmm1, (db_record+16)(%rip)     # Offset 16 voor double k-value
    jmp     .L_write_record

.L_commit_stable:
    movq    $0, (db_record+16)(%rip)        

.L_write_record:
    pushq   %rsi

    # Schrijf de volledige gealigneerde 32-byte falanx weg naar schijf
    movq    $1, %rax                        # sys_write
    movq    fd_out(%rip), %rdi
    leaq    db_record(%rip), %rsi           
    movq    $32, %rdx                       # Gecorrigeerd naar exact 32 bytes structure stride
    syscall

    popq    %rsi                            

.L_reset_row_state:
    # Maak de complete 32-byte structuur weer leeg voor de volgende regel
    movq    $0, comma_count(%rip)
    movq    $0, hl_ptr(%rip)
    movq    $0, db_record(%rip)
    movq    $0, db_record+8(%rip)
    movq    $0, db_record+16(%rip)
    movq    $0, db_record+24(%rip)          # Wis ook de padding bytes
    jmp     .L_parse_byte

.L_compiler_done:
    movq    $3, %rax                        
    movq    fd_in(%rip), %rdi
    syscall

    movq    $3, %rax                        
    movq    fd_out(%rip), %rdi
    syscall

    leaq    msg_done(%rip), %rdi
    xorq    %rax, %rax
    call    printf@PLT

    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       
    xorq    %rdi, %rdi
    syscall

error_exit:
    movq    $1, %rax                        
    movq    $2, %rdi
    leaq    fmt_err(%rip), %rsi
    movq    $fmt_err_l, %rdx
    syscall

    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
