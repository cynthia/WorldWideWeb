/*		Access Manager					HTAccess.h
**		==============
*/

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
extern int HTOpen(char * addr, WWW_Format * format);
#else
extern int HTOpen();
#endif


/*	Close socket opened for reading a file
**	--------------------------------------
**
*/
#ifdef __STDC__
extern int HTClose(int soc);
#else
extern int HTClose();
#endif
