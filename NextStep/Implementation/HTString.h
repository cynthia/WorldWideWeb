/*		Case-independent string comparison		HTString.h
**		and allocations with copies
*/
#ifndef HTSTRING_H
#define HTSTRING_H

#include "HTUtils.h"

extern int WWW_TraceFlag;	/* Global flag for all W3 trace */

extern CONST char * HTLibraryVersion;	/* String for help screen etc */

extern int strcasecomp  PARAMS((CONST char *a, CONST char *b));
extern int strncasecomp PARAMS((CONST char *a, CONST char *b, int n));

extern char * HTSACopy PARAMS ((char **dest, CONST char *src));
extern char * HTSACat  PARAMS ((char **dest, CONST char *src));

/* Enable the old macro-like calling methods */
#define StrAllocCopy(dest, src) HTSACopy (&(dest), src)
#define StrAllocCat(dest, src)  HTSACat  (&(dest), src)

#endif
