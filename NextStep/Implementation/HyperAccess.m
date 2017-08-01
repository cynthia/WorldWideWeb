//								HyperAccess.m

//	A HyperAccess object provides access to hyperinformation, using
//	particular protocols and data format transformations.
//	This actual class will not work itself: it just contains common code.

// History:
//	26 Sep 90	Written TBL


#include <stdio.h>
#include <appkit/appkit.h>
#import "HyperAccess.h"
#import "HyperManager.h"
#import "Anchor.h"
#import "HTUtils.h"

@implementation HyperAccess

//	Methods used by the Interface Builder code to connect up the application:
- setTitleString:anObject
{
    titleString = anObject;
    return self;
}

- setAddressString:anObject
{
    addressString = anObject;
    return self;
}

- setOpenString:anObject
{
    openString = anObject;
    return self;
}

- setKeywords:anObject
{
    keywords = anObject;
    return self;
}

- setContentSearch:anObject
{
    contentSearch = anObject;
    return self;
}

- setManager:anObject;
{
    manager = anObject;
    [(HyperManager *)manager registerAccess:self];
    return self;
}

//	Methods to return the values of instance variables

- manager
{
    return manager;
}

//	Return the name of this access method

- (const char *)name
{
    return "Generic";
}


//		Actions:

//	These are all dummies, because only subclasses of this class actually work.

- search:sender
{
    return nil;
}

- searchRTF:sender
{
    return nil;
}

- searchSGML:sender
{
    return nil;
}

//	Direct open buttons:

- open:sender
{
    return nil;
}

- openRTF:sender
{
    return nil;
}

- openSGML:sender
{
    return nil;
}
- accessName:(const char *)name Diagnostic:(int)level
{
    return nil;		/* can't do that. */
}

//	This will load an anchor which has a name
 
- loadAnchor: (Anchor *) anAnchor
{
    return [self loadAnchor:anAnchor Diagnostic:0];	// If not otherwise implemented
}

- loadAnchor: (Anchor *)a Diagnostic:(int)diagnostic
{
    return nil;	
}

- saveNode:(HyperText *)aText
{
    NXRunAlertPanel(NULL,
"You cannot overwrite this original document. You can use `save a copy in...'",
	    	NULL,NULL,NULL);
    printf(
    "HyperAccess: You cannot save a hypertext document in this domain.\n");
    return nil;
}


//	Text Delegate methods
//	---------------------
//	These default methods for an access allow editing, and change the cross
//	in the window close button to a broken one if the text changes.

#ifdef TEXTISEMPTY
//	Called whenever the text is changed
- text:thatText isEmpty:flag
{
    if (TRACE) printf("Text %i changed, length=%i\n", thatText, [thatText textLength]);
    return self;
}
#endif

- textDidChange:textObject
{
    if (TRACE) printf("HM: text Did Change.\n");
    [[textObject window] setDocEdited:YES];	/* Broken cross in close button */
    return self;
}

- (BOOL)textWillChange:textObject
{
    if (TRACE) printf("HM: text Will Change -- OK\n");
    return NO;			/* Ok - you may change (sic) */
}


//	These delegate methods are special to HyperText:

- hyperTextDidBecomeMain: sender
{
    return [manager hyperTextDidBecomeMain: sender];	/* Pass the buck */
}
@end
