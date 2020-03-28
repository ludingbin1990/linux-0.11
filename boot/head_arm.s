#include "../config/arm_config"
.arm
.text

.globl _start

_start:


/* 1.create the page table first*/
/* clear the page dir table ,the space is 4M*/
	ldr  r8,=PHYS_OFFSET     
	add	r4, r8, #TEXT_OFFSET - PG_DIR_SIZE
	mov	r0, r4
	mov	r3, #0
	add	r6, r0, #PG_DIR_SIZE
1:	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
	teq	r0, r6
	bne	1b


	adr r0, mmu_flags
	ldr  r7,[r0]


/* 1.1do the Identity mapping on the turn on the mmu code. make the mapping address equal to the physical address*/
	adr	r0, __turn_mmu_on_loc
	ldmia	r0, {r3, r5, r6}
	sub	r0, r0, r3			@ virt->phys offset
	add	r5, r5, r0			@ phys __turn_mmu_on
	add	r6, r6, r0			@ phys __turn_mmu_on_end
	mov	r5, r5, lsr #SECTION_SHIFT
	mov	r6, r6, lsr #SECTION_SHIFT

1:	orr	r3, r7, r5, lsl #SECTION_SHIFT	@ flags + kernel base
	str	r3, [r4, r5, lsl #PMD_ORDER]	@ identity mapping
	cmp	r5, r6
	addlo	r5, r5, #1			@ next section
	blo	1b






/* 1.2 Map our RAM from the start to the end */
	add	r0, r4, #PAGE_OFFSET >> (SECTION_SHIFT - PMD_ORDER)
	ldr	r6, =(PAGE_OFFSET+PHYS_SIZE)
	orr	r3, r8, r7
	add	r6, r4, r6, lsr #(SECTION_SHIFT - PMD_ORDER)
1:	str	r3, [r0], #1 << PMD_ORDER
	add	r3, r3, #1 << SECTION_SHIFT
	cmp	r0, r6
	bls	1b





/* 1.3 Map the uart for debug before the kernel ready*/

	ldr	r7, = S3C24XX_PA_UART
	ldr	r3, = S3C24XX_VA_UART
	mov	r3, r3, lsr #SECTION_SHIFT
	mov	r3, r3, lsl #PMD_ORDER
	add	r0, r4, r3
	mov	r3, r7, lsr #SECTION_SHIFT
	adr r10, io_mmu_flags   @ io_mmuflags
	ldr  r7,[r10]
	orr	r3, r7, r3, lsl #SECTION_SHIFT
	orr	r3, r3, #16            @PMD_SECT_XN
	str	r3, [r0], #4



/* 1.4 prepare for enable mmu*/
	ldr	r13, =__mmap_switched		@ address to jump to after
	adr	lr, 1f			@ return (PIC) address
	mov	r8, r4				@ set TTBR1 to swapper_pg_dir
	adr	pc, __arm920_setup
	1:	b	__enable_mmu


.type __enable_mmu, @function
.globl __enable_mmu
__enable_mmu:
	orr	r0, r0, #2
	mov	r5, #31
	/*(domain_val(DOMAIN_USER, DOMAIN_MANAGER) | \
		      domain_val(DOMAIN_KERNEL, DOMAIN_MANAGER) | \
		      domain_val(DOMAIN_TABLE, DOMAIN_MANAGER) | \
		      domain_val(DOMAIN_IO, DOMAIN_CLIENT))*/
	mcr	p15, 0, r5, c3, c0, 0		@ load domain access register
	mcr	p15, 0, r4, c2, c0, 0		@ load page table pointer
	b	__turn_mmu_on



.type __arm920_setup, @function
.globl __arm920_setup
__arm920_setup:
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7		@ invalidate I,D caches on v4
	mcr	p15, 0, r0, c7, c10, 4		@ drain write buffer on v4
	mcr	p15, 0, r0, c8, c7		@ invalidate I,D TLBs on v4
	adr	r5, arm920_crval
	ldmia	r5, {r5, r6}
	mrc	p15, 0, r0, c1, c0		@ get control register v4
	bic	r0, r0, r5
	orr	r0, r0, r6
	mov	pc, lr





/*default use the s3c2440 uart0 for debug */

#define S3C2410_UFCON_FIFOMODE	  (1<<0)
#define S3C2410_UFCON	  (0x08)
#define S3C2410_UTRSTAT	  (0x10)
#define S3C2410_UTRSTAT_TXFE	  (1<<1)
#define S3C2410_UTXH	  (0x20)
#define S3C2410_UFSTAT	  (0x18)
#define S3C2440_UFSTAT_TXMASK	  (63<<8)
#define S3C2440_UFSTAT_TXFULL	  (1<<14)


.macro addruart, rp, rv, tmp
		ldr	\rp, = S3C24XX_PA_UART
		ldr	\rv, = S3C24XX_VA_UART
.endm

.macro	addruart_current, rx, tmp1, tmp2
		addruart	\tmp1, \tmp2, \rx
		mrc		p15, 0, \rx, c1, c0
		tst		\rx, #1
		moveq		\rx, \tmp1
		movne		\rx, \tmp2
.endm

.macro	waituart,rd,rx
		ldr	\rd, [\rx, # S3C2410_UFCON]
		tst	\rd, #S3C2410_UFCON_FIFOMODE	@ fifo enabled?
		beq	1001f	@
		@ FIFO enabled...
	1003:
		fifo_level \rd, \rx
		teq	\rd, #0
		bne	1003b
		b	1002f
	1001:
		@ idle waiting for non fifo
		ldr	\rd, [\rx, # S3C2410_UTRSTAT]
		tst	\rd, #S3C2410_UTRSTAT_TXFE
		beq	1001b
	1002:	@ exit busyuart
.endm

.macro	senduart,rd,rx
		strb 	\rd, [\rx, # S3C2410_UTXH]
.endm

.macro	busyuart, rd, rx
		ldr	\rd, [\rx, # S3C2410_UFCON]
		tst	\rd, #S3C2410_UFCON_FIFOMODE	@ fifo enabled?
		beq	1001f				@
		@ FIFO enabled...
	1003:
		fifo_full \rd, \rx
		bne	1003b
		b	1002f

	1001:
		@ busy waiting for non fifo
		ldr	\rd, [\rx, # S3C2410_UTRSTAT]
		tst	\rd, #S3C2410_UTRSTAT_TXFE
		beq	1001b

	1002:		@ exit busyuart
.endm

.macro fifo_level_s3c2440 rd, rx
		ldr	\rd, [\rx, # S3C2410_UFSTAT]
		and	\rd, \rd, #S3C2440_UFSTAT_TXMASK
.endm

#define fifo_level fifo_level_s3c2440

.macro  fifo_full_s3c2440 rd, rx
		ldr	\rd, [\rx, # S3C2410_UFSTAT]
		tst	\rd, #S3C2440_UFSTAT_TXFULL
.endm

#define fifo_full fifo_full_s3c2440


.type printascii, @function
.globl printascii
printascii:
		addruart_current r3, r1, r2
		b	2f
1:		waituart r2, r3
		senduart r1, r3
		busyuart r2, r3
		teq	r1, #'\n'
		moveq	r1, #'\r'
		beq	1b
2:		teq	r0, #0
		ldrneb	r1, [r0], #1
		teqne	r1, #0
		bne	1b
		mov	pc, lr


.type __mmap_switched, @function

.globl __mmap_switched

__mmap_switched:
	adr	r3, __mmap_switched_data

	ldmia	r3!, {r6, r7}

	mov	fp, #0				@ Clear BSS (and zero fp)
1:	cmp	r6, r7
	strcc	fp, [r6],#4
	bcc	1b

	ldr sp,=stack_start
	b	main


.align	4
__turn_mmu_on:
	mov	r0, r0
	mcr	p15, 0, r0, c1, c0, 0		@ write control reg
	mrc	p15, 0, r3, c0, c0, 0		@ read id reg
	mov	r3, r3
	mov	r3, r13
	mov	pc, r3
__turn_mmu_on_end:
.align	4

.data

arm920_crval:
	.word 0x00003f3f
	.word 0x00003135

__mmap_switched_data:
	.long	_bstart			@ r6
	.long	_bend				@ r7

__turn_mmu_on_loc:
	.long	.
	.long	__turn_mmu_on
	.long	__turn_mmu_on_end

mm_mmu_flags: 
	.long 0x00000c1e
	/*mm flags setting:
		PMD_TYPE_SECT | \
		PMD_SECT_BUFFERABLE | \
		PMD_SECT_CACHEABLE | \
		PMD_BIT4 | \
		PMD_SECT_AP_WRITE | \
		PMD_SECT_AP_READ*/
		
io_mmu_flags: 
	.long 0x00000c12
	/*io flags setting:
		PMD_TYPE_SECT | \
		PMD_BIT4 | \		
		PMD_SECT_AP_WRITE | \
		PMD_SECT_AP_READ*/

