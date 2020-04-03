#ifdef S3C2440
//copy the current register value and make the returned stack,so that when we
//returned to the user space use the ret_from_fork and we can restore the register
//can still run in the main function for the remianed code
#define move_to_user_mode() \
		init0_regs= current_pt_regs(); \
		memset(init0_regs->uregs, 0, sizeof(init0_regs->uregs));			\
		init0_regs->ARM_cpsr = USR_MODE;				\
		init0_regs->ARM_sp = ((void *)((&stack_start)+1))-8;					\
		init0_sp=(unsigned int) init0_regs;\
		init0_pc=(unsigned int)ret_from_fork & ~1;	\
	__asm__ volatile (  "ldr %0  r0\n\t" \
					"ldr %1  r1\n\t" \
					"ldr %2  r2\n\t" \
					"ldr %3  r3\n\t" \
					"ldr %4  r4\n\t" \
					"ldr %5  r5\n\t" \
					"ldr %6  r6\n\t" \
					"ldr %7  r7\n\t" \
					"ldr %8  r8\n\t" \
					"ldr %9  r9\n\t" \
					"ldr %10  r10\n\t" \
					"ldr %11  r11\n\t" \
					"ldr %12  r12\n\t" \
					"ldr sp  %14\n\t" \
					"ldr %13  pc\n\t" \
					"ldr pc  %15\n\t" \
	: "m"(init0_regs->uregs[0]), "m"(init0_regs->uregs[1]),"m"(init0_regs->uregs[2]), \
	"m"(init0_regs->uregs[3]),"m"(init0_regs->uregs[4]),"m"(init0_regs->uregs[5]), \
	"m"(init0_regs->uregs[6]),"m"(init0_regs->uregs[7]),"m"(init0_regs->uregs[8]), \
	"m"(init0_regs->uregs[9]),"m"(init0_regs->uregs[10]),"m"(init0_regs->uregs[11]), \
	"m"(init0_regs->uregs[12],"m"(init0_regs->uregs[14])\
	:"m"(init0_sp),"m"(init0_pc) \
	: "memory" ); 
#else
#define move_to_user_mode() \
__asm__ ("movl %%esp,%%eax\n\t" \
	"pushl $0x17\n\t" \
	"pushl %%eax\n\t" \
	"pushfl\n\t" \
	"pushl $0x0f\n\t" \
	"pushl $1f\n\t" \
	"iret\n" \
	"1:\tmovl $0x17,%%eax\n\t" \
	"movw %%ax,%%ds\n\t" \
	"movw %%ax,%%es\n\t" \
	"movw %%ax,%%fs\n\t" \
	"movw %%ax,%%gs" \
	:::"ax")

#define sti() __asm__ ("sti"::)
#define cli() __asm__ ("cli"::)
#define nop() __asm__ ("nop"::)

#define iret() __asm__ ("iret"::)

#define _set_gate(gate_addr,type,dpl,addr) \
__asm__ ("movw %%dx,%%ax\n\t" \
	"movw %0,%%dx\n\t" \
	"movl %%eax,%1\n\t" \
	"movl %%edx,%2" \
	: \
	: "i" ((short) (0x8000+(dpl<<13)+(type<<8))), \
	"o" (*((char *) (gate_addr))), \
	"o" (*(4+(char *) (gate_addr))), \
	"d" ((char *) (addr)),"a" (0x00080000))

#define set_intr_gate(n,addr) \
	_set_gate(&idt[n],14,0,addr)

#define set_trap_gate(n,addr) \
	_set_gate(&idt[n],15,0,addr)

#define set_system_gate(n,addr) \
	_set_gate(&idt[n],15,3,addr)

#define _set_seg_desc(gate_addr,type,dpl,base,limit) {\
	*(gate_addr) = ((base) & 0xff000000) | \
		(((base) & 0x00ff0000)>>16) | \
		((limit) & 0xf0000) | \
		((dpl)<<13) | \
		(0x00408000) | \
		((type)<<8); \
	*((gate_addr)+1) = (((base) & 0x0000ffff)<<16) | \
		((limit) & 0x0ffff); }

#define _set_tssldt_desc(n,addr,type) \
__asm__ ("movw $104,%1\n\t" \
	"movw %%ax,%2\n\t" \
	"rorl $16,%%eax\n\t" \
	"movb %%al,%3\n\t" \
	"movb $" type ",%4\n\t" \
	"movb $0x00,%5\n\t" \
	"movb %%ah,%6\n\t" \
	"rorl $16,%%eax" \
	::"a" (addr), "m" (*(n)), "m" (*(n+2)), "m" (*(n+4)), \
	 "m" (*(n+5)), "m" (*(n+6)), "m" (*(n+7)) \
	)

#define set_tss_desc(n,addr) _set_tssldt_desc(((char *) (n)),addr,"0x89")
#define set_ldt_desc(n,addr) _set_tssldt_desc(((char *) (n)),addr,"0x82")
#endif
