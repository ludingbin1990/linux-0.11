#define SYS_ERROR0 10420224 /* 0x9f0000	@ */
#define SVC_MODE	0x00000013
#define S_FRAME_SIZE 72
#define PSR_ISETSTATE	0
#define S_PSR 64
#define S_PC 60
#define S_OLD_R0 68
#define STATE_OFFSET 0
#define COUNT_OFFSET 4
.arm
.text

.macro	usr_entry

	sub	sp, sp, #S_FRAME_SIZE
	stmib	sp, {r1 - r12}
	ldmia	r0, {r3 - r5}
	add	r0, sp, #S_PC		@ here for interlock avoidance
	mov	r6, #-1			@  ""  ""     ""        ""
	str	r3, [sp]		@ save the "real" r0 copied
					@ from the exception stack
	stmia	r0, {r4 - r6}
	stmdb	r0, {sp, lr}^
.endm


.macro	get_thread_info, rd
	mov	\rd, sp, lsr #12  @task struct and the kernel stack is in the same 4K page
	mov	\rd, \rd, lsl #12
.endm


.macro	restore_user_regs, fast = 0, offset = 0
	ldr	r1, [sp, #\offset + S_PSR]	@ get calling cpsr
	ldr	lr, [sp, #\offset + S_PC]!	@ get pc
	msr	spsr_cxsf, r1			@ save in spsr_svc
	.if	\fast
	ldmdb	sp, {r1 - lr}^			@ get calling r1 - lr
	.else
	ldmdb	sp, {r0 - lr}^			@ get calling r0 - lr
	.endif
	mov	r0, r0				@ ARMv5T and earlier require a nop
						@ after ldm {}^
	add	sp, sp, #S_FRAME_SIZE - S_PC
	movs	pc, lr				@ return & move spsr_svc into cpsr
.endm

	.align	5
__irq_usr:
	usr_entry
	ldr    r1, =handle_arch_irq 
    	mov  r0, sp
    	adr    lr, __irq_usr_1
    	ldr    pc, [r1]
__irq_usr_1:
	get_thread_info r9  @task struct is r9
	mov	r8, #0
	b	ret_to_user_from_irq


ret_to_user_from_irq:
	restore_user_regs fast = 0, offset = 0


.macro	svc_exit, rpsr, irq = 0
	.if	\irq != 0
	@ IRQs already off

	.else
	@ IRQs off again before pulling preserved data off the stack
	disable_irq_notrace

	.endif
@	msr	spsr_cxsf, \rpsr  
	ldr    spsr_cxsf, [sp, #S_PSR]          @avoid the r5 been destroy,reread the old cpsr from the stack
	ldmia	sp, {r0 - pc}^			@ load r0 - pc, cpsr
.endm


.macro	svc_entry, stack_hole=0
	sub	sp, sp, #(S_FRAME_SIZE + \stack_hole - 4)
	stmia	sp, {r1 - r12}

	ldmia	r0, {r3 - r5}
	add	r7, sp, #S_SP - 4	@ here for interlock avoidance
	mov	r6, #-1			@  ""  ""      ""       ""
	add	r2, sp, #(S_FRAME_SIZE + \stack_hole - 4)
	str	r3, [sp, #-4]!		@ save the "real" r0 copied
					@ from the exception stack
	mov	r3, lr
	@
	@ We are now ready to fill in the remaining blanks on the stack:
	@
	@  r2 - sp_svc
	@  r3 - lr_svc
	@  r4 - lr_<exception>, already fixed up for correct return/restart
	@  r5 - spsr_<exception>
	@  r6 - orig_r0 (see pt_regs definition in ptrace.h)
	@
	stmia	r7, {r2 - r6}
.endm


	.align	5
__irq_svc:
	svc_entry
	ldr    r1, =handle_arch_irq 
    	mov  r0, sp
    	adr    lr, __irq_svc_1
    	ldr    pc, [r1]
__irq_svc_1:
	svc_exit r5, irq = 1			@ return from exception







.macro	vector_stub, name, mode, correction=0
	.align	5

vector_\name:
	.if \correction
	sub	lr, lr, #\correction
	.endif

	@
	@ Save r0, lr_<exception> (parent PC) and spsr_<exception>
	@ (parent CPSR)
	@
	stmia	sp, {r0, lr}		@ save r0, lr
	mrs	lr, spsr
	str	lr, [sp, #8]		@ save spsr

	@
	@ Prepare for SVC32 mode.  IRQs remain disabled.
	@
	mrs	r0, cpsr
	eor	r0, r0, #(\mode ^ SVC_MODE | PSR_ISETSTATE)
	msr	spsr_cxsf, r0

	@
	@ the branch table must immediately follow this code
	@
	and	lr, lr, #0x0f
	mov	r0, sp
	ldr	lr, [pc, lr, lsl #2]
	movs	pc, lr			@ branch to handler in SVC mode
ENDPROC(vector_\name)

	.align	2
	@ handler addresses follow this label
1:
	.endm


	.align	5

vector_swi:
	sub	sp, sp, #S_FRAME_SIZE
	stmia	sp, {r0 - r12}			@ Calling r0 - r12
	add	r8, sp, #S_PC             
	stmdb	r8, {sp, lr}^               	@ Calling sp, lr
	mrs	r8, spsr			@ called from non-FIQ mode, so ok.
	str	lr, [sp, #S_PC]			@ Save calling PC
	str	r8, [sp, #S_PSR]		@ Save CPSR
	str	r0, [sp, #S_OLD_R0]		@ Save OLD_R0
       
	/* save the all context before
	 * Get the system call number.
	 */


	/*
	 * If we have CONFIG_OABI_COMPAT then we need to look at the swi
	 * value to determine if it is an EABI or an old ABI call.
	 */

	ldr	r10, [lr, #-4]			@ get SWI instruction,system call number is in the SWI instruction,0xff******,**is the call number

	msr     CPSR_c, #19    @enable_irq  0x13

	get_thread_info r9  @task struct is r9
	
	/*
	 * If the swi argument is zero, this is an EABI call and we do nothing.
	 *
	 * If this is an old ABI call, get the syscall number into scno and
	 * get the old ABI syscall table address.
	 */
	bic	r10, r10, #0xff000000     @get the system call number
	mov	r7, r10
	adr	r8, sys_call_table		@ load syscall table pointer

	stmdb	sp!, {r4, r5}			@ push fifth and sixth args
	adr	lr, ret_from_syscall1	@ return address
	cmp	r7, #72		@ check upper syscall limit,asume the max system call number is 72
	ldrcc	pc, [r8, r7, lsl #2]		@ call sys_* routine	
	b	bad_sys_call			@ system call number invalid


/*
 * This is the fast syscall return path.  We do as little as
 * possible here, and this includes saving r0 back into the SVC
 * stack.
 */
reschedule:
	adr  lr,ret_from_syscall2
	b schedule

ret_from_syscall1:
	                                        @ msr     CPSR_c, #147    @ 0x93			@ disable interrupts
	cmp	[r9, #STATE_OFFSET],#0         @the task not in running state,need reschedule
	bne     reschedule
	cmp	[r9, #COUNT_OFFSET],#0         @the task run too long time,need reschedule
	beq      reschedule

ret_from_syscall2:
	
	ldr r1,=current   @get the current address
	ldr r2,=task     @get the task0 address
	cmp [r1],r2      @compare if the current value equal to the task0 address,if current task not task0,ignore the signal
	beq ret_form_syscall3




ret_form_syscall3:

	ldr r1,[sp,#72]    @get the saved cpsr
	ldr lr,[sp,#68]!    @get the saved return address,and update the sp to the S_PC
	msr	spsr_cxsf, r1
	ldmdb	sp, {r1 - lr}^
	mov	r0, r0
	add	sp, sp, #S_FRAME_SIZE - S_PC   @reset the kernel stack equal to the enter kernel
	movs	pc, lr
	

	.globl	__stubs_start
__stubs_start:


 /*
 *Interrupt dispatcher
 */
	vector_stub	irq, IRQ_MODE, 4

	.long	__irq_usr			@  0  (USR_26 / USR_32)
	.long	__irq_invalid			@  1  (FIQ_26 / FIQ_32)
	.long	__irq_invalid			@  2  (IRQ_26 / IRQ_32)
	.long	__irq_svc			@  3  (SVC_26 / SVC_32)
	.long	__irq_invalid			@  4
	.long	__irq_invalid			@  5
	.long	__irq_invalid			@  6
	.long	__irq_invalid			@  7
	.long	__irq_invalid			@  8
	.long	__irq_invalid			@  9
	.long	__irq_invalid			@  a
	.long	__irq_invalid			@  b
	.long	__irq_invalid			@  c
	.long	__irq_invalid			@  d
	.long	__irq_invalid			@  e
	.long	__irq_invalid			@  f

/*
 * Data abort dispatcher
 * Enter in ABT mode, spsr = USR CPSR, lr = USR PC
 */
	vector_stub	dabt, ABT_MODE, 8

	.long	__dabt_usr			@  0  (USR_26 / USR_32)
	.long	__dabt_invalid			@  1  (FIQ_26 / FIQ_32)
	.long	__dabt_invalid			@  2  (IRQ_26 / IRQ_32)
	.long	__dabt_svc			@  3  (SVC_26 / SVC_32)
	.long	__dabt_invalid			@  4
	.long	__dabt_invalid			@  5
	.long	__dabt_invalid			@  6
	.long	__dabt_invalid			@  7
	.long	__dabt_invalid			@  8
	.long	__dabt_invalid			@  9
	.long	__dabt_invalid			@  a
	.long	__dabt_invalid			@  b
	.long	__dabt_invalid			@  c
	.long	__dabt_invalid			@  d
	.long	__dabt_invalid			@  e
	.long	__dabt_invalid			@  f

/*
 * Prefetch abort dispatcher
 * Enter in ABT mode, spsr = USR CPSR, lr = USR PC
 */
	vector_stub	pabt, ABT_MODE, 4

	.long	__pabt_usr			@  0 (USR_26 / USR_32)
	.long	__pabt_invalid			@  1 (FIQ_26 / FIQ_32)
	.long	__pabt_invalid			@  2 (IRQ_26 / IRQ_32)
	.long	__pabt_svc			@  3 (SVC_26 / SVC_32)
	.long	__pabt_invalid			@  4
	.long	__pabt_invalid			@  5
	.long	__pabt_invalid			@  6
	.long	__pabt_invalid			@  7
	.long	__pabt_invalid			@  8
	.long	__pabt_invalid			@  9
	.long	__pabt_invalid			@  a
	.long	__pabt_invalid			@  b
	.long	__pabt_invalid			@  c
	.long	__pabt_invalid			@  d
	.long	__pabt_invalid			@  e
	.long	__pabt_invalid			@  f

/*
 * Undef instr entry dispatcher
 * Enter in UND mode, spsr = SVC/USR CPSR, lr = SVC/USR PC
 */
	vector_stub	und, UND_MODE

	.long	__und_usr			@  0 (USR_26 / USR_32)
	.long	__und_invalid			@  1 (FIQ_26 / FIQ_32)
	.long	__und_invalid			@  2 (IRQ_26 / IRQ_32)
	.long	__und_svc			@  3 (SVC_26 / SVC_32)
	.long	__und_invalid			@  4
	.long	__und_invalid			@  5
	.long	__und_invalid			@  6
	.long	__und_invalid			@  7
	.long	__und_invalid			@  8
	.long	__und_invalid			@  9
	.long	__und_invalid			@  a
	.long	__und_invalid			@  b
	.long	__und_invalid			@  c
	.long	__und_invalid			@  d
	.long	__und_invalid			@  e
	.long	__und_invalid			@  f

	.align	5

/*=============================================================================
 * Undefined FIQs
 *-----------------------------------------------------------------------------
 * Enter in FIQ mode, spsr = ANY CPSR, lr = ANY PC
 * MUST PRESERVE SVC SPSR, but need to switch to SVC mode to show our msg.
 * Basically to switch modes, we *HAVE* to clobber one register...  brain
 * damage alert!  I don't think that we can execute any code in here in any
 * other mode than FIQ...  Ok you can switch to another mode, but you can't
 * get out of that mode without clobbering one register.
 */
vector_fiq:
	subs	pc, lr, #4

/*=============================================================================
 * Address exception handler
 *-----------------------------------------------------------------------------
 * These aren't too critical.
 * (they're not supposed to happen, and won't happen in 32-bit data mode).
 */

vector_addrexcptn:
	b	vector_addrexcptn

/*
 * We group all the following data together to optimise
 * for CPUs with separate I & D caches.
 */
/*
 * We group all the following data together to optimise
 * for CPUs with separate I & D caches.
 */
	.align	5

.LCvswi:
	.word	vector_swi

	.globl	__stubs_end
__stubs_end:

	.equ	stubs_offset, __vectors_start + 0x200 - __stubs_start

	.globl	__vectors_start
__vectors_start:
	swi	SYS_ERROR0
	W(b)	vector_und + stubs_offset
	W(ldr)	pc, .LCvswi + stubs_offset
	W(b)	vector_pabt + stubs_offset
	W(b)	vector_dabt + stubs_offset
	W(b)	vector_addrexcptn + stubs_offset
	W(b)	vector_irq + stubs_offset
	W(b)	vector_fiq + stubs_offset

	.globl	__vectors_end
__vectors_end:

	.data
