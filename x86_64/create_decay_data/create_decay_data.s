# ============================================================================
# Title       : CUDA Decay Data Generator Host (10-Digit High Fidelity Edition)
# Architecture: x86_64 | Linux SysV ABI | AT&T Syntax
# Description : Headerless GPU Execution with 16-byte datapunten (double2).
#               Dynamische max_t parsing vanaf de commandline (argv[3]).
# Author      : agguro
# ============================================================================

.section .rodata
    .align 16
    func_name:    .string "create_decay_data"
    def_bin:      .string "decay_data.bin"
    def_csv:      .string "decay_data.csv"
    
    flag_o:       .string "-o"
    flag_csv:     .string "-csv"
    
    fmt_start:    .ascii "\033[1;34m[generator]\033[0m Generating f64 data on GPU...\n"
    fmt_start_l:  .long . - fmt_start
    fmt_done:     .ascii "\033[1;32m[SUCCES]\033[0m High-fidelity data veilig weggeschreven.\n"
    fmt_done_l:   .long . - fmt_done
    fmt_error:    .ascii "\033[1;31m[ERROR]\033[0m Ongeldige argumenten.\nGebruik: create_decay_data k npoints max_t [-o file.bin] [-csv]\n"
    fmt_error_l:  .long . - fmt_error
    fmt_fail:     .ascii "\033[1;31m[CUDA LAUNCH FAILED]\033[0m Error-code: 0x"
    fmt_fail_l:   .long . - fmt_fail
    fmt_dot:      .ascii "."
    
    csv_prec:     .quad 10              
    csv_mult:     .quad 10000000000     

    csv_header:   .ascii "t,y\n"
    csv_header_l: .long . - csv_header
    fmt_comma:    .ascii ","
    fmt_nl:       .ascii "\n"

    .align 8
    cubin_start:
        .incbin "create_decay_data.cubin"
    cubin_end:

.section .data
    .align 16
    cu_ctx:        .quad 0
    cu_device:     .long 0
    cu_module:     .quad 0
    cu_function:   .quad 0
    d_out_ptr:     .quad 0          

    # Output bestandsnamen pointers
    bin_path:      .quad def_bin
    csv_path:      .quad 0
    write_csv:     .byte 0

    # Geparsed parameters uit CLI (64-bit doubles)
    .align 8
    k_val:         .double 0.0      
    npoints:       .long 0          
    max_t:         .double 0.0       # Nu standaard 0.0, wordt overschreven via CLI

    # De argumenten-array die de DIRECTE ADRESSEN bevat
    .align 8
    kernel_args:   .quad d_out_ptr, k_val, npoints, max_t

    # Buffers voor bestandsafhandeling
    fd_bin:        .quad 0
    fd_csv:        .quad 0
    host_buffer:   .quad 0    
    buffer_size:   .quad 0    

    .align 16
    ascii_buf:     .zero 64
    hex_buf:       .ascii "00\n"

.section .text
.globl _start
_start:
    # --- 1. Argument Parsing ---
    movq    (%rsp), %r15                    # %r15 = argc
    cmpq    $4, %r15                        # Nu minimaal 4 argumenten vereist (prog, k, npoints, max_t)
    jl      .L_usage

    # Parse K as double (64-bit) -> argv[1]
    movq    16(%rsp), %rax                  
    call    parse_float_double
    movsd   %xmm0, k_val(%rip)

    # Parse npoints -> argv[2]
    movq    24(%rsp), %rax                  
    call    parse_int
    movl    %eax, npoints(%rip)
    testl   %eax, %eax
    jle     .L_usage

    # Bereken totale buffer grootte (npoints * 16 bytes per double2 paar)
    shll    $4, %eax            
    movq    %rax, buffer_size(%rip)

    # Parse max_t as double (64-bit) -> argv[3]
    movq    32(%rsp), %rax
    call    parse_float_double
    movsd   %xmm0, max_t(%rip)

    # Loop door optionele vlaggen vanaf argv[4]
    movq    $4, %r12
.L_arg_parse_loop:
    cmpq    %r15, %r12
    jge     .L_arg_parse_done
    
    movq    8(%rsp, %r12, 8), %rdi          
    leaq    flag_o(%rip), %rsi
    call    strcmp_local
    testl   %eax, %eax
    jnz     .L_check_csv_flag

    incq    %r12
    cmpq    %r15, %r12
    jge     .L_usage
    movq    8(%rsp, %r12, 8), %rax
    movq    %rax, bin_path(%rip)
    jmp     .L_next_arg

.L_check_csv_flag:
    movq    8(%rsp, %r12, 8), %rdi
    leaq    flag_csv(%rip), %rsi
    call    strcmp_local
    testl   %eax, %eax
    jnz     .L_next_arg

    movb    $1, write_csv(%rip)
    leaq    def_csv(%rip), %rax
    movq    %rax, csv_path(%rip)

.L_next_arg:
    incq    %r12
    jmp     .L_arg_parse_loop

.L_usage:
    movl    $1, %eax                        
    movl    $2, %edi                        
    leaq    fmt_error(%rip), %rsi
    movl    fmt_error_l(%rip), %edx
    syscall
    movl    $1, %edi
    jmp     .L_exit

.L_arg_parse_done:
    # --- 2. Stack Frame Setup ---
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp                      
    subq    $256, %rsp                      

    # --- 3. CUDA Setup via v2 Entrypoints ---
    xorl    %edi, %edi
    call    cuInit@PLT

    leaq    128(%rsp), %rdi                 
    xorl    %esi, %esi
    call    cuDeviceGet@PLT

    leaq    136(%rsp), %rdi                 
    xorl    %esi, %esi
    movl    128(%rsp), %edx                 
    call    cuCtxCreate_v2@PLT

    leaq    cu_module(%rip), %rdi
    leaq    cubin_start(%rip), %rsi
    call    cuModuleLoadData@PLT

    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    func_name(%rip), %rdx
    call    cuModuleGetFunction@PLT

    # --- 4. Memory Allocation ---
    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_start(%rip), %rsi
    movl    fmt_start_l(%rip), %edx
    syscall

    leaq    d_out_ptr(%rip), %rdi
    movq    buffer_size(%rip), %rsi
    call    cuMemAlloc_v2@PLT

    movl    $9, %eax                        
    xorq    %rdi, %rdi
    movq    buffer_size(%rip), %rsi
    movl    $3, %edx                        
    movl    $34, %r10d                      
    movq    $-1, %r8
    xorq    %r9, %r9
    syscall
    movq    %rax, host_buffer(%rip)

    # --- 5. GPU Launch ---
    movq    cu_function(%rip), %rdi
    movl    $32, %esi                       
    movl    $1, %edx
    movl    $1, %ecx
    movl    $256, %r8d                      
    movl    $1, %r9d
    
    subq    $48, %rsp                       
    movq    $1, 0(%rsp)     
    movq    $1, 8(%rsp)     
    movq    $0, 16(%rsp)    
    leaq    kernel_args(%rip), %rax         
    movq    %rax, 24(%rsp)  
    movq    $0, 32(%rsp)
    movq    $0, 40(%rsp)
    call    cuLaunchKernel@PLT
    addq    $48, %rsp

    # --- BARE-METAL RETURN-CODE CHECK ---
    testl   %eax, %eax                      
    jz      .L_launch_ok                    

    movl    %eax, %r13d                     
    movl    $1, %eax
    movl    $2, %edi
    leaq    fmt_fail(%rip), %rsi
    movl    fmt_fail_l(%rip), %edx
    syscall

    leaq    hex_buf(%rip), %rdi
    movl    %r13d, %edx
    shrl    $4, %edx
    andl    $15, %edx
    cmpb    $10, %dl
    jae     .L_hex_alpha1
    addb    $48, %dl
    jmp     .L_hex_store1
.L_hex_alpha1:
    addb    $55, %dl
.L_hex_store1:
    movb    %dl, (%rdi)

    movl    %r13d, %edx
    andl    $15, %edx
    cmpb    $10, %dl
    jae     .L_hex_alpha2
    addb    $48, %dl
    jmp     .L_hex_store2
.L_hex_alpha2:
    addb    $55, %dl
.L_hex_store2:
    movb    %dl, 1(%rdi)

    movl    $1, %eax
    movl    $2, %edi
    leaq    hex_buf(%rip), %rsi
    movl    $3, %edx
    syscall
    movl    $1, %edi                        
    jmp     .L_exit

.L_launch_ok:
    call    cuCtxSynchronize@PLT

    movq    host_buffer(%rip), %rdi
    movq    d_out_ptr(%rip), %rsi
    movq    buffer_size(%rip), %rdx
    call    cuMemcpyDtoH_v2@PLT

    # ==========================================
    # FILE SERIALIZATION
    # ==========================================
    # 1. Schrijf BIN-bestand
    movl    $2, %eax                        
    movq    bin_path(%rip), %rdi
    movl    $577, %esi                      
    movl    $0644, %edx                     
    syscall
    movq    %rax, fd_bin(%rip)

    movl    $1, %eax                        
    movq    fd_bin(%rip), %rdi
    movq    host_buffer(%rip), %rsi
    movq    buffer_size(%rip), %rdx
    syscall

    movl    $3, %eax                        
    movq    fd_bin(%rip), %rdi
    syscall

    # 2. Schrijf optioneel CSV-bestand
    cmpb    $1, write_csv(%rip)
    jne     .L_cleanup

    movl    $2, %eax                        
    movq    csv_path(%rip), %rdi
    movl    $577, %esi          
    movl    $0644, %edx         
    syscall
    movq    %rax, fd_csv(%rip)

    movl    $1, %eax                        
    movq    fd_csv(%rip), %rdi
    leaq    csv_header(%rip), %rsi
    movl    csv_header_l(%rip), %edx
    syscall

    xorl    %r12d, %r12d                    
    movq    host_buffer(%rip), %r13 
.L_csv_loop:
    cmpl    npoints(%rip), %r12d
    jge     .L_csv_done

    movsd   (%r13), %xmm0                   
    call    write_double_text
    
    movl    $1, %eax
    movq    fd_csv(%rip), %rdi
    leaq    fmt_comma(%rip), %rsi
    movl    $1, %edx
    syscall

    movsd   8(%r13), %xmm0                  
    call    write_double_text

    movl    $1, %eax
    movq    fd_csv(%rip), %rdi
    leaq    fmt_nl(%rip), %rsi
    movl    $1, %edx
    syscall

    addq    $16, %r13                       
    incl    %r12d
    jmp     .L_csv_loop

.L_csv_done:
    movl    $3, %eax                        
    movq    fd_csv(%rip), %rdi
    syscall

.L_cleanup:
    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_done(%rip), %rsi
    movl    fmt_done_l(%rip), %edx
    syscall

    movq    %rbp, %rsp
    popq    %rbp
    xorl    %edi, %edi
.L_exit:
    movq    $231, %rax                      
    syscall

# -----------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------
strcmp_local:
    xorl    %eax, %eax
.L_sloop:
    movb    (%rdi), %dl
    movb    (%rsi), %cl
    cmpb    %cl, %dl
    jne     .L_sdiff
    testb   %dl, %dl
    jz      .L_sdone
    incq    %rdi
    incq    %rsi
    jmp     .L_sloop
.L_sdiff:
    sbbl    %eax, %eax
    orl     $1, %eax
.L_sdone:
    ret

parse_int:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rdx                
    pushq   %rcx
    movq    %rax, %rdx          
    xorl    %eax, %eax          
.L_int_loop:
    movb    (%rdx), %cl         
    testb   %cl, %cl            
    jz      .L_int_done
    subb    $48, %cl            
    imull   $10, %eax, %eax     
    movzbl  %cl, %ecx
    addl    %ecx, %eax          
    incq    %rdx                
    jmp     .L_int_loop
.L_int_done:
    popq    %rcx                
    popq    %rdx
    movq    %rbp, %rsp
    popq    %rbp
    ret

parse_float_double:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rdx                
    pushq   %rcx
    pushq   %r8
    movq    %rax, %rdx          
    xorl    %ecx, %ecx
    cvtsi2sd %ecx, %xmm0        
    movq    $10, %r8
    cvtsi2sd %r8, %xmm2         
.L_fp_pre:
    movb    (%rdx), %cl
    testb   %cl, %cl
    jz      .L_fp_done
    cmpb    $46, %cl            
    je      .L_fp_dot
    subb    $48, %cl
    mulsd   %xmm2, %xmm0        
    movzbl  %cl, %ecx
    cvtsi2sd %ecx, %xmm1
    addsd   %xmm1, %xmm0        
    incq    %rdx
    jmp     .L_fp_pre
.L_fp_dot:
    incq    %rdx                
    movq    $1, %r8
    cvtsi2sd %r8, %xmm3         
.L_fp_post:
    movb    (%rdx), %cl
    testb   %cl, %cl
    jz      .L_fp_done
    subb    $48, %cl
    mulsd   %xmm2, %xmm3        
    movzbl  %cl, %ecx
    cvtsi2sd %ecx, %xmm1
    divsd   %xmm3, %xmm1        
    addsd   %xmm1, %xmm0        
    incq    %rdx
    jmp     .L_fp_post
.L_fp_done:
    popq    %r8                 
    popq    %rcx
    popq    %rdx
    movq    %rbp, %rsp
    popq    %rbp
    ret

write_double_text:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rax                
    pushq   %rdi
    pushq   %rsi
    pushq   %rdx
    
    cvttsd2si %xmm0, %rax           
    pushq   %rax                
    call    write_int_to_csv    
    
    movl    $1, %eax            
    movq    fd_csv(%rip), %rdi
    leaq    fmt_dot(%rip), %rsi 
    movl    $1, %edx
    syscall
    popq    %rax                
    
    cvtsi2sd %rax, %xmm1
    subsd   %xmm1, %xmm0            
    
    movq    csv_mult(%rip), %rax
    cvtsi2sd %rax, %xmm1
    mulsd   %xmm1, %xmm0
    
    cvtsd2siq %xmm0, %rax           
    
    movq    csv_prec(%rip), %rsi    
    call    write_fract_to_csv
    
    popq    %rdx                
    popq    %rsi
    popq    %rdi
    popq    %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret

write_fract_to_csv:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rax
    pushq   %rcx
    pushq   %rdx
    pushq   %r8
    
    leaq    (ascii_buf + 63)(%rip), %rcx
    movq    $10, %r8
    xorq    %r9, %r9                

.L_conv_fract_loop:
    xorq    %rdx, %rdx              
    divq    %r8                     
    addb    $48, %dl                
    decq    %rcx
    movb    %dl, (%rcx)
    incq    %r9
    testq   %rax, %rax
    jnz     .L_conv_fract_loop

.L_pad_fract_loop:
    cmpq    %rsi, %r9
    jge     .L_fract_print
    decq    %rcx
    movb    $48, (%rcx)             
    incq    %r9
    jmp     .L_pad_fract_loop

.L_fract_print:
    leaq    (ascii_buf + 64)(%rip), %rdx
    subq    %rcx, %rdx              
    
    movl    $1, %eax                
    movq    fd_csv(%rip), %rdi
    movq    %rcx, %rsi
    syscall                     

    popq    %r8
    popq    %rdx
    popq    %rcx
    popq    %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret

write_int_to_csv:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rax                
    pushq   %rcx
    pushq   %rdx
    pushq   %r8
    pushq   %rdi
    pushq   %rsi
    leaq    (ascii_buf + 63)(%rip), %rcx
    movq    $10, %r8
.L_conv_csv:
    xorl    %edx, %edx
    divq    %r8
    addb    $48, %dl
    decq    %rcx
    movb    %dl, (%rcx)
    testq   %rax, %rax
    jnz     .L_conv_csv
    leaq    (ascii_buf + 64)(%rip), %rdx
    subq    %rcx, %rdx
    movl    $1, %eax            
    movq    fd_csv(%rip), %rdi
    movq    %rcx, %rsi
    syscall                     
    popq    %rsi                
    popq    %rdi
    popq    %r8
    popq    %rdx
    popq    %rcx
    popq    %rax
    movq    %rbp, %rsp
    popq    %rbp
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
