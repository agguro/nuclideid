/* SQLite -> sorted host-memory catalog. GNU x86-64, SysV ABI, PIC.
 * Public API: isotope_catalog.h; layout: isotope_catalog.inc.
 * No global mutable state, no CUDA calls, no file writes.
 */
.include "isotope_catalog.inc"
.section .rodata
catalog_sql:
 .asciz "SELECT z,n,a,symbol,half_life_seconds,decay_constant FROM nuclides WHERE status='measured' ORDER BY decay_constant,z,n"
catalog_ln2: .double 0.693147180559945309417
catalog_tolerance: .double 0.000000000001
catalog_max: .double 1.7976931348623157e308
catalog_symbols:
 .asciz "n","H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca","Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu","Zn","Ga","Ge","As","Se","Br","Kr","Rb","Sr","Y","Zr","Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn","Sb","Te","I","Xe","Cs","Ba","La","Ce","Pr","Nd","Pm","Sm","Eu","Gd","Tb","Dy","Ho","Er","Tm","Yb","Lu","Hf","Ta","W","Re","Os","Ir","Pt","Au","Hg","Tl","Pb","Bi","Po","At","Rn","Fr","Ra","Ac","Th","Pa","U","Np","Pu","Am","Cm","Bk","Cf","Es","Fm","Md","No","Lr","Rf","Db","Sg","Bh","Hs","Mt","Ds","Rg","Cn","Nh","Fl","Mc","Lv","Ts","Og"
error_ok: .asciz "success"
error_argument: .asciz "invalid arguments or catalog is not empty"
error_sqlite: .asciz "cannot read SQLite catalog (file, schema, lock, or database error)"
error_row: .asciz "invalid isotope identity, type, half-life, decay constant, or ordering"
error_empty: .asciz "database contains no unqualified measured half-lives"
error_memory: .asciz "cannot allocate isotope catalog"
error_unknown: .asciz "unknown catalog error"

/* Stack locals, rbp-relative, below saved registers. */
.equ DB, -48
.equ STMT, -56
.equ BUFFER, -64
.equ COUNT, -72
.equ CAPACITY, -80
.equ ERROR, -88
.equ PATH, -96
.equ OUTPUT, -104
.section .text
.global isotope_catalog_load
.type isotope_catalog_load,@function
isotope_catalog_load:
 pushq %rbp
 movq %rsp,%rbp
 pushq %rbx
 pushq %r12
 pushq %r13
 pushq %r14
 pushq %r15
 subq $72,%rsp                   /* 16-byte aligned before every call */
 movq $0,DB(%rbp)
 movq $0,STMT(%rbp)
 movq $0,BUFFER(%rbp)
 movq $0,COUNT(%rbp)
 movq $0,CAPACITY(%rbp)
 movq $0,ERROR(%rbp)
 movq %rdi,PATH(%rbp)
 movq %rsi,OUTPUT(%rbp)
 testq %rdi,%rdi
 jz .Largument
 cmpb $0,(%rdi)
 je .Largument
 testq %rsi,%rsi
 jz .Largument
 movq CATALOG_DATA(%rsi),%rax
 orq CATALOG_COUNT(%rsi),%rax
 orq CATALOG_BYTES(%rsi),%rax
 jnz .Largument
 leaq DB(%rbp),%rsi
 movl $1,%edx                   /* SQLITE_OPEN_READONLY; never create a DB */
 xorl %ecx,%ecx
 call sqlite3_open_v2@PLT
 testl %eax,%eax
 jne .Lsqlite
 movq DB(%rbp),%rdi
 movl $5000,%esi
 call sqlite3_busy_timeout@PLT
 testl %eax,%eax
 jne .Lsqlite
 movq DB(%rbp),%rdi
 leaq catalog_sql(%rip),%rsi
 movl $-1,%edx
 leaq STMT(%rbp),%rcx
 xorl %r8d,%r8d
 call sqlite3_prepare_v2@PLT
 testl %eax,%eax
 jne .Lsqlite
.Lstep:
 movq STMT(%rbp),%rdi
 call sqlite3_step@PLT
 cmpl $101,%eax                 /* SQLITE_DONE */
 je .Ldone
 cmpl $100,%eax                 /* SQLITE_ROW */
 jne .Lsqlite
 movq COUNT(%rbp),%rax
 cmpq CAPACITY(%rbp),%rax
 jb .Lspace
 movq CAPACITY(%rbp),%rbx
 testq %rbx,%rbx
 jnz .Lgrow
 movq $32,%rbx
.Lgrow:
 /* Check multiplication by 2*64 before growing. */
 movabsq $0x00ffffffffffffff,%rax
 cmpq %rax,%rbx
 ja .Lmemory
 shlq $1,%rbx
 movq %rbx,%rsi
 shlq $6,%rsi
 movq BUFFER(%rbp),%rdi
 call realloc@PLT
 testq %rax,%rax
 jz .Lmemory
 movq %rax,BUFFER(%rbp)
 movq %rbx,CAPACITY(%rbp)
.Lspace:
 movq COUNT(%rbp),%r15
 shlq $6,%r15
 addq BUFFER(%rbp),%r15
 pxor %xmm0,%xmm0
 movdqu %xmm0,(%r15)
 movdqu %xmm0,16(%r15)
 movdqu %xmm0,32(%r15)
 movdqu %xmm0,48(%r15)
 /* Identity columns must be SQLite INTEGER, not coercible strings. */
 xorl %r12d,%r12d
.Lidentity:
 movq STMT(%rbp),%rdi
 movl %r12d,%esi
 call sqlite3_column_type@PLT
 cmpl $1,%eax
 jne .Lrow_error
 movq STMT(%rbp),%rdi
 movl %r12d,%esi
 call sqlite3_column_int64@PLT
 movq %rax,(%r15,%r12,8)
 incq %r12
 cmpq $3,%r12
 jb .Lidentity
 cmpq $118,ISOTOPE_Z(%r15)
 ja .Lrow_error
 cmpq $1000,ISOTOPE_N(%r15)
 ja .Lrow_error
 movq ISOTOPE_Z(%r15),%rax
 addq ISOTOPE_N(%r15),%rax
 jz .Lrow_error
 cmpq ISOTOPE_A(%r15),%rax
 jne .Lrow_error
 movq STMT(%rbp),%rdi
 movl $3,%esi
 call sqlite3_column_type@PLT
 cmpl $3,%eax                   /* SQLITE_TEXT */
 jne .Lrow_error
 movq STMT(%rbp),%rdi
 movl $3,%esi
 call sqlite3_column_text@PLT
 testq %rax,%rax
 jz .Lmemory
 movq %rax,%r14
 movq STMT(%rbp),%rdi
 movl $3,%esi
 call sqlite3_column_bytes@PLT
 cmpl $1,%eax
 jb .Lrow_error
 cmpl $2,%eax
 ja .Lrow_error
 movl %eax,%r13d
 leaq catalog_symbols(%rip),%rsi
 movq ISOTOPE_Z(%r15),%rcx
.Lseek_symbol:
 testq %rcx,%rcx
 jz .Lcompare_symbol
.Lnext_symbol:
 cmpb $0,(%rsi)
 leaq 1(%rsi),%rsi
 jne .Lnext_symbol
 decq %rcx
 jmp .Lseek_symbol
.Lcompare_symbol:
 movq %r14,%rdi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lrow_error
 /* Reject embedded NULs that strcmp alone would overlook. */
 movq %r14,%rdi
 call strlen@PLT
 cmpq %r13,%rax
 jne .Lrow_error
 movb (%r14),%al
 movb %al,ISOTOPE_SYMBOL(%r15)
 cmpq $2,%r13
 jne .Lnumbers
 movb 1(%r14),%al
 movb %al,ISOTOPE_SYMBOL+1(%r15)
.Lnumbers:
 movl $4,%r12d
.Lnumber_column:
 movq STMT(%rbp),%rdi
 movl %r12d,%esi
 call sqlite3_column_type@PLT
 cmpl $1,%eax
 je .Lcolumn_numeric
 cmpl $2,%eax                   /* SQLITE_FLOAT */
 jne .Lrow_error
.Lcolumn_numeric:
 movq STMT(%rbp),%rdi
 movl %r12d,%esi
 call sqlite3_column_double@PLT
 pxor %xmm1,%xmm1
 ucomisd %xmm1,%xmm0
 jbe .Lrow_error                /* Also rejects NaN (unordered sets CF). */
 ucomisd catalog_max(%rip),%xmm0
 ja .Lrow_error
 movsd %xmm0,(%r15,%r12,8)     /* columns 4,5 map to offsets 32,40 */
 incq %r12
 cmpq $6,%r12
 jb .Lnumber_column
 /* Reject an inconsistent stored k instead of passing it to inference. */
 movsd catalog_ln2(%rip),%xmm0
 divsd ISOTOPE_HALF_LIFE(%r15),%xmm0
 pxor %xmm1,%xmm1
 ucomisd %xmm1,%xmm0
 jbe .Lrow_error
 ucomisd catalog_max(%rip),%xmm0
 ja .Lrow_error
 movapd %xmm0,%xmm1
 subsd ISOTOPE_K(%r15),%xmm1
 movq %xmm1,%rax
 btrq $63,%rax
 movq %rax,%xmm1
 mulsd catalog_tolerance(%rip),%xmm0
 ucomisd %xmm0,%xmm1
 ja .Lrow_error
 movsd ISOTOPE_K(%r15),%xmm0
 movsd %xmm0,ISOTOPE_SORT_KEY(%r15)
 cmpq $0,COUNT(%rbp)
 je .Laccept
 ucomisd ISOTOPE_K-ISOTOPE_SIZE(%r15),%xmm0
 jb .Lrow_error
.Laccept:
 incq COUNT(%rbp)
 jmp .Lstep
.Ldone:
 cmpq $0,COUNT(%rbp)
 je .Lempty
 movq STMT(%rbp),%rdi
 call sqlite3_finalize@PLT
 movq $0,STMT(%rbp)
 testl %eax,%eax
 jne .Lsqlite
 movq DB(%rbp),%rdi
 call sqlite3_close@PLT
 testl %eax,%eax
 jne .Lsqlite
 movq $0,DB(%rbp)
 /* Publish the descriptor only after the entire snapshot was loaded. */
 movq OUTPUT(%rbp),%rdx
 movq BUFFER(%rbp),%rax
 movq %rax,CATALOG_DATA(%rdx)
 movq COUNT(%rbp),%rax
 movq %rax,CATALOG_COUNT(%rdx)
 shlq $6,%rax
 movq %rax,CATALOG_BYTES(%rdx)
 movq $0,BUFFER(%rbp)
 jmp .Lcleanup
.Largument: movq $1,ERROR(%rbp); jmp .Lcleanup
.Lsqlite: movq $2,ERROR(%rbp); jmp .Lcleanup
.Lrow_error: movq $3,ERROR(%rbp); jmp .Lcleanup
.Lempty: movq $4,ERROR(%rbp); jmp .Lcleanup
.Lmemory: movq $5,ERROR(%rbp)
.Lcleanup:
 movq STMT(%rbp),%rdi
 testq %rdi,%rdi
 je .Lclose_db
 call sqlite3_finalize@PLT
.Lclose_db:
 movq DB(%rbp),%rdi
 testq %rdi,%rdi
 je .Lfree_buffer
 call sqlite3_close@PLT
.Lfree_buffer:
 movq BUFFER(%rbp),%rdi
 call free@PLT
 movl ERROR(%rbp),%eax
 addq $72,%rsp
 popq %r15
 popq %r14
 popq %r13
 popq %r12
 popq %rbx
 popq %rbp
 ret
.size isotope_catalog_load,.-isotope_catalog_load

.global isotope_catalog_free
.type isotope_catalog_free,@function
isotope_catalog_free:
 testq %rdi,%rdi
 jz .Lfree_return
 pushq %rbx
 movq %rdi,%rbx
 movq CATALOG_DATA(%rbx),%rdi
 call free@PLT
 movq $0,CATALOG_DATA(%rbx)
 movq $0,CATALOG_COUNT(%rbx)
 movq $0,CATALOG_BYTES(%rbx)
 popq %rbx
.Lfree_return: ret
.size isotope_catalog_free,.-isotope_catalog_free

.global isotope_catalog_error
.type isotope_catalog_error,@function
isotope_catalog_error:
 leaq error_ok(%rip),%rax
 testl %edi,%edi
 je .Lerror_return
 leaq error_argument(%rip),%rax
 cmpl $1,%edi
 je .Lerror_return
 leaq error_sqlite(%rip),%rax
 cmpl $2,%edi
 je .Lerror_return
 leaq error_row(%rip),%rax
 cmpl $3,%edi
 je .Lerror_return
 leaq error_empty(%rip),%rax
 cmpl $4,%edi
 je .Lerror_return
 leaq error_memory(%rip),%rax
 cmpl $5,%edi
 je .Lerror_return
 leaq error_unknown(%rip),%rax
.Lerror_return: ret
.size isotope_catalog_error,.-isotope_catalog_error
.section .note.GNU-stack,"",@progbits
