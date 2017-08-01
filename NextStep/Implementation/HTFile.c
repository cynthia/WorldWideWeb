/*			File Access				HTFile.c
**			===========
**
**	This is unix-specific code in general, with some VMS bits.
**	These are routines for file access used by WWW browsers.
**
** History:
**	   Feb 91	Written Tim Berners-Lee CERN/CN
**	   Apr 91	vms-vms access included using DECnet syntax
**
** Bugs:
**	Cannot access VMS files from a unix machine. How can we know that the
**	target machine runs VMS?
*/


#ifdef EXPLICIT_INCLUDES
#ifdef vms
include <unixio.h>
#else
#include <sys/param.h>
#include <sys/stat.h>
#endif
#endif

#include "HTUtils.h"
#include "WWW.h"
#include "HTParse.h"
#include "tcp.h"
#include "HTTCP.h"
#include "HTFTP.h"

PRIVATE char *HTMountRoot = "/Net/";		/* Where to find mounts */
/* PRIVATE char *HTCacheRoot = "/tmp/Cache/";*/    /* Where to cache things */
/* PRIVATE char *HTSaveRoot  = "$(HOME)/WWW/";*/    /* Where to save things */

/*	Convert filenames between local and WWW formats
**	-----------------------------------------------
**	Make up a suitable name for saving the node in
**
**	E.g.	$(HOME)/WWW/news/1234@cernvax.cern.ch
**		$(HOME)/WWW/http/crnvmc/FIND/xx.xxx.xx
**
** On exit,
**	returns	a malloc'ed string which must be freed by the caller.
*/
#ifdef __STDC__
PUBLIC char * HTLocalName(const char * name)
#else
PUBLIC char * HTLocalName(name)
    char * name;
#endif
{
    char * access = HTParse(name, "", PARSE_ACCESS);
    char * host = HTParse(name, "", PARSE_HOST);
    char * path = HTParse(name, "", PARSE_PATH+PARSE_PUNCTUATION);
    
    if (0==strcmp(access, "file")) {
        free(access);	
	if ((0==strcmp(host, HTHostName())) || !*host) {
	    free(host);
	    if (TRACE) printf("Node `%s' means path `%s'\n", name, path);
	    return(path);
	} else {
	    char * result = (char *)malloc(
	    			strlen("/Net/")+strlen(host)+strlen(path)+1);
	    sprintf(result, "%s%s%s", "/Net/", host, path);
	    free(host);
	    free(path);
	    if (TRACE) printf("Node `%s' means file `%s'\n", name, result);
	    return result;
	}
    } else {  /* other access */
	char * result;
        CONST char * home =  (CONST char*)getenv("HOME");
	if (!home) home = "/tmp"; 
	result = (char *)malloc(
		strlen(home)+strlen(access)+strlen(host)+strlen(path)+6+1);
	sprintf(result, "%s/WWW/%s/%s%s", home, access, host, path);
	free(path);
	free(access);
	free(host);
	return result;
    }
}


/*	Make a WWW name from a full local path name
**
** Bugs:
**	At present, only the names of two network root nodes are hand-coded
**	in and valid for the NeXT only. This should be configurable in
**	the general case.
*/
#ifdef __STDC__
PUBLIC char * WWW_nameOfFile(const char * name)
#else
PUBLIC char * WWW_nameOfFile(name)
    char * name;
#endif
{
    char * result;
    if (0==strncmp("/private/Net/", name, 13)) {
	result = (char *)malloc(7+strlen(name+13)+1);
	sprintf(result, "file://%s", name+13);
    } else if (0==strncmp(HTMountRoot, name, 5)) {
	result = (char *)malloc(7+strlen(name+5)+1);
	sprintf(result, "file://%s", name+5);
    } else {
        result = (char *)malloc(7+strlen(HTHostName())+strlen(name)+1);
	sprintf(result, "file://%s%s", HTHostName(), name);
    }
    if (TRACE) printf("File `%s'\n\tmeans node `%s'\n", name, result);
    return result;
}


/*	Determine file format from file name
**	------------------------------------
**
**
*/

#ifdef __STDC__
PUBLIC WWW_Format HTFileFormat(const char * filename)
#else
PUBLIC WWW_Format HTFileFormat(filename)
    char * filename;
#endif	
{
    CONST char * extension;
    for (extension=filename+strlen(filename);
	(extension>filename) &&
		(*extension != '.') &&
		(*extension!='/');
	extension--) /* search */ ;

    if (*extension == '.') {
	return    0==strcmp(".html", extension) ? WWW_HTML
		: 0==strcmp(".rtf",  extension) ? WWW_RICHTEXT
		: 0==strcmp(".txt",  extension) ? WWW_PLAINTEXT
		: WWW_INVALID;		/* Unrecognised */
    } else {
	return WWW_PLAINTEXT;
    } 
}


/*	Determine write access to a file
//	--------------------------------
//
// On exit,
//	return value	YES if file can be accessed and can be written to.
//
//	Isn't there a quicker way?
*/

#ifdef __STDC__
PUBLIC BOOL HTEditable(const char * filename)
#else
PUBLIC BOOL HTEditable(filename)
    char * filename;
#endif
{
#ifndef vms
#ifndef NO_UNIX_IO
    int 	groups[NGROUPS];	
    uid_t	myUid;
    int		ngroups;			/* The number of groups  */
    struct stat	fileStatus;
    int		i;
        
    if (stat(filename, &fileStatus))		/* Get details of filename */
    	return NO;				/* Can't even access file! */

    ngroups = getgroups(NGROUPS, groups);	/* Groups to which I belong  */
    myUid = geteuid();				/* Get my user identifier */

    if (TRACE) {
        int i;
	printf("File mode is 0%o, uid=%d, gid=%d. My uid=%d, %d groups (",
    	    fileStatus.st_mode, fileStatus.st_uid, fileStatus.st_gid,
	    myUid, ngroups);
	for (i=0; i<ngroups; i++) printf(" %d", groups[i]);
	printf(")\n");
    }
    
    if (fileStatus.st_mode & 0002)		/* I can write anyway? */
    	return YES;
	
    if ((fileStatus.st_mode & 0200)		/* I can write my own file? */
     && (fileStatus.st_uid == myUid))
    	return YES;

    if (fileStatus.st_mode & 0020)		/* Group I am in can write? */
    {
   	for (i=0; i<ngroups; i++) {
            if (groups[i] == fileStatus.st_gid)
	        return YES;
	}
    }
    if (TRACE) printf("\tFile is not editable.\n");
    return NO;					/* If no excuse, can't do */
#else /* NO_UNIX_IO */
    return NO;		/* Safe answer if no files exist anyway */
#endif
#else /* vms */
    return NO;		/* Safe answer till we find the correct algorithm */
#endif
}


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
int HTOpenFile(const char * addr, WWW_Format * pFormat)
#else
int HTOpenFile(addr, pFormat)
    char 	* addr;
    WWW_Format	* pFormat;
#endif
{
    char * filename;
    int fd = -1;		/* Unix file descriptor number = INVALID */
    char * nodename = 0;
    char * newname=0;	/* Simplified name of file */

/*	Reduce the filename to a basic form (hopefully unique!)
*/
    StrAllocCopy(newname, addr);
    HTSimplify(newname);
    filename=HTParse(newname, "", PARSE_PATH|PARSE_PUNCTUATION);
    nodename=HTParse(newname, "", PARSE_HOST);
    free(newname);
    
    *pFormat = HTFileFormat(filename);

    
#ifdef vms
/* Assume that the file is remote ultrix! @@ */
    {

/*	We try converting the filename into Files-11 syntax. That is, we assume
**	first that the file is, like us, on a VMS node. We try remote
**	(or local) DECnet access. Files-11, VMS, VAX and DECnet
**	are trademarks of Digital Equipment Corporation. 
*/
	char wholename[255];        /* VMS Fudge */
	char vmsname[255];
	char *second = strchr(filename+1, '/');		/* 2nd slash */
	char *last = strrchr(filename, '/');	/* last slash */
	if (!second) {				/* Only one slash */
	    sprintf(vmsname, "%s::%s", nodename, filename);
	} else if(second==last) {		/* Exactly two slashes */
	    *second = 0;		/* Split filename from disk */
	    sprintf(vmsname, "%s::%s:%s", nodename, filename+1, second+1);
	    *second = '/';	/* restore */
	} else { 				/* More than two slashes */
	    char * p;
	    *second = 0;		/* Split disk from directories */
	    *last = 0;		/* Split dir from filename */
	    sprintf(vmsname, "%s::%s:[%s]%s",
		    nodename, filename+1, second+1, last+1);
	    *second = *last = '/';	/* restore filename */
	    for (p=strchr(vmsname, '['); *p!=']'; p++)
		if (*p=='/') *p='.';	/* Convert dir sep.  to dots */
	}
	fd = open(vmsname, O_RDONLY, 0);

/*	If the file wasn't VMS syntax, then perhaps it is ultrix
*/
	if (fd<0) {
	    if (TRACE) printf("HTAccess: Can't open as %s\n", vmsname);
	    sprintf(vmsname, "%s::\"%s\"", nodename, filename);
	    fd = open(vmsname, O_RDONLY, 0);
	    if (fd<0) {
		if (TRACE) printf("HTAccess: Can't open as %s\n", vmsname);
	    }
	}
    }
#else

/*	For unix, we try to translate the name into the name of a transparently
**	mounted file.
*/
#ifndef NO_UNIX_IO
    {
	char * localname = HTLocalName(addr);
	fd = open(localname, O_RDONLY, 0);
	if(TRACE) printf ("HTAccess: Opening `%s' gives %d\n",
			    localname, fd);
	free(localname);
    }
#endif
#endif

/*	Now, as transparently mounted access has failed, we try FTP.
*/
    if (fd<0)
	if (strcmp(nodename, HTHostName())!=0) {
	    free(filename);
	    return HTFTP_open_file_read(addr);
    }

/*	All attempts have failed if fd<0.
*/
    if (fd<0) printf("Can't open `%s', errno=%d\n", filename, errno);
    free(filename);
    return fd;

}
