//								NewsAccess.m

// A HyperAccess object provides access to hyperinformation, using particular
//	protocols and data format transformations. This one provides access to
//	the Internet/Usenet News system using NNTP/TCP().

// History:
//	26 Sep 90	Written TBL

#define NEWS_PORT 119		/* See rfc977 */
#define APPEND			/* Use append methods */
#define MAX_CHUNK	40	/* Largest number of articles in one window */
#define CHUNK_SIZE	20	/* Optimum number of articles for quick display */

#import "NewsAccess.h"
#import <defaults/defaults.h>
#import "Anchor.h"
#import "HTParse.h"
#import "HTStyle.h"
#import <ctype.h>

extern HTStyleSheet * styleSheet;

#define NEXT_CHAR next_char()
#define LINE_LENGTH 512			/* Maximum length of line of ARTICLE etc */
#define GROUP_NAME_LENGTH	256	/* Maximum length of group name */
/*	Module parameters:
**	-----------------
**
**  These may be undefined and redefined by syspec.h
*/

#define NETCLOSE close	    /* Routine to close a TCP-IP socket		*/
#define NETREAD  read	    /* Routine to read from a TCP-IP socket	*/
#define NETWRITE write	    /* Routine to write to a TCP-IP socket	*/

#ifdef NeXT
#import <libc.h>		/* NeXT has all this packaged up */
#define ntohs(x) (x)
#define htons(x) (x)
#else
#include <string.h>		/* For bzero etc */
#include <stdio.h>

/*	TCP-specific types
*/
#include <sys/types.h>
#include <sys/socket.h>
#include <errno.h>	    /* independent */
#include <sys/time.h>	    /* independent */
extern char *malloc();
extern void free();
extern char *strncpy();
#endif

#include <netinet/in.h>
#include <arpa/inet.h>	    /* Must be after netinet/in.h */
#include <netdb.h>
#import <streams/streams.h>
#import "HTUtils.h"		/* Coding convention macros */

@implementation NewsAccess

//	Module-wide variables

static const char * NewsHost;
static struct sockaddr_in soc_address;		/* Binary network address */
static int s;					/* Socket for conn. to NewsHost */
static char response_text[LINE_LENGTH+1];	/* Last response from NewsHost */
static HyperText *	HT;			/* the new hypertext  		*/
static int	diagnostic;			/* level: 0=none 1=rtf 2=source */

static HTStyle *addressStyle;			/* For heading, from address etc */
static HTStyle *textStyle;			/* Text style */

#define INPUT_BUFFER_SIZE 4096
static char input_buffer[INPUT_BUFFER_SIZE];		/* Input buffer */
static char * input_read_pointer;
static char * input_write_pointer;


/*	Procedure: Read a character from the input stream
**	-------------------------------------------------
*/
PRIVATE char next_char(void)
{
    int status;
    if (input_read_pointer >= input_write_pointer) {
	status = read(s, input_buffer, INPUT_BUFFER_SIZE);	/*  Get some more data */
	if (status <= 0) return (char)-1;
	input_write_pointer = input_buffer + status;
	input_read_pointer = input_buffer;
    }
    return *input_read_pointer++;
}


//	Initialisaion for this class
//	----------------------------
//
//	We pick up the NewsHost name from, in order:
//
//	1.	WorldWideWeb
//	2.	Global
//	3.	News
//	4.	Defualt to cernvax.cern.ch	(!!!)

+ initialize
{
    const struct hostent  *phost;	    		/* Pointer to host - See netdb.h */
    struct sockaddr_in* sin = &soc_address;
    
/*  Set up defaults:
*/
    sin->sin_family = AF_INET;	    	/* Family = internet, host order  */
    sin->sin_port = NEWS_PORT;		    	/* Default: new port,    */

/*   Get name of Host
*/
    if ((NewsHost = NXGetDefaultValue("WorldWideWeb","NewsHost"))==0)
        if ((NewsHost = NXGetDefaultValue("News","NewsHost")) == 0)
	    NewsHost = "cernvax.cern.ch";

    if (*NewsHost>='0' && *NewsHost<='9') {   /* Numeric node address: */
	sin->sin_addr.s_addr = inet_addr((char *)NewsHost); /* See arpa/inet.h */

    } else {		    /* Alphanumeric node name: */
	phost=gethostbyname((char*)NewsHost);	/* See netdb.h */
	if (!phost) {
	    NXRunAlertPanel(NULL, "Can't find internet node name `%s'.",
	    	NULL,NULL,NULL,
		NewsHost);
	    CTRACE(tfp,
	      "NewsAccess: Can't find internet node name `%s'.\n",NewsHost);
	    return nil;  /* Fail */
	}
	memcpy(&sin->sin_addr, phost->h_addr, phost->h_length);
    }

    if (TRACE) printf( 
	"NewsAccess: Parsed address as port %4x, inet %d.%d.%d.%d\n",
		(unsigned int)ntohs(sin->sin_port),
		(int)*((unsigned char *)(&sin->sin_addr)+0),
		(int)*((unsigned char *)(&sin->sin_addr)+1),
		(int)*((unsigned char *)(&sin->sin_addr)+2),
		(int)*((unsigned char *)(&sin->sin_addr)+3));

    s=-1;		/* Disconnected */
    
    return self;
}


//	Return the name of the access
//	-----------------------------

- (const char *)name
{
    return "news";
}


//	Get Styles from stylesheet
//
static void get_styles()
{
    if (!addressStyle) addressStyle = HTStyleNamed(styleSheet, "Address");
    if (!textStyle) textStyle = HTStyleNamed(styleSheet, "Example");
}


/*	Send NNTP Command line to remote host & Check Response
**	------------------------------------------------------
**
** On entry,
**	command	points to the command to be sent, including CRLF, or is null
**		pointer if no command to be sent.
** On exit,
**	Negative status indicates transmission error, socket closed.
**	Positive status is an NNTP status.
*/


static int response(const char * command)
{
    int result;    
    char * p = response_text;
    if (command) {
        int status = write(s, command, strlen(command));
	if (status<0){
	    if (TRACE) printf(
	        "NewsAccess: Unable to send comand. Disconnecting.\n");
	    close(s);
	    s = -1;
	    return status;
	} /* if bad status */
	if (TRACE) printf("NNTP command sent: %s", command);
    } /* if command to be sent */
    
    for(;;) {  
	if (((*p++=NEXT_CHAR) == '\n') || (p == &response_text[LINE_LENGTH])) {
	    *p++=0;				/* Terminate the string */
	    if (TRACE) printf("NNTP Response: %s\n", response_text);
	    sscanf(response_text, "%i", &result);
	    return result;	    
	} /* if end of line */
	
	if (*(p-1) < 0) return -1;	/* End of file on response */
	
    } /* Loop over characters */
}


//	Case insensitive string comparisons
//	-----------------------------------
//
// On entry,
//	template must be already un upper case.
//	unknown may be in upper or lower or mixed case to match.
//
static BOOL match(const char * unknown, const char * template)
{
    const char * u = unknown;
    const char * t = template;
    for (;*u && *t && (toupper(*u)==*t); u++, t++) /* Find mismatch or end */ ;
    return (BOOL)(*t==0);		/* OK if end of template */
}

//	Find Author's name in mail address
//	----------------------------------
//
// On exit,
//	THE EMAIL ADDRESS IS CORRUPTED
//
// For example, returns "Tim Berners-Lee" if given any of
//	" Tim Berners-Lee <tim@online.cern.ch> "
//  or	" tim@online.cern.ch ( Tim Berners-Lee ) "
//
static char * author_name(char * email)
{
    char *s, *e;
    
    if ((s=index(email,'(')) && (e=index(email, ')')))
        if (e>s) {
	    *e=0;			/* Chop off everything after the ')'  */
	    return HTStrip(s+1);	/* Remove leading and trailing spaces */
	}
	
    if ((s=index(email,'<')) && (e=index(email, '>')))
        if (e>s) {
	    strcpy(s, e+1);		/* Remove <...> */
	    return HTStrip(email);	/* Remove leading and trailing spaces */
	}
	
    return HTStrip(email);		/* Default to the whole thing */
    

}


/*	Paste in an Anchor
**	------------------
**
**
** On entry,
**	HT 	has a selection of zero length at the end.
**	text 	points to the text to be put into the file, 0 terminated.
**	addr	points to the hypertext refernce address,
**		terminated by white space, comma, NULL or '>' 
*/
static void write_anchor(const char * text, const char * addr)
{
    char href[LINE_LENGTH+1];
		
    {
    	const char * p;
	strcpy(href,"news:");
	for(p=addr; *p && (*p!='>') && !WHITE(*p) && (*p!=','); p++);
        strncat(href, addr, p-addr);		/* Make complete hypertext reference */
    }
    
    [HT appendBeginAnchor:"" to:href];
    [HT appendText:text];
    [HT appendEndAnchor];
}

/*	Write list of anchors
**	---------------------
**
**	We take a pointer to a list of objects, and write out each,
**	generating an anchor for each.
**
** On entry,
**	HT 	has a selection of zero length at the end.
**	text 	points to a comma or space separated list of addresses.
** On exit,
**	*text	is NOT any more chopped up into substrings.
*/
static void write_anchors(char * text)
{
    char * start = text;
    char * end;
    char c;
    for (;;) {
        for(;*start && (WHITE(*start)); start++);  /* Find start */
	if (!*start) return;						/* (Done) */
        for(end=start; *end && (*end!=' ') && (*end!=','); end++);	/* Find end */
	if (*end) end++;		/* Include comma or space but not NULL */
	c = *end;
	*end = 0;
	write_anchor(start, start);
	*end = c;
	start = end;			/* Point to next one */
    }
}

/*	Read in an Article
**	------------------
*/
//
//	Note the termination condition of a single dot on a line by itself.
//	RFC 977 specifies that the line "folding" of RFC850 is not used, so we
//	do not handle it here.
        
static void read_article()
{

    char line[LINE_LENGTH+1];
    char *references=NULL;			/* Hrefs for other articles */
    char *newsgroups=NULL;			/* Newsgroups list */
    char *p = line;
    BOOL done = NO;
    
/*	Read in the HEADer of the article:
**
**	The header fields are either ignored, or formatted and put into the
**	 Text.
*/
    if (diagnostic!=2)
#ifdef APPEND
    [HT appendStyle:addressStyle];
#else
    [HT applyStyle:addressStyle];
#endif
    while(!done){
	if (((*p++=NEXT_CHAR) == '\n') || (p == &line[LINE_LENGTH])) {
	    *--p=0;				/* Terminate the string */
	    if (TRACE) printf("H %s\n", line);
	    if (line[0]=='.') {	
		if (line[1]<' ') {		/* End of article? */
		    done = YES;
		    break;
		}
	    
	    } else if (line[0]<' ') {
		break;		/* End of Header? */
	    } else if (match(line, "SUBJECT:")) {
		[HT setTitle:line+8];
	    } else if (match(line, "DATE:")
		   || match(line, "FROM:")
		   || match(line, "ORGANIZATION:")) {
		strcat(line, "\n");
#ifdef APPEND
		[HT appendText:index(line,':')+1];
#else
		[HT replaceSel:index(line,':')+1 style:addressStyle];
#endif		
	    } else if (match(line, "NEWSGROUPS:")) {
		StrAllocCopy(newsgroups, HTStrip(index(line,':')+1));
		
	    } else if (match(line, "REFERENCES:")) {
		StrAllocCopy(references, HTStrip(index(line,':')+1));
		
	    } /* end if match */
	    p = line;			/* Restart at beginning */
	} /* if end of line */
    } /* Loop over characters */

#ifdef APPEND
    [HT appendText:"\n"];
    [HT appendStyle:textStyle];
#else
    [HT replaceSel:"\n" style:addressStyle];
#endif    

    if (newsgroups) {
	[HT appendText: "\nNewsgroups: "];
	write_anchors(newsgroups);
	free(newsgroups);
    }
    
    if (references) {
	[HT appendText: "\nReferences: "];
	write_anchors(references);
	free(references);
    }

	[HT appendText: "\n\n\n"];

//	Read in the BODY of the Article:
//
    p = line;
    while(!done){
	if (((*p++=NEXT_CHAR) == '\n') || (p == &line[LINE_LENGTH])) {
	    *p++=0;				/* Terminate the string */
	    if (TRACE) printf("B %s", line);
	    if (line[0]=='.') {
		if (line[1]<' ') {		/* End of article? */
		    done = YES;
		    break;
		} else {			/* Line starts with dot */
		    [HT appendText: &line[1]];	/* Ignore first dot */
		}
	    } else {

/*	Normal lines are scanned for buried references to other articles.
**	Unfortunately, it will pick up mail addresses as well!
*/
		char *l = line;
		char * p;
		while (p=index(l, '<')) {
		    char *q=index(l,'>');
		    if (q>p && index(p,'@')) {
		        char c = q[1];
			q[1] = 0;		/* chop up */
			*p = 0;
			[HT appendText:l];
			*p = '<'; 		/* again */
			*q = 0;
			[HT appendBeginAnchor:"" to:p+1];
			*q = '>'; 		/* again */
			[HT appendText:p];
			[HT appendEndAnchor];
			q[1] = c;		/* again */
			l=q+1;
		    } else break;		/* line has unmatched <> */
		} 
		[HT appendText: l];		/* Last bit of the line */
	    } /* if not dot */
	    p = line;				/* Restart at beginning */
	} /* if end of line */
    } /* Loop over characters */
}


/*	Read in a List of Newsgroups
**	----------------------------
*/
//
//	Note the termination condition of a single dot on a line by itself.
//	RFC 977 specifies that the line "folding" of RFC850 is not used, so we
//	do not handle it here.
        
static void read_list()
{

    char line[LINE_LENGTH+1];
    char *p;
    BOOL done = NO;
    
/*	Read in the HEADer of the article:
**
**	The header fields are either ignored, or formatted and put into the
**	Text.
*/
#ifdef APPEND
    [HT appendText: "\nNewsgroups:\n\n"];	/* Should be haeding style */
#else
    [HT replaceSel:"\nNewsgroups:\n\n" style:textStyle];	/* Should be heading */
#endif  
    p = line;
    while(!done){
	if (((*p++=NEXT_CHAR) == '\n') || (p == &line[LINE_LENGTH])) {
	    *p++=0;				/* Terminate the string */
	    if (TRACE) printf("B %s", line);
	    if (line[0]=='.') {
		if (line[1]<' ') {		/* End of article? */
		    done = YES;
		    break;
		} else {			/* Line starts with dot */
#ifdef APPEND
		    [HT appendText: &line[1]];
#else
		    [HT replaceSel:&line[1] style:textStyle];	/* Ignore first dot */
#endif
		}
	    } else {

/*	Normal lines are scanned for references to newsgroups.
*/
		char group[LINE_LENGTH];
		int first, last;
		char postable;
		if (sscanf(line, "%s %i %i %c", group, &first, &last, &postable)==4)
		    write_anchor(line, group);
		else
#ifdef APPEND
		    [HT appendText:line];
#else
		    [HT replaceSel:line style:textStyle];
#endif
	    } /* if not dot */
	    p = line;			/* Restart at beginning */
	} /* if end of line */
    } /* Loop over characters */
}


/*	Read in a Newsgroup
**	-------------------
**	Unfortunately, we have to ask for each article one by one if we want more
**	than one field.
**
*/
void read_group(const char * groupName, int first_required, int last_required)
{
    char line[LINE_LENGTH+1];
    char author[LINE_LENGTH+1];
    char subject[LINE_LENGTH+1];
    char *p;
    BOOL done;

    char buffer[LINE_LENGTH];
    char *reference=0;			/* Href for article */
    int art;				/* Article number WITHIN GROUP */
    int status, count, first, last;	/* Response fields */
					/* count is only an upper limit */

    sscanf(response_text, " %i %i %i %i", &status, &count, &first, &last);
    if(TRACE) printf("Newsgroup status=%i, count=%i, (%i-%i) required:(%i-%i)\n",
    			status, count, first, last, first_required, last_required);
    if (last==0) {
        [HT appendText: "\nNo articles in this group.\n"];
	return;
    }
    
#define FAST_THRESHOLD 100	/* Above this, read IDs fast */
#define CHOP_THRESHOLD 50	/* Above this, chop off the rest */

    if (first_required<first) first_required = first;		/* clip */
    if ((last_required==0) || (last_required > last)) last_required = last;
    
    if (last_required<=first_required) {
        [HT appendText: "\nNo articles in this range.\n"];
	return;
    }

    if (last_required-first_required+1 > MAX_CHUNK) {	/* Trim this block */
        first_required = last_required-CHUNK_SIZE+1;
    }
    if (TRACE) printf ("    Chunk will be (%i-%i)\n", first_required, last_required);

/*	Link to earlier articles
*/
    if (first_required>first) {
    	int before;			/* Start of one before */
	if (first_required-MAX_CHUNK <= first) before = first;
	else before = first_required-CHUNK_SIZE;
    	sprintf(buffer, "%s/%i-%i", groupName, before, first_required-1);
	if (TRACE) printf("    Block before is %s\n", buffer);
	[HT appendBeginAnchor:"" to:buffer];
	[HT appendText: " (Earlier articles...)\n\n"];
	[HT appendEndAnchor];
    }
    
    done = NO;

/*#define USE_XHDR*/
#ifdef USE_XHDR
    if (count>FAST_THRESHOLD)  {
        sprintf(buffer,
	"\nThere are about %i articles currently available in %s, IDs as follows:\n\n",
		count, groupName); 
        [HT appendText:buffer];
        anchor_start = [HT textLength];
        sprintf(buffer, "XHDR Message-ID %i-%i\n", first, last);
	status = response(buffer);
	if (status==221) {

	    p = line;
	    while(!done){
		if (((*p++=NEXT_CHAR) == '\n') || (p == &line[LINE_LENGTH])) {
		    *p++=0;				/* Terminate the string */
		    if (TRACE) printf("X %s", line);
		    if (line[0]=='.') {
			if (line[1]<' ') {		/* End of article? */
			    done = YES;
			    break;
			} else {			/* Line starts with dot */
			    	/* Ignore strange line */
			}
		    } else {
	
	/*	Normal lines are scanned for references to articles.
	*/
			char * space = strchr(line, ' ');
			if (space++)
			    write_anchor(space, space);
		    } /* if not dot */
		    p = line;			/* Restart at beginning */
		} /* if end of line */
	    } /* Loop over characters */

	    /* leaving loop with "done" set */
	} /* Good status */
    };
#endif

/*	Read newsgroup using individual fields:
*/
    if (!done) {
        if (first==first_required && last==last_required)
		[HT appendText:"\nAll available articles:\n\n"];
        else [HT appendText: "\nArticles:\n\n"];
	for(art=first_required; art<=last_required; art++) {
    
/*#define OVERLAP*/
#ifdef OVERLAP
/*	With this code we try to keep the server running flat out by queuing just
**	one extra command ahead of time. We assume (1) that the server won't abort if
**	it get input during output, and (2) that TCP buffering is enough for the
**	two commands. Both these assumptions seem very reasonable. However, we HAVE had
**	a hangup with a loaded server.
*/
	    if (art==first_required) {
		if (art==last_required) {
			sprintf(buffer, "HEAD %i\n", art);	/* Only one */
			status = response(buffer);
		    } else {					/* First of many */
			sprintf(buffer, "HEAD %i\nHEAD %i\n", art, art+1);
			status = response(buffer);
		    }
	    } else if (art==last_required) {			/* Last of many */
		    status = response(NULL);
	    } else {						/* Middle of many */
		    sprintf(buffer, "HEAD %i\n", art+1);
		    status = response(buffer);
	    }
#else
	    sprintf(buffer, "HEAD %i\n", art);
	    status = response(buffer);
#endif
	    if (status == 221) {	/* Head follows - parse it:*/
    
		p = line;				/* Write pointer */
		done = NO;
		while(!done){
		    if (   ((*p++=NEXT_CHAR) == '\n')
			|| (p == &line[LINE_LENGTH]) ) {
		    
			*--p=0;			/* Terminate  & chop LF*/
			p = line;			/* Restart at beginning */
			if (TRACE) printf("G %s\n", line);
			switch(line[0]) {
    
			case '.':
			    done = (line[1]<' ');		/* End of article? */
			    break;
    
			case 'S':
			case 's':
			    if (match(line, "SUBJECT:"))
				strcpy(subject, line+8);	/* Save author */
			    break;
    
			case 'M':
			case 'm':
			    if (match(line, "MESSAGE-ID:")) {
				char * addr = HTStrip(line+11) +1;	/* Chop < */
				addr[strlen(addr)-1]=0;		/* Chop > */
				StrAllocCopy(reference, addr);
			    }
			    break;
    
			case 'f':
			case 'F':
			    if (match(line, "FROM:"))
				strcpy(author, author_name(index(line,':')+1));
			    break;
				    
			} /* end switch on first character */
		    } /* if end of line */
		} /* Loop over characters */
    
		sprintf(buffer, "\"%s\" - %s\n", subject, author);
		if (reference) {
		    write_anchor(buffer, reference);
		    free(reference);
		    reference=0;
		} else {
		    [HT appendText:buffer];
		}
		
    
/*	Change the title bar to indicate progress!
*/
		if (art%10 == 0) {
		    sprintf(buffer, "Reading newsgroup %s,  Article %i (of %i-%i) ...",
			    groupName, art, first, last);
		    [HT setTitle:buffer];
		}
    
	    } /* If good response */
	} /* Loop over article */	    
    } /* If read headers */
    
/*	Link to later articles
*/
    if (last_required<last) {
    	int after;			/* End of article after */
	after = last_required+CHUNK_SIZE;
    	if (after==last) sprintf(buffer, "news:%s", groupName);	/* original group */
    	else sprintf(buffer, "news:%s/%i-%i", groupName, last_required+1, after);
	if (TRACE) printf("    Block after is %s\n", buffer);
	[HT appendBeginAnchor:"" to:buffer];
	[HT appendText: "\n(Later articles...)\n"];
	[HT appendEndAnchor];
    }
    
/*	Set window title
*/
    sprintf(buffer, "Newsgroup %s,  Articles %i-%i",
    		groupName, first_required, last_required);
    [HT setTitle:buffer];

}


//	Open by name					-accessName:anchor:diagnostic:
//	------------
	
- accessName:(const char *)arg
	anchor:(Anchor *)anAnchor
	diagnostic:(int)diag
{
    char command[257];			/* The whole command */
    char groupName[GROUP_NAME_LENGTH];	/* Just the group name */
    int status;				/* tcp return */
    int retries;			/* A count of how hard we have tried */ 
    BOOL group_wanted;			/* Flag: group was asked for, not article */
    BOOL list_wanted;			/* Flag: group was asked for, not article */
    int first, last;			/* First and last articles asked for */

    diagnostic = diag;			/* set global flag */
    
    if (TRACE) printf("NewsAccess: Looking for %s\n", arg);
    get_styles();
    {
        char * p1;

/*	We will ask for the document, omitting the host name & anchor.
**
**	Syntax of address is
**		xxx@yyy			Article
**		<xxx@yyy>		Same article
**		xxxxx			News group (no "@")
*/        
	group_wanted = (index(arg, '@')==0) && (index(arg, '*')==0);
	list_wanted  = (index(arg, '@')==0) && (index(arg, '*')!=0);
	
	p1 = HTParse(arg, "", PARSE_PATH|PARSE_PUNCTUATION);
	if (list_wanted) {
	    strcpy(command, "LIST ");
	} else if (group_wanted) {
	    char * slash = strchr(p1, '/');
	    strcpy(command, "GROUP ");
	    first = 0;
	    last = 0;
	    if (slash) {
		*slash = 0;
		strcpy(groupName, p1);
		*slash = '/';
		(void) sscanf(slash+1, "%i-%i", &first, &last);
	    } else {
		strcpy(groupName, p1);
	    }
	    strcat(command, groupName);
	} else {
	    strcpy(command, "ARTICLE ");
	    if (index(p1, '<')==0) strcat(command,"<");
	    strcat(command, p1);
	    if (index(p1, '>')==0) strcat(command,">");
	}
	free(p1);

        strcat(command, "\r\n");		/* CR LF, as in rfc 977 */
	
    } /* scope of p1 */
    
    if (!*arg) return nil;			// Ignore if no name

    
//	Make a hypertext object with an anchor list.
        
    HT = [HyperText newAnchor:anAnchor Server:self];

    [HT setupWindow];			
    [HT selectText:self];		/* Replace everything with what's to come */
	
//	Now, let's get a stream setup up from the NewsHost:
        
    for(retries=0;retries<2; retries++){
    
        if (s<0) {
    	    [[HT window]setTitle:"Connecting to NewsHost ..."];	/* Tell user  */
	    s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	    status = connect(s, (struct sockaddr*)&soc_address, sizeof(soc_address));
	    if (status<0){
		char message[256];
	        close(s);
		s=-1;
		if (TRACE) printf("NewsAccess: Unable to connect to news host.\n");
/*		if (retries<=1) continue;   WHY TRY AGAIN ? 	*/
		NXRunAlertPanel(NULL,
    		    "Could not access newshost %s.",
		    NULL,NULL,NULL,
		    NewsHost);
		sprintf(message,
"\nCould not access %s.\n\n (Check default WorldWideWeb NewsHost ?)\n",
		    NewsHost);
		[HT setText:message];
		return HT;
	    } else {
		if (TRACE) printf("NewsAccess: Connected to news host %s.\n",
				NewsHost);
		if ((response(NULL) / 100) !=2) {
			close(s);
			s=-1;
			NXRunAlertPanel("News access",
			    "Could not retrieve information:\n   %s.",
			    NULL,NULL,NULL,
			    response_text);
    			[[HT window]setTitle: "News host response"];
			[HT setText:response_text];
			return HT;
		}
	    }
	} /* If needed opening */
	
        [[HT window]setTitle:arg];		/* Tell user something's happening */
	status = response(command);
	if (status<0) break;
	if ((status/ 100) !=2) {
	    NXRunAlertPanel("News access", response_text,
	    	NULL,NULL,NULL);
	    [HT setText:response_text];
	    close(s);
	    s=-1;
	    // return HT; -- no:the message might be "Timeout-disconnected" left over
	    continue;	//	Try again
	}
  
//	Load a group, article, etc
//
        [HT appendBegin];
	
	if (list_wanted) read_list();
	else if (group_wanted) read_group(groupName, first, last);
        else read_article();

	[HT appendEnd];

    	[HT setEditable:NO];		/* This is read-only data */
	[HT adjustWindow];
	return HT;
	
    } /* Retry loop */
    
    [HT setText:"Sorry, could not load requested news.\n"];
    
/*    NXRunAlertPanel(NULL, "Sorry, could not load `%s'.",
	    	NULL,NULL,NULL, arg);	No -- message earlier wil have covered it */
    return HT;
}

//		Actions:
//		=======


//	This will load an anchor which has a name
//	-----------------------------------------
//
// On entry,
//	Anchor's address is valid.
// On exit:
//	If there is no success, nil is returned.
//	Otherwise, the anchor is returned.
//

- loadAnchor: (Anchor *) a Diagnostic:(int)diagnostic
{
    HyperText * HT;

    if (![a node]) {
        HT = [self accessName:[a address] anchor:a diagnostic:diagnostic];
    	if (!HT) return nil;
	[[HT window] setDocEdited:NO];
    }
    return a;
}
@end
