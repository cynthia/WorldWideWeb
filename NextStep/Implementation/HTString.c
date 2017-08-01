/*		Case-independent string comparison		HTString.c
**
**	Original version came with listserv implementation.
**	Version TBL Oct 91 replaces one which modified the strings.
**	02-Dec-91 (JFG) Added stralloccopy and stralloccat
**	23 Jan 92 (TBL) Changed strallocc* to 8 char HTSAC* for VM and suchlike
**	 6 Oct 92 (TBL) Moved WWW_TraceFlag in here to be in library
*/
#include <ctype.h>
#include "HTUtils.h"
#include "tcp.h"

PUBLIC int WWW_TraceFlag = 0;	/* Global trace flag for ALL W3 code */
PUBLIC CONST char * HTLibraryVersion = "nextfudge"; /* String for help screen etc */

#ifndef VM		/* VM has these already it seems */
	
/*	Strings of any length
**	---------------------
*/
PUBLIC int strcasecomp ARGS2 (CONST char*,a, CONST char *,b)
{
	CONST char *p =a;
	CONST char *q =b;
	for(p=a, q=b; *p && *q; p++, q++) {
	    int diff = TOLOWER(*p) - TOLOWER(*q);
	    if (diff) return diff;
	}
	if (*p) return 1;	/* p was longer than q */
	if (*q) return -1;	/* p was shorter than q */
	return 0;		/* Exact match */
}


/*	With count limit
**	----------------
*/
PUBLIC int strncasecomp ARGS3(CONST char*,a, CONST char *,b, int,n)
{
	CONST char *p =a;
	CONST char *q =b;
	
	for(p=a, q=b;; p++, q++) {
	    int diff;
	    if (p == a+n) return 0;	/*   Match up to n characters */
	    if (!(*p && *q)) return *p - *q;
	    diff = TOLOWER(*p) - TOLOWER(*q);
	    if (diff) return diff;
	}
	/*NOTREACHED*/
}
#endif

/*	Allocate a new copy of a string, and returns it
*/
PUBLIC char * HTSACopy
  ARGS2 (char **,dest, CONST char *,src)
{
  if (*dest) free(*dest);
  if (! src)
    *dest = NULL;
  else {
    *dest = (char *) malloc (strlen(src) + 1);
    if (*dest == NULL) outofmem(__FILE__, "HTSACopy");
    strcpy (*dest, src);
  }
  return *dest;
}

PUBLIC char * HTSACat
  ARGS2 (char **,dest, CONST char *,src)
{
  if (src && *src) {
    if (*dest) {
      int length = strlen (*dest);
      *dest = (char *) realloc (*dest, length + strlen(src) + 1);
      if (*dest == NULL) outofmem(__FILE__, "HTSACat");
      strcpy (*dest + length, src);
    } else {
      *dest = (char *) malloc (strlen(src) + 1);
      if (*dest == NULL) outofmem(__FILE__, "HTSACat");
      strcpy (*dest, src);
    }
  }
  return *dest;
}
