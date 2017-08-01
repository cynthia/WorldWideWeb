/*		Access Manager					HTAccess.c
**		==============
*/

#include "HTParse.h"
#include "HTUtils.h"
#include "WWW.h"
#include "HTFTP.h"
#include "HTTP.h"
#include "HTFile.h"
#include <errno.h>
#include <stdio.h>

#ifdef EXPLICIT_INCLUDES
#ifndef vms
#include <string.h>
#include <sys/file.h>

#else	/* VMS */
#include <errno.h>
#include file
#include unixio
#endif	/* VMS */

#else	/* not explicit includes */
#include "tcp.h"
#endif


/*	Open a file descriptor for a document
**	-------------------------------------
**
** On entry,
**	addr		must point to the fully qualified hypertext reference.
**
** On exit,
**	returns		<0	Error has occured.
**			>=0	Value of file descriptor or socket to be used
**				 to read data.
**	*pFormat	Set to the format of the file, if known.
**			(See WWW.h)
**
*/
#ifdef __STDC__
int HTOpen(const char * addr, WWW_Format * pFormat)
#else
int HTOpen(addr, pFormat)
    char 	* addr;
    WWW_Format	* pFormat;
#endif
{
    char * access=0;	/* Name of access method */
    
    access =  HTParse(addr, "file:", PARSE_ACCESS);
    if (0==strcmp(access, "file")) {
        return HTOpenFile(addr, pFormat);

    } else if (0==strcmp(access, "http")) {
        free(access);
	*pFormat = WWW_HTML;
	return HTTP_Get(addr);
	
    } else if (0==strcmp(access, "news")) {
        printf("HTAccess: Sorry, Internet news not integrated yet.\n");
    }

    printf("HTAccess: Unknown access `%s'\n", access);
    free(access);
    return -1;
}


/*	Close socket opened for reading a file
**	--------------------------------------
**
*/
#ifdef __STDC__
PUBLIC int HTClose(int soc)
#else
PUBLIC int HTClose(soc)
    int soc;
#endif
{
    return HTFTP_close_file(soc);
}
