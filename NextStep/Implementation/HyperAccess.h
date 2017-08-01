//	A HyperAccess object provides access to hyperinformation, using particular
//	protocols and data format transformations.

// History:
//	26 Sep 90	Written TBL

#import <objc/Object.h>
#import <objc/List.h>
#import "Anchor.h"
#import "HyperText.h"

@interface HyperAccess:Object

//	Target variables for interface builder hookups:

{
    id  manager;	// The object which manages different access mechanisms.
    id  openString;
    id	keywords;
    id	titleString;
    id	addressString;
    id	contentSearch;
    
}

//	Interface builder initialisation methods:

- setManager:anObject;
- setOpenString:anObject;
- setKeywords:anObject;
- setTitleString:anObject;
- setAddressString:anObject;
- setContentSearch:anObject;

//	Action methods for buttons etc:

- search:sender;
- searchRTF: sender;
- searchSGML: sender;

- open: sender;
- openRTF:sender;
- openSGML:sender;
- saveNode:(HyperText *)aText;

//	Calls form other code:

- manager;
- (const char *)name;				// Name for this access method
- loadAnchor:(Anchor *)a;			// Loads an anchor.
- loadAnchor:(Anchor *)a Diagnostic:(int)level ;// Loads an anchor.

//	Text delegate methods:

- textDidChange:textObject;
- (BOOL)textWillChange:textObject;

//	HyperText delegate methods:

- hyperTextDidBecomeMain:sender;


@end
