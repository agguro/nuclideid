/* Fit all samples, load reference isotopes ONLY from SQLite, report candidates.
 * Default GPU centered reduction; --cpu selects the reference implementation.
 * Measurements are t,y CSV. No isotope or measurement .bin is used.
 */
.include "decay.inc"
.include "isotope_catalog.inc"
.global main
.section .rodata
default_data: .asciz "decay_data.csv"
default_db: .asciz "isotopes.sqlite3"
flag_help: .asciz "--help"
flag_cpu: .asciz "--cpu"
flag_tolerance: .asciz "--tolerance"
usage: .asciz "Usage: learn_decay [DATA.csv [DATABASE.sqlite3]] [--cpu] [--tolerance FRACTION]\nDefault GPU; CSV header t,y, 3..1000000 strictly increasing nonnegative times, positive y.\nDefault relative k tolerance 0.01; report all measured candidates, not a definitive identity."
kernel_name: .asciz "learnDecayMoments"
backend_gpu: .asciz "GPU"
backend_cpu: .asciz "CPU reference"
fit_format: .asciz "k=%.17g half_life_seconds=%.17g log_amplitude=%.17g log_rmse=%.17g r_squared=%.17g samples=%lu backend=%s\n"
candidate_summary: .asciz "%lu candidate(s) within relative k tolerance %.6g; decay rate alone does not establish identity.\n"
candidate_format: .asciz "candidate=%s-%lu z=%lu n=%lu k=%.17g relative_error=%.17g\n"
error_format: .asciz "learn_decay: %s\n"
gpu_error_format: .asciz "learn_decay: CUDA error %d (use --cpu explicitly for the reference backend)\n"
msg_args: .asciz "invalid arguments; use --help"
msg_csv: .asciz "cannot read measurements: expected t,y CSV with 3..1000000 finite numeric pairs"
msg_samples: .asciz "invalid samples: times must increase strictly from t>=0; y must be positive and finite"
msg_fit: .asciz "measurements do not yield a finite positive single-exponential decay fit"
msg_quality: .asciz "fit rejected: requires log_rmse<=0.05 and r_squared>=0.95"
msg_no_match: .asciz "no measured isotope lies within the requested decay-constant tolerance"
max_rmse: .double 0.05
min_r2: .double 0.95
one: .double 1.0
.align 8
image: .incbin "learn_decay.cubin"
.section .data
.align 8
tolerance: .double 0.01
param_input: .quad 0
param_output: .quad 0
param_count: .long 0
.align 8
kernel_args: .quad param_input,param_output,param_count
job: .quad image,kernel_name,kernel_args,0,0,param_input,stats,40,param_output,1
.section .bss
.align 8
catalog: .zero CATALOG_SIZE
work: .zero WORK_SIZE
stats: .zero 40
fit: .zero FIT_SIZE
data_name: .zero 8
db_name: .zero 8
cpu_mode: .zero 8
tolerance_seen: .zero 8
candidates: .zero 8
status: .zero 8
.section .text
main:
 pushq %rbp
 movq %rsp,%rbp
 andq $-16,%rsp
 leaq -8(%rsi),%r12
 movl %edi,%r13d
 leaq default_data(%rip),%rax
 movq %rax,data_name(%rip)
 leaq default_db(%rip),%rax
 movq %rax,db_name(%rip)
 movq $1,%r14
 xorl %r15d,%r15d
.Largs:
 cmpq %r13,%r14
 jae .Lload
 movq 8(%r12,%r14,8),%rdi
 leaq flag_help(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lcpu_flag
 cmpq $2,%r13
 jne .Lbad_args
 leaq usage(%rip),%rdi
 call puts@PLT
 jmp .Lcleanup
.Lcpu_flag:
 movq 8(%r12,%r14,8),%rdi
 leaq flag_cpu(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Ltolerance_flag
 cmpq $0,cpu_mode(%rip)
 jne .Lbad_args
 movq $1,cpu_mode(%rip)
 jmp .Lnext_arg
.Ltolerance_flag:
 movq 8(%r12,%r14,8),%rdi
 leaq flag_tolerance(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lpositional
 cmpq $0,tolerance_seen(%rip)
 jne .Lbad_args
 movq $1,tolerance_seen(%rip)
 incq %r14
 cmpq %r13,%r14
 jae .Lbad_args
 movq 8(%r12,%r14,8),%rdi
 leaq tolerance(%rip),%rsi
 call decay_parse_number
 testl %eax,%eax
 jne .Lbad_args
 pxor %xmm1,%xmm1
 movsd tolerance(%rip),%xmm0
 ucomisd %xmm1,%xmm0
 jbe .Lbad_args
 ucomisd one(%rip),%xmm0
 ja .Lbad_args
 jmp .Lnext_arg
.Lpositional:
 movq 8(%r12,%r14,8),%rax
 cmpb $0,(%rax)
 je .Lbad_args
 cmpb $'-',(%rax)
 je .Lbad_args
 testq %r15,%r15
 jnz .Ldb_path
 movq %rax,data_name(%rip)
 jmp .Lgot_path
.Ldb_path:
 cmpq $1,%r15
 jne .Lbad_args
 movq %rax,db_name(%rip)
.Lgot_path: incq %r15
.Lnext_arg:
 incq %r14
 jmp .Largs
.Lload:
 movq db_name(%rip),%rdi
 leaq catalog(%rip),%rsi
 call isotope_catalog_load
 testl %eax,%eax
 jne .Lcatalog_error
 movq data_name(%rip),%rdi
 leaq work(%rip),%rsi
 call decay_csv_load
 testl %eax,%eax
 jne .Lcsv_error
 leaq work(%rip),%rdi
 call decay_prepare
 testl %eax,%eax
 jne .Lsample_error
 cmpq $0,cpu_mode(%rip)
 jne .Lcpu_fit
 movq work+WORK_DATA(%rip),%rax
 movq %rax,job+JOB_INPUT(%rip)
 movq work+WORK_COUNT(%rip),%rax
 movl %eax,param_count(%rip)
 shlq $4,%rax
 movq %rax,job+JOB_INPUT_BYTES(%rip)
 leaq job(%rip),%rdi
 call decay_gpu_run
 testl %eax,%eax
 jne .Lgpu_error
 jmp .Lfinish_fit
.Lcpu_fit:
 leaq work(%rip),%rdi
 leaq stats(%rip),%rsi
 call decay_moments_cpu
.Lfinish_fit:
 leaq work(%rip),%rdi
 leaq stats(%rip),%rsi
 leaq fit(%rip),%rdx
 call decay_finish
 testl %eax,%eax
 jne .Lfit_error
 leaq fit_format(%rip),%rdi
 movsd fit+FIT_K(%rip),%xmm0
 movsd fit+FIT_HALF(%rip),%xmm1
 movsd fit+FIT_LOG_A(%rip),%xmm2
 movsd fit+FIT_RMSE(%rip),%xmm3
 movsd fit+FIT_R2(%rip),%xmm4
 movq work+WORK_COUNT(%rip),%rsi
 leaq backend_gpu(%rip),%rdx
 cmpq $0,cpu_mode(%rip)
 je .Lprint_fit
 leaq backend_cpu(%rip),%rdx
.Lprint_fit:
 movl $5,%eax
 call printf@PLT
 movsd fit+FIT_RMSE(%rip),%xmm0
 ucomisd max_rmse(%rip),%xmm0
 ja .Lquality_error
 movsd fit+FIT_R2(%rip),%xmm0
 ucomisd min_r2(%rip),%xmm0
 jb .Lquality_error
 movq catalog+CATALOG_DATA(%rip),%r12
 movq catalog+CATALOG_COUNT(%rip),%r13
.Lcount_candidates:
 call .Lrelative_error
 ucomisd tolerance(%rip),%xmm0
 ja .Lcount_next
 incq candidates(%rip)
.Lcount_next:
 addq $ISOTOPE_SIZE,%r12
 decq %r13
 jnz .Lcount_candidates
 cmpq $0,candidates(%rip)
 je .Lno_match
 leaq candidate_summary(%rip),%rdi
 movq candidates(%rip),%rsi
 movsd tolerance(%rip),%xmm0
 movl $1,%eax
 call printf@PLT
 movq catalog+CATALOG_DATA(%rip),%r12
 movq catalog+CATALOG_COUNT(%rip),%r13
.Lprint_candidates:
 call .Lrelative_error
 ucomisd tolerance(%rip),%xmm0
 ja .Lprint_next
 movapd %xmm0,%xmm1
 movsd ISOTOPE_K(%r12),%xmm0
 leaq candidate_format(%rip),%rdi
 leaq ISOTOPE_SYMBOL(%r12),%rsi
 movq ISOTOPE_A(%r12),%rdx
 movq ISOTOPE_Z(%r12),%rcx
 movq ISOTOPE_N(%r12),%r8
 movl $2,%eax
 call printf@PLT
.Lprint_next:
 addq $ISOTOPE_SIZE,%r12
 decq %r13
 jnz .Lprint_candidates
 jmp .Lcleanup
.Lrelative_error:
 movsd ISOTOPE_K(%r12),%xmm0
 subsd fit+FIT_K(%rip),%xmm0
 movq %xmm0,%rax
 btrq $63,%rax
 movq %rax,%xmm0
 divsd fit+FIT_K(%rip),%xmm0
 ret
.Lcatalog_error:
 movl %eax,%edi
 call isotope_catalog_error
 movq %rax,%rdx
 jmp .Lerror
.Lgpu_error:
 movl %eax,%edx
 movq stderr(%rip),%rdi
 leaq gpu_error_format(%rip),%rsi
 xorl %eax,%eax
 call fprintf@PLT
 movq $1,status(%rip)
 jmp .Lcleanup
.Lbad_args: leaq msg_args(%rip),%rdx; jmp .Lerror
.Lcsv_error: leaq msg_csv(%rip),%rdx; jmp .Lerror
.Lsample_error: leaq msg_samples(%rip),%rdx; jmp .Lerror
.Lfit_error: leaq msg_fit(%rip),%rdx; jmp .Lerror
.Lquality_error: leaq msg_quality(%rip),%rdx; jmp .Lrejected
.Lno_match: leaq msg_no_match(%rip),%rdx
.Lrejected:
 movq $2,status(%rip)
 jmp .Lmessage
.Lerror:
 movq $1,status(%rip)
.Lmessage:
 movq stderr(%rip),%rdi
 leaq error_format(%rip),%rsi
 xorl %eax,%eax
 call fprintf@PLT
.Lcleanup:
 movq work+WORK_DATA(%rip),%rdi
 call free@PLT
 leaq catalog(%rip),%rdi
 call isotope_catalog_free
 xorl %edi,%edi
 call fflush@PLT
 testl %eax,%eax
 je .Lexit
 movq $1,status(%rip)
.Lexit:
 movl status(%rip),%edi
 call exit@PLT
.section .note.GNU-stack,"",@progbits
