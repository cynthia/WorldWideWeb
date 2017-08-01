/*		Parse HyperText Document Address		HTParse.h
**		================================
*/
/*	These are flag bits which may be ORed together to form a number to give
**	the 'wanted' argument to HTParse.
*/
#define PARSE_ACCESS		16
#define PARSE_HOST		 8
#define PARSE_PATH		 4
#define PARSE_ANCHOR		 2
#define PARSE_PUNCTUATION	 1
#define PARSE_ALL		31

/*	Parse a Name relative to another name
**	-------------------------------------
**
**	This returns those parts of a name which are given (and requested)
**	substituting bits from the realted name where necessary.
**
** On entry,
**	aName		A filename given
**	relatedName	A name relative to ehich aName is to be parsed
**      wanted          A mask for the bits which are wanted.
**
** On exit,
**	returns		A pointer to a malloc'd string which MUST BE FREED
*/
#ifdef __STDC__
extern char * HTParse(const char * aName, const char * relatedName, int wanted);
#else
extern char * HTParse();
#endif

/*	Strip white space off a string
**	------------------------------
**
** On exit,
**	Return value points to first non-white character, or to 0 if none.
**	All trailing white space is OVERWRITTEN with zero.
*/
#ifdef __STDC__
extern char * HTStrip(char * s);
#else
extern char * HTStrip();
#endif

/*	        Simplify a filename
**		-------------------
**
**	A unix-style file is allowed to contain the seqeunce xxx/../ which
**	may be replaced by "" , and the seqeunce "/./" which may be replaced
**	by "/".
**	Simplification helps us recognize duplicate filenames. It doesn't deal
**	with soft links, though.
**	The new (shorter) filename overwrites the old.
**
**	Thus, 	/etc/junk/../fred 	becomes	/etc/fred
**		/etc/junk/./fred	becomes	/etc/junk/fred
*/
#ifdef __STDC__
extern void HTSimplify(char * filename);
#else
extern void HTSimplify();
#endif

/*		Make Relative Name
**		------------------
**
**	This function creates and returns a string which gives an expression of
**	one address as related to another. Where there is no relation, an
**	absolute address is retured.
**
**  On entry,
**	Both names must be absolute, fully qualified names of nodes
**	(no anchor bits)
**
**  On exit,
**	The return result points to a newly allocated name which, if parsed
**	by HTParse relative to relatedName, will yield aName. The caller is
**	responsible for freeing the resulting name later.
**
*/
#ifdef __STDC__
extern char * HTRelative(const char * aName, const char *relatedName);
#else
extern char * HTRelative();
#endif
