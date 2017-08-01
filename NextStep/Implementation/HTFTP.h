/*			FTP access functions		HTFTP.h
**			====================
*/

/*	Retrieve File from Server
**	-------------------------
**
** On exit,
**	returns		Socket number for file if good.
**			<0 if bad.
*/
#ifdef __STDC__
extern int HTFTP_open_file_read(CONST char * name);
#else
extern int HTFTP_open_file_read();
#endif

/*	Close socket opened for reading a file, and get final message
**	-------------------------------------------------------------
**
*/
#ifdef __STDC__
extern int HTFTP_close_file(int soc);
#else
extern int HTFTP_close_file();
#endif


/*	Return Host Name
**	----------------
*/
#ifdef __STDC__
extern const char * HTHostName(void);
#else
extern char * HTHostName();
#endif
