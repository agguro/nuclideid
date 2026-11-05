/*
 * IAEA ground-state CSV downloader. GNU x86-64 assembly, SysV ABI.
 * Usage: fetch_isotopes [-o FILE] | --help
 *
 * libcurl owns HTTPS, certificate/hostname verification, HTTP framing and
 * bounded network I/O. Downloads use a unique file beside the destination;
 * rename publishes only a complete response with a recognizable CSV header
 * and at least one data row. Existing output survives any earlier failure.
 */
.global _start

/* Stable libcurl public API option numbers (curl/curl.h). */
.equ CURLOPT_WRITEDATA,        10001
.equ CURLOPT_URL,              10002
.equ CURLOPT_USERAGENT,        10018
.equ CURLOPT_ERRORBUFFER,      10010
.equ CURLOPT_FAILONERROR,      45
.equ CURLOPT_TIMEOUT,          13
.equ CURLOPT_CONNECTTIMEOUT,   78
.equ CURLOPT_LOW_SPEED_LIMIT,  19
.equ CURLOPT_LOW_SPEED_TIME,   20
.equ CURLOPT_NOSIGNAL,         99
.equ CURLOPT_SSL_VERIFYPEER,   64
.equ CURLOPT_SSL_VERIFYHOST,   81
.equ CURLOPT_PROTOCOLS,        181
.equ CURLPROTO_HTTPS,          2

.section .rodata
url:        .asciz "https://nds.iaea.org/relnsd/v1/data?fields=ground_states&nuclides=all"
agent:      .asciz "nuclideid/1.0"
default_csv:.asciz "isotopes.csv"
opt_output: .asciz "-o"
opt_help:   .asciz "--help"
usage:      .asciz "Usage: fetch_isotopes [-o FILE] | --help\n"
tmp_suffix: .asciz ".tmp.XXXXXX"
mode_write: .asciz "w"
mode_read:  .asciz "r"
header_start: .asciz "z,n,symbol,"
header_half:  .asciz ",half_life_sec,"
msg_args:   .asciz "fetch_isotopes: invalid arguments; use --help"
msg_init:   .asciz "fetch_isotopes: cannot initialize libcurl"
msg_option: .asciz "fetch_isotopes: cannot configure libcurl"
msg_alloc:  .asciz "fetch_isotopes: cannot allocate temporary filename"
msg_temp:   .asciz "fetch_isotopes: cannot create temporary file"
msg_stream: .asciz "fetch_isotopes: cannot open temporary stream"
msg_write:  .asciz "fetch_isotopes: cannot flush or close downloaded file"
msg_csv:    .asciz "fetch_isotopes: response is not a complete recognizable isotope CSV"
msg_rename: .asciz "fetch_isotopes: cannot replace destination"
fmt_error:  .asciz "%s\n"
fmt_curl:   .asciz "fetch_isotopes: transfer failed: %s\n"
fmt_done:   .asciz "Saved isotope CSV to %s\n"

.section .bss
.align 8
destination: .zero 8
temporary:   .zero 8
stream:      .zero 8
reader:      .zero 8
handle:      .zero 8
global_ready:.zero 8
temp_created:.zero 8
exit_status: .zero 8
error_buffer:.zero 256
line_buffer: .zero 16384

.section .text
_start:
    /* Preserve initial argv before aligning for C calls. */
    movq %rsp, %r12
    andq $-16, %rsp
    leaq default_csv(%rip), %rax
    movq %rax, destination(%rip)
    cmpq $1, (%r12)
    je .Linit
    cmpq $2, (%r12)
    jne .Loutput_arg
    movq 16(%r12), %rdi
    leaq opt_help(%rip), %rsi
    call strcmp@PLT
    testl %eax, %eax
    jne .Lbad_args
    leaq usage(%rip), %rdi
    call puts@PLT
    jmp .Lcleanup
.Loutput_arg:
    cmpq $3, (%r12)
    jne .Lbad_args
    movq 16(%r12), %rdi
    leaq opt_output(%rip), %rsi
    call strcmp@PLT
    testl %eax, %eax
    jne .Lbad_args
    movq 24(%r12), %rax
    cmpb $0, (%rax)
    je .Lbad_args
    movq %rax, destination(%rip)
.Linit:
    movl $3, %edi                  /* CURL_GLOBAL_DEFAULT */
    call curl_global_init@PLT
    testl %eax, %eax
    jne .Linit_error
    movq $1, global_ready(%rip)
    call curl_easy_init@PLT
    testq %rax, %rax
    je .Linit_error
    movq %rax, handle(%rip)

    movq destination(%rip), %rdi
    call strlen@PLT
    leaq 12(%rax), %rdi            /* suffix length 11 plus NUL */
    call malloc@PLT
    testq %rax, %rax
    je .Lalloc_error
    movq %rax, temporary(%rip)
    movq %rax, %rdi
    movq destination(%rip), %rsi
    call strcpy@PLT
    movq temporary(%rip), %rdi
    leaq tmp_suffix(%rip), %rsi
    call strcat@PLT
    movq temporary(%rip), %rdi
    call mkstemp@PLT               /* exclusive, mode 0600 */
    testl %eax, %eax
    js .Ltemp_error
    movq $1, temp_created(%rip)
    movl %eax, %r13d
    movl %eax, %edi
    leaq mode_write(%rip), %rsi
    call fdopen@PLT
    testq %rax, %rax
    je .Lstream_error
    movq %rax, stream(%rip)

    /* Every option is checked. libcurl's default writer is fwrite. */
.macro set_pointer option, label
    movq handle(%rip), %rdi
    movl $\option, %esi
    leaq \label(%rip), %rdx
    xorl %eax, %eax
    call curl_easy_setopt@PLT
    testl %eax, %eax
    jne .Loption_error
.endm
.macro set_number option, value
    movq handle(%rip), %rdi
    movl $\option, %esi
    movq $\value, %rdx
    xorl %eax, %eax
    call curl_easy_setopt@PLT
    testl %eax, %eax
    jne .Loption_error
.endm
    set_pointer CURLOPT_URL, url
    set_pointer CURLOPT_USERAGENT, agent
    set_pointer CURLOPT_ERRORBUFFER, error_buffer
    set_number CURLOPT_FAILONERROR, 1
    set_number CURLOPT_CONNECTTIMEOUT, 30
    set_number CURLOPT_TIMEOUT, 120
    set_number CURLOPT_LOW_SPEED_LIMIT, 1
    set_number CURLOPT_LOW_SPEED_TIME, 30
    set_number CURLOPT_NOSIGNAL, 1
    set_number CURLOPT_SSL_VERIFYPEER, 1
    set_number CURLOPT_SSL_VERIFYHOST, 2
    set_number CURLOPT_PROTOCOLS, CURLPROTO_HTTPS
    movq handle(%rip), %rdi
    movl $CURLOPT_WRITEDATA, %esi
    movq stream(%rip), %rdx
    xorl %eax, %eax
    call curl_easy_setopt@PLT
    testl %eax, %eax
    jne .Loption_error
    movq handle(%rip), %rdi
    call curl_easy_perform@PLT
    testl %eax, %eax
    jne .Ltransfer_error

    /* Require HTTP 200; redirects and other successful statuses are rejected. */
    movq handle(%rip), %rdi
    movl $0x200002, %esi           /* CURLINFO_RESPONSE_CODE */
    leaq exit_status(%rip), %rdx   /* scratch, reset before cleanup */
    xorl %eax, %eax
    call curl_easy_getinfo@PLT
    testl %eax, %eax
    jne .Lcsv_error
    cmpq $200, exit_status(%rip)
    jne .Lcsv_error
    movq $0, exit_status(%rip)
    movq stream(%rip), %rdi
    call fclose@PLT               /* checks buffered writes as well */
    movq $0, stream(%rip)
    testl %eax, %eax
    jne .Lwrite_error

    movq temporary(%rip), %rdi
    leaq mode_read(%rip), %rsi
    call fopen@PLT
    testq %rax, %rax
    je .Lcsv_error
    movq %rax, reader(%rip)
    call read_line
    testq %rax, %rax
    je .Lcsv_error
    leaq line_buffer(%rip), %rdi
    leaq header_start(%rip), %rsi
    movl $11, %edx
    call strncmp@PLT
    testl %eax, %eax
    jne .Lcsv_error
    leaq line_buffer(%rip), %rdi
    leaq header_half(%rip), %rsi
    call strstr@PLT
    testq %rax, %rax
    je .Lcsv_error
    /* Require a complete header line and a nonempty, complete first row. */
    call complete_line
    testq %rax, %rax
    je .Lcsv_error
    call read_line
    testq %rax, %rax
    je .Lcsv_error
    cmpb $'0', line_buffer(%rip)
    jb .Lcsv_error
    cmpb $'9', line_buffer(%rip)
    ja .Lcsv_error
    call complete_line
    testq %rax, %rax
    je .Lcsv_error
    movq reader(%rip), %rdi
    call fclose@PLT
    movq $0, reader(%rip)
    testl %eax, %eax
    jne .Lcsv_error
    movq temporary(%rip), %rdi
    movq destination(%rip), %rsi
    call rename@PLT
    testl %eax, %eax
    jne .Lrename_error
    movq $0, temp_created(%rip)
    leaq fmt_done(%rip), %rdi
    movq destination(%rip), %rsi
    xorl %eax, %eax
    call printf@PLT
    jmp .Lcleanup

/* Helpers enter with rsp % 16 == 8. Tail calls preserve that ABI. */
read_line:
    leaq line_buffer(%rip), %rdi
    movl $16384, %esi
    movq reader(%rip), %rdx
    jmp fgets@PLT
complete_line:
    leaq line_buffer(%rip), %rdi
    movl $10, %esi
    jmp strchr@PLT

.Lbad_args:     leaq msg_args(%rip), %rsi; jmp .Lerror
.Linit_error:   leaq msg_init(%rip), %rsi; jmp .Lerror
.Loption_error: leaq msg_option(%rip), %rsi; jmp .Lerror
.Lalloc_error:  leaq msg_alloc(%rip), %rsi; jmp .Lerror
.Ltemp_error:   leaq msg_temp(%rip), %rsi; jmp .Lerror
.Lstream_error:
    movl %r13d, %edi
    call close@PLT
    leaq msg_stream(%rip), %rsi
    jmp .Lerror
.Lwrite_error:  leaq msg_write(%rip), %rsi; jmp .Lerror
.Lcsv_error:    leaq msg_csv(%rip), %rsi; jmp .Lerror
.Lrename_error: leaq msg_rename(%rip), %rsi; jmp .Lerror
.Ltransfer_error:
    movl %eax, %edi
    call curl_easy_strerror@PLT
    movq %rax, %rdx
    cmpb $0, error_buffer(%rip)
    je .Lcurl_message
    leaq error_buffer(%rip), %rdx
.Lcurl_message:
    movq stderr(%rip), %rdi
    leaq fmt_curl(%rip), %rsi
    xorl %eax, %eax
    call fprintf@PLT
    jmp .Lfailed
.Lerror:
    movq %rsi, %rdx
    movq stderr(%rip), %rdi
    leaq fmt_error(%rip), %rsi
    xorl %eax, %eax
    call fprintf@PLT
.Lfailed:
    movq $1, exit_status(%rip)
.Lcleanup:
    movq handle(%rip), %rdi
    testq %rdi, %rdi
    je .Lclose_stream
    call curl_easy_cleanup@PLT
.Lclose_stream:
    movq stream(%rip), %rdi
    testq %rdi, %rdi
    je .Lclose_reader
    call fclose@PLT
.Lclose_reader:
    movq reader(%rip), %rdi
    testq %rdi, %rdi
    je .Lremove_temp
    call fclose@PLT
.Lremove_temp:
    cmpq $0, temp_created(%rip)
    je .Lfree_temp
    movq temporary(%rip), %rdi
    call unlink@PLT
.Lfree_temp:
    movq temporary(%rip), %rdi
    call free@PLT
    cmpq $0, global_ready(%rip)
    je .Lexit
    call curl_global_cleanup@PLT
.Lexit:
    movl exit_status(%rip), %edi
    call exit@PLT                 /* flush C stdio before terminating */
.section .note.GNU-stack,"",@progbits
