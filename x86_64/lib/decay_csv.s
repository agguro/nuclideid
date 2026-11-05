/* Strict two-column measurement CSV reader. Header: t,y. No binary files.
 * int decay_csv_load(path, work*) returns 0/1. On failure output unchanged.
 * On success caller frees work.data. Strictly increasing nonnegative times
 * and positive finite y are validated by decay_prepare before fitting.
 */
.include "decay.inc"
.section .rodata
csv_mode: .asciz "r"
csv_header: .asciz "t,y"
.section .text
.global decay_csv_load
.type decay_csv_load,@function
decay_csv_load:
 pushq %rbp
 movq %rsp,%rbp
 pushq %rbx
 pushq %r12
 pushq %r13
 pushq %r14
 pushq %r15
 subq $88,%rsp
 /* locals: FILE -48, line -56, cap -64, data -72, count -80,
  * allocation count -88, out -96, result -104, line number -112. */
 movq $0,-48(%rbp)
 movq $0,-56(%rbp)
 movq $0,-64(%rbp)
 movq $0,-72(%rbp)
 movq $0,-80(%rbp)
 movq $0,-88(%rbp)
 movq %rsi,-96(%rbp)
 movl $1,-104(%rbp)
 movq $0,-112(%rbp)
 testq %rdi,%rdi
 jz .Lcsv_cleanup
 testq %rsi,%rsi
 jz .Lcsv_cleanup
 cmpq $0,WORK_DATA(%rsi)
 jne .Lcsv_cleanup
 leaq csv_mode(%rip),%rsi
 call fopen@PLT
 testq %rax,%rax
 jz .Lcsv_cleanup
 movq %rax,-48(%rbp)
.Lread:
 leaq -56(%rbp),%rdi
 leaq -64(%rbp),%rsi
 movq -48(%rbp),%rdx
 call getline@PLT
 testq %rax,%rax
 js .Lcsv_eof
 movq %rax,%r15
 incq -112(%rbp)
 movq -56(%rbp),%rdi
 call strlen@PLT
 cmpq %r15,%rax
 jne .Lcsv_cleanup
 movq -56(%rbp),%r12
 cmpb $10,-1(%r12,%r15)
 jne .Ltrim_done
 decq %r15
 testq %r15,%r15
 jz .Ltrim_done
 cmpb $13,-1(%r12,%r15)
 jne .Ltrim_done
 decq %r15
.Ltrim_done:
 movb $0,(%r12,%r15)
 cmpq $1,-112(%rbp)
 jne .Lcsv_row
 movq %r12,%rdi
 leaq csv_header(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lcsv_cleanup
 jmp .Lread
.Lcsv_row:
 testq %r15,%r15
 jz .Lread
 movq %r12,%rdi
 movl $44,%esi
 call strchr@PLT
 testq %rax,%rax
 jz .Lcsv_cleanup
 movb $0,(%rax)
 leaq 1(%rax),%r13
 movq %r13,%rdi
 movl $44,%esi
 call strchr@PLT
 testq %rax,%rax
 jnz .Lcsv_cleanup
 cmpq $MAX_SAMPLES,-80(%rbp)
 jae .Lcsv_cleanup
 movq -80(%rbp),%rax
 cmpq -88(%rbp),%rax
 jb .Lcsv_space
 movq -88(%rbp),%rbx
 testq %rbx,%rbx
 jnz .Lcsv_grow
 movq $32,%rbx
.Lcsv_grow:
 shlq $1,%rbx
 movq %rbx,%rsi
 shlq $4,%rsi
 movq -72(%rbp),%rdi
 call realloc@PLT
 testq %rax,%rax
 jz .Lcsv_cleanup
 movq %rax,-72(%rbp)
 movq %rbx,-88(%rbp)
.Lcsv_space:
 movq -80(%rbp),%r14
 shlq $4,%r14
 addq -72(%rbp),%r14
 movq %r12,%rdi
 movq %r14,%rsi
 call decay_parse_number@PLT
 testl %eax,%eax
 jne .Lcsv_cleanup
 movq %r13,%rdi
 leaq 8(%r14),%rsi
 call decay_parse_number@PLT
 testl %eax,%eax
 jne .Lcsv_cleanup
 incq -80(%rbp)
 jmp .Lread
.Lcsv_eof:
 movq -48(%rbp),%rdi
 call feof@PLT
 testl %eax,%eax
 jz .Lcsv_cleanup
 movq -48(%rbp),%rdi
 call ferror@PLT
 testl %eax,%eax
 jnz .Lcsv_cleanup
 cmpq $3,-80(%rbp)
 jb .Lcsv_cleanup
 movq -48(%rbp),%rdi
 call fclose@PLT
 movq $0,-48(%rbp)
 testl %eax,%eax
 jne .Lcsv_cleanup
 movq -96(%rbp),%rdx
 movq -72(%rbp),%rax
 movq %rax,WORK_DATA(%rdx)
 movq -80(%rbp),%rax
 movq %rax,WORK_COUNT(%rdx)
 movq $0,WORK_T0(%rdx)
 movq $0,WORK_SPAN(%rdx)
 movq $0,WORK_LOG_Y0(%rdx)
 movq $0,-72(%rbp)
 movl $0,-104(%rbp)
.Lcsv_cleanup:
 movq -48(%rbp),%rdi
 testq %rdi,%rdi
 jz .Lcsv_free
 call fclose@PLT
.Lcsv_free:
 movq -56(%rbp),%rdi
 call free@PLT
 movq -72(%rbp),%rdi
 call free@PLT
 movl -104(%rbp),%eax
 addq $88,%rsp
 popq %r15
 popq %r14
 popq %r13
 popq %r12
 popq %rbx
 leave
 ret
.size decay_csv_load,.-decay_csv_load
.section .note.GNU-stack,"",@progbits
