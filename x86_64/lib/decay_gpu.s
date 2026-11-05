/* Checked CUDA Driver API execution, with deterministic teardown on all paths.
 * int decay_gpu_run(struct job*). Returns the first CUDA error, zero on success.
 */
.include "decay.inc"
.section .text
.global decay_gpu_run
.type decay_gpu_run,@function
decay_gpu_run:
 pushq %rbp
 movq %rsp,%rbp
 pushq %rbx
 pushq %r12
 subq $64,%rsp
 movq %rdi,%r12
 movq $0,-24(%rbp)             /* context */
 movq $0,-32(%rbp)             /* module */
 movq $0,-40(%rbp)             /* function */
 movq $0,-48(%rbp)             /* device input */
 movq $0,-56(%rbp)             /* device output */
 movl $0,-64(%rbp)             /* result */
 xorl %edi,%edi
 call cuInit@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 leaq -72(%rbp),%rdi
 xorl %esi,%esi
 call cuDeviceGet@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 leaq -24(%rbp),%rdi
 xorl %esi,%esi
 movl -72(%rbp),%edx
 call cuCtxCreate_v2@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 leaq -32(%rbp),%rdi
 movq JOB_IMAGE(%r12),%rsi
 call cuModuleLoadData@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 leaq -40(%rbp),%rdi
 movq -32(%rbp),%rsi
 movq JOB_NAME(%r12),%rdx
 call cuModuleGetFunction@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 cmpq $0,JOB_INPUT_BYTES(%r12)
 je .Lallocate_output
 leaq -48(%rbp),%rdi
 movq JOB_INPUT_BYTES(%r12),%rsi
 call cuMemAlloc_v2@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 movq JOB_INPUT_SLOT(%r12),%rdx
 movq -48(%rbp),%rax
 movq %rax,(%rdx)
 movq %rax,%rdi
 movq JOB_INPUT(%r12),%rsi
 movq JOB_INPUT_BYTES(%r12),%rdx
 call cuMemcpyHtoD_v2@PLT
 testl %eax,%eax
 jne .Lgpu_fail
.Lallocate_output:
 leaq -56(%rbp),%rdi
 movq JOB_OUTPUT_BYTES(%r12),%rsi
 call cuMemAlloc_v2@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 movq JOB_OUTPUT_SLOT(%r12),%rdx
 movq -56(%rbp),%rax
 movq %rax,(%rdx)
 movq -40(%rbp),%rdi
 movl JOB_GRID(%r12),%esi
 movl $1,%edx
 movl $1,%ecx
 movl $256,%r8d
 movl $1,%r9d
 subq $48,%rsp
 movq $1,0(%rsp)
 movq $0,8(%rsp)
 movq $0,16(%rsp)
 movq JOB_ARGS(%r12),%rax
 movq %rax,24(%rsp)
 movq $0,32(%rsp)
 call cuLaunchKernel@PLT
 addq $48,%rsp
 testl %eax,%eax
 jne .Lgpu_fail
 call cuCtxSynchronize@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 movq JOB_OUTPUT(%r12),%rdi
 movq -56(%rbp),%rsi
 movq JOB_OUTPUT_BYTES(%r12),%rdx
 call cuMemcpyDtoH_v2@PLT
 testl %eax,%eax
 jne .Lgpu_fail
 jmp .Lgpu_cleanup
.Lgpu_fail:
 movl %eax,-64(%rbp)
.Lgpu_cleanup:
 movq -48(%rbp),%rdi
 testq %rdi,%rdi
 je .Lgpu_free_out
 call cuMemFree_v2@PLT
 call .Lremember_cleanup
.Lgpu_free_out:
 movq -56(%rbp),%rdi
 testq %rdi,%rdi
 je .Lgpu_destroy
 call cuMemFree_v2@PLT
 call .Lremember_cleanup
.Lgpu_destroy:
 movq -24(%rbp),%rdi
 testq %rdi,%rdi
 je .Lgpu_return
 call cuCtxDestroy_v2@PLT
 call .Lremember_cleanup
.Lgpu_return:
 movq JOB_INPUT_SLOT(%r12),%rdx
 testq %rdx,%rdx
 je .Lzero_output
 movq $0,(%rdx)
.Lzero_output:
 movq JOB_OUTPUT_SLOT(%r12),%rdx
 movq $0,(%rdx)
 movl -64(%rbp),%eax
 addq $64,%rsp
 popq %r12
 popq %rbx
 leave
 ret
.Lremember_cleanup:
 cmpl $0,-64(%rbp)
 jne .Lremember_done
 movl %eax,-64(%rbp)
.Lremember_done: ret
.size decay_gpu_run,.-decay_gpu_run
.section .note.GNU-stack,"",@progbits
