/*	Hypertext "Anchor" Object				       Anchor.h
**	==========================
**
**	An anchor represents a region of a hypertext node which is linked
**	to another anchor in the same or a different node.
*/

#import <objc/Object.h>
#import <objc/List.h>
#import <appkit/appkit.h>

//			Main definition of anchor:
//			========================== 

@interface Anchor:Object
{
    id		Node;		// The node within which this is an anchor
    				/* (HyperText *) */
				// If not a subanchor
    Anchor *	parent;		// If this is a subanchor
    List *	children;	// If this has subanchors, these are they.
       
//	Information about this anchor:

    char * 	Address;	// The address of this anchor

//	Generated locally, not archived:

    List *	Sources;	// A list of anchors pointing to this
    id		DestAnchor;	// The anchor, if loaded, to which this leads
}

+ initialize;
+ setManager:aManager;		// Set class variable

+ newAddress:(const char *)address;
+ newParent:(Anchor*)anAnchor tag:(const char *)tag;

+back;
+next;
+previous;

- (void)setNode:(id)node;
- (const char *)address;
- (char *)fullAddress;
- setAddress: (const char *) ref_string;
- select;			// Load if nec, select and bring to front
- selectDiagnostic:(int)diag;	// Same with source display option
- isLastChild;			// Move it in the list of children
- (BOOL)follow;			// Follow  link if we can, return "can we?"
- (void) linkTo:(Anchor *)destination;
- node;				// Return the node in which the anchor sits
- destination;			// Return the desination anchor
- parent;			// Return the parent if any
- unload;			// Make link dangle
@end


