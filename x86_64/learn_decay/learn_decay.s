.global _start

.section .rodata
    db_file:     .string "isotopes.db"
    data_file:   .string "data.bin"
    func_name:   .string "learnDecayK"
    
    fmt_start:   .ascii "\033[1;34m[nuclideid]\033[0m Starting standalone hardware inference...\n"
    fmt_start_l: .long . - fmt_start
    fmt_match:   .ascii "\033[1;32m[IDENTIFICATIE GESLAAGD]\033[0m\n"
    fmt_match_l: .long . - fmt_match
    fmt_z:       .ascii "  Protonen (Z): "
    fmt_z_l:     .long . - fmt_z
    fmt_a:       .ascii "  Massa (A):    "
    fmt_a_l:     .long . - fmt_a
    fmt_name:    .ascii "  Nuclide:      "
    fmt_name_l:  .long . - fmt_name
    fmt_nl:      .ascii "\n"

    fmt_nocuda:   .ascii "\033[1;31m[ERROR]\033[0m No NVIDIA GPU or driver detected on this system.\n"
    fmt_nocuda_l: .long . - fmt_nocuda

    fmt_nomod:    .ascii "\033[1;31m[ERROR]\033[0m Loaded CUDA data is corrupt or rejected by driver.\n"
    fmt_nomod_l:  .long . - fmt_nomod

    # Strikte 8-byte alignment voor de ingebakken CUBIN data
    .align 8
cubin_start:
    .incbin "learn_decay.cubin"
cubin_end:

.section .data
    .align 8
    cu_ctx:       .quad 0
    cu_device:    .long 0
    cu_module:    .quad 0
    cu_function:  .quad 0
    
    d_t_ptr:      .quad 0
    d_y_ptr:      .quad 0
    d_k_out:      .quad 0

    .align 8
    kernel_params:
        p_t:      .quad 0
        p_y:      .quad 0
        p_k:      .quad 0
        p_num:    .long 1024
    .align 8
    kernel_args:  .quad kernel_params, kernel_params+8, kernel_params+12, kernel_params+16

    fd_db:        .quad 0
    fd_data:      .quad 0
    ptr_db:       .quad 0
    ptr_data:     .quad 0
    
    .align 8
    stat_buf:     .zero 144

    .align 4
    learned_k:    .float 0.0
    ascii_buf:    .zero 32

.section .text
_start:
    # Garandeer strikte x86_64 ABI stack-alignment
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    # ==========================================
    # CUDA HARDWARE DETECTION & INITIALIZATION
    # ==========================================
    xorl    %edi, %edi
    call    cuInit@PLT
    testl   %eax, %eax
    jnz     .L_cuda_error

    # Meld de start van de runtime-engine via sys_write
    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_start(%rip), %rsi
    movl    fmt_start_l(%rip), %edx
    syscall

    # ==========================================
    # 1. DOUBLE ZERO-COPY FILE MMAP
    # ==========================================
    # Open isotopes.db
    movl    $2, %eax              
    leaq    db_file(%rip), %rdi
    movl    $0, %esi              
    syscall
    movq    %rax, fd_db(%rip)

    # Map isotopes.db in virtuele adresruimte (128 KB)
    movl    $9, %eax              
    xorq    %rdi, %rdi
    movq    $131072, %rsi         
    movl    $1, %edx              # PROT_READ
    movl    $2, %r10d             # MAP_PRIVATE
    movq    fd_db(%rip), %r8
    xorq    %r9, %r9
    syscall
    movq    %rax, ptr_db(%rip)

    # Open data.bin
    movl    $2, %eax              
    leaq    data_file(%rip), %rdi
    movl    $0, %esi              
    syscall
    movq    %rax, fd_data(%rip)

    # Map data.bin in virtuele adresruimte (8 KB)
    movl    $9, %eax              
    xorq    %rdi, %rdi
    movq    $8192, %rsi           
    movl    $1, %edx              # PROT_READ
    movl    $2, %r10d             # MAP_PRIVATE
    movq    fd_data(%rip), %r8
    xorq    %r9, %r9
    syscall
    movq    %rax, ptr_data(%rip)

    # ==========================================
    # 2. CUDA EXECUTION SYSTEM CONTEXT SETUP
    # ==========================================
    leaq    cu_device(%rip), %rdi
    xorl    %esi, %esi
    call    cuDeviceGet@PLT
    
    leaq    cu_ctx(%rip), %rdi
    xorl    %esi, %esi
    movl    cu_device(%rip), %edx
    call    cuCtxCreate@PLT

    # Vraag GPU-geheugen aan via the Driver API
    leaq    d_t_ptr(%rip), %rdi
    movl    $4096, %esi
    call    cuMemAlloc@PLT
    
    leaq    d_y_ptr(%rip), %rdi
    movl    $4096, %esi
    call    cuMemAlloc@PLT
    
    leaq    d_k_out(%rip), %rdi
    movl    $4, %esi
    call    cuMemAlloc@PLT

    # Sluis de gemmapte buffers direct over naar de videokaart (HtoD)
    movq    d_t_ptr(%rip), %rdi
    movq    ptr_data(%rip), %rsi   
    movl    $4096, %edx
    call    cuMemcpyHtoD@PLT

    movq    d_y_ptr(%rip), %rdi
    movq    ptr_data(%rip), %rsi
    addq    $4096, %rsi                   
    movl    $4096, %edx
    call    cuMemcpyHtoD@PLT

    # IN-MEMORY MODULE LOADING (Geen schijfafhankelijkheid meer)
    leaq    cu_module(%rip), %rdi       # %rdi = Bestemming voor module handle
    leaq    cubin_start(%rip), %rsi     # %rsi = Adres van ingebakken CUBIN data in RAM
    call    cuModuleLoadData@PLT
    testl   %eax, %eax
    jnz     .L_mod_error
    
    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    func_name(%rip), %rdx
    call    cuModuleGetFunction@PLT

    # Update de parameter pointer maps in .data
    movq    d_t_ptr(%rip), %rax
    movq    %rax, kernel_params(%rip)
    movq    d_y_ptr(%rip), %rax
    movq    %rax, (kernel_params+8)(%rip)
    movq    d_k_out(%rip), %rax
    movq    %rax, (kernel_params+16)(%rip)

    # Activeer de videokaart-threads (Grid: 4, Block: 256)
    movq    cu_function(%rip), %rdi
    movl    $4, %esi              
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

    # Haal het resultaat terug van de GPU naar RAM
    leaq    learned_k(%rip), %rdi
    movq    d_k_out(%rip), %rsi
    movl    $4, %edx
    call    cuMemcpyDtoH@PLT

    # ==========================================
    # 3. STACK-LESS CPU BINARY SEARCH
    # ==========================================
    movss   learned_k(%rip), %xmm0 
    movq    ptr_db(%rip), %r12     

    xorl    %ebx, %ebx                    # Low index = 0
    movl    $3387, %ecx                   # High index = 3388 - 1

BINARY_SEARCH_LOOP:
    cmpl    %ecx, %ebx
    jg      FOUND_NEAREST               

    movl    %ebx, %eax
    addl    %ecx, %eax
    shrl    $1, %eax                      # Mid index

    movl    %eax, %edx
    shll    $5, %edx                      # Mid * 32 bytes per struct
    addq    %r12, %rdx                    # %rdx = Absolute pointer naar record_mid

    movss   (%rdx), %xmm1                 # Haal k-float op (offset 0 van struct)

    comiss  %xmm1, %xmm0
    je      MATCH_EXACT                 
    ja      SEARCH_HIGHER               

    movl    %eax, %ecx
    decl    %ecx                          # High = Mid - 1
    jmp     BINARY_SEARCH_LOOP

SEARCH_HIGHER:
    movl    %eax, %ebx
    incl    %ebx                          # Low = Mid + 1
    jmp     BINARY_SEARCH_LOOP

MATCH_EXACT:
    jmp     PRINT_DETERMINATION

FOUND_NEAREST:
    shll    $5, %ebx
    addq    %r12, %rbx
    movq    %rbx, %rdx                    # Dichtstbijzijnde record als fallback

    # ==========================================
    # 4. OUTPUT GENERATOR (PRINT RESULT)
    # ==========================================
PRINT_DETERMINATION:
    movq    %rdx, %r15                     

    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_match(%rip), %rsi
    movl    fmt_match_l(%rip), %edx
    syscall

    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_z(%rip), %rsi
    movl    fmt_z_l(%rip), %edx
    syscall

    movl    8(%r15), %eax                 # Z bevindt zich op offset 8
    call    print_uint

    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_a(%rip), %rsi
    movl    fmt_a_l(%rip), %edx
    syscall

    movl    4(%r15), %eax                 # A bevindt zich op offset 4
    call    print_uint

    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_name(%rip), %rsi
    movl    fmt_name_l(%rip), %edx
    syscall

    leaq    12(%r15), %rsi                # String start op offset 12
    xorl    %edx, %edx
LEN_LOOP:
    cmpb    $0, (%rsi,%rdx)
    je      PRINT_NAME
    incq    %rdx
    jmp     LEN_LOOP
PRINT_NAME:
    movl    $1, %eax
    movl    $1, %edi
    syscall

    movl    $1, %eax
    movl    $1, %edi
    leaq    fmt_nl(%rip), %rsi
    movl    $1, %edx
    syscall

    # Herstel stack frame en sluit clean af
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax
    xorl    %edi, %edi
    syscall

# --- STACK-PROOF INT TO ASCII WRITER ---
print_uint:
    leaq    (ascii_buf + 31)(%rip), %rcx       
    movb    $10, (%rcx)          
    movq    $10, %r8                      
.L_conv:
    xorl    %edx, %edx
    divq    %r8
    addb    $48, %dl                      
    decq    %rcx
    movb    %dl, (%rcx)
    testq   %rax, %rax
    jnz     .L_conv
    
    leaq    (ascii_buf + 32)(%rip), %rdx
    subq    %rcx, %rdx
    movl    $1, %eax
    movl    $1, %edi
    movq    %rcx, %rsi
    syscall
    ret

.L_cuda_error:
    movl    $1, %eax              # sys_write
    movl    $2, %edi              # stderr
    leaq    fmt_nocuda(%rip), %rsi
    movl    fmt_nocuda_l(%rip), %edx
    syscall
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax
    movl    $1, %edi              # Exit code 1
    syscall

.L_mod_error:
    movl    $1, %eax              # sys_write
    movl    $2, %edi              # stderr
    leaq    fmt_nomod(%rip), %rsi
    movl    fmt_nomod_l(%rip), %edx
    syscall
    movq    %rbp, %rsp
    popq    %rbp
    movl    $60, %eax
    movl    $1, %edi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

