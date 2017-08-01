/*			File Transfer Protocol (FTP) Client
**			for a WorldWideWeb browser
**			===================================
**
**	A cache of control connections is kept.
**
** Note: Port allocation
**
**	It is essential that the port is allocated by the system, rather
**	than chosen in rotation by us (POLL_PORTS), or the following
**	problem occurs.
**
**	It seems that an attempt by the server to connect to a port which has
**	been used recently by a listen on the same socket, or by another
**	socket this or another process causes a hangup of (almost exactly)
**	one minute. Therefore, we have to use a rotating port number.
**	The problem remians that if the application is run twice in quick
**	succession, it will hang for what remains of a minute.
**
** History:
**	 2 May 91	Written TBL, as a part of the WorldWideWeb project.
**
** Options:
**	LISTEN		We listen, the other guy connects for data.
**			Otherwise, other way round, but problem finding our
**			internet address!
*/

#define LISTEN		/* @@@@ Test */

/*
BUGS:	@@@  	Limit connection cache size!
		400 errors should cause drop connection.
		Error reporting to user.
		400 & 500 errors are acked by user with windows.
		Use configuration file for user names
		Prompt user for password
		
**		Note for portablility this version does not use select() and
**		so does not watch the control and data channels at the
**		same time.
*/		

#define REPEAT_PORT	/* Give the port number for each file */
#define REPEAT_LISTEN	/* Close each listen socket and open a new one */

#ifndef IPPORT_FTP
#define IPPORT_FTP	21
#endif
/* define POLL_PORTS		 If allocation does not work, poll ourselves.*/
#define LISTEN_BACKLOG 2	/* Number of pending connect requests (TCP)*/

#define FIRST_TCP_PORT	1024	/* Region to try for a listening port */
#define LAST_TCP_PORT	5999	

#define LINE_LENGTH 256
#define COMMAND_LENGTH 256

#include "HTParse.h"
#include "HTUtils.h"
#include "tcp.h"
#include "HTTCP.h"

#ifdef REMOVED_CODE
extern char *malloc();
extern void free();
extern char *strncpy();
#endif

typedef struct _connection {
    struct _connection *	next;	/* Link on list 	*/
    u_long			addr;	/* IP address		*/
    int				socket;	/* Socket number for communication */
} connection;

#ifndef NIL
#define NIL 0
#endif


/*	Module-Wide Variables
**	---------------------
*/
PRIVATE connection * connections =0;	/* Linked list of connections */
PRIVATE char    response_text[LINE_LENGTH+1];/* Last response from NewsHost */
PRIVATE connection * control;		/* Current connection */
PRIVATE int	data_soc;		/* Socket for data transfer */

#ifdef POLL_PORTS
PRIVATE	unsigned short	port_number = FIRST_TCP_PORT;
#endif

#ifdef LISTEN
PRIVATE int     master_socket = -1;	/* Listening socket = invalid	*/
PRIVATE char	port_command[255];	/* Command for setting the port */
PRIVATE fd_set	open_sockets; 		/* Mask of active channels */
PRIVATE int	num_sockets;  		/* Number of sockets to scan */
#else
PRIVATE	unsigned short	passive_port;	/* Port server specified for data */
#endif


#define INPUT_BUFFER_SIZE 4096
PRIVATE char input_buffer[INPUT_BUFFER_SIZE];		/* Input buffer */
PRIVATE char * input_read_pointer;
PRIVATE char * input_write_pointer;
#define NEXT_CHAR next_char()



/*	Procedure: Read a character from the control connection
**	-------------------------------------------------------
*/
#ifdef __STDC__
PRIVATE char next_char(void)
#else
PRIVATE char next_char()
#endif
{
    int status;
    if (input_read_pointer >= input_write_pointer) {
	status = NETREAD(control->socket, input_buffer, INPUT_BUFFER_SIZE);	/*  Get some more data */
	if (status <= 0) return (char)-1;
	input_write_pointer = input_buffer + status;
	input_read_pointer = input_buffer;
    }
#ifdef NOT_ASCII
    {
        char c = *input_read_pointer++;
	return FROMASCII(c);
    }
#else
    return *input_read_pointer++;
#endif
}


/*	Execute Command and get Response
**	--------------------------------
**
**	See the state machine illustrated in RFC959, p57. This implements
**	one command/reply sequence.  It also interprets lines which are to
**	be continued, which are marked with a "-" immediately after the
**	status code.
**
** On entry,
**	con	points to the connection which is established.
**	cmd	points to a command, or is NIL to just get the response.
**
**	The command is terminated with the CRLF pair.
**
** On exit,
**	returns:  The first digit of the reply type,
**		  or negative for failure.
*/
#ifdef __STDC__
PRIVATE int response(char * cmd)
#else
PRIVATE int response(cmd)
    char * cmd;
#endif
{
    int result;				/* Three-digit decimal code */
    char	continuation;
    int status;
    if (cmd) {
    
	if (TRACE) printf("  Tx: %s", cmd);

#ifdef NOT_ASCII
	{
	    char * p;
	    for(p=cmd; *p; p++) {
	        *p = TOASCII(*p);
	    }
	}
#endif 
	status = NETWRITE(control->socket, cmd, strlen(cmd));
	if (status<0) {
	    if (TRACE) printf("FTP: Error %d sending command",
		status);
	    return status;
	}
    }

    do {
	char *p = response_text;
	for(;;) {  
	    if (((*p++=NEXT_CHAR) == '\n')
			|| (p == &response_text[LINE_LENGTH])) {
		*p++=0;			/* Terminate the string */
		if (TRACE) printf("    Rx: %s", response_text);
		sscanf(response_text, "%d%c", &result, &continuation);
		break;	    
	    } /* if end of line */
	    
	    if (*(p-1) < 0) return -1;	/* End of file on response */
	    
	} /* Loop over characters */

    } while (continuation == '-');
    
    return result/100;
}


/*	Close an individual connection
**
*/
#ifdef TEST		/* use later when cache is limited! */
#ifdef __STDC__
PRIVATE int close_connection(connection * con)
#else
PRIVATE int close_connection(con)
    connection *con;
#endif
{
    connection * scan;
    int status = NETCLOSE(con->socket);
    if (TRACE) printf("FTP: Closing control socket %d\n", con->socket);
    if (connections==con) {
        connections = con->next;
	return status;
    }
    for(scan=connections; scan; scan=scan->next) {
        if (scan->next == con) {
	    scan->next = con->next;	/* Unlink */
	    return status;
	} /*if */
    } /* for */
    return -1;		/* very strange -- was not on list. */
}
#endif /* TEST */

/*	Get a valid connection to the host
**	----------------------------------
**
** On entry,
**	arg	points to the name of the host in a hypertext address
** On exit,
**	returns	<0 if error
**		socket number if success
**
**	This routine takes care of managing timed-out connections, and
**	limiting the number of connections in use at any one time.
**
**	It ensures that all connections are logged in if they exist.
**	It ensures they have the port number transferred.
*/
#ifdef __STDC__
PRIVATE int get_connection(const char * arg)
#else
PRIVATE int get_connection(arg)
	char * arg;
#endif

{
    struct hostent * phost;		/* Pointer to host -- See netdb.h */
    struct sockaddr_in soc_address;	/* Binary network address */
    struct sockaddr_in* sin = &soc_address;
    if (!arg) return -1;		/* Bad if no name sepcified	*/
    if (!*arg) return -1;		/* Bad if name had zero length	*/

/*  Set up defaults:
*/
    sin->sin_family = AF_INET;	    		/* Family, host order  */
    sin->sin_port = htons(IPPORT_FTP);	    	/* Well Known Number    */

    if (TRACE) printf("FTP: Looking for %s\n", arg);

/* Get node name:
*/
    {
	char *p1 = HTParse(arg, "", PARSE_HOST);
	
	if (*p1>='0' && *p1<='9') {   /* Numeric node address: */
	    sin->sin_addr.s_addr = inet_addr(p1); /* See arpa/inet.h */

	} else {		    /* Alphanumeric node name: */
	    phost=gethostbyname(p1);	/* See netdb.h */
	    if (!phost) {
		if (TRACE) printf(
			"FTP: Can't find internet node name `%s'.\n",
			p1);
		return -3;  /* Fail? */
	    }
	    memcpy(&sin->sin_addr, phost->h_addr, phost->h_length);
	}

	if (TRACE) printf( 
	    "FTP: Parsed remote address as port %d, inet %d.%d.%d.%d\n",
		    (unsigned int)ntohs(sin->sin_port),
		    (int)*((unsigned char *)(&sin->sin_addr)+0),
		    (int)*((unsigned char *)(&sin->sin_addr)+1),
		    (int)*((unsigned char *)(&sin->sin_addr)+2),
		    (int)*((unsigned char *)(&sin->sin_addr)+3));
        free(p1);
    } /* scope of p1 */

    input_read_pointer = input_write_pointer = input_buffer;
    
/*	Now we check whether we already have a connection to that port.
*/

    {
	connection * scan;
	for (scan=connections; scan; scan=scan->next) {
	    if (sin->sin_addr.s_addr == scan->addr) {
	  	if (TRACE) printf(
		"FTP: Already have connection for %d.%d.%d.%d.\n",
		    (int)*((unsigned char *)(&scan->addr)+0),
		    (int)*((unsigned char *)(&scan->addr)+1),
		    (int)*((unsigned char *)(&scan->addr)+2),
		    (int)*((unsigned char *)(&scan->addr)+3));
		return scan->socket;		/* Good return */
	    } else {
	  	if (TRACE) printf(
		"FTP: Existing connection is %d.%d.%d.%d\n",
		    (int)*((unsigned char *)(&scan->addr)+0),
		    (int)*((unsigned char *)(&scan->addr)+1),
		    (int)*((unsigned char *)(&scan->addr)+2),
		    (int)*((unsigned char *)(&scan->addr)+3));
	    }
	}
    }

   
/*	Now, let's get a socket set up from the server:
*/      
    {
        int status;
	connection * con = (connection *)malloc(sizeof(*con));
	con->addr = sin->sin_addr.s_addr;	/* save it */
	status = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (status<0) {
	    (void) HTInetStatus("socket");
	    free(con);
	    return status;
	}
	con->socket = status;

    	status = connect(con->socket, (struct sockaddr*)&soc_address,
	 sizeof(soc_address));
        if (status<0){
	    (void) HTInetStatus("connect");
	    if (TRACE) printf(
	    	"FTP: Unable to connect to remote host for `%s'.\n",
	    	arg);
	    NETCLOSE(con->socket);
	    free(con);
	    return status;			/* Bad return */
	}
	
	if (TRACE) printf("FTP connected, socket %d\n", con->socket);
	control = con;			/* Current control connection */


/*	Now we log in		@@@ Look up username, prompt for pw.
*/
	{
	    int status = response(NIL);	/* Get greeting */
	    if (status == 2) status = response("USER anonymous\r\n");
	    if (status == 3) {
	        char * command = (char*)malloc(10+strlen(HTHostName())+2+1);
		sprintf(command, "PASS user@%s\r\n", HTHostName()); /*@@*/
	        status = response(command);
		free(command);
	    }
	    if (status == 3) status = response("ACCT noaccount\r\n");
	    if (status !=2) {
	        if (TRACE) printf("FTP: Login fail: %s", response_text);
	    	NETCLOSE(con->socket);
		free(con);
	        return -status;		/* Bad return */
	    }
	    if (TRACE) printf("FTP: Logged in.\n");
	}

/*	Now we inform the server of the port number we will listen on
*/
#ifndef REPEAT_PORT
	{
	    int status = response(port_command);
	    if (status !=2) {
	    	NETCLOSE(con->socket);
		free(con);
	        return -status;		/* Bad return */
	    }
	    if (TRACE) printf("FTP: Port defined.\n");
	}
#endif
	con->next = connections;	/* Link onto list of good ones */
	connections = con;
	return con->socket;			/* Good return */
    } /* Scope of con */
}


#ifdef LISTEN

/*	Close Master (listening) socket
**	-------------------------------
**
**
*/
#ifdef __STDC__
PRIVATE int close_master_socket(void)
#else
PRIVATE int close_master_socket()
#endif
{
    int status;
    FD_CLR(master_socket, &open_sockets);
    status = close(master_socket);
    if (TRACE) printf("FTP: Closed master socket %d\n", master_socket);
    master_socket = -1;
    if (status<0) return HTInetStatus("close master socket");
    else return status;
}


/*	Open a master socket for listening on
**	-------------------------------------
**
**	When data is transferred, we open a port, and wait for the server to
**	connect with the data.
**
** On entry,
**	master_socket	Must be negative if not set up already.
** On exit,
**	Returns		socket number if good
**			less than zero if error.
**	master_socket	is socket number if good, else negative.
**	port_number	is valid if good.
*/
#ifdef __STDC__
PRIVATE int get_listen_socket(void)
#else
PRIVATE int get_listen_socket()
#endif
{
    struct sockaddr_in soc_address;	/* Binary network address */
    struct sockaddr_in* sin = &soc_address;
    int new_socket;			/* Will be master_socket */
    
    
    FD_ZERO(&open_sockets);	/* Clear our record of open sockets */
    num_sockets = 0;
    
#ifndef REPEAT_LISTEN
    if (master_socket>=0) return master_socket;  /* Done already */
#endif

/*  Create internet socket
*/
    new_socket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	
    if (new_socket<0)
	return HTInetStatus("socket for master socket");
    
    if (TRACE) printf("FTP: Opened master socket number %d\n", new_socket);
    
/*  Search for a free port.
*/
    sin->sin_family = AF_INET;	    /* Family = internet, host order  */
    sin->sin_addr.s_addr = INADDR_ANY; /* Any peer address */
#ifdef POLL_PORTS
    {
        unsigned short old_port_number = port_number;
	for(port_number=old_port_number+1;;port_number++){ 
	    int status;
	    if (port_number > LAST_TCP_PORT)
		port_number = FIRST_TCP_PORT;
	    if (port_number == old_port_number) {
		return HTInetStatus("bind");
	    }
	    soc_address.sin_port = htons(port_number);
	    if ((status=bind(new_socket,
		    (struct sockaddr*)&soc_address,
			    /* Cast to generic sockaddr */
		    sizeof(soc_address))) == 0)
		break;
	    if (TRACE) printf(
	    	"TCP bind attempt to port %d yields %d, errno=%d\n",
		port_number, status, errno);
	} /* for */
    }
#else
    {
        int status;
	int address_length = sizeof(soc_address);
	status = getsockname(control->socket,
			(struct sockaddr *)&soc_address,
			 &address_length);
	if (status<0) return HTInetStatus("getsockname");
	CTRACE(tfp, "FTP: This host is %s\n",
	    HTInetString(sin));
	
	soc_address.sin_port = 0;	/* Unspecified: please allocate */
	status=bind(new_socket,
		(struct sockaddr*)&soc_address,
			/* Cast to generic sockaddr */
		sizeof(soc_address));
	if (status<0) return HTInetStatus("bind");
	
	address_length = sizeof(soc_address);
	status = getsockname(new_socket,
			(struct sockaddr*)&soc_address,
			&address_length);
	if (status<0) return HTInetStatus("getsockname");
    }
#endif    

    CTRACE(tfp, "FTP: bound to port %d on %s\n",
    	(unsigned int)ntohs(sin->sin_port),
	HTInetString(sin));

#ifdef REPEAT_LISTEN
    if (master_socket>=0)
        (void) close_master_socket();
#endif    
    
    master_socket = new_socket;
    
/*	Now we must find out who we are to tell the other guy
*/
    (void)HTHostName(); 	/* Make address valid - doesn't work*/
/*   memcpy(&sin->sin_addr, &HTHostAddress.sin_addr, sizeof(sin->sin_addr)); */
    sprintf(port_command, "PORT %d,%d,%d,%d,%d,%d\r\n",
		    (int)*((unsigned char *)(&sin->sin_addr)+0),
		    (int)*((unsigned char *)(&sin->sin_addr)+1),
		    (int)*((unsigned char *)(&sin->sin_addr)+2),
		    (int)*((unsigned char *)(&sin->sin_addr)+3),
		    (int)*((unsigned char *)(&sin->sin_port)+0),
		    (int)*((unsigned char *)(&sin->sin_port)+1));


/*	Inform TCP that we will accept connections
*/
    if (listen(master_socket, 1)<0) {
	master_socket = -1;
	return HTInetStatus("listen");
    }
    CTRACE(tfp, "TCP: Master socket(), bind() and listen() all OK\n");
    FD_SET(master_socket, &open_sockets);
    if ((master_socket+1) > num_sockets) num_sockets=master_socket+1;

    return master_socket;		/* Good */

} /* get_listen_socket */
#endif


/*	Retrieve File from Server
**	-------------------------
**
** On entry,
**	name		WWW address of a file: document, including hostname
** On exit,
**	returns		Socket number for file if good.
**			<0 if bad.
*/
#ifdef __STDC__
PUBLIC int HTFTP_open_file_read(CONST char * name)
#else
PUBLIC int HTFTP_open_file_read(name)
    char * name;
#endif
{
    int status = get_connection(name);
    if (status<0) return status;

#ifdef LISTEN
    status = get_listen_socket();
    if (status<0) return status;
    
#ifdef REPEAT_PORT
/*	Inform the server of the port number we will listen on
*/
    {
	int status = response(port_command);
	if (status !=2) {
	    return -status;		/* Bad return */
	}
	if (TRACE) printf("FTP: Port defined.\n");
    }
#endif
#else	/* Use PASV */
/*	Tell the server to be passive
*/
    {
	int status = response("PASV\r\n");
	char *p;
	int reply, h0, h1, h2, h3, p0, p1;	/* Parts of reply */
	if (status !=2) {
	    return -status;		/* Bad return */
	}
	for(p=response_text; *p; p++)
	    if ((*p<'0')||(*p>'9')) *p = ' ';	/* Keep only digits */
	status = sscanf(response_text, "%d%d%d%d%d%d%d",
		&reply, &h0, &h1, &h2, &h3, &p0, &p1);
	if (status<5) {
	    if (TRACE) printf("FTP: PASV reply has no inet address!\n");
	    return -99;
	}
	passive_port = (p0<<8) + p1;
	if (TRACE) printf("FTP: Server is listening on port %d\n",
		passive_port);
    }

/*	Open connection for data:
*/
    {
	struct sockaddr_in soc_address;
	int status = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (status<0) {
	    (void) HTInetStatus("socket for data socket");
	    return status;
	}
	data_soc = status;
	
	soc_address.sin_addr.s_addr = control->addr;
	soc_address.sin_port = htons(passive_port);
        soc_address.sin_family = AF_INET;	    /* Family, host order  */
	if (TRACE) printf( 
	    "FTP: Data remote address is port %d, inet %d.%d.%d.%d\n",
		    (unsigned int)ntohs(soc_address.sin_port),
		    (int)*((unsigned char *)(&soc_address.sin_addr)+0),
		    (int)*((unsigned char *)(&soc_address.sin_addr)+1),
		    (int)*((unsigned char *)(&soc_address.sin_addr)+2),
		    (int)*((unsigned char *)(&soc_address.sin_addr)+3));

    	status = connect(data_soc, (struct sockaddr*)&soc_address,
	 	sizeof(soc_address));
        if (status<0){
	    (void) HTInetStatus("connect for data");
	    NETCLOSE(data_soc);
	    return status;			/* Bad return */
	}
	
	if (TRACE) printf("FTP data connected, socket %d\n", data_soc);
    }
#endif /* use PASV */

/*	Ask for the file:
*/    
    {
        char *filename = HTParse(name, "", PARSE_PATH + PARSE_PUNCTUATION);
	char command[LINE_LENGTH+1];
	sprintf(command, "RETR %s\r\n", filename);
	status = response(command);
	free(filename);
	
	if (status!=1) return -status;		/* Action not started */
    }

#ifdef LISTEN
/*	Wait for the connection
*/    
    {
	struct sockaddr_in soc_address;
        int	soc_addrlen=sizeof(soc_address);
	status = accept(master_socket,
			(struct sockaddr *)&soc_address,
			&soc_addrlen);
	if (status<0)
	    return HTInetStatus("accept");
	CTRACE(tfp, "TCP: Accepted new socket %d\n", status);
	data_soc = status;
    }
#else
#endif
    return data_soc;
       
} /* open_file_read */

/*	Close socket opened for reading a file, and get final message
**	-------------------------------------------------------------
**
*/
#ifdef __STDC__
PUBLIC int HTFTP_close_file(int soc)
#else
PUBLIC int HTFTP_close_file(soc)
    int soc;
#endif
{
    int status;

    if (soc!=data_soc) {
        if (TRACE) printf("HTFTP: close socket %d: (not FTP data socket).\n",
		soc);
	return NETCLOSE(soc);
    }
    status = NETCLOSE(data_soc);
    if (TRACE) printf("FTP: Closing data socket %d\n", data_soc);
    if (status<0) (void) HTInetStatus("close");	/* Comment only */
    
    status = response(NIL);
    if (status!=2) return -status;
    
    data_soc = -1;	/* invalidate it */
    return status; 	/* Good */
}


/*___________________________________________________________________________
*/
/*	Test program only
**	-----------------
**
**	Compiling this with -DTEST produces a test program.
**
** Syntax:
**	test <file or option> ...
**
**	options:	-v	Verbose: Turn trace on at this point
*/
#ifdef TEST

PUBLIC int WWW_TraceFlag;

#ifdef __STDC__
int main(int argc, char*argv[])
#else
int main(argc, argv)
	int argc;
	char *argv[];
#endif
{
    
    int arg;			/* Argument number */
    int status;
    connection * con;
    WWW_TraceFlag = (0==strcmp(argv[1], "-v"));	/* diagnostics ? */

#ifdef SUPRESS    
    status = get_listen_socket();
    if (TRACE) printf("get_listen_socket returns %d\n\n", status);
    if (status<0) exit(status);

    status = get_connection(argv[1]);	/* test double use */
    if (TRACE) printf("get_connection(`%s') returned %d\n\n", argv[1], status);
    if (status<0) exit(status);
#endif

    for(arg=1; arg<argc; arg++) {		/* For each argument */
         if (0==strcmp(argv[arg], "-v")) {
             WWW_TraceFlag = 1;			/* -v => Trace on */

	 } else {				/* Filename: */
	
	    status = HTTP_open_file_read(argv[arg]);
	    if (TRACE) printf("open_file_read returned %d\n\n", status);
	    if (status<0) exit(status);
		
	/*	Copy the file to std out:
	*/   
	    {
		char buffer[INPUT_BUFFER_SIZE];
		for(;;) {
		    int status = NETREAD(data_soc, buffer, INPUT_BUFFER_SIZE);
		    if (status<=0) {
			if (status<0) (void) HTInetStatus("read");
			break;
		    }
		    status = write(1, buffer, status);
		    if (status<0) {
			printf("Write failure!\n");
			break;
		    }
		}
	    }
	
	    status = HTTP_close_file(data_soc);
	    if (TRACE) printf("Close_file returned %d\n\n", status);

        } /* if */
    } /* for */
    status = response("QUIT\r\n");		/* Be good */
    if (TRACE) printf("Quit returned %d\n", status);

    while(connections) close_connection(connections);
    
    close_master_socket();
         
} /* main */
#endif  /* TEST */

