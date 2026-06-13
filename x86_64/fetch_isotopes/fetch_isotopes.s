/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * File         : fetch_isotopes.s
 * Description  : Stream-Buffered HTTPS Downloader for IAEA Nuclide Data.
 * Usage        : ./fetch_isotopes [-o custom_output.csv]
 * ============================================================================
 */

.global _start

.section .rodata
    host_ssl:     .asciz "nds.iaea.org:443"
    sni_name:     .asciz "nds.iaea.org"
    default_csv:  .string "isotopes.csv"

    http_request:
        .ascii "GET /relnsd/v1/data?fields=ground_states&nuclides=all HTTP/1.1\r\n"
        .ascii "Host: nds.iaea.org\r\n"
        .ascii "User-Agent: curl/7.81.0\r\n"
        .ascii "Accept: */*\r\n"
        .ascii "Connection: close\r\n\r\n"
    http_len = . - http_request

    msg_conn:     .asciz "[NETWERK] Connecting to nds.iaea.org:443 via TLS...\n"
    msg_done:     .asciz "[NETWERK] Download successfully completed and saved.\n"
    err_io:       .ascii "\033[1;31m[ERROR]\033[0m Cannot open or create target CSV file.\n"
    err_io_l = . - err_io
    err_ssl:      .ascii "\033[1;31m[ERROR]\033[0m TLS Handshake or OpenSSL protocol constraints failed.\n"
    err_ssl_l = . - err_ssl

.section .data
    .align 8
    ctx:          .quad 0
    bio:          .quad 0
    ssl_ptr:      .quad 0
    csv_fd:       .quad 0
    csv_name:     .quad 0

.section .bss
    .align 16
    net_buffer:   .space 4096

.section .text
_start:
    # Set up safe frame pointer and align stack to 16 bytes (ABI compliant)
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    subq    $16, %rsp

    # --- ABI Stack Parser for -o Override Flag ---
    movq    8(%rbp), %r8                    # %r8 = argc (corrected offset)
    leaq    24(%rbp), %rcx                  # %rcx = argv[1] (corrected offset)
    leaq    default_csv(%rip), %rax
    movq    %rax, csv_name(%rip)

    cmpq    $1, %r8
    jle     .L_init_network

.L_arg_loop:
    movq    (%rcx), %rdi
    testq   %rdi, %rdi
    jz      .L_init_network

    movb    (%rdi), %al
    cmpb    $45, %al                        # Check for '-' prefix
    jne     .L_next_arg

    movb    1(%rdi), %al
    cmpb    $111, %al                       # Check for 'o' override flag
    jne     .L_next_arg

    addq    $8, %rcx
    movq    (%rcx), %rax
    testq   %rax, %rax
    jz      .L_init_network
    movq    %rax, csv_name(%rip)

.L_next_arg:
    addq    $8, %rcx
    jmp     .L_arg_loop

.L_init_network:
    # Print connection log notification
    movq    $1, %rax
    movq    $1, %rdi
    leaq    msg_conn(%rip), %rsi
    movq    $53, %rdx
    syscall

    # Open target destination file (O_RDWR|O_CREAT|O_TRUNC = 0x242)
    movq    $2, %rax                        # sys_open
    movq    csv_name(%rip), %rdi
    movq    $0x242, %rsi
    movq    $0644, %rdx
    syscall
    js      error_io_exit
    movq    %rax, csv_fd(%rip)

    # --- OpenSSL Secure Pipeline Bootstrap ---
    xorq    %rdi, %rdi
    xorq    %rsi, %rsi
    call    OPENSSL_init_ssl@PLT
    call    TLS_client_method@PLT
    movq    %rax, %rdi
    call    SSL_CTX_new@PLT
    testq   %rax, %rax
    jz      error_ssl_exit
    movq    %rax, ctx(%rip)

    # CRITICAL RESTRICTION BYPASS: Disable strict peer certificate verification
    movq    ctx(%rip), %rdi
    xorq    %rsi, %rsi                      # SSL_VERIFY_NONE = 0
    xorq    %rdx, %rdx                      # NULL Callback
    call    SSL_CTX_set_verify@PLT

    movq    ctx(%rip), %rdi
    call    BIO_new_ssl_connect@PLT
    testq   %rax, %rax
    jz      error_ssl_exit
    movq    %rax, bio(%rip)

    movq    bio(%rip), %rdi
    movl    $100, %esi                      # BIO_C_SET_CONNECT
    xorq    %rdx, %rdx
    leaq    host_ssl(%rip), %rcx
    call    BIO_ctrl@PLT

    movq    bio(%rip), %rdi
    movl    $110, %esi                      # BIO_C_GET_SSL
    xorq    %rdx, %rdx
    leaq    ssl_ptr(%rip), %rcx
    call    BIO_ctrl@PLT

    movq    ssl_ptr(%rip), %rdi
    movl    $55, %esi                       # SSL_CTRL_SET_TLSEXT_HOSTNAME
    movq    $0, %rdx                        # Nametype = host_name (0)
    leaq    sni_name(%rip), %rcx
    call    SSL_ctrl@PLT

    # Execute dynamic TLS Handshake
    movq    bio(%rip), %rdi
    movl    $101, %esi                      # BIO_C_DO_STATE_MACHINE
    xorq    %rdx, %rdx
    xorq    %rcx, %rcx
    call    BIO_ctrl@PLT
    testq   %rax, %rax
    jle     error_ssl_exit

    # Transmit HTTP request payload
    movq    bio(%rip), %rdi
    leaq    http_request(%rip), %rsi
    movq    $http_len, %rdx
    call    BIO_write@PLT

    xorq    %r15, %r15                      # State 0: Header scan mode
    xorq    %rbx, %rbx                      # Reset chunk processing counters

FETCH_BLOCK:
    leaq    net_buffer(%rip), %rsi
    movq    bio(%rip), %rdi
    movq    $4096, %rdx
    call    BIO_read@PLT
    testq   %rax, %rax
    jle     NET_DONE                        # End of transmission stream reached

    leaq    net_buffer(%rip), %r12
    movq    %r12, %r11
    addq    %rax, %r11                      # %r11 = network block buffer end

PROCESS_BYTES:
    cmpq    %r11, %r12
    jae     FETCH_BLOCK

    movzbq  (%r12), %rax
    incq    %r12

    cmpq    $0, %r15
    je      STATE_0
    cmpq    $1, %r15
    je      STATE_1
    cmpq    $2, %r15
    je      STATE_2
    cmpq    $3, %r15
    je      STATE_3
    jmp     PROCESS_BYTES

STATE_0:
    # --- Skip HTTP Headers via Sequential Break Detection ---
    cmpb    $13, %al
    je      PROCESS_BYTES
    cmpb    $10, %al
    jne     .L_reset_h
    incq    %rbx
    cmpq    $2, %rbx
    jne     PROCESS_BYTES
    movq    $1, %r15                        # Headers consumed -> Proceed to chunk size
    xorq    %rbx, %rbx
    jmp     PROCESS_BYTES

.L_reset_h:
    xorq    %rbx, %rbx
    jmp     PROCESS_BYTES

STATE_1:
    # --- Parse Chunked Payload Hex Size Flags ---
    cmpb    $13, %al
    je      PROCESS_BYTES
    cmpb    $10, %al
    je      .L_hex_done

    shlq    $4, %rbx
    cmpb    $58, %al
    jl      .L_num
    cmpb    $97, %al
    jl      .L_caps
    subb    $87, %al
    jmp     .L_merge

.L_caps:
    subb    $55, %al
    jmp     .L_merge

.L_num:
    subb    $48, %al

.L_merge:
    movzbq  %al, %rax
    addq    %rax, %rbx
    jmp     PROCESS_BYTES

.L_hex_done:
    testq   %rbx, %rbx
    jz      NET_DONE                        # Terminal empty chunk -> Stream end
    movq    $2, %r15                        # Proceed to State 2: Data stream extraction
    jmp     PROCESS_BYTES

STATE_2:
    # --- Ingest Active Character Byte Straight to CSV Storage ---
    # Secure loop bounds against kernel modification context overrides
    pushq   %rbx
    pushq   %rax
    pushq   %rcx
    pushq   %r11

    movq    $1, %rax                        # sys_write
    movq    csv_fd(%rip), %rdi
    leaq    16(%rsp), %rsi                  # Map exact pointer position on stack frame
    movq    $1, %rdx
    syscall

    popq    %r11                            # Recover boundary limits untouched
    popq    %rcx
    popq    %rax
    popq    %rbx

    decq    %rbx
    jnz     PROCESS_BYTES
    movq    $3, %r15                        # Chunk boundary reached -> Skip trailer
    jmp     PROCESS_BYTES

STATE_3:
    # --- Consume Trailing CR/LF Break Frames ---
    cmpb    $10, %al
    jne     PROCESS_BYTES
    movq    $1, %r15                        # Recycle state back to loop detection
    xorq    %rbx, %rbx
    jmp     PROCESS_BYTES

NET_DONE:
    # Safe context disposal
    movq    bio(%rip), %rdi
    call    BIO_free_all@PLT
    movq    ctx(%rip), %rdi
    call    SSL_CTX_free@PLT

    movq    $3, %rax                        # sys_close
    movq    csv_fd(%rip), %rdi
    syscall

    # Print success notice to standard output
    movq    $1, %rax
    movq    $1, %rdi
    leaq    msg_done(%rip), %rsi
    movq    $45, %rdx
    syscall

    # Return frame context back to parent environment coordinates
    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # sys_exit Exit(0)
    xorq    %rdi, %rdi
    syscall

error_io_exit:
    movq    $1, %rax                        # sys_write stderr
    movq    $2, %rdi
    leaq    err_io(%rip), %rsi
    movq    $err_io_l, %rdx
    syscall
    jmp     .L_terminate

error_ssl_exit:
    movq    $1, %rax                        # sys_write stderr
    movq    $2, %rdi
    leaq    err_ssl(%rip), %rsi
    movq    $err_ssl_l, %rdx
    syscall

.L_terminate:
    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax                       # Exit(1)
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
