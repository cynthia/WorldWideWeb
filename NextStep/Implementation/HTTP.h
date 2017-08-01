/*	HyperText Tranfer Protocol					HTTP.h
**	==========================
*/


/*		Open Socket for reading from HTTP Server		HTTP_get()
**		========================================
**
**	Given a hypertext address, this routine opens a socket to the server,
**	sends the "get" command to ask for teh node, and then returns the
**	socket to the caller. The socket must later be closed by the caller.
**
** On entry,
**	arg	is the hypertext reference of the article to be loaded.
** On exit,
**	returns	>=0	If no error, a good socket number
**		<0	Error.
**
*/
#ifdef __STDC__
extern int HTTP_Get(const char * arg);
#else
extern int HTTP_Get();
#endif
