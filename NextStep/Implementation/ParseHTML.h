/*				FORMAT CONVERSION FROM SGML
**				===========================
**
**
**	22 Nov 92	Fixed quoting of hrefs.
**			CERN_WEIRDO ifdefed out -- proper SGML expected
**			REMOVE_SCRIPT ifdefed out -- did ignore lines starting with "."
*/

#import "HTStyle.h"

extern HTStyleSheet * styleSheet;

#ifndef NEXT_CHAR
static FILE * sgmlStream;
#define END_OF_FILE NXAtEOS(sgmlStream)		/* @@@@ */
#define NEXT_CHAR getc(sgmlStream)
#define BACK_UP	ungetc(sgmlStream)
#endif

#define upper(c) (  ((c>='a')&&(c<='z')) ? (char)((int)c-32) : c )

/*	State machine states:
*/
enum state_enum {S_text,	/* We are not in a tag				*/
#ifdef REMOVE_SCRIPT
		S_column_1,	/* as Text but first character on input line	*/
		S_dot,		/* We have had dor in first column		*/
		S_junk_script,	/* Ignore everything until NL or ";"		*/
#else
#define S_column_1 S_text
#endif
		S_word,		/* We have just had a non-white printable 	*/
		S_tag_start,	/* We have just had "<"				*/
		S_tag_h,
		S_tag_a, S_end_a,
		S_tag_d, S_end_d,
		S_tag_i,
		S_tag_l, S_tag_lis,
		S_tag_n,
		S_tag_o, S_end_o,
		S_tag_p,
		S_tag_u, S_end_u,
		S_tag_end,	/* We have just had "</"			*/
		S_restoffile,
		S_end_h, 
		S_title,
		S_anchor, S_href, S_href_quoted, S_href_unquoted, S_aname,
		S_junk_tag,	/* Ignore everything until ">"			*/
#ifdef CERN_WEIRDO
		S_junk_line,	/* Ignore everything until "\n"			*/
#endif
		S_done};

typedef struct _SGML_style {
    char *	start_tag;	/* Tag to mark start of a style 	*/
    char *	paragraph_tag;	/* Tag to mark paragraph mark within style */
    char *	tab_tag;	/* Tag to mark tab within style 	*/
    char *	end_tag;	/* Tag to mark end of style 		*/
    char *	start_text;	/* Text conventionally starting this style */
    char *	paragraph_text;	/* Text used as a paragraph mark within style*/
    char *	end_text;	/* Text used to end a style 		*/
    HTStyle *	style;		/* Paragraph style to be used 		*/
    int		free_format;	/* Flag: are line ends word breaks only? */
    int		litteral;	/* Flag: end only at close tag (cheat) ? */
} SGML_style;

/*	Stack of previous styles:
*/
typedef struct _NestedStyle {
	struct _NestedStyle *	next;		/* previously nested style or 0 */
	SGML_style * 		SGML;		/* SGML style interrupted */
} NestedStyle;

/*				MODULE-WIDE DATA
**
**
*/

/*	We delay changing style until necessary to avoid dummy style changes
**	resulting in too many extra newlines.
*/
static SGML_style * current_style;	/* The current output style */
static SGML_style * next_style;		/* The next style to go into */

static NestedStyle * styleStack;
static int output_in_word;		/* Flag: Last character ouput was non-white */

/*	Paragraph Styles used by the SGML parser:
**	----------------------------------------
*/

static SGML_style	Normal =
	{ "", "<P>\n", "\t", "",
	 "","", "", 0 ,1, 0};
	
static SGML_style	Heading[6] = {
	{ "\n<H1>", "</H1>\n<H1>", "\t", "</H1>", "", "", "", 0, 1, 0},
	{ "\n<H2>", "</H2>\n<H2>", "\t", "</H2>", "", "", "", 0, 1, 0},
	{ "\n<H3>", "</H3>\n<H3>", "\t", "</H3>", "", "", "", 0, 1, 0},
	{ "\n<H4>", "</H4>\n<H4>", "\t", "</H4>", "", "", "", 0, 1, 0},
	{ "\n<H5>", "</H5>\n<H5>", "\t", "</H5>", "", "", "", 0, 1, 0},
	{ "\n<H6>", "</H6>\n<H6>", "\t", "</H6>", "", "", "", 0, 1, 0}
};
	 
static SGML_style	Glossary =	/* Large hanging indent with tab */
	{ "\n<DL>\n<DT>", "\n<DT>", "\n<DD>", "\n</DL>\n",
	"", "", "", 0, 1};
	
static SGML_style	listStyle  =		/* Hanging indent with tab */
	{ "\n<UL>\n<LI>", "\n<LI>", "\t", "\n</UL>",
	"\267\t", "\267\t", "", 0, 1, 0};

static SGML_style	addressStyle =
	{ "\n<ADDRESS>", "<P>", "\t", "\n</ADDRESS>",
	"", "", "", 0, 1, 0 };
	
/*	Explicit format styles:
*/	
static SGML_style	Example =	/* Fixed width font, at least 80 chars wide */
	{ "\n<XMP>", "\n", "\t", "</XMP>",
	"", "", "", 0 , 0, 1};

static SGML_style	Preformatted =	/* Fixed width font, at least 80 chars wide */
	{ "\n<PRE>", "\n", "\t", "</PRE>",
	"", "", "", 0 , 0, 0};		/* not litteral */

static SGML_style	Fixed =	/* Fixed width font, at least 80 chars wide */
	{ "\n<FIXED>", "<P>", "\t", "</FIXED>",
	"", "", "", 0 , 1, 0};

static SGML_style	Listing =	/* Fixed width font, at least 80 chars wide */
	{ "\n<LISTING>", "\n", "\t", "</LISTING>",
	"", "", "", 0 , 0, 1};

/*	Table of all possible SGML paragraph styles
*/
static SGML_style * styleTable[] = {
	&Normal, &Heading[0], &Heading[1], &Heading[2],
	&Heading[3], &Heading[4], &Heading[5],
	&Glossary, &listStyle, &addressStyle,  &Preformatted, &Fixed, &Example, &Listing
}; /* style table */

#define NUMBER_OF_STYLES (sizeof(styleTable)/sizeof(styleTable[0]))


/*	Highlighting styles
*/
static HTStyle * Highlighting[3];

/*				F U N C T I O N S
*/


/*	Get Styles from style sheet
**	---------------------------
*/
void get_styles()
{
    Normal.style =		HTStyleNamed(styleSheet, "Normal");
    Heading[0].style =		HTStyleNamed(styleSheet, "Heading1");
    Heading[1].style =		HTStyleNamed(styleSheet, "Heading2");
    Heading[2].style =		HTStyleNamed(styleSheet, "Heading3");
    Heading[3].style =		HTStyleNamed(styleSheet, "Heading4");
    Heading[4].style =		HTStyleNamed(styleSheet, "Heading5");
    Heading[5].style =		HTStyleNamed(styleSheet, "Heading6");
    Glossary.style =		HTStyleNamed(styleSheet, "Glossary");
    listStyle.style =		HTStyleNamed(styleSheet, "List");
    addressStyle.style= 	HTStyleNamed(styleSheet, "Address");
    Example.style =		HTStyleNamed(styleSheet, "Example");
    Preformatted.style =	HTStyleNamed(styleSheet, "Example");
    Listing.style =		HTStyleNamed(styleSheet, "Listing");
    
    Highlighting[0] =	HTStyleNamed(styleSheet, "Italic");
    Highlighting[1] =	HTStyleNamed(styleSheet, "Bold");
    Highlighting[2] =	HTStyleNamed(styleSheet, "Bold-Italic");
}


/*	Output the code for styles
**	--------------------------
*/
void output_paragraph()
{
    HTStyle * s = current_style->style;
    int newlines = ((s->spaceBefore+s->spaceAfter) / s->paragraph->lineHt) + 1;
    int i;
    for(i=0; i<newlines; i++) OUTPUT('\n');	/* Rather approximate! @@	*/
    OUTPUTS(current_style->paragraph_text);
    output_in_word = 0;
}

/*	Switch SGML paragraph style (finishing the old one)
**
**	The "formatted" flag allows us to add a paragraph end at the end of a
**	normal style (such as <H1> etc) but suppresses this for litteral text
**	styles such as <XMP> and <LISTING which have explicit paragraph end.
**	Thus, ALL text between <XMP> tags is litteral, and no newline results
**	from going in and out of <XMP> sections.
**
**	Now, we allow only the larger of the space before/space after
**	requirements, as that is nearer what is meant.
*/
void update_style()
{
    HTStyle * cur = current_style->style;
    HTStyle * next = next_style->style;
    
    OUTPUTS(current_style->end_text);
    
    if (current_style->free_format && cur && next) {	/* generate new lines */
    	int i;
	float space = cur->spaceAfter > next->spaceBefore ?
			cur->spaceAfter : next->spaceBefore;	/* max */
        int newlines = (space/cur->paragraph->lineHt) + 1;
	
	output_in_word = 0;
        for(i=0; i<newlines; i++) OUTPUT('\n');	/* Rather approximate! 	*/
    }

    current_style = next_style;
    if (current_style->style) SET_STYLE(current_style->style);

    OUTPUTS(current_style->start_text);
}

#define UPDATE_STYLE {if (current_style!=next_style) update_style();}

/*	Rememember that we will be going into style s
**	---------------------------------------------
*/
void change_style(SGML_style * s)
{
    next_style = s;
}


/*	End an SGML style
*/
void end_style()
{
    if (styleStack) {
        NestedStyle * N = styleStack;
	styleStack = N->next;
	free(N);
	if (styleStack) change_style(styleStack->SGML);
	else change_style(&Normal);
    } else {
        if (TRACE) printf("HTML: We have ended more styles than we have started!\n");
        change_style(&Normal);		/* Note there is no nesting! */
    }
}

/*	Start a nested SGML style
*/
void start_style(SGML_style * s)
{
    NestedStyle * N = malloc(sizeof(*N));
    N->next = styleStack;
    N->SGML = s;
    styleStack = N;
    change_style(s);
}

/*	Start a highlighted area
**	------------------------
*/

void start_highlighting(HTStyle * style)
{
    /* SET_STYLE(style);  @@@ to be fixed up */
}

/*	End a highlighted area
**	----------------------
*/
void end_highlighting()
{
	/* @@@@@@ Need set and unset style functions, traits and nesting */
}

/*	Check keyword syntax
**	---------------------
**
**	This function is called when there is only one thing it can be.
**	The check is case-insensitive.
**
** On entry,
**	s		Points to a template string in uppercase, with a space
**			standing for any amount of space in the input stream.
**			THE FIRST CHARACTER HAS ALREADY BEEN READ AND CHECKED.
** On exit,
**	returns		YES if matched, all maching characters gobbled up;
**			NO  if failure, only matching characters gobbled up.
*/
static BOOL check(char *s)
{
    char * p = s+1;	/* Pointer to template string */
    char c;		/* Character from stream */
    for (; *p; p++) {
        if (*p == ' ') {
     	    for(c=NEXT_CHAR; WHITE(c) ;c=NEXT_CHAR) /*null*/ ;
	    BACK_UP;		/* Put non-blank back into stream */
    	} else {
	    c = NEXT_CHAR;
	    if (upper(c) != *p) {
	    	printf("SGML parse: `%c' found when `%c' in `%s' was expected.\n",
				c, *p, s);
		BACK_UP;	/* Put eroneous character back on stream */
	    	return NO;	/* failed: syntax error */
	    } /* bad char */
	} /* non-blank */
    } /* for */
    return YES;			/* succeded: go to end of template string */
}


/*	Read example text
**	-----------------
**
**	Returns when terminator or end-of-file found.
**
**	As we are looking for a terminator, we have to buffer things which
**	could be terminators so as to be able to replace thm into the output
**	stream if we find they aren't. If there wasn't the ambiguity as to
**	upper/lower case, we could of course just regurgitate the terminator
**	itself.
**
*/
static int parse_example(SGML_style * style, char * terminator)
{
    char * p = terminator;
    char buffer[20];			/* One longer than the terminator */
    char * q = buffer;

    start_style(style);
    UPDATE_STYLE;
    for (;;){
    	if (END_OF_FILE) return S_text;	/* return if end of stream */
    	*q = NEXT_CHAR;
	if (upper(*q)==*p) {
	    p++; q++;
	    if (!*p) {
	        end_style();
	        return S_text;		/* Return: terminator found */
	    }
	} else {
	    if (q!=buffer) {		/* Replace what could have been terminator */
	        for(p=buffer; p<q; p++) {
    	    		OUTPUT(*p);
		}
		buffer[0] = *q;		/* Put this char back at beginning of buffer */
		p = terminator;	        /* point to start of terminator again */
		q = buffer;
	    }
#ifdef JUNK
    	    if (*q !=10) {
	        OUTPUT(*q);		/* 	Most common 99% path  */
	    } else {
	    	output_paragraph();	/* @@ gives space_before and after */
	    }
#else
	    OUTPUT(*q);		/* 	Most common 99% path  */
#endif
	}
    }    
}


/*	Read in an SGML Stream						readSGML:
**	----------------------
*/

/*	State machine to perform lexical analysis of SGML
**
**	This routine parses an SGML stream to produce styles, text and anchors.
**
**	This machine does not do good error recovery. It ignores tags which it doesn't
**	understand. It is a simple finite state machine with no push-down stack, and
**	therefore cannot (yet) understand nested constructs.
**
**	NON-REENTRANT.
**
** On entry,
**	sgmlStream	is open for read, and will provide the marked up data.
**	diagnostic	0 => Read and interpret
**			1 => Dump RTF into buffer as text.
** On exit,
**	return value	is self.
**	self		has anchors added which came up.
**			Is loaded if state returned is "done".
*/


/*	When a state has been found, we break out of the switch with this macro.
**	It is a macro to allow the code to be changed more easily (eg to return).
**	As it breaks out of the inner switch only, we must remember breaks after
**	that switch to get out of the next outer one, and so on.
*/
#ifdef NeXT
- readSGML: (NXStream *)stream diagnostic:(int)diagnostic
#else
int readSGML(HyperText * self, FILE * stream, int diagnostic)

#endif
#define SETSTATE(x) {state=(x); break;}
{    
    enum state_enum state = S_column_1;
     
/*	Information to be accumulated:
*/
    char title[256];			/* See <TITLE> tag. */
    char reference[256];		/* See <A HREF=...> attribute */
    char anchor_name[256];		/* See <A NAME=...> attribute */
    int title_length = 0;
    int reference_length = 0;
    int anchor_name_length = 0;		/* See <A NAME=...> attribte */
    BOOL end_style_on_nl = NO;		/* For styles which only last a line (ugh!) */
    BOOL white_significant = NO;	/* Not free format */

    
/*	Set up global pointer for other routines
*/
    output_in_word = 0;		/* Flag: Last character output was non-white */
    HT = self;
    sgmlStream = stream;	

/*	Pick up the styles we want from a local style sheet
*/
    get_styles();
    styleStack = 0;
    current_style = &Normal;
    
    if (TRACE) printf("Parsing SGML stream %i\n", sgmlStream);
    START_OUTPUT;
    set_style(Normal.style);		/* Was random! 910910 TBL */  

    while(!END_OF_FILE && (state!=S_done)) {
        char c = NEXT_CHAR;
	if (c == (char)-1) {
	    if (TRACE) printf("*** HT: -1 found on input stream not at EOF!\n");
	    break;
	}
#ifdef CHARACTER_TRACE
	if(TRACE) printf("<%c>", c);
#endif
	switch (state) {
	    
#ifdef REMOVE_SCRIPT
	case S_column_1:
	    if (c=='.') {
	        SETSTATE(S_dot);
	    }
	    BACK_UP;
	    SETSTATE(S_text);
	    
	case S_dot:				/* Dot in first column */
	    if (WHITE(c)) {
	        OUTPUT('.');
		BACK_UP;
		SETSTATE(S_text);		/* OOPS: must have been real "." */
	    } else {
	        SETSTATE(S_junk_script);	/* Throw away SCRIPT commands */
	    }

	case S_junk_script:
		SETSTATE( (c=='\n')||(c==';') ? S_column_1
 					      : S_junk_script);

#endif	    
	case S_word:		/* We have just had non-white characters */
	    if (c=='<') SETSTATE(S_tag_start);
	    if (c=='&') goto rcdata;
	    if (!WHITE(c)) {
	        OUTPUT(c);
		break;
	    }
	    	    
	case S_text:		/* We are not in a tag or a word */
	    switch(c) {
	    case '<':	SETSTATE(S_tag_start);
		
/*	Special code for CERN SGML double newline significance: ugh!  :-(
*/
	    case '\n':
	    	if (white_significant) {
		    output_paragraph();
		    output_in_word = 0;
		    SETSTATE(S_text);
		}
		
#ifdef CERN_WEIRDO				/* Obsolete 921122 */
		if (end_style_on_nl) {
		    end_style();
		    end_style_on_nl = NO;
		} else {
		    int newlines = 1;
		    while( (c=NEXT_CHAR)==10) {
			newlines++;
		    }
		    if (newlines>1) {
		        output_paragraph(); /* n newlines becomes a paragraph.*/
			output_in_word=0;
		    }
		    BACK_UP;		/* Go back and check c again */
		    SETSTATE(S_column_1);
		}
#else
		{
		    int newlines = 1;
		    while( (c=NEXT_CHAR)==10) {
			newlines++;
		    }
		    BACK_UP;		/* Go back and check c again */
		    SETSTATE(S_column_1);
		}
#endif
	    
	    case '\t':
	        UPDATE_STYLE;			/* Must be in new style */
						/* FALL THROUGH! */
	    case ' ':
	    	OUTPUT(c);
		output_in_word = 0;
		SETSTATE(S_text);
		
	    default:	   				/* New word */

		/* The character is non-white. Print a space if necessary. */
	        UPDATE_STYLE;			/* Must be in new style */
		if (output_in_word) {
		    OUTPUT(' ');
		}
rcdata:
		if (c=='&') {			/* Entities */
		    c = NEXT_CHAR;
		    switch (c) {
			case 'a': if (check("AMP;")) { c = '&'; goto printable; }; break;
			case 'l': if (check("LT;"))  { c = '<'; goto printable; }; break;
			case 'g': if (check("GT;"))  { c = '>'; goto printable; }; break;
			case 'q': if (check("QUOT;")){ c = '"'; goto printable; }; break;
			default: break;
		    }
		    if (TRACE) fprintf(stderr, "HTML: Bad entity.\n");
		    SETSTATE(S_word);
		}
printable:
	    	OUTPUT(c);			/* First char of new word */ 
		output_in_word = 1;
	        SETSTATE(S_word);		/* Now take rest of word faster */
	    
	    } /* switch(c) */
	    break;
	    
	case S_tag_start:
	    switch (c) {
	    case 'A':
	    case 'a':	SETSTATE(S_tag_a);
	    case 'd':
	    case 'D':   SETSTATE(S_tag_d);
	    case 'H':
	    case 'h':	SETSTATE(S_tag_h);
	    case 'i':
	    case 'I':	SETSTATE(S_tag_i);
	    case 'L':
	    case 'l':	SETSTATE(S_tag_l);
	    case 'n':
	    case 'N':	SETSTATE(S_tag_n);
	    case 'O':
	    case 'o':	SETSTATE(S_tag_o);
	    case 'p':
	    case 'P':	SETSTATE(S_tag_p);
	    case 'r':
	    case 'R':	SETSTATE(check("RESTOFFILE")
	    			? S_restoffile:S_junk_tag)
	    case 'T':
	    case 't':	SETSTATE(check("TITLE>") ? S_title : S_junk_tag);
	    case 'U':
	    case 'u':	SETSTATE(S_tag_u);
	    case 'X':
	    case 'x':	SETSTATE( check("XMP>") ? 
			  parse_example(&Example, "</XMP>")
			  : S_junk_tag);
	    case '/':	SETSTATE( S_tag_end);
	    default:	SETSTATE( S_junk_tag);
	    } /*  switch on character */
	    break;
    
	case S_tag_end:
	    switch (c) {
	    case 'A':
	    case 'a':	SETSTATE(S_end_a);
	    case 'D':
	    case 'd':	SETSTATE(S_end_d);
	    case 'H':
	    case 'h':	SETSTATE(S_end_h);
	    case 'I':
	    case 'i':   if (check("ISINDEX")) isIndex = YES;
	    		SETSTATE(S_junk_tag);
	    case 'n':
	    case 'N':	SETSTATE(check("NODE>") ? S_done : S_junk_tag)
	    case 'O':
	    case 'o':	SETSTATE(S_end_o);
	    case 'P':
	    case 'p':   if (check("PRE")) {
			    end_style();
			    white_significant = NO;
			    SETSTATE(S_junk_tag);
			}
	    case 'U':
	    case 'u':	SETSTATE(S_end_u);
	    default:	SETSTATE(S_junk_tag);
	    } /*  switch on character */
	    break;
	
	case S_junk_tag:	SETSTATE( (c=='>') ? S_text : S_junk_tag);

#ifdef CERN_WEIRDO
	case S_junk_line:	SETSTATE( (c=='\n') ? S_column_1 : S_junk_line);
#endif
	case S_tag_i:
            switch(c) {
#ifdef CERN_WEIRDO
	    case '1':	SETSTATE(S_junk_line); /* Junk I1 */
#endif
	    case 's':
	    case 'S':	if (check("SINDEX")) isIndex = YES;
	    		SETSTATE(S_junk_tag);
	    default:	SETSTATE(S_junk_tag);
	    }	
	    break;
	case S_tag_a:
	    switch(c) {
	    case 'd':
	    case 'D':
		if (!check("DDRESS>")) { SETSTATE(S_junk_tag) };
		start_style(&addressStyle);
		SETSTATE( S_text);
	    
	    case '\n':
	    case ' ':
	    case '>':
	    	reference_length = 0;
	    	anchor_name_length = 0;
	    	SETSTATE(S_anchor);
	    
	    } /* switch on character */
	    break;
	    
	case S_tag_p:	if ((c==' ') || (c=='>')) {
			    output_paragraph();
			    SETSTATE( c=='>'? S_text : S_junk_tag);
			}
			
			if ((c=='R') || (c=='r')) {		/* <PRE> */
			    if (check("RE")) {
				start_style(&Preformatted);
				update_style();
			        white_significant = YES;
				SETSTATE( S_junk_tag);
			    }
			}
			if ((c=='L') || (c=='l')) {		/* OBSOLETE @@ */
			    if (check("LAINTEXT>")) {
				if (TRACE) printf("Loading as plain text\n");
				[self readText:sgmlStream];	/* will read to end */
				SETSTATE(S_done);		/* Inhibit RTF load */
                             }
			 }
			 SETSTATE(S_junk_tag);

	case S_tag_lis:
	    		SETSTATE( check("TING>") ? 
			  parse_example(&Listing, "</LISTING>")
			  : S_junk_tag);


/* Subnodes are delimited by <NODE>...</NODE>. They have the same address as the
** node, but the anchor IDs must be different. This is not thought out.	@@
** Perhaps a hierarchical anchor ID format ....
*/
	case S_tag_n:
	    switch(c) {
	    case 'o':
	    case 'O':	if (check("ODE>")) {	/* Load a subnode */
			    if(TRACE)  printf("Loading subnode...NOT IMPLEMENTED\n");
#ifdef NOT_DEFINED
			    Anchor * a = [Anchor new];
			    HyperText * SN;
			    [a setAddress:[nodeAnchor address]];
			    SN = [HyperText newAnchor:a Server:server];
			    [alsoStore addObject:SN];
			    SN->storeWith = self;
			    [SN readSGML:sgmlStream diagnostic:diagnostic];
			    /* But leave it hidden from view for now. */
#endif
	    		}
	    		SETSTATE(S_text);
			
	    case 'E':					/* <NE */
	    case 'e':
	        if (check("EXTID ")) {
		    int value = 0;
		    for(;;){
		        c = NEXT_CHAR;
			if ((c=='N') || (c=='n')) {
			    if (!check("N = ")) {
				if (TRACE) fprintf(stderr, 
					"HTML: Bad nextid\n");
				SETSTATE(S_junk_tag);
			    }
			    c = NEXT_CHAR;
			}
			if (c=='"') continue;	/* 921122 */
			if ((c<'0') || (c>'9')) {
			    nextAnchorNumber = value;
			    if (TRACE) fprintf(stderr, "Next anchor number: %i\n", value);
			    BACK_UP;
			    SETSTATE(S_junk_tag);
			    break;
			}
			value = value*10 + (c-'0');
		    }
		}
		SETSTATE(S_junk_tag);
		
	    } /* switch */
	    break;
	    
/*	Parse anchor tag:
**	----------------
*/
	case S_anchor:
	    if (c==' ') SETSTATE( S_anchor);			/* Ignore spaces */
	    if ((c=='H')||(c=='h')) {
		if (check("HREF = ")) {
		    SETSTATE( S_href);
		}
	    }
	    if ((c=='N')||(c=='n')) {
		if (check("NAME = ")) {
		    SETSTATE( S_aname);
		}
	    }
	    
	    if (c=='>') {			/* Anchor tag is over */
		/* Should use appendStartAnchor! @@@ */
		HTStyle * style = HTStyleNew();
	    	char * parsed_address;
		int anchorNumber;
		
	        reference[reference_length]=0;		/* Terminate it */
	        anchor_name[anchor_name_length]=0;	/* Terminate it */

		style->anchor =
		  *anchor_name ? [Anchor newParent:nodeAnchor tag:anchor_name]
			      : [self anchor];
			      
		/* If next anchor number not specified, ensure it is safe */
		
		if ((anchor_name[0] == ANCHOR_ID_PREFIX)
		&&  (sscanf(anchor_name+1, "%i", &anchorNumber) > 0))	/* numeric? */
		 if (anchorNumber >= nextAnchorNumber)
		  nextAnchorNumber = anchorNumber+1;		/* Prevent reuse */
		
		
		[(Anchor *)style->anchor isLastChild];	/* Put in correct order */	      
		if (*reference) {			/* Link only if href */
		    parsed_address = HTParse(reference, [nodeAnchor address],
		    	 PARSE_ALL);
		    [(Anchor *)(style->anchor) linkTo:
		    			[Anchor newAddress:parsed_address]];
		    free(parsed_address);
		}
		
		UPDATE_STYLE;
		SET_STYLE(style);		/* Start anchor here */
		free(style);
		SETSTATE(S_text);
	    }
	    printf("SGML: Bad attribute in anchor.\n");
	    SETSTATE( S_junk_tag);
    
	case S_href:
	    if (c=='"') SETSTATE (S_href_quoted);
	case S_href_unquoted:
	    if ((c==' ') || (c=='\n')) SETSTATE( S_anchor);
	    if (c=='>'){
	        BACK_UP;
	    	SETSTATE( S_anchor);
	    }
	    if (reference_length<255) {
		reference[reference_length++] = c;
	    }
	    SETSTATE(S_href_unquoted);

	case S_href_quoted:
	    if (c=='"') SETSTATE( S_anchor);
	    if (reference_length<255) {
		reference[reference_length++] = c;
	    }
	    SETSTATE( state);

	case S_aname:
	    if ((c==' ') || (c=='\n')) SETSTATE( S_anchor);
	    if (c=='>'){
	        BACK_UP;
	    	SETSTATE( S_anchor);
	    }
	    if (anchor_name_length<255) {
		anchor_name[anchor_name_length++] = c;
	    }
	    SETSTATE( state);
    
	case S_end_a:
	    switch(c) {
	    case 'd':					/* End address */
	    case 'D':
	    	if (!check("DDRESS >")) SETSTATE(S_junk_tag);
		end_style();
		SETSTATE(S_text);

	    case '>':					/* End anchor */
		{
		    [HT appendEndAnchor];
		    SETSTATE(S_text);
		}
		
	    default: SETSTATE(S_junk_tag);
	    } /* switch c */
	    break;

/*	Parse glossary tags
**	-------------------
**
**	We allow <DL> </DL> but we do not allow <DL> (text) <DT> ...
*/
	case S_tag_d:
	    switch(c) {
	    case 'L':
	    case 'l':				/* Start Definition list 	<DL> */
		(void) check("L> <");		/* Ignore first DT */
		c = NEXT_CHAR;
		if (c=='/') {
		    check("/DL>");
		} else {
		    (void) check("DT>");
		    start_style(&Glossary);
		}
		SETSTATE(S_text);
	    case 'T':
	    case 't':				/* Definition term 		<DT> */
        	output_paragraph();
	        SETSTATE(S_junk_tag);
	    case 'D':
	    case 'd':				/* Definition definition 	<DD> */
		OUTPUT('\t');
	        SETSTATE(S_junk_tag);
	    } /*switch c */
	    break;

	case S_end_d:				/* end definition list 	</DL> */
	    if ((c != 'l')&&(c!='L')) SETSTATE(S_junk_tag);
	    end_style();
	    SETSTATE(S_junk_tag);
	        
/*	Parse highlighting and headers
**	------------------------------
**	@ All these formats should be nested, and should be defined by a style sheet.
*/	
	case S_tag_h:
	    switch (c) {
	    case '1':
	    case '2':
	    case '3':
	    case '4':
	    case '5':
	    case '6':
		    start_style(&Heading[c-'1']);
		    update_style();

#ifdef CERN_WEIRDO
		    end_style_on_nl = YES;		/* Style can end at line end */
#endif
		    SETSTATE( S_junk_tag);
	    case 'P':
	    case 'p':
		switch (c=NEXT_CHAR) {
		case '1':
		case '2':
		case '3':
		    start_highlighting(Highlighting[c-'1']);
		    SETSTATE( S_junk_tag);	    
		default: SETSTATE( S_junk_tag);	    
		}
		break;
		    
	    default: SETSTATE( S_junk_tag);
	    } /* switch c */
	    break;
    
	case S_end_h:
	    switch (c) {
	    case '1':
	    case '2':
	    case '3':
	    case '4':
	    case '5':
	    case '6':
#ifdef CERN_WEIRDO
		    end_style_on_nl = NO;		/* That's over. */
#endif
		    end_style();
		    SETSTATE( S_junk_tag);
	    case 'P':
	    case 'p':
		switch (NEXT_CHAR) {
		case '1':
		case '2':
		case '3':
		    end_highlighting();
		    SETSTATE( S_junk_tag);
		default: SETSTATE( S_junk_tag);
		} /* switch */
		break;	    

	    default: SETSTATE( S_junk_tag);
	    
	    } /* switch c */
	    break;
    
/*	Parse Lists, ordered and unordered
**	----------------------------------
**
**	This only affects the horizontal line format, not the font.
*/
        case S_tag_o:
	case S_tag_u:
	    
	    if ((c == 'l') || (c=='L')) {        
		(void) check("L> <LI>");	/* Ignore first LI after UL */
		start_style(&listStyle);
	    }
	    SETSTATE(S_text);
	    
	case S_tag_l:
	    switch(c) {
	    case 'I':
	    case 'i':				/* List element		<LI> */
        	c = NEXT_CHAR;
		if (c=='S') {
		    SETSTATE(S_tag_lis);
		}
		output_paragraph();
	        SETSTATE(S_text);
		
	    default: SETSTATE(S_junk_tag);
	    } /*switch c */
	    break;

	case S_end_o:				/* end n list 		</UL> */
	case S_end_u:				/* end n list 		</UL> */
	    if ((c != 'l')&&(c!='L')) SETSTATE(S_junk_tag);
	    end_style();
	    SETSTATE(S_junk_tag);

/*	Parse rest of file on another format
*/
	case S_restoffile:
	    switch (c) {
	    
	    case ' ':
	    case '\n':
	    case '\t':
	    	break;
	     
	    case 'p':
	    case 'P':
	       	if (check("PLAINTEXT>")) {
		    if (TRACE) printf("Loading as plain text\n");
		    start_style(&Example);
		    LOADPLAINTEXT;
		    SETSTATE(S_done);		/* ... */
		 }
	     
	    case 'R':
	    case 'r':
	       	if (check("RTF>")) {
		    if (TRACE) printf("Loading as RTF\n");
		    [self readRichText:sgmlStream];	/* will read to end */
		    [self adjustWindow];		/* Fix scrollers */
		    SETSTATE(S_done);		/* Inhibit RTF load */
		 }
	     
	     }
	     break;
	             
/*	Parse <TITLE>..</TITLE>
*/
	case S_title:
	    if (c=='<') {
		if (check("</TITLE>")) {
		    title[title_length]=0;		/* Add a terminator */
		    if (TRACE)printf("\nTitle:\t`%s'\n", title);
		    [[self window] setTitle:title];
		    SETSTATE( S_text);
		} else SETSTATE( S_junk_tag);	/* @@@ forgets < in titles! */
	    } else {
		if (title_length < 255) title[title_length++] = c; 
		SETSTATE( state);
	    } /* if */
	case S_done:
	    break;			/* Should never happen */
	    
	} /* switch state */
    } /* for loop */

    if ((state!=S_text) && (state != S_done))
        if(TRACE) printf("*** Unfinished SGML file: Left in state %i\n", state);
	
    if (state != S_done) {
        OUTPUT('\n');	/* Ensure that the text always ends in \n for ScanALine */
        FINISH_OUTPUT;
    }

/*	Clean up any styles left nested
*/
    while (styleStack) {
	NestedStyle * N = styleStack;
	styleStack = N->next;
	if (TRACE) printf("HT: Left in style at end of document!\n");
	free(N);
    }
    
    [window setDocEdited:NO];
    tFlags.changeState = 0; 		/* Please notify delegate if changed */
    return self;
    
} /* readSGML:diagnostic: */


/*		Write SGML File back OUT
**		------------------------
**
**	This is currently quite NeXT-specific.
**
**	We run through te runs. When a characteristic of a run changes, we
**	output the approporiate SGML code. When several characteristics change at
**	the same place, we output the code in an order such that the resulting
**	structures wil be nested. This means first unwrapping the old ones, and
**	then entering the new ones. For example, it is better to produce
**
**		<h2><a>...</a></h2><a>...</a>
**	than
**
**		<h2><a>...</h2></a><a>...</a>
**
**	The special treatment of newlines is because we want to strip extra newlines
**	out. We ignore newlines at the beginning and end of the para style,
**	and we treat multiple newlines as a single paragraph mark.
**
**	Bugs:	@@@ Highlighting is ignored.
**		@@@ end text is ignored.
*/

#define LINE_WRAP 64		/* Start thinking about line wrap here */

static int SGML_gen_newlines;	/* Number of newlines pending during SGML generation */
static SGML_gen_errors;		/* Number of unrcognizable runs */
static SGML_style * currentSGML;
static const char * saveName;	/* pointer to name node is being saved under */
static char * prefix;		/* Pointer to prefix string to be junked */
static int	lineLength;	/* Number of characters on a line so far */

/*	This function, for any paragraph style, finds the SGML style, if any
*/
SGML_style * findSGML(void *para)
{
    int i;
    if (!para) return &Normal;			/* Totally unstyled becomes Normal */
    for (i=0; i<NUMBER_OF_STYLES; i++) {
	SGML_style * S = styleTable[i];
	if (S) {
	    HTStyle * style = S->style;
	    if(style) {
	        if (style->paragraph == para)
		    return S;
	    }
	}
    }
    if (TRACE) printf("HT: Can't find SGML style!\n");
    SGML_gen_errors++; 
    return &Normal;
}


/*	This function generates the code for one run, given the previous run.
**
*/
void change_run(NXRun *last, NXRun *r)
{
    int chars_left = r->chars;
       
    if (r->info != last->info) {			/* End anchor */
	if (last->info) NXPrintf(sgmlStream, "</A>");
    }
    
    if (r->paraStyle != last->paraStyle)
     if (last->paraStyle) {				/* End paragraph */
	if (currentSGML) NXPrintf(sgmlStream, "%s", currentSGML->end_tag);
	else NXPrintf(sgmlStream,"<P>\n");
	lineLength = 0;	 /* At column 1 */
    }

    
    if (r->paraStyle != last->paraStyle) {		/* Start paragraph */
	currentSGML = findSGML(r->paraStyle);
	if (currentSGML) {

	    if (currentSGML->free_format)
	     while(chars_left && WHITE(*read_pointer)) {/* Strip leading */
		(chars_left)--;				/*   white space */
		(void) NEXT_TEXT_CHAR;
	    }
	    NXPrintf(sgmlStream, "%s", currentSGML->start_tag);
	    prefix = currentSGML->start_text;
	} 
	SGML_gen_newlines=0;				/* Cancel  */
    }
    
    if (r->info != last->info) {			/* Start anchor */

	if (SGML_gen_newlines) {	/* Got anchor, need paragraph separator */
	    NXPrintf(sgmlStream, "%s", currentSGML->paragraph_tag);
	    SGML_gen_newlines=0;	/* paragraph flushed. */
	}
	if (r->info) {
	    Anchor * a = (Anchor *) r->info;
	    Anchor * d = [a destination];
	    NXPrintf(sgmlStream, "<A\nNAME=%s", [a address]);
	    if (d) {
	        Anchor * p = [d parent];
		Anchor * n = p ? p : d;		/* The node anchor */
	        char *absolute = HTParse([n address], [[HT nodeAnchor]address],
		  		PARSE_ALL);
		char * relative = HTRelative(absolute, saveName);
		if (!p)						/* Whole node */
		    NXPrintf(sgmlStream, " HREF=\"%s\"", relative);
	        else if (p == [HT nodeAnchor])			/* In same node */
		    NXPrintf(sgmlStream, " HREF=\"#%s\"", [d address]);
		else						/* In different node */
		    NXPrintf(sgmlStream, " HREF=\"%s#%s\"", relative, [d address]);
		free(relative);
		free(absolute);
	    }
	    NXPrintf(sgmlStream, ">");
	}
    }

/*	Now output the textual part of the run
**
**	Within the prefix region (prefix!=0), we discard white space and
**	characters matching *prefix++. Note the prefix string may contain white space.
**
**	The SGML_gen_newlines flag means that newlines have been found. They are
**	not actually implemented unless some more non-white text is found, so that
**	trailing newlines on the end of paragraphs are stripped.
**
**	The line wrapping is primitive in the extreme, as only text characters are
**	counted. In practise it limits the length of any line to a reasonable amount,
**	though this is not guarranteed.
*/
    {
	while (chars_left) {	
	    char c = NEXT_TEXT_CHAR;
	    chars_left--;
	    if (prefix) {
	        if (*prefix) {
		    if (c==*prefix) {
			++prefix;
			continue;			/* Strip prefix characters */
		    }
		    if (WHITE(c)) continue;			/* Strip white space */
		    if (TRACE) printf(
	   "HTML: WARNING: Paragraph prefix incomplete: %i found where %i expected.\n",
			     c, *prefix);
		    }
		prefix=0;				/* Prefix is over */
	    }
	    
	    if (c=='\n') {				/* Paragraph Marks:	*/
		if (currentSGML->free_format) {
		    SGML_gen_newlines++;		/* Just flag it */
		    prefix = currentSGML->paragraph_text;
	        } else {
		    NXPrintf(sgmlStream, "%s", currentSGML->paragraph_tag);
		}
		lineLength = 0;	 /* At column 1 */
		
	    } else {					/* Not newline */

		if (SGML_gen_newlines) {/* Got text, need paragraph separator */
		    NXPrintf(sgmlStream, "%s", currentSGML->paragraph_tag);
		    SGML_gen_newlines=0;	/* paragraph flushed. */
		    lineLength = 0;	 	/* At column 1 */
		}
		if (c=='\t') {
		    if (currentSGML) NXPrintf(sgmlStream, "%s", currentSGML->tab_tag);
		    else NXPrintf(sgmlStream, "\t");
		} else {				/* Not tab or newline */
		    lineLength ++;	/* @@bug doesn't count entity names */
		    if ((currentSGML->free_format)
		    &&  (lineLength++ > LINE_WRAP)	/* Wrap lines if we can */
		    &&  (c==' ')) {
			    c = '\n';
			    lineLength = 0;
		    }
		    
		    if (currentSGML->litteral) {
		        NXPrintf(sgmlStream, "%c", c);
		    } else {
			switch(c) {
		    	case '<': 	NXPrintf(sgmlStream, "&lt;"); break;
		    	case '&': 	NXPrintf(sgmlStream, "&amp;"); break;
			default:	NXPrintf(sgmlStream, "%c", c); break;
			} /* switch */
		    } /* not litteral */
	        }
	    }
	}
    }
} /* change_run */



/*	This is the body of the SGML output method.
*/
- writeSGML:(NXStream *) stream relativeTo:(const char *)aName
{
    NXRun * r = theRuns->runs;
    int sor;				/* Character position of start of run */
    NXRun dummy;
    
    dummy.paraStyle = 0;
    dummy.info = 0;
    dummy.chars = 0;
    
    SGML_gen_newlines=0;		/* Number of newlines read but not inserted */    
    HT = self;
    saveName = aName;
    sgmlStream = stream;
    SGML_gen_errors = 0;
    currentSGML = 0;
    prefix = 0;				/* No prefix to junk */
    
    START_INPUT;
    lineLength = 0;			/* Starting in column 1 */
    		
    NXPrintf(stream, "<HEADER>\n");
    NXPrintf(stream, "<TITLE>%s</TITLE>", [window title]);
    
    if (nextAnchorNumber) NXPrintf(stream, "\n<NEXTID N=\"%i\">\n",
	 nextAnchorNumber);
    NXPrintf(stream, "</HEADER>\n");
    NXPrintf(stream, "<BODY>");

/*	Change style tags etc
*/
    change_run(&dummy, r);			/* Start first run */
    
    for (sor=r++->chars; sor<textLength; sor=sor+(r++)->chars)  {
        if (TRACE) printf("%4i:  %i chars in run %3i.\n",
			sor, r->chars, r-theRuns->runs);
	change_run(r-1, r);	/* Runs 2 to N */
    }
    change_run(r, &dummy);			/* Close last run */

    tFlags.changeState = 0; 		/* Please notify delegate if changed */
    NXPrintf(stream, "</BODY>\n");

    return (SGML_gen_errors) ? nil : self;    
}
