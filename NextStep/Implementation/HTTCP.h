/*			Generic Communication Code		HTTCP.h
**			==========================
**
**	Requires tcp.h to be included first.
*/
#ifdef SHORT_NAMES
#define HTInetStatus            HTInStat
#define HTInetString 		HTInStri
#define HTParseInet		HTPaInet
#endif

/*	Produce a string for an internet address
**	---------------------------------------
**
** On exit,
**	returns	a pointer to a static string which must be copied if
**		it is to be kept.
*/
#ifdef __STDC__
extern const char * HTInetString(struct sockaddr_in* sin);
#else
extern char * HTInetString();
#endif


/*	Encode INET status (as in sys/errno.h)			  inet_status()
**	------------------
**
** On entry,
**	where		gives a description of what caused the error
**	global errno	gives the error number in the unix way.
**
** On return,
**	returns		a negative status in the unix way.
*/
#ifdef __STDC__
extern int HTInetStatus(char *where);
#else
extern int HTInetStatus();
#endif

/*	Publicly accesible variables
*/
extern struct sockaddr_in HTHostAddress;/* The internet address of the host */
					/* Valid after call to HTHostName() */

/*	Parse a cardinal value				       parse_cardinal()
**	----------------------
**
** On entry,
**	*pp	    points to first character to be interpreted, terminated by
**		    non 0:9 character.
**	*pstatus    points to status already valid
**	maxvalue    gives the largest allowable value.
**
** On exit,
**	*pp	    points to first unread character
**	*pstatus    points to status updated iff bad
*/
#ifdef __STDC__
extern unsigned int HTCardinal(int *pstatus,
	char		**pp,
	unsigned int	max_value);
#else
extern unsigned int HTCardinal();
#endif

/*	Parse an internet node address and port
**	---------------------------------------
**
** On entry,
**	str	points to a string with a node name or number,
**		with optional trailing colon and port number.
**	sin	points to the binary internet address field.
**
** On exit,
**	*sin	is filled in. If no port is specified in str, that
**		field is left unchanged in *sin.
*/
#ifdef __STDC__
extern int HTParseInet(struct sockaddr_in* sin, const char *str);
#else
extern int HTParseInet();
#endif

/*	Get Name of This Machine
**	------------------------
**
*/
#ifdef __STDC__
extern const char * HTHostName(void);
#else
extern char * HTHostName();
#endif
