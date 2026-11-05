/* Historical command name, new role: inspect the SQLite -> RAM catalog.
 * No .bin input/output, CUDA initialization, padding, or GPU sorting.
 * Link isotope_catalog.o into inference to retain the buffer in that process.
 */
.include "isotope_catalog.inc"
.global _start
.section .rodata
default_db: .asciz "isotopes.sqlite3"
help_flag: .asciz "--help"
list_flag: .asciz "--list"
usage: .asciz "Usage: isotopes_bitonic_sort [DATABASE] [--list]\nLoads unqualified measured isotopes from SQLite into sorted host memory.\nNo database changes or isotope .bin files. --list prints the loaded records."
summary: .asciz "Loaded %lu measured isotopes (%lu bytes) from %s into host memory.\n"
list_header: .asciz "z\tn\ta\tsymbol\thalf_life_seconds\tdecay_constant"
record_format: .asciz "%lu\t%lu\t%lu\t%s\t%.17g\t%.17g\n"
error_format: .asciz "isotopes_bitonic_sort: %s\n"
bad_args: .asciz "invalid arguments; use --help (-o and .bin files are no longer supported)"
.section .bss
.align 8
catalog: .zero CATALOG_SIZE
show_list: .zero 8
return_code: .zero 8
.section .text
_start:
 movq %rsp,%r12
 andq $-16,%rsp
 movq (%r12),%r13
 leaq default_db(%rip),%r14
 xorl %ebx,%ebx                 /* whether a database path was provided */
 movq $1,%r15
.Larguments:
 cmpq %r13,%r15
 jae .Lload
 movq 8(%r12,%r15,8),%rdi
 leaq help_flag(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Ltry_list
 cmpq $2,%r13
 jne .Lbad_arguments
 leaq usage(%rip),%rdi
 call puts@PLT
 jmp .Lexit
.Ltry_list:
 movq 8(%r12,%r15,8),%rdi
 leaq list_flag(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lpath
 cmpq $0,show_list(%rip)
 jne .Lbad_arguments
 movq $1,show_list(%rip)
 jmp .Lnext
.Lpath:
 testl %ebx,%ebx
 jnz .Lbad_arguments
 movq 8(%r12,%r15,8),%rax
 cmpb $0,(%rax)
 je .Lbad_arguments
 cmpb $'-',(%rax)
 je .Lbad_arguments
 movq %rax,%r14
 movl $1,%ebx
.Lnext:
 incq %r15
 jmp .Larguments
.Lload:
 movq %r14,%rdi
 leaq catalog(%rip),%rsi
 call isotope_catalog_load
 testl %eax,%eax
 jne .Lload_error
 cmpq $0,show_list(%rip)
 jne .Llist
 leaq summary(%rip),%rdi
 movq catalog+CATALOG_COUNT(%rip),%rsi
 movq catalog+CATALOG_BYTES(%rip),%rdx
 movq %r14,%rcx
 xorl %eax,%eax
 call printf@PLT
 jmp .Lrelease
.Llist:
 leaq list_header(%rip),%rdi
 call puts@PLT
 movq catalog+CATALOG_DATA(%rip),%r12
 movq catalog+CATALOG_COUNT(%rip),%r13
.Lprint_record:
 leaq record_format(%rip),%rdi
 movq ISOTOPE_Z(%r12),%rsi
 movq ISOTOPE_N(%r12),%rdx
 movq ISOTOPE_A(%r12),%rcx
 leaq ISOTOPE_SYMBOL(%r12),%r8
 movsd ISOTOPE_HALF_LIFE(%r12),%xmm0
 movsd ISOTOPE_K(%r12),%xmm1
 movl $2,%eax
 call printf@PLT
 addq $ISOTOPE_SIZE,%r12
 decq %r13
 jnz .Lprint_record
.Lrelease:
 leaq catalog(%rip),%rdi
 call isotope_catalog_free
 movq stdout(%rip),%rdi
 call fflush@PLT
 testl %eax,%eax
 je .Lexit
 movq $1,return_code(%rip)
 jmp .Lexit
.Lbad_arguments:
 leaq bad_args(%rip),%rdx
 jmp .Lerror
.Lload_error:
 movl %eax,%edi
 call isotope_catalog_error
 movq %rax,%rdx
.Lerror:
 movq stderr(%rip),%rdi
 leaq error_format(%rip),%rsi
 xorl %eax,%eax
 call fprintf@PLT
 movq $1,return_code(%rip)
.Lexit:
 movl return_code(%rip),%edi
 call exit@PLT
.section .note.GNU-stack,"",@progbits
