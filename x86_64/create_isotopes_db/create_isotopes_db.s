/* Validated IAEA CSV -> SQLite importer, GNU x86-64 AT&T / SysV ABI.
 * Usage: create_isotopes_db [CSV [DATABASE]]
 * The previous database contents survive a failed import (one transaction).
 * source_csv retains all 55 source fields, including uncertainty/provenance.
 * SQLite >= 3.37 is required for STRICT tables. No CUDA dependency.
 */
.global _start
.section .rodata
csv_default: .asciz "isotopes.csv"
db_default: .asciz "isotopes.sqlite3"
read_mode: .asciz "r"
help_arg: .asciz "--help"
usage: .asciz "Usage: create_isotopes_db [CSV [DATABASE]]"
header_expected: .asciz "z,n,symbol,radius,unc_r,abundance,unc_a,energy_shift,energy,unc_e,ripl_shift,jp,half_life,operator_hl,unc_hl,unit_hl,half_life_sec,unc_hls,decay_1,decay_1_%,unc_1,decay_2,decay_2_%,unc_2,decay_3,decay_3_%,unc_3,isospin,magnetic_dipole,unc_md,electric_quadrupole,unc_eq,qbm,unc_qb,qbm_n,unc_qbmn,qa,unc_qa,qec,unc_qec,sn,unc_sn,sp,unc_sp,binding,unc_ba,atomic_mass,unc_am,massexcess,unc_me,me_systematics,discovery,ENSDFpublicationcut-off,ENSDFauthors,Extraction_date"
schema:
 .ascii "CREATE TABLE IF NOT EXISTS nuclides ("
 .ascii "z INTEGER NOT NULL CHECK(z BETWEEN 0 AND 118),"
 .ascii "n INTEGER NOT NULL CHECK(n BETWEEN 0 AND 1000),"
 .ascii "a INTEGER NOT NULL CHECK(a=z+n AND a>0),"
 .ascii "symbol TEXT NOT NULL,"
 .ascii "half_life_seconds REAL CHECK(half_life_seconds>0 AND half_life_seconds<=1.7976931348623157e308),"
 .ascii "decay_constant REAL CHECK(decay_constant>=0 AND decay_constant<=1.7976931348623157e308),"
 .ascii "status TEXT NOT NULL CHECK(status IN ('measured','qualified','stable','unknown')),"
 .ascii "qualifier TEXT NOT NULL CHECK(qualifier IN ('','LT','GT','GE','AP')),"
 .ascii "half_life_raw TEXT NOT NULL,unit_raw TEXT NOT NULL,uncertainty_raw TEXT NOT NULL,"
 .ascii "source_line INTEGER NOT NULL,source_csv TEXT NOT NULL,PRIMARY KEY(z,n),"
 .ascii "CHECK((status='stable' AND half_life_seconds IS NULL AND decay_constant IS NOT NULL AND decay_constant=0 AND qualifier='') OR "
 .ascii "(status='unknown' AND half_life_seconds IS NULL AND decay_constant IS NULL) OR "
 .ascii "(status IN ('measured','qualified') AND half_life_seconds IS NOT NULL AND decay_constant IS NOT NULL AND decay_constant>0 AND "
 .ascii "((status='measured' AND qualifier='') OR (status='qualified' AND qualifier<>''))))) STRICT;"
 .asciz "CREATE INDEX IF NOT EXISTS nuclides_decay_idx ON nuclides(decay_constant) WHERE status IN ('measured','qualified');DELETE FROM nuclides;"
begin_sql: .asciz "BEGIN IMMEDIATE"
commit_sql: .asciz "COMMIT"
rollback_sql: .asciz "ROLLBACK"
insert_sql: .asciz "INSERT INTO nuclides VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
stable_word: .asciz "STABLE"
unknown_word: .asciz "?"
status_stable: .asciz "stable"
status_unknown: .asciz "unknown"
status_measured: .asciz "measured"
status_qualified: .asciz "qualified"
qualifiers: .asciz "LT"
 .asciz "GT"
 .asciz "GE"
 .asciz "AP"
units: .asciz "s"
 .asciz "ms"
 .asciz "us"
 .asciz "ns"
 .asciz "ps"
 .asciz "as"
 .asciz "m"
 .asciz "h"
 .asciz "d"
 .asciz "Y"
 .asciz "eV"
 .asciz "keV"
 .asciz "MeV"
/* Atomic-number-indexed, NUL-separated symbols. */
symbols: .asciz "n","H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca","Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu","Zn","Ga","Ge","As","Se","Br","Kr","Rb","Sr","Y","Zr","Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn","Sb","Te","I","Xe","Cs","Ba","La","Ce","Pr","Nd","Pm","Sm","Eu","Gd","Tb","Dy","Ho","Er","Tm","Yb","Lu","Hf","Ta","W","Re","Os","Ir","Pt","Au","Hg","Tl","Pb","Bi","Po","At","Rn","Fr","Ra","Ac","Th","Pa","U","Np","Pu","Am","Cm","Bk","Cf","Es","Fm","Md","No","Lr","Rf","Db","Sg","Bh","Hs","Mt","Ds","Rg","Cn","Nh","Fl","Mc","Lv","Ts","Og"
/* All ordinary numeric columns, zero based; special fields handled below. */
numeric_columns: .byte 3,4,5,6,8,9,10,17,19,20,22,23,25,26,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,51,255
uncertainty_columns: .byte 4,6,9,17,20,23,26,29,31,33,35,37,39,41,43,45,47,49,255
ln2: .double 0.693147180559945309417
maximum: .double 1.7976931348623157e308
msg_args: .asciz "invalid arguments; use --help"
msg_input: .asciz "cannot open/read/close input CSV"
msg_header: .asciz "unexpected CSV header (expected IAEA's 55 columns)"
msg_csv: .asciz "malformed CSV or wrong column count (expected 55)"
msg_value: .asciz "invalid numeric value, identity, qualifier, unit, or half-life combination"
msg_memory: .asciz "out of memory"
msg_empty: .asciz "CSV contains no nuclides"
msg_db: .asciz "SQLite operation failed"
error_fmt: .asciz "create_isotopes_db: line %ld: %s\n"
db_error_fmt: .asciz "SQLite: %s\n"
success_fmt: .asciz "Imported %ld nuclides into %s\n"
.section .bss
.align 8
csv_name: .zero 8
db_name: .zero 8
input: .zero 8
database: .zero 8
statement: .zero 8
transaction: .zero 8
line: .zero 8
capacity: .zero 8
length: .zero 8
line_number: .zero 8
record_count: .zero 8
raw_line: .zero 8
fields: .zero 440
end_number: .zero 8
z_value: .zero 8
n_value: .zero 8
half_value: .zero 8
k_value: .zero 8
status: .zero 8
result: .zero 8
.section .text
_start:
 movq %rsp,%r12
 andq $-16,%rsp
 movq %rsp,startup_stack(%rip)
 leaq csv_default(%rip),%rax
 movq %rax,csv_name(%rip)
 leaq db_default(%rip),%rax
 movq %rax,db_name(%rip)
 cmpq $1,(%r12)
 je .Lopen
 cmpq $3,(%r12)
 ja .Largs_error
 movq 16(%r12),%rdi
 leaq help_arg(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Largs_paths
 cmpq $2,(%r12)
 jne .Largs_error
 leaq usage(%rip),%rdi
 call puts@PLT
 jmp .Lcleanup
.Largs_paths:
 movq 16(%r12),%rax
 cmpb $0,(%rax)
 je .Largs_error
 cmpb $'-',(%rax)
 je .Largs_error
 movq %rax,csv_name(%rip)
 cmpq $3,(%r12)
 jne .Lopen
 movq 24(%r12),%rax
 cmpb $0,(%rax)
 je .Largs_error
 movq %rax,db_name(%rip)
.Lopen:
 movq csv_name(%rip),%rdi
 leaq read_mode(%rip),%rsi
 call fopen@PLT
 testq %rax,%rax
 je .Linput_error
 movq %rax,input(%rip)
 call get_line
 testq %rax,%rax
 js .Lheader_error
 movq line(%rip),%rdi
 leaq header_expected(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lheader_error
 movq db_name(%rip),%rdi
 leaq database(%rip),%rsi
 call sqlite3_open@PLT
 testl %eax,%eax
 jne .Ldb_error
 movq database(%rip),%rdi
 movl $5000,%esi
 call sqlite3_busy_timeout@PLT
 testl %eax,%eax
 jne .Ldb_error
 leaq begin_sql(%rip),%rdi
 call exec_sql
 movq $1,transaction(%rip)
 leaq schema(%rip),%rdi
 call exec_sql
 movq database(%rip),%rdi
 leaq insert_sql(%rip),%rsi
 movl $-1,%edx
 leaq statement(%rip),%rcx
 xorl %r8d,%r8d
 call sqlite3_prepare_v2@PLT
 testl %eax,%eax
 jne .Ldb_error
.Lrow:
 call get_line
 testq %rax,%rax
 js .Lend
 cmpq $0,length(%rip)
 je .Lrow
 movq line(%rip),%rdi
 call strdup@PLT
 testq %rax,%rax
 je .Lmemory_error
 movq %rax,raw_line(%rip)
 call parse_csv
 testl %eax,%eax
 jne .Lcsv_error
 call validate_row
 call insert_row
 incq record_count(%rip)
 movq raw_line(%rip),%rdi
 call free@PLT
 movq $0,raw_line(%rip)
 jmp .Lrow
.Lend:
 movq input(%rip),%rdi
 call feof@PLT
 testl %eax,%eax
 je .Linput_error
 movq input(%rip),%rdi
 call ferror@PLT
 testl %eax,%eax
 jne .Linput_error
 movq input(%rip),%rdi
 call fclose@PLT
 movq $0,input(%rip)
 testl %eax,%eax
 jne .Linput_error
 cmpq $0,record_count(%rip)
 je .Lempty_error
 movq statement(%rip),%rdi
 call sqlite3_finalize@PLT
 movq $0,statement(%rip)
 testl %eax,%eax
 jne .Ldb_error
 leaq commit_sql(%rip),%rdi
 call exec_sql
 movq $0,transaction(%rip)
 leaq success_fmt(%rip),%rdi
 movq record_count(%rip),%rsi
 movq db_name(%rip),%rdx
 xorl %eax,%eax
 call printf@PLT
 jmp .Lcleanup

/* Strip line ending, reject embedded NUL, retain all other bytes. */
get_line:
 pushq %rbp
 movq %rsp,%rbp
 leaq line(%rip),%rdi
 leaq capacity(%rip),%rsi
 movq input(%rip),%rdx
 call getline@PLT
 testq %rax,%rax
 js .Lgetline_done
 incq line_number(%rip)
 movq %rax,length(%rip)
 movq line(%rip),%rdi
 call strlen@PLT
 cmpq length(%rip),%rax
 jne .Lcsv_error
 movq line(%rip),%rdx
 testq %rax,%rax
 jz .Ltrimmed
 cmpb $10,-1(%rdx,%rax)
 jne .Ltrimmed
 decq %rax
 testq %rax,%rax
 jz .Ltrimmed
 cmpb $13,-1(%rdx,%rax)
 jne .Ltrimmed
 decq %rax
.Ltrimmed:
 movb $0,(%rdx,%rax)
 movq %rax,length(%rip)
.Lgetline_done:
 leave
 ret

/* In-place CSV tokenizer: preserves empty fields, supports quoted fields and
 * doubled quotes. Multiline quoted fields are rejected explicitly.
 * No libc calls. Return 0 only for exactly 55 fields. */
parse_csv:
 movq line(%rip),%rsi
 movq %rsi,%rdi
 leaq fields(%rip),%r8
 xorl %ecx,%ecx
.Lfield:
 cmpl $55,%ecx
 jae .Lparse_bad
 movq %rdi,(%r8,%rcx,8)
 incl %ecx
 cmpb $34,(%rsi)
 je .Lquoted
.Lunquoted:
 movb (%rsi),%al
 testb %al,%al
 je .Llast_field
 cmpb $44,%al
 je .Lcomma
 cmpb $34,%al
 je .Lparse_bad
 cmpb $13,%al
 je .Lparse_bad
 movb %al,(%rdi)
 incq %rsi
 incq %rdi
 jmp .Lunquoted
.Lquoted:
 incq %rsi
.Lquoted_char:
 movb (%rsi),%al
 testb %al,%al
 je .Lparse_bad
 incq %rsi
 cmpb $34,%al
 jne .Lquoted_copy
 cmpb $34,(%rsi)
 jne .Lquote_end
 incq %rsi
.Lquoted_copy:
 movb %al,(%rdi)
 incq %rdi
 jmp .Lquoted_char
.Lquote_end:
 movb (%rsi),%al
 testb %al,%al
 je .Llast_field
 cmpb $44,%al
 jne .Lparse_bad
.Lcomma:
 incq %rsi
 movb $0,(%rdi)
 incq %rdi
 jmp .Lfield
.Llast_field:
 movb $0,(%rdi)
 cmpl $55,%ecx
 jne .Lparse_bad
 xorl %eax,%eax
 ret
.Lparse_bad:
 movl $1,%eax
 ret

/* Strict decimal grammar followed by strtod with full-consumption, errno,
 * and finite checks. Accepts scientific notation and decimal fractions.
 * rdi=input, xmm0=output; all invalid paths abort the transaction. */
number:
 pushq %rbp
 movq %rsp,%rbp
 pushq %r12
 subq $8,%rsp
 movq %rdi,%r12
 movq %rdi,%rcx
 cmpb $'+',(%rcx)
 je .Lsign
 cmpb $'-',(%rcx)
 jne .Ldigits_start
.Lsign: incq %rcx
.Ldigits_start:
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
 jz .Lvalue_error
 cmpb $'e',(%rcx)
 je .Lexp_sign
 cmpb $'E',(%rcx)
 jne .Lnumber_end
.Lexp_sign:
 incq %rcx
 cmpb $'+',(%rcx)
 je .Lexp_skip
 cmpb $'-',(%rcx)
 jne .Lexp_digits_start
.Lexp_skip: incq %rcx
.Lexp_digits_start:
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
 jz .Lvalue_error
.Lnumber_end:
 cmpb $0,(%rcx)
 jne .Lvalue_error
 call __errno_location@PLT
 movl $0,(%rax)
 movq %r12,%rdi
 leaq end_number(%rip),%rsi
 call strtod@PLT
 movsd %xmm0,(%rsp)
 call __errno_location@PLT
 cmpl $0,(%rax)
 jne .Lvalue_error
 movsd (%rsp),%xmm0
 ucomisd %xmm0,%xmm0
 jp .Lvalue_error
 movapd %xmm0,%xmm1
 /* Infinity check via absolute value bit mask in a general register. */
 movq %xmm0,%rax
 btrq $63,%rax
 movq %rax,%xmm1
 ucomisd maximum(%rip),%xmm1
 ja .Lvalue_error
 addq $8,%rsp
 popq %r12
 leave
 ret

/* rdi=unsigned decimal integer, maximum 1000 (identity limits below). */
integer:
 xorl %eax,%eax
 cmpb $0,(%rdi)
 je .Lvalue_error
.Linteger_loop:
 movzbl (%rdi),%edx
 testl %edx,%edx
 jz .Linteger_done
 subl $48,%edx
 cmpl $9,%edx
 ja .Lvalue_error
 imulq $10,%rax
 addq %rdx,%rax
 cmpq $1000,%rax
 ja .Lvalue_error
 incq %rdi
 jmp .Linteger_loop
.Linteger_done: ret

validate_row:
 pushq %rbp
 movq %rsp,%rbp
 pushq %r12
 pushq %r13
 leaq fields(%rip),%r13
 movq (%r13),%rdi
 call integer
 cmpq $118,%rax
 ja .Lvalue_error
 movq %rax,z_value(%rip)
 movq 8(%r13),%rdi
 call integer
 movq %rax,n_value(%rip)
 addq z_value(%rip),%rax
 jz .Lvalue_error
 leaq symbols(%rip),%rsi
 movq z_value(%rip),%rcx
.Lsymbol_seek:
 testq %rcx,%rcx
 jz .Lsymbol_compare
.Lsymbol_next:
 cmpb $0,(%rsi)
 leaq 1(%rsi),%rsi
 jne .Lsymbol_next
 decq %rcx
 jmp .Lsymbol_seek
.Lsymbol_compare:
 movq 16(%r13),%rdi
 call strcmp@PLT
 testl %eax,%eax
 jne .Lvalue_error
 xorl %r12d,%r12d
.Lnumeric_loop:
 leaq numeric_columns(%rip),%rax
 movzbl (%rax,%r12),%ecx
 cmpl $255,%ecx
 je .Lqualifier
 movq (%r13,%rcx,8),%rdi
 cmpb $0,(%rdi)
 je .Lnumeric_next
 call number
 /* Percentages must be 0..100; uncertainties must be nonnegative. */
 leaq numeric_columns(%rip),%rax
 movzbl (%rax,%r12),%ecx
 cmpl $5,%ecx
 je .Lpercentage
 cmpl $19,%ecx
 je .Lpercentage
 cmpl $22,%ecx
 je .Lpercentage
 cmpl $25,%ecx
 je .Lpercentage
 leaq uncertainty_columns(%rip),%rdx
.Lunc_index:
 movzbl (%rdx),%eax
 cmpl $255,%eax
 je .Lnumeric_next
 cmpl %eax,%ecx
 je .Lnonnegative
 incq %rdx
 jmp .Lunc_index
.Lpercentage:
 movl $100,%eax
 cvtsi2sd %eax,%xmm1
 ucomisd %xmm1,%xmm0
 ja .Lvalue_error
.Lnonnegative:
 pxor %xmm1,%xmm1
 ucomisd %xmm1,%xmm0
 jb .Lvalue_error
.Lnumeric_next:
 incq %r12
 jmp .Lnumeric_loop
.Lqualifier:
 /* Uncertainty is either empty, digits, or asymmetric +digits-digits. */
 movq 112(%r13),%rdi
 cmpb $0,(%rdi)
 je .Lcheck_qualifier
 cmpb $'+',(%rdi)
 je .Lasymmetric
 call digit_string
 cmpb $0,(%rdi)
 jne .Lvalue_error
 jmp .Lcheck_qualifier
.Lasymmetric:
 incq %rdi
 call digit_string
 cmpb $'-',(%rdi)
 jne .Lvalue_error
 incq %rdi
 call digit_string
 cmpb $0,(%rdi)
 jne .Lvalue_error
.Lcheck_qualifier:
 movq 104(%r13),%rdi
 cmpb $0,(%rdi)
 je .Lhalf
 leaq qualifiers(%rip),%rsi
 movl $4,%edx
 call member
 testl %eax,%eax
 jne .Lvalue_error
.Lhalf:
 leaq status_unknown(%rip),%rax
 movq %rax,status(%rip)
 movq $0,half_value(%rip)
 movq $0,k_value(%rip)
 movq 96(%r13),%rdi
 leaq stable_word(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 je .Lstable
 movq 96(%r13),%rdi
 cmpb $0,(%rdi)
 je .Lunknown
 leaq unknown_word(%rip),%rsi
 call strcmp@PLT
 testl %eax,%eax
 je .Lunknown
 movq 96(%r13),%rdi
 call number
 pxor %xmm1,%xmm1
 ucomisd %xmm1,%xmm0
 jbe .Lvalue_error
 movq 120(%r13),%rdi
 leaq units(%rip),%rsi
 movl $13,%edx
 call member
 testl %eax,%eax
 jne .Lvalue_error
 movq 128(%r13),%rdi
 call number
 pxor %xmm1,%xmm1
 ucomisd %xmm1,%xmm0
 jbe .Lvalue_error
 movsd %xmm0,half_value(%rip)
 movsd ln2(%rip),%xmm1
 divsd %xmm0,%xmm1
 pxor %xmm0,%xmm0
 ucomisd %xmm0,%xmm1
 jbe .Lvalue_error
 ucomisd maximum(%rip),%xmm1
 ja .Lvalue_error
 movsd %xmm1,k_value(%rip)
 leaq status_measured(%rip),%rax
 movq 104(%r13),%rdx
 cmpb $0,(%rdx)
 je .Lset_status
 leaq status_qualified(%rip),%rax
.Lset_status:
 movq %rax,status(%rip)
 jmp .Lvalidated
.Lstable:
 leaq status_stable(%rip),%rax
 movq %rax,status(%rip)
 movq 104(%r13),%rax
 cmpb $0,(%rax)
 jne .Lvalue_error
.Lunknown:
 movq 128(%r13),%rax
 cmpb $0,(%rax)
 jne .Lvalue_error
.Lvalidated:
 popq %r13
 popq %r12
 leave
 ret

/* Consume one or more decimal digits, stopping at the first nondigit. */
digit_string:
 movb (%rdi),%al
 subb $'0',%al
 cmpb $9,%al
 ja .Lvalue_error
.Ldigit_string_loop:
 incq %rdi
 movb (%rdi),%al
 subb $'0',%al
 cmpb $9,%al
 jbe .Ldigit_string_loop
 ret

/* String membership in edx consecutive NUL-terminated entries at rsi. */
member:
 pushq %rbp
 movq %rsp,%rbp
 pushq %r12
 pushq %r13
 pushq %r14
 subq $8,%rsp
 movq %rdi,%r12
 movq %rsi,%r13
 movl %edx,%r14d
.Lmember_loop:
 movq %r12,%rdi
 movq %r13,%rsi
 call strcmp@PLT
 testl %eax,%eax
 je .Lmember_done
.Lmember_next:
 cmpb $0,(%r13)
 leaq 1(%r13),%r13
 jne .Lmember_next
 decl %r14d
 jnz .Lmember_loop
 movl $1,%eax
.Lmember_done:
 addq $8,%rsp
 popq %r14
 popq %r13
 popq %r12
 leave
 ret

/* Binding helpers: esi=index, rdx=value or xmm0=double. */
bind_int:
 pushq %rbp
 movq %rsp,%rbp
 movq statement(%rip),%rdi
 call sqlite3_bind_int64@PLT
 testl %eax,%eax
 jne .Ldb_error
 leave
 ret
bind_text:
 pushq %rbp
 movq %rsp,%rbp
 movq statement(%rip),%rdi
 movl $-1,%ecx
 movq $-1,%r8                   /* SQLITE_TRANSIENT: SQLite copies text. */
 call sqlite3_bind_text@PLT
 testl %eax,%eax
 jne .Ldb_error
 leave
 ret
bind_double:
 pushq %rbp
 movq %rsp,%rbp
 movq statement(%rip),%rdi
 call sqlite3_bind_double@PLT
 testl %eax,%eax
 jne .Ldb_error
 leave
 ret
insert_row:
 pushq %rbp
 movq %rsp,%rbp
 movl $1,%esi
 movq z_value(%rip),%rdx
 call bind_int
 movl $2,%esi
 movq n_value(%rip),%rdx
 call bind_int
 movl $3,%esi
 movq z_value(%rip),%rdx
 addq n_value(%rip),%rdx
 call bind_int
 movl $4,%esi
 movq fields+16(%rip),%rdx
 call bind_text
 movq status(%rip),%rax
 leaq status_unknown(%rip),%rdx
 cmpq %rdx,%rax
 je .Lbind_status
 leaq status_stable(%rip),%rdx
 cmpq %rdx,%rax
 je .Lbind_stable
 movl $5,%esi
 movsd half_value(%rip),%xmm0
 call bind_double
.Lbind_stable:
 movl $6,%esi
 movsd k_value(%rip),%xmm0
 call bind_double
.Lbind_status:
 movl $7,%esi
 movq status(%rip),%rdx
 call bind_text
 movl $8,%esi
 movq fields+104(%rip),%rdx
 call bind_text
 movl $9,%esi
 movq fields+96(%rip),%rdx
 call bind_text
 movl $10,%esi
 movq fields+120(%rip),%rdx
 call bind_text
 movl $11,%esi
 movq fields+112(%rip),%rdx
 call bind_text
 movl $12,%esi
 movq line_number(%rip),%rdx
 call bind_int
 movl $13,%esi
 movq raw_line(%rip),%rdx
 call bind_text
 movq statement(%rip),%rdi
 call sqlite3_step@PLT
 cmpl $101,%eax                  /* SQLITE_DONE */
 jne .Ldb_error
 movq statement(%rip),%rdi
 call sqlite3_reset@PLT
 testl %eax,%eax
 jne .Ldb_error
 movq statement(%rip),%rdi
 call sqlite3_clear_bindings@PLT /* Unbound values remain SQL NULL. */
 testl %eax,%eax
 jne .Ldb_error
 leave
 ret

exec_sql:
 pushq %rbp
 movq %rsp,%rbp
 movq %rdi,%rsi
 movq database(%rip),%rdi
 xorl %edx,%edx
 xorl %ecx,%ecx
 xorl %r8d,%r8d
 call sqlite3_exec@PLT
 testl %eax,%eax
 jne .Ldb_error
 leave
 ret

/* Error paths may originate at any call depth: restore the startup stack. */
.Largs_error: leaq msg_args(%rip),%rdx; jmp .Lerror
.Linput_error: leaq msg_input(%rip),%rdx; jmp .Lerror
.Lheader_error: leaq msg_header(%rip),%rdx; jmp .Lerror
.Lcsv_error: leaq msg_csv(%rip),%rdx; jmp .Lerror
.Lvalue_error: leaq msg_value(%rip),%rdx; jmp .Lerror
.Lmemory_error: leaq msg_memory(%rip),%rdx; jmp .Lerror
.Lempty_error: leaq msg_empty(%rip),%rdx; jmp .Lerror
.Ldb_error:
 movq startup_stack(%rip),%rsp
 movq database(%rip),%rdi
 call sqlite3_errmsg@PLT
 movq %rax,%rdx
 movq stderr(%rip),%rdi
 leaq db_error_fmt(%rip),%rsi
 xorl %eax,%eax
 call fprintf@PLT
 leaq msg_db(%rip),%rdx
.Lerror:
 movq startup_stack(%rip),%rsp
 movq %rdx,%rcx
 movq line_number(%rip),%rdx
 leaq error_fmt(%rip),%rsi
 movq stderr(%rip),%rdi
 xorl %eax,%eax
 call fprintf@PLT
 movq $1,result(%rip)
.Lcleanup:
 movq statement(%rip),%rdi
 testq %rdi,%rdi
 je .Lrollback
 call sqlite3_finalize@PLT
.Lrollback:
 cmpq $0,transaction(%rip)
 je .Lclose_db
 movq database(%rip),%rdi
 leaq rollback_sql(%rip),%rsi
 xorl %edx,%edx
 xorl %ecx,%ecx
 xorl %r8d,%r8d
 call sqlite3_exec@PLT
.Lclose_db:
 movq database(%rip),%rdi
 testq %rdi,%rdi
 je .Lclose_input
 call sqlite3_close@PLT
.Lclose_input:
 movq input(%rip),%rdi
 testq %rdi,%rdi
 je .Lfree
 call fclose@PLT
.Lfree:
 movq line(%rip),%rdi
 call free@PLT
 movq raw_line(%rip),%rdi
 call free@PLT
 movl result(%rip),%edi
 call exit@PLT
.section .bss
.align 8
startup_stack: .zero 8
.section .note.GNU-stack,"",@progbits
