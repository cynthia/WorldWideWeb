/*			File Access				HTFile.h
**			===========
**
**	These are routines for file access used by WWW browsers.
**
*/

/*	Convert filenames between local and WWW formats
**	-----------------------------------------------
**	Make up a suitable name for saving the node in
**
**	E.g.	$(HOME)/WWW/news/1234@cernvax.cern.ch
**		$(HOME)/WWW/http/crnvmc/FIND/xx.xxx.xx
*/
#ifdef __STDC__
extern char * HTLocalName(const char * name);
#else
extern char * HTLocalName();
#endif

/*	Make a WWW name from a full local path name
**
*/
#ifdef __STDC__
extern char * WWW_nameOfFile(const char * name);
#else
extern char * WWW_nameOfFile();
#endif


/*	Determine file format from file name
**	------------------------------------
*/

#ifdef __STDC__
extern int HTFileFormat(const char * filename);
#else
extern int HTFileFormat();
#endif	


/*	Determine write access to a file
//	--------------------------------
//
// On exit,
//	return value	YES if file can be accessed and can be written to.
//
//	Isn't there a quicker way?
*/

#ifdef __STDC__
extern BOOL HTEditable(const char * filename);
#else
extern BOOL HTEditable();
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
extern int HTOpenFile(const char * addr, WWW_Format* format);
#else
extern int HTOpenFile();
#endif

