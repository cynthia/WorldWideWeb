//								TcpAccess.m

// A HyperAccess object provides access to hyperinformation, using particular
//	protocols and data format transformations. This one provides access to
//	the CERNVM FIND system using HTTP/TCP.

// History:
//	26 Sep 90	Written TBL


#import "TcpAccess.h"
#import "Anchor.h"
#import "HTUtils.h"
#import "HTTP.h"

/*	Module parameters:
**	-----------------
**
**  These may be undefined and redefined by syspec.h
*/

@implementation TcpAccess

//	Return the name of the access
//	-----------------------------

- (const char *)name
{
    return "http";
}

//	Open or search  by name
//	-----------------------
	
- accessName:(const char *)arg
	anchor:(Anchor *)anAnchor
	diagnostic:(int)diagnostic
{
    HyperText *	HT;			// the new hypertext
    NXStream * sgmlStream;		// Input stream for marked up hypertext
    int s;				// Socket number for returned data 

/* Get node name:
*/
    
//	Make a hypertext object with an anchor list.
        
    HT = [HyperText newAnchor:anAnchor Server:self];

    [HT setupWindow];			
    [[HT window]setTitle:"Connecting..."];	/* Tell user something's happening */
    [HT setEditable:NO];			/* This is read-only data */

//	Now, let's get a stream setup up from the server for the sgml data:
        
    s = HTTP_Get(arg);
    if (s<0) return nil;	/* Failed .. error will be reported by HTTP_get */
    sgmlStream = NXOpenFile(s, NX_READONLY);

    if (diagnostic == 2) {			/* Can read the SGML straight */
	[HT readText:sgmlStream];
	return HT;
    }

//	Now we parse the SGML

    [[HT window]setTitle:"Loading..."];	/* Tell user something's happening */
    [HT readSGML:sgmlStream diagnostic:diagnostic];    
    
//	Clean up now it's on the screen:
    
    if (TRACE) printf("Closing streams\n");
    NXClose(sgmlStream);
    close(s);

    return HT;
}

//		Actions:



//	This will load an anchor which has a name
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

    if ([a node]) {
    	return a;		/* Already loaded */
    } else {
        HT = [self accessName:[a address] anchor:a diagnostic:diagnostic];
    	if (!HT) return nil;
	return a;
    }
}

@end
