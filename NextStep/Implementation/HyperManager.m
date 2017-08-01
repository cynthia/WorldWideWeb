//	HyperText Access method manager Object			HyperManager.m
//	--------------------------------------
//
//	It is the job of a hypermanager to keep track of all the HyperAccess modules
//	which exist, and to pass on to the right one a general request.
//
// History:
//	   Oct 90	Written TBL
//
#import "HyperManager.h"
#import "HyperText.h"
#import "HTUtils.h"
#import "HTParse.h"
#import "FileAccess.h"

@implementation HyperManager 

#import "WWWPageLayout.h"

#define THIS_TEXT  (HyperText *)[[[NXApp mainWindow] contentView] docView]

extern char * WWW_nameOfFile(const char * name);	/* In file access */

/*	Exported to everyone */

int WWW_TraceFlag;	/* Exported to everyone */
char * appDirectory;	/* Name of the directory containing the application */


/*	Private to this module
*/
PRIVATE FileAccess * fileAccess = nil;

+ new
{
    self = [super new];
    accesses = [List new];		// Create and clear list
    return self;
}

- traceOn:sender { WWW_TraceFlag = 1; return self;}
- traceOff:sender { WWW_TraceFlag = 0; return self;}

- manager {return nil; }		// we have no manager
- setManager {return nil; }		// we have no manager

- (const char *) name
{
    return "any";
}

//			Access Management functions
//
- registerAccess:(HyperAccess *)access
{
    if (!accesses) accesses=[List new];
    if (TRACE) printf(
    	"HyperManager: Registering access `%s'.\n", [access name]);
    if (0==strcmp([access name], "file"))
        fileAccess = (FileAccess*)access;		/* We need that one */
    return [accesses addObject:access];
}


//	Load an anchor from some access				loadAnchor:
//	-------------------------------
//
//	This implementation simply looks for an access with the right name.
//	It also checks whether in fact the anchor
//	is already loaded and linked, and that the address string is not null.
//
// On exit:
//	If a duplicate node is found, that anchor is returned
//	If there is no success, nil is returned.
//	Otherwise, the anchor is returned.

- loadAnchor:(Anchor *)anAnchor Diagnostic:(int)diagnostic
{

    char * s=0;
    const char *addr;
    int i;
    HyperAccess * access;
    
    if ([anAnchor node]) {
        return [[anAnchor node] nodeAnchor];	/* Already loaded and linked. */
        if (TRACE) printf("HyperManger: Anchor already has a node.\n");
    }
    
    addr = [anAnchor address];
    if (!addr) {
        if (TRACE) printf("HyperManger: Anchor has no address - can't load it.\n");
	return nil;			/* No address? Can't load it. */
    }
    
    if (TRACE) printf("HyperManager: Asked for `%s'\n", addr);
    
    s= HTParse(addr, "", PARSE_ACCESS);
    for(i=0; i<[accesses count]; i++) {
        access = [accesses objectAt:i];
	if (0==strcmp(s, [access name])) {
	    id status;
	    HyperText * HT;
	    if(TRACE) printf("AccessMgr: Loading `%s' using `%s' access.\n",
	    	[anAnchor address], [access name]);
	    free(s);
	    status =  [access loadAnchor:anAnchor Diagnostic:diagnostic];
	    if (!status) return nil;

	    //	The node may have become an index: update the existence
	    //   state of the panel.
	    
	    HT = [anAnchor node];
	    if ([HT isIndex]) {
		[[keywords window] makeKeyAndOrderFront:self];
	    } else {
		[[keywords window] close];
//		[[keywords window] orderOut:self];    @@ bug?
	    }

	    return status;
	}
	
    }
    
//	Error: No access. Print useful error message.

    {
	char got[100];
	char *format;
	
	format = *s ?
	"Invalid access prefix for `%s'\n    Can be one of %s but not `%s:'.\n"
	: "No access prefix specified for `%s'\n    Accesses are: %s .\n";

	for(i=0; i<[accesses count]; i++) {
	    sprintf(got, "%s: ",[[accesses objectAt:i] name]);
	}
	printf(format,[anAnchor address], got, s);
	NXRunAlertPanel(NULL,format,
	    	NULL,NULL,NULL,
		[anAnchor address], got, s);
    }
    free(s);
    return nil;
}

//______________________________________________________________________________


//	Open or search  by name
//	-----------------------
//
//	
- accessName:(const char *)arg
	Diagnostic:(int)diagnostic
{
    return [[Anchor newAddress:arg] selectDiagnostic:diagnostic];
}


//	Search with a given diagnostic level
//
//	This involves making a special address string, being the index address
//	with a ? sign followed by a "+" separated list of keywords.
//
- searchDiagnostic:(int)diagnostic
{
    char addr[256];
    char keys[256];
    char *p, *q;
    HyperText * HT = THIS_TEXT;
    if (!HT) return nil;
    strcpy(addr, [[HT nodeAnchor] address]);
    if ((p=strchr(addr, '?'))!=0) *p=0;		/* Chop off existing search string */   
    strcat(addr,"?");
    strcpy(keys, [keywords stringValueAt:0]);
    q =HTStrip(keys);			/* Strip leading and trailing */
    for(p=q; *p; p++)
        if (WHITE(*p)) {
	    *p='+';			/* Separate with plus signs */
	    while (WHITE(p[1])) p++;	/* Skip multiple blanks */
	    if (p[1]==0) *p = 0;	/* Chop a single trailing space */
        }
    strcat(addr, keys);			/* Make combined node name */
    return [self accessName:HTStrip(addr) Diagnostic:diagnostic];
}

//				N A V I G A T I O N


//	Realtive moves
//	--------------
//
//	These navigate around the web as though it were a tree, from the point of
//	view of the user's browsing order.

- back:sender		{ return [Anchor back]; }
- next:sender		{ return [Anchor next]; }
- previous:sender	{ return [Anchor previous]; }

//	@@ Note: the following 2 methods are duplicated (virtually) in FileAccess.m
//	and should not be here.

//	Go Home
//	-------
//
//	This accesses the default page of text for the user or, failing that,
//	for the system. 
//
- goHome:sender
{
    return [fileAccess openMy:"default.html" diagnostic:0];
}

//	Load Help information
//	---------------------
//
//
- help:sender
{
    return [fileAccess openMy:"help.html" diagnostic:0];
}

//	Go to the Blank Page
//	--------------------
//
//
- goToBlank:sender
{
    return [fileAccess openMy:"blank.html" diagnostic:0];
}

//				Application Delegate Methods
//				============================


//	On Initialisation, Load Initial File
//	------------------------------------

-appDidInit:sender
{
    if (TRACE) printf("HyperManager: appDidInit\n");
    
//    StrAllocCopy(appDirectory, NXArgv[0]);
//    if (p = strrchr(appDirectory, '/')) p[1]=0;	/* Chop home slash */
//    if (TRACE) printf("WWW: Run from %s\n", appDirectory);
    
    [Anchor setManager:self];
    return [self goHome:self];
}

//	Accept that we can open files from the workspace

- (BOOL)appAcceptsAnotherFile:sender
{
    return YES;
}

//	Open file from the Workspace
//
- (int)appOpenFile:(const char *)filename type:(const char *)aType
{
    char * name = WWW_nameOfFile(filename);
    HyperText * HT = [self accessName:name Diagnostic:0];
    free(name);
    return (HT!=0);
}

//	Open Temporary file
//
//	@@ Should unlink(2) the file when we have done with it!

- (int)appOpenTempFile:(const char *)filename type:(const char *)aType
{
    char * name = WWW_nameOfFile(filename);	/* No host */
    HyperText * HT = [self accessName:name Diagnostic:0];
    free(name);
    return (HT!=0);
}



//		Actions:
//		-------
- search:sender
{
    return [self searchDiagnostic:0];
}

- searchRTF:sender
{
    return [self searchDiagnostic:1];
}

- searchSGML:sender
{
    return [self searchDiagnostic:2];
}


//	Direct open buttons:

- open:sender
{
    return [self accessName:[openString stringValueAt:0] Diagnostic:0];
}

- linkToString:sender
{
    return [THIS_TEXT linkSelTo:
        [Anchor newAddress:[openString stringValueAt:0]]];
}

- openRTF:sender
{
 return [self accessName:[openString stringValueAt:0] Diagnostic:1];
}

- openSGML:sender
{
 return [self accessName:[openString stringValueAt:0] Diagnostic:2];
}


//	Save a hypertext back to its original server
//	--------------------------------------------
- save:sender
{
    HyperText * HT = THIS_TEXT;
    id status = [(HyperAccess *)[HT server] saveNode:HT];
    if (status) [[HT window] setDocEdited:NO];
    return status;
}

//	Save all hypertexts back
//	-------------------------

- saveAll:sender
{
    List * windows = [NXApp windowList];
    id cv;
    int i;
    int n = [windows count];
    
    for(i=0; i<n ; i++){
	Window * w = [windows objectAt:i];
	if (cv=[w contentView])
	 if ([cv respondsTo:@selector(docView)])
	 if ([w isDocEdited]) {
		HyperText * HT = [[w contentView] docView];
		if ([(HyperAccess *)[HT server] saveNode:HT])
			[w setDocEdited: NO];
	}
    }

    return self;
}


//	Close all unedited windows except this one
//	------------------------------------------
//

- closeOthers:sender
{
    Window * thisWindow = [NXApp mainWindow];
    List * windows = [[NXApp windowList] copy];

    {
        int i;
	id cv;					// Content view
	int n = [windows count];
        for(i=0; i<n; i++){
	    Window * w = [windows objectAt:i];
	    if (w != thisWindow)
	    if (cv=[w contentView])
	    if ([cv respondsTo:@selector(docView)]) {
	    	if (![w isDocEdited]) {
		    if (TRACE) printf(" Closing window %p\n", w);
		    [w performClose:self];
	        }
	    }
	}
	[windows free];				/* Free off copy of list */
	return self;
    }
}

//	Print Postscript code for the main window
//	-----------------------------------------

- print:sender
{
     return [THIS_TEXT printPSCode:sender];
}

//	Run the page layout panel
//
- runPagelayout:sender
{
    PageLayout * pl = [WWWPageLayout new];
    [pl runModal];
    return self;
}

//	Set the title of the main window
//	--------------------------------

- setTitle: sender
{
    Window * thisWindow = [NXApp mainWindow];
    [thisWindow setTitle:[titleString stringValueAt:0]];
    [thisWindow setDocEdited:YES];
    return self;
}

//	Inspect Link
//	------------

- inspectLink:sender
{
    Anchor * source = [THIS_TEXT selectedLink];
    Anchor * destination;
    if (!source){
    	[openString setStringValue: "(No anchor selected in main document.)"
                at:0];
         return nil;
    }
    {
    	char * source_address = [source fullAddress];
    	[addressString setStringValue: source_address];
	free(source_address);
    }

    destination = [source destination];
    if (destination) {
    	char * destination_address = [destination fullAddress];
    	[openString setStringValue: destination_address at:0];
	free(destination_address);
    } else {
	[openString setStringValue: "Anchor not linked."  at:0];
    }

    return self;
}

//	Copy address of document
//	------------------------
- copyAddress:sender
{
    [openString setStringValue: [[THIS_TEXT nodeAnchor] address] at:0];
    return self;
}

//		HyperText delegate methods
//		==========================
//
//	This one has been passed from a window
//	to the hypertext which is its delegate,
//	to the access server module of that hypertext,
//	to this access manager.
//
// When a hypertext windown becomes a key window, the search
// panel is turned on or off depending on whether a search can be done,
// and the default address in the "open using full reference" panel
// is set to the address of the current hypertext.
//
- hyperTextDidBecomeMain: sender
{

    if ([sender isIndex]) {
        [[keywords window] makeKeyAndOrderFront:self];
    } else {
        [[keywords window] close];
//        [[keywords window] orderOut:self];	bug?
    }
    [titleString setStringValue: [[sender window] title] at:0];
    [addressString setStringValue: [[sender nodeAnchor] address]];
//  [openString setStringValue: [[sender nodeAnchor] address] at:0];
    return self;
}

//	Panel delegate methods
//
//	The only windows to which this object is a delegate
//	are the open and search panels. When they become key,
//	we ensure that the text is selected.

- windowDidBecomeKey:sender
{
    if (sender == [openString window])
        [openString selectTextAt:0];	// Preselect the text
    else if (sender == [keywords window])
        [keywords selectTextAt:0];	// Preselect the text

    return self;
}
@end
