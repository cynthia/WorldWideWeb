/*	HyperText Tranfer Protocol	- Client implementation		HTTP.c
**	==========================
*/

/*	Module parameters:
**	-----------------
**
**  These may be undefined and redefined by syspec.h
*/
#include "HTParse.h"
#include "HTUtils.h"
#include "tcp.h"
#include "HTTCP.h"


/*		Open Socket for reading from HTTP Server	HTTP_get()
**		========================================
**
**	Given a hypertext address, this routine opens a socket to the server.
**
** On entry,
**	arg	is the hypertext reference of the article to be loaded.
** On exit,
**	returns	>=0	If no error, a good socket number
**		<0	Error.
**
**	The socket must be closed by the caller after the document has been
**	read.
**
*/
#ifdef __STDC__
int HTTP_Get(const char * arg)
#else
int HTTP_Get(arg)
    char * arg;
#endif
{
    int s;				/* Socket number for returned data */
    char command[257];			/* The whole command */
    int status;				/* tcp return */
 
    struct sockaddr_in soc_address;	/* Binary network address */
    struct sockaddr_in* sin = &soc_address;

    if (!arg) return -3;			/* Bad if no name sepcified	*/
    if (!*arg) return -2;			/* Bad if name had zero length	*/

/*  Set up defaults:
*/
    sin->sin_family = AF_INET;	    		/* Family, host order  */
    sin->sin_port = htons(TCP_PORT);	    	/* Default: new port,    */

    if (TRACE) printf("HTTPAccess: Looking for %s\n", arg);

/* Get node name and optional port number:
*/
    {
	char *p1 = HTParse(arg, "", PARSE_HOST);
	HTParseInet(sin, p1);
        free(p1);
    }
    
/* We will ask that node for the document, omitting the host name & anchor.
*/        
    strcpy(command, "GET ");
    {
	char * p1 = HTParse(arg, "", PARSE_PATH|PARSE_PUNCTUATION);
	strcat(command, p1);
	free(p1);
    }
    strcat(command, "\n");
	    
   
/*	Now, let's get a socket set up from the server for the sgml data:
*/      
    s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    status = connect(s, (struct sockaddr*)&soc_address, sizeof(soc_address));
    if (status<0){
	if (TRACE) printf("HTTPAccess: Unable to connect to remote host for `%s'.\n",
	    arg);
	return HTInetStatus("connect");
    }
    
    if (TRACE) printf("HTTP connected, socket %d\n", s);
    if (TRACE) printf("HTTP writting command `%s' to socket %d\n", command, s);
    
#ifdef NOT_ASCII
    {
    	char * p;
	for(p = command; *p; p++) {
	    *p = TOASCII(*p);
	}
    }
#endif

    status = NETWRITE(s, command, strlen(command));
    if (status<0){
	if (TRACE) printf("HTTPAccess: Unable to send command.\n");
	    return HTInetStatus("send");
    }

    return s;			/* Good return */
}
