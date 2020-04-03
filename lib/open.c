/*
 *  linux/lib/open.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__
#include <unistd.h>
#include <stdarg.h>
#ifdef S3C2440
int open(const char * filename, int flag, ...)
{
	register int res;
	va_list arg;

	va_start(arg,flag);
	register int _a1 __asm__ ("r0")=(int)filename;
	register int _a2 __asm__ ("r1")=(int)(flag);
	register int _a3 __asm__ ("r2")=(int)va_arg(arg,int);
	__asm__ volatile("swi  %1"
		:"=r" (_a1)
		:"i" (__NR_open),"r" (_a1),"r" (_a2),"r" (_a3)
		:"memory","r0","r1","r2");
	if (_a1>=0)
		return _a1;
	errno = -_a1;
	return -1;
}
#else
int open(const char * filename, int flag, ...)
{
	register int res;
	va_list arg;

	va_start(arg,flag);
	__asm__("int $0x80"
		:"=a" (res)
		:"0" (__NR_open),"b" (filename),"c" (flag),
		"d" (va_arg(arg,int)));
	if (res>=0)
		return res;
	errno = -res;
	return -1;
}
#endif
