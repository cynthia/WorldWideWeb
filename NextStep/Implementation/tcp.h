/*	System-system differences for TCP include files and macros     tcp.h
**	===========================================================
**
**
**	This file includes for each system, the files necessary for
**	network and file I/O
**
**  History:
**	22 Feb 91	Written (TBL) as part of the WWW project.
*/

#define NETCLOSE close	    /* Routine to close a TCP-IP socket		*/
#define NETREAD  read	    /* Routine to read from a TCP-IP socket	*/
#define NETWRITE write	    /* Routine to write to a TCP-IP socket	*/

/*	On the NeXT, there's a little package of include files.
*/
#ifdef NeXT
#include <libc.h>		/* NeXT has all this packaged up */
#define ntohs(x) (x)
#define htons(x) (x)
#include <sys/errno.h>		/* Get ECONNRESET etc */
#define SELECT			/* Is supported ok */
#define INCLUDES_DONE
extern int errno;

#else				/* Not NeXT */
#include <stdio.h>

/*	MVS is compiled as for VM. MVS has no unix-style I/O
**	The command line compile options seem to come across in
**	lower case.
**
**	See aslo lots of VM stuff lower down.
*/
#ifdef mvs
#define MVS
#endif

#ifdef MVS
#define VM
#endif

/*	VM doesn't have a built-in predefined token, so we cheat: */
#ifdef __STDIO__
#define VM
#else
#include <string.h>		/* For bzero etc - not NeXT or VM */
#endif
#define SELECT			/* Handle >1 channel if we can.		*/
#endif				/* Not NeXT */


/*	Under VMS, there are many versions of TCP-IP. Define one if you
**	do not use Digital's UCX product:
**
**		UCX		DEC's "Ultrix connection" (default)
**		WIN_TCP		From Wollongong, now GEC software.
**		MULTINET	From SRI, now from TGV Inv.
**
**	The second two do not interfere with the unix i/o library, and so they
**	need special calls to read, write and close sockets. In these cases the
**	socket number is a VMS channel number, so we make the HORRIBLE
**	assumption that a channel number will be greater than 10 but a
**	unix file descriptor less than 10.
*/
#ifdef vms
#ifdef WIN_TCP
#undef NETREAD
#undef NETWRITE
#undef NETCLOSE
#define NETREAD(s,b,l)	((s)>10 ? netread((s),(b),(l)) : read((s),(b),(l)))
#define NETWRITE(s,b,l)	((s)>10 ? netwrite((s),(b),(l)) : write((s),(b),(l)))
#define NETCLOSE(s) 	((s)>10 ? netclose(s) : close(s))
#endif

#ifdef MULTINET
#undef NETCLOSE
#undef NETREAD
#undef NETWRITE
#define NETREAD(s,b,l)	((s)>10 ? socket_read((s),(b),(l)) : read((s),(b),(l)))
#define NETWRITE(s,b,l)	((s)>10 ? socket_write((s),(b),(l)) : \
				write((s),(b),(l)))
#define NETCLOSE(s) 	((s)>10 ? socket_close(s) : close(s))
#endif

/*	Certainly this works for UCX:	@@@
*/
#include types
#include errno
#include time
#include string
#include stdio
#include file
#include unixio

#define INCLUDES_DONE

#include socket
#include in
#include inet
#include netdb
#define TCP_INCLUDES_DONE

#endif	/* vms */


/*	IBM VM/CMS or MVS
**	-----------------
**
**	Note:	All files must have lines <= 80 characters
**
**	Under VM, compile with "DEF=VM"
**
**	Under MVS, compile with "NOMAR DEF(MVS)" to get rid of 72 char margin
**	  System include files TCPIP and COMMMAC neeed line number removal(!)
*/

#ifdef VM			/* or MVS -- see above. */
#define NOT_ASCII		/* char type is not ASCII */
#define NO_UNIX_IO		/* Unix I/O routines are not supported */
#define SHORT_NAMES		/* 8 character uniqueness for globals */
#include <manifest.h>                                                           
#include <bsdtypes.h>                                                           
#include <stdefs.h>                                                             
#include <socket.h>                                                             
#include <in.h>
#include <netdb.h>                                                                 
#include <errno.h>	    /* independent */
extern char asciitoebcdic[], ebcdictoascii[];
#define TOASCII(c)   (c=='\n' ?  10  : ebcdictoascii[c])
#define FROMASCII(c) (c== 10  ? '\n' : asciitoebcdic[c])                                   
#include <bsdtime.h>
#include <string.h>                                                            
#define INCLUDES_DONE
#define TCP_INCLUDES_DONE
#endif

/*	Regular BSD unix versions: */

#ifndef INCLUDES_DONE
#include <sys/types.h>
/* #include <streams/streams.h>			not ultrix */
#include <string.h>
#include <stdio.h>
#include <errno.h>	    /* independent */
#include <sys/time.h>	    /* independent */
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/file.h>	    /* For open() etc */
#endif	/* Normal includes */


/*	Default include files for TCP
*/
#ifndef TCP_INCLUDES_DONE
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>	    /* Must be after netinet/in.h */
#include <netdb.h>
#endif	/* TCP includes */


/*	Default macros for manipulating masks for select()
*/
#ifndef FD_SET
typedef unsigned int fd_set;
#define FD_SET(fd,pmask) (*(pmask)) |=  (1<<(fd))
#define FD_CLR(fd,pmask) (*(pmask)) &= ~(1<<(fd))
#define FD_ZERO(pmask)   (*(pmask))=0
#define FD_ISSET(fd,pmask) (*(pmask) & (1<<(fd)))
#endif


/*	Default macros for converting characters
**
*/
#ifndef TOASCII
#define TOASCII(c) (c)
#define FROMASCII(c) (c)                                   
#endif
