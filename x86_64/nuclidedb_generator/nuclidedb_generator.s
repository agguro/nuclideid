/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * Description  : Standalone SSL IAEA Ingestion & GPU Bitonic Merge Sort Pipeline
 * ============================================================================
 */

.global _start

.section .rodata
    # SSL Netwerk Parameters
    host:          .asciz "www-nds.iaea.org:443"
    host_name_sni: .asciz "www-nds.iaea.org"
    func_name:     .string "bitonic_sort"
    out_file:      .string "isotopes.db"
    
    # Kogelvrije HTTP Headers - Browser Footprint
    http_request:
        .ascii "GET /relnsd/v1/data?fields=ground_states&nuclides=all HTTP/1.1\r\n"
        .ascii "Host: www-nds.iaea.org\r\n"
        .ascii "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0\r\n"
        .ascii "Accept: text/csv,text/plain\r\n"
        .ascii "Accept-Language: en-US,en;q=0.5\r\n"
        .ascii "Connection: close\r\n\r\n"
    http_len = . - http_request

    .align 4
    ln2:          .float 0.69314718
    k_inf:        .float 99999.0      

    # Diagnostic Foutmeldingen
    fmt_nocuda:   .ascii "\033[1;31m[ERROR]\033[0m No NVIDIA GPU detected.\n"
    fmt_nocuda_l: .long . - fmt_nocuda
    fmt_nomod:    .ascii "\033[1;31m[ERROR]\033[0m CUDA Module rejection.\n"
    fmt_nomod_l:  .long . - fmt_nomod
    fmt_neterr:   .ascii "\033[1;31m[SSL ERROR]\033[0m Cloudflare or TLS handshake rejected client.\n"
    fmt_neterr_l: .long . - fmt_neterr

    BIO_C_SET_CONNECT = 100
    BIO_C_DO_STATE_MACHINE = 101
    BIO_C_GET_SSL = 105

    # Strikte 8-byte alignment voor de ingebakken CUBIN data via jouw framework
    .align 8
cubin_start:
    .incbin "nuclidedb_generator.cubin"
cubin_end:

.section .data
    .align 8
    ctx:          .quad 0
    bio:          .quad 0
    total_read:   .quad 0

    cu_ctx:       .quad 0
    cu_device:    .long 0
    cu_module:    .quad 0
    cu_function:  .quad 0
    d_db_ptr:     .quad 0

    .align 8
    kernel_params:
        p_db:     .quad 0
        p_j:      .long 0
        p_k:      .long 0
        p_num:    .long 4096
    .align 8
    kernel_args:  .quad kernel_params, kernel_params+8, kernel_params+12, kernel_params+16

    p_j_val:      .long 0
    p_k_val:      .long 0

.section .bss
    .align 4096
    net_buffer:   .space 524288       
    .align 16
    database:     .space 131072       

.section .text
_start:
    # Garandeer strikte x86_64 ABI stack-alignment + 16 bytes local frame space
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    subq    $16, %rsp

    # ==========================================
    # 1. SECURE INITIALIZATION & STACK-SAFE SNI
    # ==========================================
    xorq    %rdi, %rdi
    xorq    %rsi, %rsi
    call    OPENSSL_init_ssl@PLT
    
    call    TLS_client_method@PLT
    movq    %rax, %rdi
    call    SSL_CTX_new@PLT
    movq    %rax, ctx(%rip)

    movq    ctx(%rip), %rdi
    call    BIO_new_ssl_connect@PLT
    movq    %rax, bio(%rip)

    # Configureer connection target
    movq    bio(%rip), %rdi
    movq    $BIO_C_SET_CONNECT, %rsi
    xorq    %rdx, %rdx
    leaq    host(%rip), %rcx
    call    BIO_ctrl@PLT

    # --- SNI INTERN SSL POINTER EXTRACTION (STACK-PROOF) ---
    # We reserveren 8 bytes op de stack om de volatile register bypass uit te voeren
    subq    $8, %rsp                   
    movq    bio(%rip), %rdi
    movq    $BIO_C_GET_SSL, %rsi       # 105
    xorl    %edx, %edx                 
    movq    %rsp, %rcx                 # Schrijf direct naar de actieve stack pointer location
    call    BIO_ctrl@PLT

    # Haal het resultaat op van de stack en reinig de stack direct
    movq    (%rsp), %rdi                   
    addq    $8, %rsp                   
    testq   %rdi, %rdi
    jz      .L_network_error           

    # Directe aanroep van SSL_ctrl (Platgeslagen macro bypass voor SSL_set_tlsext_host_name)
    # %rdi bevat al de ongeschonden interne SSL pointer
    movq    $55, %rsi                  # 55 = SSL_CTRL_SET_TLSEXT_HOSTNAME
    xorl    %edx, %edx                 
    leaq    host_name_sni(%rip), %rcx  # Pointer naar pure host string zonder poort
    call    SSL_ctrl@PLT

    # Start secure state machine handshake
    movq    bio(%rip), %rdi
    movq    $BIO_C_DO_STATE_MACHINE, %rsi
    xorq    %rdx, %rdx
    xorq    %rcx, %rcx
    call    BIO_ctrl@PLT
    testq   %rax, %rax
    jle     .L_network_error

    # Push gecodeerde HTTP/1.1 headers over de TLS-tunnel
    movq    bio(%rip), %rdi
    leaq    http_request(%rip), %rsi
    movq    $http_len, %rdx
    call    BIO_write@PLT

    # ==========================================
    # 2. ACCUMULATION STREAM LOOP
    # ==========================================
    movq    $0, total_read(%rip)

.L_accumulation_loop:
    leaq    net_buffer(%rip), %rsi
    addq    total_read(%rip), %rsi            
    
    movq    bio(%rip), %rdi
    movq    $4096, %rdx                 
    call    BIO_read@PLT
    testq   %rax, %rax
    jle     .L_close_ssl_stream

    addq    %rax, total_read(%rip)
    jmp     .L_accumulation_loop

.L_close_ssl_stream:
    leaq    net_buffer(%rip), %rax
    addq    total_read(%rip), %rax
    movb    $0, (%rax)

    movq    bio(%rip), %rdi
    call    BIO_free_all@PLT
    movq    ctx(%rip), %rdi
    call    SSL_CTX_free@PLT

    movq    total_read(%rip), %rax
    testq   %rax, %rax
    jz      PADDING_DATABASE

    # ==========================================
    # 3. IN-MEMORY PARSER (Unix/Windows Adaptive)
    # ==========================================
    leaq    net_buffer(%rip), %rsi            
    leaq    database(%rip), %rdi              
    xorl    %r13d, %r13d                   
    
    leaq    net_buffer(%rip), %r12
    addq    total_read(%rip), %r12

.L_skip_http_header:
    # 4-byte vooruitblikkende safety-bounds lock tegen out-of-bounds scanning
    movq    %r12, %rax
    subq    $4, %rax
    cmpq    %rax, %rsi
    jae     PADDING_DATABASE

    movl    (%rsi), %eax
    cmpl    $0x0A0D0A0D, %eax              # Match \r\n\r\n
    je      .L_found_data_start_rnrn
    
    andl    $0x0000FFFF, %eax              
    cmpl    $0x0A0A, %eax                  # Match \n\n Unix style marker fallback
    je      .L_found_data_start_nn

    incq    %rsi
    jmp     .L_skip_http_header

.L_found_data_start_rnrn:
    addq    $4, %rsi                       
    jmp     .L_skip_csv_header

.L_found_data_start_nn:
    addq    $2, %rsi                       

.L_skip_csv_header:
    cmpq    %r12, %rsi
    jae     PADDING_DATABASE
    movb    (%rsi), %al
    incq    %rsi
    cmpb    $10, %al                       
    jne     .L_skip_csv_header

PARSE_RECORD_LINE:
    cmpq    %r12, %rsi
    jae     PADDING_DATABASE
    cmpl    $3388, %r13d                   
    jge     PADDING_DATABASE

    # --- Kolom 1: Z ---
    xorl    %eax, %eax
    xorl    %ecx, %ecx
PARSE_Z:
    movb    (%rsi), %cl
    incq    %rsi
    cmpb    $',', %cl
    je      STORE_Z
    imull   $10, %eax
    subb    $48, %cl
    addl    %ecx, %eax
    jmp     PARSE_Z
STORE_Z:
    movl    %eax, 8(%rdi)     

    # --- Kolom 2: A ---
    xorl    %eax, %eax
PARSE_A:
    movb    (%rsi), %cl
    incq    %rsi
    cmpb    $',', %cl
    je      STORE_A
    imull   $10, %eax
    subb    $48, %cl
    addl    %ecx, %eax
    jmp     PARSE_A
STORE_A:
    movl    %eax, 4(%rdi)     

    # --- Kolom 3: Symbool ---
    leaq    12(%rdi), %rdx              
    xorl    %eax, %eax                     
PARSE_NAME:
    movb    (%rsi), %cl
    incq    %rsi
    cmpb    $',', %cl
    je      STORE_NAME
    movb    %cl, (%rdx,%rax)
    incq    %rax
    jmp     PARSE_NAME
STORE_NAME:
    movb    $0, (%rdx,%rax)      

    # --- Kolom 4: Half_life_sec ---
    xorl    %eax, %eax                     
PARSE_THALF_INT:
    movb    (%rsi), %cl
    incq    %rsi
    cmpb    $'.', %cl
    je      PARSE_THALF_FRAC
    cmpb    $10, %cl                       
    je      CALC_K_DIRECT
    imull   $10, %eax
    subb    $48, %cl
    addl    %ecx, %eax
    jmp     PARSE_THALF_INT

PARSE_THALF_FRAC:
    cvtsi2ssl %eax, %xmm0
    
SKIP_TO_EOL:
    movb    (%rsi), %cl
    incq    %rsi
    cmpb    $10, %cl
    jne     SKIP_TO_EOL

CALC_K_DIRECT:
    cvtsi2ssl %eax, %xmm0
    movss   ln2(%rip), %xmm1
    divss   %xmm0, %xmm1
    movss   %xmm1, (%rdi)        

    incl    %r13d                         
    addq    $32, %rdi                      
    jmp     PARSE_RECORD_LINE

    # ==========================================
    # 4. POWER OF 2 PADDING
    # ==========================================
PADDING_DATABASE:
    cmpl    $4096, %r13d
    jge     PREPARE_CUDA_SORT
    
    movl    k_inf(%rip), %eax
    movl    %eax, (%rdi)
    movl    $0, 4(%rdi)       
    movl    $0, 8(%rdi)       
    movb    $0, 12(%rdi)       
    
    incl    %r13d
    addq    $32, %rdi
    jmp     PADDING_DATABASE

    # ==========================================
    # 5. GPU BITONIC MERGE SORT SYSTEM
    # ==========================================
PREPARE_CUDA_SORT:
    xorl    %edi, %edi
    call    cuInit@PLT

    leaq    cu_device(%rip), %rdi
    xorl    %esi, %esi
    call    cuDeviceGet@PLT
    leaq    cu_ctx(%rip), %rdi
    xorl    %esi, %esi
    movl    cu_device(%rip), %edx
    call    cuCtxCreate@PLT

    leaq    d_db_ptr(%rip), %rdi
    movl    $131072, %esi
    call    cuMemAlloc@PLT

    movq    d_db_ptr(%rip), %rdi
    leaq    database(%rip), %rsi
    movl    $131072, %edx
    call    cuMemcpyHtoD@PLT

    leaq    cu_module(%rip), %rdi       
    leaq    cubin_start(%rip), %rsi     
    call    cuModuleLoadData@PLT
    testl   %eax, %eax
    jnz     .L_mod_error

    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    func_name(%rip), %rdx
    call    cuModuleGetFunction@PLT

    movq    d_db_ptr(%rip), %rax
    movq    %rax, kernel_params(%rip)

    movl    $2, p_k_val(%rip)

CUDA_OUTER_LOOP:
    movl    p_k_val(%rip), %eax
    cmpl    $4096, %eax
    jg      DOWNLOAD_SORTED_DB
    movl    %eax, (kernel_params + 12)(%rip) 

    shrl    $1, %eax
    movl    %eax, p_j_val(%rip)

CUDA_INNER_LOOP:
    movl    p_j_val(%rip), %eax
    testl   %eax, %eax
    jz      CUDA_NEXT_OUTER
    movl    %eax, (kernel_params + 8)(%rip)  

    movq    cu_function(%rip), %rdi
    movl    $16, %esi          
    movl    $1, %edx
    movl    $1, %ecx
    movl    $256, %r8d         
    movl    $1, %r9d
    pushq   $0
    pushq   $0
    leaq    kernel_args(%rip), %rax
    pushq   %rax
    pushq   $0
    pushq   $1
    call    cuLaunchKernel@PLT
    addq    $40, %rsp

    call    cuCtxSynchronize@PLT

    shrl    $1, p_j_val(%rip)
    jmp     CUDA_INNER_LOOP

CUDA_NEXT_OUTER:
    shll    $1, p_k_val(%rip)
    jmp     CUDA_OUTER_LOOP

DOWNLOAD_SORTED_DB:
    leaq    database(%rip), %rdi
    movq    d_db_ptr(%rip), %rsi
    movl    $131072, %edx
    call    cuMemcpyDtoH@PLT

    movl    $2, %eax              # sys_open
    leaq    out_file(%rip), %rdi
    movl    $0101, %esi           # O_WRONLY | O_CREAT
    movl    $0644, %edx           
    syscall
    movq    %rax, %r14            

    movl    $1, %eax              # sys_write
    movq    %r14, %rdi
    leaq    database(%rip), %rsi
    movl    $131072, %edx
    syscall

    movl    $3, %eax              # sys_close
    movq    %r14, %rdi
    syscall

    addq    $16, %rsp
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax             
    xorl    %edi, %edi
    syscall

.L_mod_error:
    movl    $1, %eax              
    movl    $2, %edi              
    leaq    fmt_nomod(%rip), %rsi
    movl    fmt_nomod_l(%rip), %edx
    syscall
    jmp     .L_panic_exit

.L_network_error:
    movl    $1, %eax              
    movl    $2, %edi              
    leaq    fmt_neterr(%rip), %rsi
    movl    fmt_neterr_l(%rip), %edx
    syscall

.L_panic_exit:
    addq    $16, %rsp
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax
    movl    $1, %edi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

