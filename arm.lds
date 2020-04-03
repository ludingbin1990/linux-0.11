#include "./config/used_config"
OUTPUT_FORMAT("elf32-littlearm", "elf32-littlearm", "elf32-littlearm")
OUTPUT_ARCH(arm)
ENTRY(_start)
SECTIONS
{
	.text VM_TEXT_START_ASSRESS: { *(.text) }
	. = ALIGN(4);
	.data : { *(.data) 
	. = ALIGN(4096);
        *(.data..init_task)
	. = ALIGN(4);}
	_bstart = . ;
	.bss : { *(.bss) . = ALIGN(4); }
	_bend = . ;
	. = ALIGN(4);
}
