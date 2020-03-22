OUTPUT_FORMAT("elf32-littlearm", "elf32-littlearm", "elf32-littlearm")
OUTPUT_ARCH(arm)
ENTRY(_start)
SECTIONS
{
	.text 0xC0000000: { *(.text) }
	. = ALIGN(4);
	.data : { *(.data) }
	. = ALIGN(4);
	_bstart = . ;
	.bss : { *(.bss) . = ALIGN(4); }
	_bend = . ;
	. = ALIGN(4);
}
