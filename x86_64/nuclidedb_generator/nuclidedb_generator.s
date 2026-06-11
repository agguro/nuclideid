.global _start

.section .rodata
    host_name:    .string "www-nds.iaea.org"
    port_str:     .string "80"
    ptx_file:     .string "bitonic_sort.cubin"
    func_name:    .string "bitonic_sort"
    out_file:     .string "isotopes.db"
    
    # Cloudflare WAF Browser Integrity Check Bypassing Header Block
    http_request:
        .ascii "GET /relnsd/v1/data?fields=ground_states&nuclides=all HTTP/1.1\r\n"
        .ascii "Host: www-nds.iaea.org\r\n"
        .ascii "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\r\n"
        .ascii "Accept: text/csv\r\n"
        .ascii "Connection: close\r\n\r\n"
    http_len = . - http_request

    .align 4
    ln2:          .float 0.69314718
    k_inf:        .float 99999.0      # Oneindig hoge k-waarde voor dummy sinking

    fmt_nocuda:   .ascii "\033[1;31m[ERROR]\033[0m No NVIDIA GPU or driver detected on this system.\n"
    fmt_nocuda_l: .long . - fmt_nocuda

.section .data
    .align 8
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
    hints:        .zero 48            

.section .bss
    .align 16
    net_buffer:   .space 524288       # 512 KB network buffer
    
    .align 16
    database:     .space 131072       # 4096 records * 32 bytes = 128 KB
    
    res_addrinfo: .quad 0
    sock_fd:      .quad 0

.section .text
_start:
    # Garandeer strikte x86_64 ABI stack-alignment
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    # ==========================================
    # 1. RAW NETWORK SOCKET FETCH (IAEA INGESTIE)
    # ==========================================
    movl    $2, (hints + 4)(%rip)     # ai_family = AF_INET (IPv4)
    movl    $1, (hints + 8)(%rip)     # ai_socktype = SOCK_STREAM

    leaq    host_name(%rip), %rdi
    leaq    port_str(%rip), %rsi
    leaq    hints(%rip), %rdx
    leaq    res_addrinfo(%rip), %rcx
    call    getaddrinfo@PLT
    testl   %eax, %eax
    jnz     error_exit

    movq    res_addrinfo(%rip), %rax
    movl    4(%rax), %edi             
    movl    8(%rax), %esi             
    movl    12(%rax), %edx            
    call    socket@PLT
    movq    %rax, sock_fd(%rip)

    movq    sock_fd(%rip), %rdi
    movq    res_addrinfo(%rip), %rax
    movq    24(%rax), %rsi            
    movl    16(%rax), %edx            
    call    connect@PLT
    testl   %eax, %eax
    js      error_exit

    movq    sock_fd(%rip), %rdi
    leaq    http_request(%rip), %rsi
    movq    $http_len, %rdx
    xorq    %rcx, %rcx                     
    call    send@PLT

    leaq    net_buffer(%rip), %r12            
READ_STREAM_LOOP:
    movq    sock_fd(%rip), %rdi
    movq    %r12, %rsi
    movq    $4096, %rdx                    
    xorq    %rcx, %rcx
    call    recv@PLT
    testq   %rax, %rax
    jle     CLOSE_SOCKET                 
    addq    %rax, %r12                     
    jmp     READ_STREAM_LOOP

CLOSE_SOCKET:
    movq    sock_fd(%rip), %rdi
    call    close@PLT

    # ==========================================
    # 2. IN-MEMORY PARSER & STRUCTUREERDER
    # ==========================================
    leaq    net_buffer(%rip), %rsi            
    leaq    database(%rip), %rdi              
    xorl    %r13d, %r13d                   

SKIP_HTTP_HEADER:
    cmpq    %r12, %rsi
    jge     PADDING_DATABASE
    movl    (%rsi), %eax
    cmpl    $0x0A0D0A0D, %eax              
    je      FOUND_DATA_START
    incq    %rsi
    jmp     SKIP_HTTP_HEADER

FOUND_DATA_START:
    addq    $4, %rsi                       

SKIP_CSV_HEADER:
    cmpq    %r12, %rsi
    jge     PADDING_DATABASE
    movb    (%rsi), %al
    incq    %rsi
    cmpb    $10, %al                       
    jne     SKIP_CSV_HEADER

PARSE_RECORD_LINE:
    cmpq    %r12, %rsi
    jge     PADDING_DATABASE
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
    # 3. POWER OF 2 PADDING
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
    # 4. GPU BITONIC MERGE SORT SYSTEM
    # ==========================================
PREPARE_CUDA_SORT:
    xorl    %edi, %edi
    call    cuInit@PLT
    testl   %eax, %eax
    jnz     .L_cuda_error

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
    leaq    ptx_file(%rip), %rsi
    call    cuModuleLoad@PLT
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

    # ==========================================
    # 5. COMMIT NAAR LOCAL DISK (isotopes.db)
    # ==========================================
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

    # Herstel stack frame en sluit clean af
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax             # sys_exit
    xorl    %edi, %edi
    syscall

.L_cuda_error:
    movl    $1, %eax              # sys_write
    movl    $2, %edi              # stderr
    leaq    fmt_nocuda(%rip), %rsi
    movl    fmt_nocuda_l(%rip), %edx
    syscall
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax
    movl    $1, %edi
    syscall

error_exit:
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax
    movl    $1, %edi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

