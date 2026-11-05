/* Positive single-exponential model y=A*exp(-k*t).
 * Normalize time and log amplitude, then fit all samples by centered OLS.
 * No iterative optimizer or float32 conversion. GNU x86-64 / SysV ABI.
 */
.include "decay.inc"
.section .rodata
math_max: .double 1.7976931348623157e308
math_ln2: .double 0.693147180559945309417
math_one: .double 1.0
.section .text
.global decay_parse_number
.type decay_parse_number,@function
/* int decay_parse_number(const char*, double*); output unchanged on failure. */
decay_parse_number:
 pushq %rbp
 movq %rsp,%rbp
 pushq %r12
 pushq %r13
 subq $16,%rsp
 movq %rdi,%r12
 movq %rsi,%r13
 testq %rdi,%rdi
 jz .Lparse_bad
 testq %rsi,%rsi
 jz .Lparse_bad
 movq %rdi,%rcx
 cmpb $'+',(%rcx)
 je .Lsign
 cmpb $'-',(%rcx)
 jne .Ldigits_begin
.Lsign: incq %rcx
.Ldigits_begin:
 xorl %edx,%edx
.Ldigits:
 movb (%rcx),%al
 subb $'0',%al
 cmpb $9,%al
 ja .Ldot
 incq %rcx
 incl %edx
 jmp .Ldigits
.Ldot:
 cmpb $'.',(%rcx)
 jne .Lexponent
 incq %rcx
.Lfraction:
 movb (%rcx),%al
 subb $'0',%al
 cmpb $9,%al
 ja .Lexponent
 incq %rcx
 incl %edx
 jmp .Lfraction
.Lexponent:
 testl %edx,%edx
 jz .Lparse_bad
 cmpb $'e',(%rcx)
 je .Lexp_sign
 cmpb $'E',(%rcx)
 jne .Lnumber_end
.Lexp_sign:
 incq %rcx
 cmpb $'+',(%rcx)
 je .Lexp_skip
 cmpb $'-',(%rcx)
 jne .Lexp_start
.Lexp_skip: incq %rcx
.Lexp_start:
 xorl %edx,%edx
.Lexp_digits:
 movb (%rcx),%al
 subb $'0',%al
 cmpb $9,%al
 ja .Lexp_end
 incq %rcx
 incl %edx
 jmp .Lexp_digits
.Lexp_end:
 testl %edx,%edx
 jz .Lparse_bad
.Lnumber_end:
 cmpb $0,(%rcx)
 jne .Lparse_bad
 call __errno_location@PLT
 movl $0,(%rax)
 movq %r12,%rdi
 leaq (%rsp),%rsi
 call strtod@PLT
 movsd %xmm0,8(%rsp)
 call __errno_location@PLT
 cmpl $0,(%rax)
 jne .Lparse_bad
 movsd 8(%rsp),%xmm0
 movq %xmm0,%rax
 btrq $63,%rax
 movq %rax,%xmm1
 ucomisd math_max(%rip),%xmm1
 ja .Lparse_bad
 jp .Lparse_bad
 movsd %xmm0,(%r13)
 xorl %eax,%eax
 jmp .Lparse_end
.Lparse_bad: movl $1,%eax
.Lparse_end:
 addq $16,%rsp
 popq %r13
 popq %r12
 leave
 ret
.size decay_parse_number,.-decay_parse_number

.global decay_prepare
.type decay_prepare,@function
/* work initially owns raw (t,y) pairs; transform in place after validation. */
decay_prepare:
 pushq %rbp
 movq %rsp,%rbp
 pushq %rbx
 pushq %r12
 pushq %r13
 pushq %r14
 movq %rdi,%r12
 movq WORK_DATA(%r12),%r13
 movq WORK_COUNT(%r12),%r14
 cmpq $3,%r14
 jb .Lprepare_bad
 cmpq $MAX_SAMPLES,%r14
 ja .Lprepare_bad
 testq %r13,%r13
 jz .Lprepare_bad
 xorl %ebx,%ebx
 pxor %xmm2,%xmm2
.Lvalidate_sample:
 movq %rbx,%rax
 shlq $4,%rax
 movsd (%r13,%rax),%xmm0
 ucomisd %xmm2,%xmm0
 jb .Lprepare_bad
 jp .Lprepare_bad
 ucomisd math_max(%rip),%xmm0
 ja .Lprepare_bad
 testq %rbx,%rbx
 jz .Lvalidate_y
 ucomisd -16(%r13,%rax),%xmm0
 jbe .Lprepare_bad
.Lvalidate_y:
 movsd 8(%r13,%rax),%xmm0
 ucomisd %xmm2,%xmm0
 jbe .Lprepare_bad
 ucomisd math_max(%rip),%xmm0
 ja .Lprepare_bad
 incq %rbx
 cmpq %r14,%rbx
 jb .Lvalidate_sample
 movsd (%r13),%xmm0
 movsd %xmm0,WORK_T0(%r12)
 movq %r14,%rax
 decq %rax
 shlq $4,%rax
 movsd (%r13,%rax),%xmm1
 subsd %xmm0,%xmm1
 ucomisd %xmm2,%xmm1
 jbe .Lprepare_bad
 ucomisd math_max(%rip),%xmm1
 ja .Lprepare_bad
 movsd %xmm1,WORK_SPAN(%r12)
 movsd 8(%r13),%xmm0
 call log@PLT
 movsd %xmm0,WORK_LOG_Y0(%r12)
 xorl %ebx,%ebx
.Ltransform:
 movq %rbx,%r14
 shlq $4,%r14
 movsd 8(%r13,%r14),%xmm0
 call log@PLT
 subsd WORK_LOG_Y0(%r12),%xmm0
 movsd %xmm0,8(%r13,%r14)
 movsd (%r13,%r14),%xmm0
 subsd WORK_T0(%r12),%xmm0
 divsd WORK_SPAN(%r12),%xmm0
 movsd %xmm0,(%r13,%r14)
 incq %rbx
 cmpq WORK_COUNT(%r12),%rbx
 jb .Ltransform
 xorl %eax,%eax
 jmp .Lprepare_done
.Lprepare_bad: movl $1,%eax
.Lprepare_done:
 popq %r14
 popq %r13
 popq %r12
 popq %rbx
 leave
 ret
.size decay_prepare,.-decay_prepare

.global decay_moments_cpu
.type decay_moments_cpu,@function
/* stats[5] = mean_x, mean_v, Sxx, Sxv, Svv, two centered passes. */
decay_moments_cpu:
 movq WORK_DATA(%rdi),%rdx
 movq WORK_COUNT(%rdi),%rcx
 cvtsi2sd %rcx,%xmm7
 pxor %xmm0,%xmm0
 pxor %xmm1,%xmm1
 xorl %eax,%eax
.Lmean_loop:
 addsd (%rdx),%xmm0
 addsd 8(%rdx),%xmm1
 addq $16,%rdx
 incq %rax
 cmpq %rcx,%rax
 jb .Lmean_loop
 divsd %xmm7,%xmm0
 divsd %xmm7,%xmm1
 movsd %xmm0,(%rsi)
 movsd %xmm1,8(%rsi)
 pxor %xmm2,%xmm2
 pxor %xmm3,%xmm3
 pxor %xmm4,%xmm4
 movq WORK_DATA(%rdi),%rdx
 xorl %eax,%eax
.Lmoment_loop:
 movsd (%rdx),%xmm5
 subsd %xmm0,%xmm5
 movsd 8(%rdx),%xmm6
 subsd %xmm1,%xmm6
 movapd %xmm5,%xmm7
 mulsd %xmm5,%xmm7
 addsd %xmm7,%xmm2
 mulsd %xmm6,%xmm5
 addsd %xmm5,%xmm3
 mulsd %xmm6,%xmm6
 addsd %xmm6,%xmm4
 addq $16,%rdx
 incq %rax
 cmpq %rcx,%rax
 jb .Lmoment_loop
 movsd %xmm2,16(%rsi)
 movsd %xmm3,24(%rsi)
 movsd %xmm4,32(%rsi)
 ret
.size decay_moments_cpu,.-decay_moments_cpu

.global decay_finish
.type decay_finish,@function
/* int decay_finish(work*,stats*,fit*). Reject flat/growing/nonfinite fits.
 * Residuals are computed explicitly on the host to avoid SSE cancellation. */
decay_finish:
 pxor %xmm7,%xmm7
 movsd 16(%rsi),%xmm0
 ucomisd %xmm7,%xmm0
 jbe .Lfinish_bad
 movsd 32(%rsi),%xmm1
 ucomisd %xmm7,%xmm1
 jbe .Lfinish_bad
 movsd 24(%rsi),%xmm2
 ucomisd %xmm7,%xmm2
 jae .Lfinish_bad
 jp .Lfinish_bad
 divsd %xmm0,%xmm2             /* slope in normalized coordinates */
 movapd %xmm7,%xmm0
 subsd %xmm2,%xmm0
 divsd WORK_SPAN(%rdi),%xmm0
 ucomisd %xmm7,%xmm0
 jbe .Lfinish_bad
 ucomisd math_max(%rip),%xmm0
 ja .Lfinish_bad
 movsd %xmm0,FIT_K(%rdx)
 movsd math_ln2(%rip),%xmm1
 divsd %xmm0,%xmm1
 ucomisd math_max(%rip),%xmm1
 ja .Lfinish_bad
 movsd %xmm1,FIT_HALF(%rdx)
 mulsd WORK_T0(%rdi),%xmm0
 addsd WORK_LOG_Y0(%rdi),%xmm0
 addsd 8(%rsi),%xmm0
 movsd (%rsi),%xmm1
 mulsd %xmm2,%xmm1
 subsd %xmm1,%xmm0
 movq %xmm0,%rax
 btrq $63,%rax
 movq %rax,%xmm1
 ucomisd math_max(%rip),%xmm1
 ja .Lfinish_bad
 movsd %xmm0,FIT_LOG_A(%rdx)
 movq WORK_DATA(%rdi),%r8
 movq WORK_COUNT(%rdi),%rcx
 movsd (%rsi),%xmm3
 movsd 8(%rsi),%xmm4
 pxor %xmm0,%xmm0
 xorl %eax,%eax
.Lresidual:
 movsd (%r8),%xmm1
 subsd %xmm3,%xmm1
 mulsd %xmm2,%xmm1
 addsd %xmm4,%xmm1
 subsd 8(%r8),%xmm1
 mulsd %xmm1,%xmm1
 addsd %xmm1,%xmm0
 addq $16,%r8
 incq %rax
 cmpq %rcx,%rax
 jb .Lresidual
 movapd %xmm0,%xmm1
 divsd 32(%rsi),%xmm1
 movsd math_one(%rip),%xmm2
 subsd %xmm1,%xmm2
 movsd %xmm2,FIT_R2(%rdx)
 cvtsi2sd %rcx,%xmm1
 divsd %xmm1,%xmm0
 sqrtsd %xmm0,%xmm0
 ucomisd math_max(%rip),%xmm0
 ja .Lfinish_bad
 jp .Lfinish_bad
 movsd %xmm0,FIT_RMSE(%rdx)
 xorl %eax,%eax
 ret
.Lfinish_bad:
 movl $1,%eax
 ret
.size decay_finish,.-decay_finish
.section .note.GNU-stack,"",@progbits
