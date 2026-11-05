/* Synthetic measurements y=exp(-k*t), CSV only, atomic publication.
 * Default GPU; --cpu uses libm exp as an independent reference backend.
 */
.include "decay.inc"
.global main
.section .rodata
usage: .asciz "Usage: create_decay_data K NPOINTS MAX_T [-o FILE.csv] [--cpu]\nRequires K>0, 3<=NPOINTS<=1000000, MAX_T>0, 0<K*MAX_T<=700.\nWrites t,y CSV with 17-digit precision; no .bin output."
default_csv: .asciz "decay_data.csv"
flag_output: .asciz "-o"
flag_cpu: .asciz "--cpu"
flag_help: .asciz "--help"
header: .asciz "t,y\n"
row_format: .asciz "%.17g,%.17g\n"
write_mode: .asciz "w"
tmp_suffix: .asciz ".tmp.XXXXXX"
kernel_name: .asciz "create_decay_data"
msg_args: .asciz "invalid arguments; use --help"
msg_gpu: .asciz "GPU generation failed (CUDA error %d)\n"
msg_memory: .asciz "cannot allocate measurement buffer"
msg_values: .asciz "generated measurements are invalid or not representable"
msg_file: .asciz "cannot create, write, close, or replace output CSV"
error_format: .asciz "create_decay_data: %s\n"
done_format: .asciz "Generated %lu measurements in %s (%s).\n"
backend_gpu: .asciz "GPU"
backend_cpu: .asciz "CPU reference"
max_product: .double 700.0
one: .double 1.0
.align 8
image: .incbin "create_decay_data.cubin"
.section .data
.align 8
kernel_params:
 output_device: .quad 0
 rate: .double 0
 samples: .long 0
 .align 8
 max_time: .double 0
kernel_args: .quad output_device,rate,samples,max_time
job:
 .quad image,kernel_name,kernel_args,0,0,0,0,0,output_device,1
.section .bss
.align 8
buffer: .zero 8
buffer_bytes: .zero 8
count_value: .zero 8
count_double: .zero 8
out_name: .zero 8
temporary: .zero 8
temp_created: .zero 8
stream: .zero 8
cpu_mode: .zero 8
status: .zero 8
current_time: .zero 8
.section .text
main:
 pushq %rbp
 movq %rsp,%rbp
 andq $-16,%rsp
 leaq -8(%rsi),%r12
 movl %edi,%r13d
 cmpq $2,%r13
 jne .Lrequired
 movq 16(%r12),%rdi
 leaq flag_help(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lbad_args
 leaq usage(%rip),%rdi
 call puts@PLT
 jmp .Lcleanup
.Lrequired:
 cmpq $4,%r13
 jb .Lbad_args
 movq 16(%r12),%rdi
 leaq rate(%rip),%rsi
 call decay_parse_number
 testl %eax,%eax
 jne .Lbad_args
 movq 24(%r12),%rdi
 leaq count_double(%rip),%rsi
 call decay_parse_number
 testl %eax,%eax
 jne .Lbad_args
 movsd count_double(%rip),%xmm0
 cvttsd2siq %xmm0,%rax
 cmpq $3,%rax
 jb .Lbad_args
 cmpq $MAX_SAMPLES,%rax
 ja .Lbad_args
 cvtsi2sdq %rax,%xmm1
 ucomisd %xmm1,%xmm0
 jne .Lbad_args
 movq %rax,count_value(%rip)
 movl %eax,samples(%rip)
 shlq $4,%rax
 movq %rax,buffer_bytes(%rip)
 movq 32(%r12),%rdi
 leaq max_time(%rip),%rsi
 call decay_parse_number
 testl %eax,%eax
 jne .Lbad_args
 pxor %xmm1,%xmm1
 movsd rate(%rip),%xmm0
 ucomisd %xmm1,%xmm0
 jbe .Lbad_args
 movsd max_time(%rip),%xmm2
 ucomisd %xmm1,%xmm2
 jbe .Lbad_args
 mulsd %xmm2,%xmm0
 ucomisd %xmm1,%xmm0
 jbe .Lbad_args
 ucomisd max_product(%rip),%xmm0
 ja .Lbad_args
 leaq default_csv(%rip),%rax
 movq %rax,out_name(%rip)
 movq $4,%r14
 xorl %r15d,%r15d
.Lflags:
 cmpq %r13,%r14
 jae .Lallocate
 movq 8(%r12,%r14,8),%rdi
 leaq flag_cpu(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Loutput_flag
 cmpq $0,cpu_mode(%rip)
 jne .Lbad_args
 movq $1,cpu_mode(%rip)
 jmp .Lnext_flag
.Loutput_flag:
 movq 8(%r12,%r14,8),%rdi
 leaq flag_output(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lbad_args
 testl %r15d,%r15d
 jnz .Lbad_args
 movl $1,%r15d
 incq %r14
 cmpq %r13,%r14
 jae .Lbad_args
 movq 8(%r12,%r14,8),%rax
 cmpb $0,(%rax)
 je .Lbad_args
 movq %rax,out_name(%rip)
.Lnext_flag:
 incq %r14
 jmp .Lflags
.Lallocate:
 movq buffer_bytes(%rip),%rdi
 call malloc@PLT
 testq %rax,%rax
 je .Lmemory_error
 movq %rax,buffer(%rip)
 cmpq $0,cpu_mode(%rip)
 jne .Lcpu
 movq %rax,job+JOB_OUTPUT(%rip)
 movq buffer_bytes(%rip),%rax
 movq %rax,job+JOB_OUTPUT_BYTES(%rip)
 movq count_value(%rip),%rax
 addq $255,%rax
 shrq $8,%rax
 movq %rax,job+JOB_GRID(%rip)
 leaq job(%rip),%rdi
 call decay_gpu_run
 testl %eax,%eax
 jne .Lgpu_error
 jmp .Lcheck_buffer
.Lcpu:
 xorl %ebx,%ebx
 movq buffer(%rip),%r12
.Lcpu_sample:
 cvtsi2sdq %rbx,%xmm0
 movq count_value(%rip),%rax
 decq %rax
 cvtsi2sdq %rax,%xmm1
 divsd %xmm1,%xmm0
 mulsd max_time(%rip),%xmm0
 movsd %xmm0,current_time(%rip)
 mulsd rate(%rip),%xmm0
 pxor %xmm1,%xmm1
 subsd %xmm0,%xmm1
 movapd %xmm1,%xmm0
 call exp@PLT
 movsd current_time(%rip),%xmm1
 movsd %xmm1,(%r12)
 movsd %xmm0,8(%r12)
 addq $16,%r12
 incq %rbx
 cmpq count_value(%rip),%rbx
 jb .Lcpu_sample
.Lcheck_buffer:
 movq buffer(%rip),%r12
 xorl %ebx,%ebx
 pxor %xmm2,%xmm2
.Lcheck_sample:
 movsd (%r12),%xmm0
 ucomisd %xmm2,%xmm0
 jb .Lvalue_error
 jp .Lvalue_error
 testq %rbx,%rbx
 jz .Lcheck_y
 ucomisd -16(%r12),%xmm0
 jbe .Lvalue_error
.Lcheck_y:
 movsd 8(%r12),%xmm0
 ucomisd %xmm2,%xmm0
 jbe .Lvalue_error
 ucomisd one(%rip),%xmm0
 ja .Lvalue_error
 addq $16,%r12
 incq %rbx
 cmpq count_value(%rip),%rbx
 jb .Lcheck_sample
 /* Unique adjacent temporary file, preserving previous output on failure. */
 movq out_name(%rip),%rdi
 call strlen@PLT
 leaq 12(%rax),%rdi
 call malloc@PLT
 testq %rax,%rax
 je .Lmemory_error
 movq %rax,temporary(%rip)
 movq %rax,%rdi
 movq out_name(%rip),%rsi
 call strcpy@PLT
 movq temporary(%rip),%rdi
 leaq tmp_suffix(%rip),%rsi
 call strcat@PLT
 movq temporary(%rip),%rdi
 call mkstemp@PLT
 testl %eax,%eax
 js .Lfile_error
 movq $1,temp_created(%rip)
 movl %eax,%ebx
 movl %eax,%edi
 leaq write_mode(%rip),%rsi
 call fdopen@PLT
 testq %rax,%rax
 jz .Lfdopen_error
 movq %rax,stream(%rip)
 leaq header(%rip),%rdi
 movq %rax,%rsi
 call fputs@PLT
 testl %eax,%eax
 js .Lfile_error
 movq buffer(%rip),%r12
 movq count_value(%rip),%r13
.Lwrite_sample:
 movq stream(%rip),%rdi
 leaq row_format(%rip),%rsi
 movsd (%r12),%xmm0
 movsd 8(%r12),%xmm1
 movl $2,%eax
 call fprintf@PLT
 testl %eax,%eax
 js .Lfile_error
 addq $16,%r12
 decq %r13
 jnz .Lwrite_sample
 movq stream(%rip),%rdi
 call fclose@PLT
 movq $0,stream(%rip)
 testl %eax,%eax
 jne .Lfile_error
 movq temporary(%rip),%rdi
 movq out_name(%rip),%rsi
 call rename@PLT
 testl %eax,%eax
 jne .Lfile_error
 movq $0,temp_created(%rip)
 leaq done_format(%rip),%rdi
 movq count_value(%rip),%rsi
 movq out_name(%rip),%rdx
 leaq backend_gpu(%rip),%rcx
 cmpq $0,cpu_mode(%rip)
 je .Lreport
 leaq backend_cpu(%rip),%rcx
.Lreport:
 xorl %eax,%eax
 call printf@PLT
 jmp .Lcleanup
.Lfdopen_error:
 movl %ebx,%edi
 call close@PLT
 jmp .Lfile_error
.Lgpu_error:
 movl %eax,%edx
 movq stderr(%rip),%rdi
 leaq msg_gpu(%rip),%rsi
 xorl %eax,%eax
 call fprintf@PLT
 jmp .Lfailed
.Lbad_args: leaq msg_args(%rip),%rdx; jmp .Lerror
.Lmemory_error: leaq msg_memory(%rip),%rdx; jmp .Lerror
.Lvalue_error: leaq msg_values(%rip),%rdx; jmp .Lerror
.Lfile_error: leaq msg_file(%rip),%rdx
.Lerror:
 movq stderr(%rip),%rdi
 leaq error_format(%rip),%rsi
 xorl %eax,%eax
 call fprintf@PLT
.Lfailed: movq $1,status(%rip)
.Lcleanup:
 movq stream(%rip),%rdi
 testq %rdi,%rdi
 jz .Lremove_temp
 call fclose@PLT
.Lremove_temp:
 cmpq $0,temp_created(%rip)
 je .Lfree
 movq temporary(%rip),%rdi
 call unlink@PLT
.Lfree:
 movq temporary(%rip),%rdi
 call free@PLT
 movq buffer(%rip),%rdi
 call free@PLT
 movl status(%rip),%edi
 call exit@PLT
.section .note.GNU-stack,"",@progbits
