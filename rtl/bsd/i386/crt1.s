	.file	"crt1.c"
	.version	"01.01"
gcc2_compiled.:
.globl __progname
.section	.rodata
.LC0:
	.ascii "\0"
.data
	.p2align 2
	.type	 __progname,@object
	.size	 __progname,4
__progname:
	.long .LC0
        .align  4
___fpucw:
        .long   0x1332

        .globl  ___fpc_brk_addr         /* heap management */
        .type   ___fpc_brk_addr,@object
        .size   ___fpc_brk_addr,4
___fpc_brk_addr:
        .long   0


.text
	.p2align 2
.globl _start
	.type	 _start,@function
_start:
	pushl %ebp
	movl %esp,%ebp
	pushl %edi
	pushl %esi
	pushl %ebx
#APP
	movl %edx,%edx
#NO_APP
        leal 8(%ebp),%edi
        movl %edi,U_SYSLINUX_ARGV
        mov -4(%edi),%eax
        movl %eax,U_SYSLINUX_ARGC
	movl 4(%ebp),%ebx
        leal 12(%ebp,%ebx,4),%esi
        movl %esi,U_SYSLINUX_ENVP
	movl %esi,environ
	testl %ebx,%ebx
	jle .L2
	movl 8(%ebp),%eax
	testl %eax,%eax
	je .L2
	movl %eax,__progname
	cmpb $0,(%eax)
	je .L2
	.p2align 2,0x90
.L6:
	cmpb $47,(%eax)
	jne .L5
	leal 1(%eax),%ecx
	movl %ecx,__progname
.L5:
	incl %eax
	cmpb $0,(%eax)
	jne .L6
.L2:
#movl $_DYNAMIC,%eax
#testl %eax,%eax
#je .L9
#pushl %edx
#call atexit
#addl $4,%esp
.L9:
#pushl $_fini
#call atexit
#call _init
#pushl %esi
#pushl %edi
#pushl %ebx

# copied from linux

        finit                           /* initialize fpu */
        fwait
        fldcw   ___fpucw

        xorl    %ebp,%ebp

	call main
	pushl %eax
	jmp   _haltproc




.globl _haltproc 
.type _haltproc,@function

_haltproc:
           mov $1,%eax	
           movzwl U_SYSLINUX_EXITCODE,%ebx
	   pushl %ebx
           call _actualsyscall
           addl  $4,%esp
           jmp   _haltproc

.globl _actualsyscall 
.type _actualsyscall,@function

_actualsyscall:
         int $0x80
         ret
	.p2align 2,0x90
.Lfe1:
	.size	 _start,.Lfe1-_start
	.comm	environ,4,4
	.weak	_DYNAMIC
	.ident	"GCC: (GNU) 2.7.2.1"
