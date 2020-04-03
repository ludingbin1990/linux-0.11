/*
 *  linux/lib/_exit.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__
#include <unistd.h>
#ifdef S3C2440
volatile void _exit(int exit_code)
{
	register int _a1 __asm__ ("r0")=exit_code;
	__asm__ volatile("swi  %0"::"i" (__NR_exit),"r" ((int)(_a1)): "memory","r0");
}
#else
volatile void _exit(int exit_code)
{
	__asm__("int $0x80"::"a" (__NR_exit),"b" (exit_code));
}
#endif
