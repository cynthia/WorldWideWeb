/*	Include file for WorldWideWeb project-wide definitions
*/

/*	Formats:
*/
typedef int WWW_Format;		/* Can take the following values: */

#define WWW_INVALID   (-1)
#define WWW_SOURCE 	0	/* Whatever it was			*/
#define WWW_PLAINTEXT	1	/* plain ISO latin (ASCII)		*/
#define WWW_POSTSCRIPT	2	/* Postscript - encapsulated?		*/
#define	WWW_RICHTEXT	3	/* Microsoft RTF transfer format	*/
#define WWW_HTML	4	/* WWW HyperText Markup Language	*/

