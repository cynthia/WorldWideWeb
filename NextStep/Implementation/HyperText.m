//	HyperText Implementation				    HyperText.m
//	------------------------
//
// HyperText is like Text, but includes links to and from other hypertexts.
//
// Authors:
//	TBL		Tim Berners-Lee CERN/CN
//
// See also:
//	The Anchor class, and the HyperAccess class.
//
// History:
//	25 Sep 90	Written (TBL) with the  help of the Interface builder.
//	14 Mar 91	Page width is taken from application's page layout.


// Notes.
//
//	For all anchors to have addresses, the node must be made with
//	newAnchor:Server: . Do not use any other creation methods inherited.

#import <appkit/appkit.h>
#import "HyperText.h"
#import "HyperAccess.h"
#import "HTUtils.h"
#import "HTParse.h"
#import "HTStyle.h"
#import "WWW.h"


@implementation HyperText

#define ANCHOR_ID_PREFIX 'z'	/* Auto anchors run z1, z2, ... 921122 */

extern        HTStyleSheet * styleSheet;	/* see StyleToy */

static int window_sequence = 0;		/* For stacking windows neatly */
#define SLOTS	30			/* Number of position slots */
static HyperText * slot[SLOTS];			/* Ids of HT objects taking them */


#define NICE_HEIGHT 600.0	/* Allows a few windows to be stacked */
#define MAX_HEIGHT 720.0	/* Worth going bigger to get it all in	*/
#define MIN_HEIGHT 80.0		/* Mustn't lose the window! */
#define MIN_WIDTH 200.0

static HyperText * HT;		/* Global pointer to self to allow C mixing */
+initialize
{
    int i;
    for (i=0; i<SLOTS; i++) slot[i] = 0;
    return [super initialize];
}

//	Get Application page layout's Page Width
//	----------------------------------------
//
//	Returned in pixels
//
static float page_width()
{
    PrintInfo * pi = [NXApp printInfo];			// Page layout details
    NXCoord topMargin, bottomMargin, leftMargin, rightMargin;
    const NXRect * paper = [pi paperRect];		//	In points
    
    [pi getMarginLeft:&leftMargin right:&rightMargin
    			top:&topMargin bottom:&bottomMargin];	/* In points */
    return (paper->size.width - leftMargin - rightMargin);

}


//			Class methods
//			-------------
//


//	Build a HyperText GIVEN its nodeAnchor.
//	--------------------------------------

+ newAnchor:(Anchor *)anAnchor Server:(id)aServer
{
    NXRect aFrame = {{0.0, 0.0}, {page_width(), NICE_HEIGHT}};
    
    self = [super newFrame:&aFrame];
    if (TRACE) printf("New node, server is %i\n", aServer);

    nextAnchorNumber = 0;
    protection = 0;		// Can do anything
    format = WWW_HTML;		// By default
    [self setMonoFont: NO];	// By default
    theRuns->chunk.growby = 16 * sizeof(theRuns->runs[0]); //  efficiency

    server = (HyperAccess *)aServer;
    [self setDelegate:aServer];			/* For changes */
    nodeAnchor= anAnchor;
    [nodeAnchor setNode:self];
    return self;
}

//			Instance Methods
//			----------------


//	Free the hypertext.

- free
{
    slot[slotNumber] = 0;	//	Allow slot to be reused
    [nodeAnchor setNode:nil];	// 	Invalidate the node    
    return [super free];
}


//	Read and set format

- (int) format 		{return format; }
- setFormat:(int)f 	{format = f; return self; }


//	Useful diagnostic routine:  Dump to standard output
//	---------------------------------------------------
//
//	This first lists the runs up to and including the current run,
//	then it lists the attributes of the current run.
//
- dump:sender
{
    int pos;				/* Start of run being scanned */
    int sob=0;				/* Start of text block being scanned */
    NXRun * r = theRuns->runs;
    NXTextBlock * block = firstTextBlock;
    
    printf("Hypertext %i, selected(%i,%i)", self, sp0.cp, spN.cp);
    if (delegate) printf(", has delegate");
    printf(".\n");
    
    printf("    Frame is at (%f, %f, size is (%f, %f)\n",
    	frame.origin.x, frame.origin.y,
    	frame.size.width, frame.size.height);
    
    printf("    Text blocks and runs up to character %i:\n", sp0.cp);
    for (pos = 0; pos<=sp0.cp; pos = pos+((r++)->chars)) {
	while(sob <= pos) {
	    printf("%5i: Block of %i/%i characters at 0x%x starts `%10.10s'\n",
	    	sob, block->chars,  malloc_size(block->text), block->text,
		block->text);
	    sob = sob + block->chars;
	    block = block->next;
	}
	printf("%5i: %3i of fnt=%i p=%i gy=%3.2f RGB=%i i=%i fl=%x\n",
	    pos, r->chars, (int)r->font, r->paraStyle,
	    r->textGray,r->textRGBColor, (int)(r->info),
	    *(int*)&(r->rFlags));

    }
    r--;	/* Point to run for start of selection */

    printf("\n    Current run:\n\tFont name:\t%s\n", [r->font name]);
    {
        NXTextStyle *p = (NXTextStyle *)r->paraStyle;
	if (!p) {
	    printf("\tNo paragraph style!\n");
	} else {
	    int tab;
	    printf("\tParagraph style %i\n", p);
	    printf("\tIndents: first=%f, left=%f\n",
	    	p->indent1st, p->indent2nd);
	    printf("\tAlignment type=%i, %i tabs:\n",
	    	p->alignment, p->numTabs);
	    for (tab=0; tab<p->numTabs; tab++) {
	    	printf("\t    Tab kind=%i at %f\n",
			p->tabs[tab].kind, p->tabs[tab].x);
	    }
	}
    }
    printf("\n");
    return self;
}


//	Adjust Scrollers and Window size for current text size
//	------------------------------------------------------
//
//The scrollers are turned off if they possibly can be, to simplify the screen.
// If the text is editable, they have to be left on, although formatted text is
// allowed to wrap round, and so horizontal scroll bars are not necessary.
// The window size is adjusted as a function of the text size and scrollers.
//
//	@@ Bug: The resize bar should be removed if there are no scrollers.
//	This is difficult to do -- might have to make a new window.
//
- adjustWindow
{
#define MAX_WIDTH  paperWidth

    NXRect scroll_frame;
    NXRect old_scroll_frame;
    NXSize size;
    BOOL scroll_X, scroll_Y;			// Do we need scrollers?
    
    ScrollView* scrollview = [window contentView];// Pick up id of ScrollView
    float paperWidth = page_width();		// Get page layout width
    
    
    [window disableFlushWindow];	// Prevent flashes
    
    [self setVertResizable:YES];	// Can change size automatically
    [self setHorizResizable:tFlags.monoFont];
    [self calcLine];			// Wrap text to current text size
    [self sizeToFit];			// Reduce size if possible.
    
    if (maxY > MAX_HEIGHT) {
    	scroll_Y = YES;
        size.height = NICE_HEIGHT;
    } else {
        scroll_Y = [self isEditable];
	size.height = maxY < MIN_HEIGHT ? MIN_HEIGHT : maxY;
    }

    if (tFlags.monoFont) {
    	scroll_X = [self isEditable] || (maxX>MAX_WIDTH);
	[self setNoWrap];
    } else {
    	scroll_X = NO;
        [self setCharWrap:NO];				// Word wrap please 
    }
    if (maxX > MAX_WIDTH) {
    	size.width = MAX_WIDTH;
    } else {
        size.width = maxX < MIN_WIDTH ? MIN_WIDTH : maxX;
    }

// maxX is the length of the longest line.
//	It only represnts the width of the page
//	 needed if the line is quad left. If the longest line was
//	centered or flush right, it may be truncated unless we resize
//	it to fit.

    if (!scroll_X) {
        [self sizeTo:size.width:maxY];
	[self calcLine];
	[self sizeToFit];		// Algorithm found by trial and error.
    }

//	Set up the scroll view and window to match:

    [ScrollView getFrameSize:&scroll_frame.size
    			forContentSize: &size
			horizScroller:	scroll_X
			vertScroller:	scroll_Y
			borderType: 	NX_LINE];
			
    [scrollview setVertScrollerRequired:scroll_Y];
    [scrollview setHorizScrollerRequired:scroll_X];

//	Has the frame size changed?

    [scrollview getFrame:&old_scroll_frame];
    if ( (old_scroll_frame.size.width != scroll_frame.size.width)
       ||(old_scroll_frame.size.height != scroll_frame.size.height)) {

				
// Now we want to leave the top left corner of the window unmoved:

#ifdef OLD_METHOD	
        NXRect oldframe;
	[window getFrame:&oldframe];
    	[window sizeWindow:scroll_frame.size.width:scroll_frame.size.height];
	[window moveTopLeftTo: oldframe.origin.x
			     : oldframe.origin.y + oldframe.size.height];
#else
	NXRect newFrame;
	scroll_frame.origin.x = 150 + (slotNumber % 10)   * 30
				    + ((slotNumber/10)%3)* 40;
	scroll_frame.origin.y = 185 + NICE_HEIGHT - scroll_frame.size.height
				    - (slotNumber % 10)   * 20
				    - ((slotNumber/10)%3)*  3;
	[Window getFrameRect:&newFrame
		forContentRect:&scroll_frame
		style:NX_TITLEDSTYLE];	// Doesn't allow space for resize bar
	newFrame.origin.y = newFrame.origin.y - 9.0;
	newFrame.size.height = newFrame.size.height + 9.0; // For resize bar
	[window placeWindow:&newFrame];	
#endif
    }
    
#ifdef VERSION_1_STRANGENESS
//	In version 2, the format of the last run is overwritten with the format
//	of the preceding run!
    {
      NXRect frm;		/* Try this to get over "text strangeness" */
      [self getFrame:&frm];      
      [self renewRuns:NULL text:NULL frame:&frm tag:0];
    }
#endif
    [window reenableFlushWindow];
    [self calcLine];		/* Prevent messy screen */
    [window display];		/* Ought to clean it up */
    return self;
    
} /* adjustWindow */


//	Set up a window in the current application for this hypertext
//	-------------------------------------------------------------

- setupWindow
{
    NXRect scroll_frame;				// Calculated later
    NXSize min_size = {300.0,200.0};			// Minimum size of text
    NXSize max_size = {1.0e30,1.0e30};			// Maximum size of text
   
    ScrollView * scrollview;
    NXSize nice_size = { 0.0, NICE_HEIGHT };		// Guess height
        
    nice_size.width = page_width();
    [ScrollView getFrameSize:&scroll_frame.size
    			forContentSize: &nice_size
			horizScroller:NO
			vertScroller:YES
			borderType: NX_LINE];

    {
    	int i;	/* Slot address */
	for(i=0; (i<SLOTS) && slot[i]; i++) ;	/* Find spare slot */
	if (i=SLOTS) i = (window_sequence = (window_sequence+1) % SLOTS);
	slot[i] = self;
	slotNumber = i;
	scroll_frame.origin.x = 150 + (slotNumber % 10)   * 30
				    + ((slotNumber/10)%3)* 40;
	scroll_frame.origin.y = 185 - (slotNumber % 10)   * 20
				    - ((slotNumber/10)%3)*  3;
     }
     
 //	Build a window around the text in order to display it.

#define NX_ALLBUTTONS 7  // Fudge -- the followin methos is obsolete in 3.0:    
    window = [Window newContent:		&scroll_frame
    				style:		NX_TITLEDSTYLE
				backing: 	NX_BUFFERED
				buttonMask:	NX_ALLBUTTONS
				defer:		NO];		// display now				
    [window setDelegate:self];			// Get closure warning
    [window makeKeyAndOrderFront:self];		// Make it visible
    [window setBackgroundGray: 1.0];		// White seems to be necessary.
    
    scrollview = [ScrollView newFrame:&scroll_frame];
    [scrollview setVertScrollerRequired:YES];
    [scrollview setHorizScrollerRequired:NO];		// Guess.
    [[window setContentView:scrollview] free]; 	// Free old view, size new one.

						
    [scrollview setDocView:self];
    [self setOpaque:YES];			// Suggested in the book
    [self setVertResizable:YES];		// Changes size automatically
    [self setHorizResizable:NO];
    [self setMinSize:&min_size];		// Stop it shrinking to nought
    [self setMaxSize:&max_size];		// Stop it being chopped when editing
    [self notifyAncestorWhenFrameChanged: YES]; // Tell scrollview See QA 555
    [window display];				// Maybe we will see it now
    return self;
}


//		Return Instance Variables
//		-------------------------
- server	{ return server;}
- nodeAnchor	{ return nodeAnchor; }
- (BOOL)isIndex	{ return isIndex; }


/*	Return reference to a part of, or all of, this node
**	---------------------------------------------------
*/

//	Generate an anchor for a given part of this node, giving it an
//	arbitrary (numeric) name.

- (Anchor *) anchor
{
    Anchor * a;
    char s[20];

    sprintf(s,"%c%i",ANCHOR_ID_PREFIX, nextAnchorNumber++);
    a = [Anchor newParent:nodeAnchor tag:s];
    [delegate textDidChange:self];
    return a;
}


//	Check whether an anchor has been selected
//	-----------------------------------------

- (Anchor *) anchorSelected
{
    int sor;
    NXRun *r, *s, *e;		/* Scan, Start and end runs */
    Anchor * a;
    
    
    for (sor = 0, s=theRuns->runs;
    	sor+s->chars<=sp0.cp;
    	sor = sor+((s++)->chars)) ;
    for (e=s; sor+e->chars<spN.cp; sor = sor+ (e++)->chars);
    for(r=s; r<=e; r++) {
	if (a= (Anchor *)r->info) return a;
    }
    if (TRACE) printf("HyperText: No anchor selected.\n");
    return nil;
}


//	Public method:	Generate an anchor for the selected text
//	--------------------------------------------------------
//
//	If the document is not editable, then nil is returned
//	(unless the user asks for an existing anchor).
//
- (Anchor *) referenceSelected
{
    Anchor * a;
    HTStyle * style = HTStyleNew();
    
    a = [self anchorSelected];
    if (a) return a;			/* User asked for existing one */
    
    if ([self isEditable]) [window setDocEdited:YES];
    else return nil;

    a = [self anchor];
    style->anchor = a;
    [self applyStyle:style];
    if (TRACE) printf("HyperText: New dest anchor %i from %i to %i.\n",
    	a, sp0.cp, spN.cp);
    [delegate textDidChange:self];
    return a;
}

//	Generate a live anchor for the text, and link it to a given one
//	----------------------------------------------------------------

- (Anchor *) linkSelTo:(Anchor *)anAnchor
{
    Anchor * a;
    HTStyle * style = HTStyleNew();
    
    if (!anAnchor) return nil;			/* Anchor must exist */
    
    if ([self isEditable]) [window setDocEdited:YES];
    else return nil;
    
    a = [self anchorSelected];
    if (!a) {
	a = [self anchor];
    	if (TRACE) printf("HyperText: New source anchor %i from %i to %i.\n",
	 		a, sp0.cp, spN.cp);
    } else {
	[a select];
    	if (TRACE) printf("HyperText: Existing source anchor %i selected.\n",a);
    }
    style->anchor = a;
    [a linkTo:anAnchor];		// Link it up
    [self applyStyle:style];		// Will highlight it because linked
    free(style);
    return a;
}


//	Purge anchor from selected text
//	-------------------------------
//
//	The anchor is left becuase in general we don't delete anchors.
//	In any case, we would have to check whether all text referencing it
//	was deleted.
//
- unlinkSelection
{
    HTStyle * style = HTStyleNew();
    
    if ([self isEditable]) [window setDocEdited:YES];
    else return nil;
    
    style->anchor = CLEAR_POINTER;
    [self applyStyle:style];
    free(style);
    return self;
}


- (Anchor *) referenceAll
{
    return nodeAnchor;	// Just return the same one each time
    
}


//	Select an anchor
//	----------------
//
//	If there are any runs linked to this anchor, we select them. Otherwise,
//	we just bring the window to the front.

- selectAnchor:(Anchor *)anchor
{
    NXRun *s, *e;	/* run for start, run for end */
    int start, sor;
    NXRun * limit = (NXRun *)((char *)theRuns->runs + theRuns->chunk.used);
    for (sor=0, s=theRuns->runs; s<limit; sor = sor+(s++)->chars) {
        if (s->info == (void *)anchor){
		start = sor;
		
	        for (e=s; (e < limit)
				&&((e+1)->info == (void*)anchor);
			sor = sor+(e++)->chars);
    		[window makeKeyAndOrderFront: self];
		[self setSel:start:sor+e->chars];
		return [self scrollSelToVisible];
	    }
    }
    if (TRACE) printf("HT: Anchor has no explicitly related text.\n");
    return [window makeKeyAndOrderFront: self];
}


//

//	Return selected link (if any)				selectedLink:
//	-----------------------------
//
//	This implementation scans down the list of anchors to find the first one
//	on the list which is at least partially selected.
//

- selectedLink
{

    int sor;			/* Start of run */
    NXRun *r, *s, *e;		/* Scan, Start and end runs */
    Anchor * a;
    int startPos, endPos;
    
    for (sor = 0, s=theRuns->runs;
    	sor+s->chars<=sp0.cp;
    	sor = sor+((s++)->chars)) ;
    startPos = sor;			/* Start of s */
    for (e=s; sor+e->chars<spN.cp; sor = sor+ (e++)->chars);
    for(r=s, a=nil; r<=e; startPos = startPos + (r++)->chars) {
	if (a= (Anchor *)r->info) {
	    break;
	}
    }

    if (!a) {
        if (TRACE) printf("HyperText: No anchor selected.\n");
	return nil;
    }
    
//	Extend/reduce selection to entire anchor

    {
	endPos = startPos + r->chars;
 	for (s=r; (Anchor *)((s-1)->info) == a; s--)
		startPos = startPos-(s-1)->chars;
	for (e=r; (Anchor *)((e+1)->info) == a; e++)
		endPos   =   endPos+(e+1)->chars;
	[self setSel:startPos:endPos];
    }
    return a;
}

///	Follow selected link (if any)				followLink:
//	-----------------------------
//

//	Find selected link and follow it

- followLink
{
    Anchor * a = [self selectedLink];

    if (!a) return a;		// No link selected
   
    if ([a follow]) return a;	// Try to follow link
    
    if (TRACE) printf("HyperText: Can't follow anchor.\n");
    return a;			// ... but we did highlight it.
}

- setTitle:(const char *)title
{
    return [window setTitle:title];
}


//				STYLE METHODS
//				=============
//

//	Find Unstyled Text
//	------------------
//
// We have to check whether the paragraph style for each run is one
// on the style sheet.
//
- selectUnstyled: (HTStyleSheet *)sheet
{
    NXRun * r = theRuns->runs;
    int sor;
    for (sor=0; sor<textLength; r++) {
        if (!HTStyleForParagraph(sheet, r->paraStyle)) {
	    [self setSel:sor:sor+r->chars];	/* Select unstyled run */
	    return self;
	}
        sor = sor+r->chars;
    }
    return nil;
}


//	Copy a style into a run
//	-----------------------
static void apply(HTStyle * style, NXRun * r)
{
    if (style->font) {
	r->font = style->font;
    }
    if (style->paragraph) {
	r->paraStyle = style->paragraph;
    }
    if (style->anchor) {
	r->info = (style->anchor == CLEAR_POINTER) ? 0 : (style->anchor);
    }
    
    
    if (style->textGray>=0)
    	r->textGray = style->textGray;
	
    r->rFlags.underline = NO;
    if (r->info) {
//    	r->textGray = 0.166666666;		/* Slightly grey - horrid */
        if ([(Anchor *)(r->info) destination]) {
//	    r->textGray = NX_DKGRAY;	/* Anchor highlighting */
	    r->rFlags.underline = YES;
	}
    }
    r->rFlags.dummy = (r->info != 0);		/* Keep track for typingRun */
    
    if (style->textRGBColor>=0)
    	r->textRGBColor = style->textRGBColor;
}


//	Check whether copying a style into a run will change it
//	-------------------------------------------------------

static BOOL willChange(HTStyle * style, NXRun *r)
{
    if (r->font != style->font) return YES;

    if (style->textRGBColor>=0)
    	if (r->textRGBColor != style->textRGBColor) return YES;

    if (style->textGray>=0)
    	if (r->textGray != style->textGray) return YES;

    if (style->paragraph) {
        if (r->paraStyle != style->paragraph) return YES;
    }
    if (style->anchor) {
        if (r->info != style->anchor) return YES;
    }
    return NO;
}

//	Update a style
//	--------------
//
//
- updateStyle:(HTStyle *)style
{
    NXRun * r = theRuns->runs;
    int sor;
    for (sor=0; sor<textLength; r++) {
        if (r->paraStyle == style->paragraph) 
	    apply(style, r);
        sor = sor+r->chars;
    }
    [self calcLine];
    [window display];
    return nil;
}


//	Delete an anchor from this node, without freeing it.
//	----------------
//
//
- disconnectAnchor:(Anchor *)anchor
{
    NXRun * r = theRuns->runs;
    int sor;
    for (sor=0; sor<textLength; r++) {
        if (r->info == (void *)anchor) 
	    r->info = 0;
	    r->textGray =  NX_BLACK;
        sor = sor+r->chars;
    }
    [window display];
    return nil;
}


//	Find start of paragraph
//	-----------------------
//
//	Returns the position of the character after the newline, or 0.
//
- (int) startOfParagraph: (int) pos
{
    NXTextBlock * block;
    int sob;
    unsigned char * p;
    for(block=firstTextBlock, sob=0; sob+block->chars <=pos; block=block->next)
        sob = sob + block->chars;
    for(p=block->text+(pos-sob)-1; p >= block->text; p--)
        if (*p == '\n') return sob + (p - block->text) +1 ;/* Position of newline */
    while (block->prior) {
        block = block->prior;
	sob = sob - block->chars;
        for(p=block->text+(block->chars-1); p>=block->text; p--)
            if (*p == '\n') return sob + (p-block->text)+1;/* Position of newline */
    }
    return 0;
}


//	Find end of paragraph
//	-----------------------
//
//	Returns the position after the newline, or the length of the text.
//	Note that any number of trailing newline characters are included in
//	this paragraph .. basically because the text object does not support
//	the concept of space after or before paragraphs, so extra paragrpah
//	marks must be used.
//
- (int) endOfParagraph: (int) pos
{
    NXTextBlock * block;
    int sob;
    unsigned char * p;
    BOOL found_newline = NO;
    
    if (pos>=textLength) return textLength;
    
    for(block=firstTextBlock, sob=0; sob+block->chars <=pos; block=block->next)
        sob = sob + block->chars;	// Find text block for pos
    
    p = block->text+(pos-sob);		// Start part way through this one
    
    while (block) {
        for(; p < block->text+block->chars; p++) {
            if (found_newline) {
	    	if (*p != '\n')
		    return sob + (p-block->text); /* Position after newline */
	    } else {
		if (*p == '\n') {
		    found_newline = YES;
		}
	    }
	}
	sob = sob + block->chars;	/* Move to next block */
        block = block->next;
	if (block) p = block->text;
	
    }
    return textLength;
}


//	Do two runs imply the same format?
//	----------------------------------

BOOL run_match(NXRun* r1, NXRun *r2)
{
    return 	(r1->font == r2->font)
    	&&	(r1->paraStyle == r2->paraStyle)
    	&&	(r1->textGray == r2->textGray)
    	&&	(r1->textRGBColor == r2->textRGBColor)
	&&	(r1->superscript == r2->superscript)
	&&	(r1->subscript == r2->subscript)
	&&	(r1->info == r2->info)
	&&	(*(int *)&r1->rFlags == *(int*)&r2->rFlags);
}

//	Check Consecutive runs and merge if necessary
//	---------------------------------------------
//
//	If the runs match in EVERY way, they are combined into one, and
//	all the other runs are shuffled down.
//
- (BOOL) mergeRun: (NXRun *) run
{
    NXRun * r, *last;
    if (run_match(run, run+1) ) {
        if (TRACE) printf("HT: Merging run %i\n", run);
        run->chars = run->chars +(run+1)->chars;
	last = ((NXRun *)((char*)theRuns->runs + theRuns->chunk.used))-1;
	for(r=run+1; r<last; r++) r[0] = r[1];
        theRuns->chunk.used = theRuns->chunk.used - sizeof(*r);
    	return YES;
    }
    return NO;
}


//	Apply style to a given region
//	-----------------------------
//
// 	Note that one should not have two consecutive runs of the same style,
// 	nor any zero length runs. We have a little calculation, therefore,
// 	in order to work out how many runs will eventually be needed:
//	this may be more or less than we started with.
//	Remember that appling a style to a run may or may not change it.
//
//	PS: Actually, we notice that text insertion does leave two consecutive
//	runs the same in the Text object, but deletion cleans up.


- applyStyle:(HTStyle *)style from:(int)start to:(int)end
{
    int pos;				/* Character position within text */
    int increase;			/* Number of runs to be split	*/
    int new_used;			/* New number of bytes in runs	*/
    BOOL need_run_before, need_run_after;/* Sometimes we don't need them	*/
    int	run_before_start, run_after_end;/* Start of run_before etc 	*/
    NXRun * s, *e;			/* Start and end run 		*/
    NXRun *p;				/* Pointer to run being read	*/
    NXRun *w;				/* Pointer to run being written	*/
    NXRun *r;				/* Pointer to end of runs	*/
    
    if (start == end) {
        apply(style, &typingRun);		/* Will this work? */
        if (TRACE) printf("Style applied to typing run\n");
	return nil;				/* Can't operate on nothing */
    }

//	First we determine in which runs the first and last characters to
//	be changed lie.
   
    for (pos=0, s=theRuns->runs; pos+s->chars<=start;
    			pos = pos+((s++)->chars)) /*loop*/;
/*	s points to run containing char after selection start */
    run_before_start = pos;

    for (e=s; pos+e->chars < end; pos = pos+((e++)->chars)) ;	/* Find end run */
/*	e points to run containing character before selection end */
    run_after_end = pos+e->chars;

    r = (NXRun *) (((char *)(theRuns->runs)) +theRuns->chunk.used);	/* The end*/
    
    if (TRACE) {
        printf("Runs: used=%i, elt. size=%i, %i elts, total=%i\n",
    		theRuns->chunk.used, sizeof(*r), r - theRuns->runs,
		(r-theRuns->runs)*sizeof(*r) );   
	printf("    runs at %i, r=%i. textLength:%i, r ends at:%i\n",
		theRuns->runs, r, textLength, pos);
    }
    
       
//	Move up runs as necessary in order to make room for the splitting
//	of the start and end runs into two.  We only do this if necessary.

    if (!willChange(style, s))
        start = run_before_start;	/* No run before is needed now */
    need_run_before = (start>run_before_start);
 
    if (!willChange(style, e)) 
        end = run_after_end;			/* No run after is needed now */
    need_run_after = (end < run_after_end);

    if (TRACE) printf(
    	"Run s=%i, starts at %i; changing (%i,%i); Run e=%i ends at %i\n",
    	s-theRuns->runs, run_before_start, start, end, e-theRuns->runs, run_after_end); 
    
    increase = need_run_after + need_run_before;
    if (increase) {
        new_used = theRuns->chunk.used + increase*sizeof(*r);   
	if (new_used> theRuns->chunk.allocated) {
	    NXRun* old = theRuns->runs;
	    theRuns = (NXRunArray*)NXChunkGrow(&theRuns->chunk, new_used);
	    if (theRuns->runs !=old) {			/* Move pointers */
		if (TRACE) printf("HT:Apply style: moving runs!\n");
		e = theRuns->runs + (e-old);
		r = theRuns->runs + (r-old);
		s = theRuns->runs + (s-old);
	    }
	}
	for (p=r-1; p>=e; p--) p[increase] = p[0];	/* Move up the runs after */
	r = r+increase;					/* Point to after them 910212*/
	/* p = e-1 */
	
	if (need_run_after) {
	    e = e + increase-1;				/* Point last to be changed */
	    e[0] = e[1];				/* Copy the last run */
	    e[1].chars = run_after_end - end;
	    e[0].chars = e[0].chars - e[1].chars;	/* Split the run into two */
	}
	
	if (need_run_before) {
	    for(;p>=s; p--) p[1] = p[0];		/* Move runs up, copying 1st*/
	    s[0].chars = start - run_before_start;	/* Split the run into two */
	    if (need_run_after && (s+1==e)) {		/* If only one middle run */
		s[1].chars = end-start;			/* The run we need */
	    } else {
	        s[1].chars = s[1].chars - s[0].chars;	/* The remainder */
	    }
	    s++;		/* Move on to point to first run to be changed */
	    if (!need_run_after) e++;			/* First to be changed */
	}
    	theRuns->chunk.used = new_used; 
	
    } /* end if increase */
    
//	We consider the bit of text which is to be styled, s thru e.
//	We scan through, first, applying the style, until we find two runs which
//	need to be merged.

    p=s;
    if (p==theRuns->runs) {
        apply(style, p++);		/* Don't merge with run -1! */
    }
    
    for(; p<=e; p++) {
	apply(style, p);
	if (run_match(p,p-1)) {
	    break;
        }
    }

//	Once we have merged two runs, we have to copy the rest of them across,
//	merging others as necessary.

    w = p-1;			/* w now points to last written run */
    for(;p<=e; p++) {
        apply(style, p);
	if (run_match(p,w)) {
	    w->chars = w->chars+p->chars;	/* Combine  with w */
	} else {
	    w++;				/* or skip */
	    *w = *p;				/* and keep a copy */
	}
    }

//	Now, is any runs were merged, we have to copy the rest of the runs down
//	and decrease the size of the chunk.

    w++;					/* Point to next to be written */
    if (w<p) {					/* If any were moved, */
	for(;p<r;) *w++ = *p++;			/* Move the following runs down */	
    	theRuns->chunk.used = (char*)w - (char*)theRuns->runs; 
    }
    
    [self calcLine];				/* Update line breaks */
    return [window display];				/* Update window */
}


//	Apply a style to the selection
//	------------------------------
//
//	If the style is a paragraph style, the
//	selection is extended to encompass a number of paragraphs.
//
- applyStyle:(HTStyle *)style
{
    int start, end;
    if (TRACE) printf("Applying style %i to (%i,%i)\n",
    		style, sp0.cp, spN.cp);
    
    if (sp0.cp<0) {					/* No selection */
    	return [self applyStyle:style from:0 to:0];	/* Apply to typing run */
    }
    
    if (!style) return nil;

    if ([self isEditable]) [window setDocEdited:YES];
    else return nil;

    	
    start = sp0.cp;
    end = spN.cp;
    if (style->paragraph) {	/* Extend to an integral number of paras. */
        start = [self startOfParagraph:start];
        end = [self endOfParagraph:end];
    }
    return [self applyStyle:style from:start to:end];
}


//	Apply style to all similar text
//	-------------------------------
//
//
- applyToSimilar:(HTStyle*)style
{
    NXRun * r = theRuns->runs;
    int sor;
    NXRun old_run;
    
    for (sor = 0; sor<=sp0.cp; sor = sor+((r++)->chars)) ;/* Find run after */
    old_run = *(r-1);			/* Point to run for start of selection */

    if (TRACE) printf(
    	"Applying style %i to unstyled text similar to (%i,%i)\n",
    	style, sp0.cp, spN.cp);

    for(r=theRuns->runs;
    	 (char*)r-(char*)theRuns->runs < theRuns->chunk.used; r++) {
        if (r->paraStyle == old_run.paraStyle) {
	    if(TRACE) printf("    Applying to run %i\n", r);
	    apply(style,r);
	    if (r!=theRuns->runs){
	    	if ([self mergeRun:r-1]) r--;	/* Do again if shuffled down */
	    }
	}
    }
    [self calcLine];
    [window display];
    return self;
}

//	Pick up the style of the selection
//	----------------------------------

- (HTStyle *) selectionStyle:(HTStyleSheet *) sheet
{
    NXRun * r = theRuns->runs;
    int sor;
    
    for (sor = 0; sor<=sp0.cp; sor = sor+((r++)->chars)) ;/* Find run after */
    r--;				/* Run for start of selection */
    return HTStyleForRun(sheet, r);	/* for start of selection */
    
}


//	Another replaceSel method, this time using styles:
//	-------------------------------------------------
//
//	The style is as given, or where that is not defined, as the
//	current style of the selection.

- replaceSel: (const char *)aString style:(HTStyle*)aStyle
{
    NXRun * r = theRuns->runs;
    int sor;
    NXRunArray	newRuns;
    
    for (sor = 0; sor<=sp0.cp; sor = sor+((r++)->chars)) ;/* Find run after */
    r--;					/* Run for start of selection */
    newRuns.runs[0] = *r;			/* Copy it */
    newRuns.chunk.used = sizeof(*r);		/* 1 run used */
    apply(aStyle, newRuns.runs);		/* change it */
    newRuns.runs->chars = strlen(aString);	/* Match the size to the string */
    return [self replaceSel:aString length:newRuns.runs->chars runs:&newRuns];
}


//	Read in as Plain Text					readText:
//	---------------------
//
//	This method overrides the method of Text, so as to force a plain text
//	hypertext to be monofont and fixed width.  Also, the window is updated.
//
- readText: (NXStream *)stream
{
//    [self setMonoFont:YES];		Seems to leave it in a strange state
    [self setHorizResizable:YES];
    [self setNoWrap];
    [self setFont:[Font newFont:"Ohlfs" size:10.0]];	// @@ Should be XMP
    [super readText:stream];
    format = WWW_PLAINTEXT;				// Remember
    
#ifdef NOPE
    {
      NXRect frm;		/* Try this to get over "text strangeness" */
      [self getFrame:&frm];      /* on plain text only Aug 91 */
      [self renewRuns:NULL text:NULL frame:&frm tag:0];
    }
#endif
    [self adjustWindow];
    return self;
}


//	Read in as Rich Text					readRichText:
//	---------------------
//
//	This method overrides the method of Text, so as to force a plain text
//	hypertext to be monofont and fixed width.  Also, the window is updated.
//
- readRichText: (NXStream *)stream
{
    id status =  [super readRichText:stream];
    [self adjustWindow];
    format = WWW_RICHTEXT;				// Remember
    return status;
}

//				Window Delegate Methods
//				=======================

//	Prevent closure of edited window without save
//
- windowWillClose:sender
{
    int choice;
    if (![window isDocEdited]) return self;
    choice = NXRunAlertPanel("Close", "Save changes to `%s'?",
    	"Yes", "No", "Don't close", [window title]);
    if (choice == NX_ALERTALTERNATE) return self;
    if (choice == NX_ALERTOTHER) return nil;
    return [server saveNode:self];
}

//	Change configuration as window becomes key window
//
- windowDidBecomeMain:sender
{
    return [delegate hyperTextDidBecomeMain:self];
}

/*				FORMAT CONVERSION FROM SGML
**				===========================
**
**	As much as possible, this is written in C for portability. It is in a separate
**	include file which could be used elsewhere.
*/
/*		Input procedure for printing a trace as we go
*/
#define NEXT_CHAR NXGetc(sgmlStream)
#define BACK_UP NXUngetc(sgmlStream)

/*	Globals for using many subroutines within a method
*/
static NXStream		*sgmlStream;
static HyperText * HT;				/* Pointer to self for C */

//	Inputting from the text object:
//	------------------------------

static unsigned char * read_pointer;		/* next character to be read */
static unsigned char * read_limit;
static NXTextBlock * read_block;

void start_input()
{
    read_block = HT->firstTextBlock;
    read_pointer = read_block->text;	/* next character to be read */
    read_limit = read_pointer+read_block->chars;
}

unsigned char next_input_block()
{
    char c = *read_pointer;
    read_block = read_block->next;
    if (!read_block) read_block = HT->firstTextBlock;	/* @@@ FUDGE */
    read_pointer = read_block->text;
    read_limit = read_pointer + read_block->chars;
    return c;
}
#define START_INPUT start_input()
#define NEXT_TEXT_CHAR (read_pointer+1==read_limit? next_input_block():*read_pointer++)


//			Outputting to the text object
//			=============================
//
//	These macros are used by the parse routines
//
#define BLOCK_SIZE NX_TEXTPER			/* Match what Text seems to use */

static NXTextBlock 	*write_block;		/* Pointer to block being filled */
static unsigned char 	*write_pointer;	/* Pointer to next characetr to be written */
static unsigned char	*write_limit;	/* Pointer to the end of the allocated area*/
static NXRun *		lastRun;	/* Pointer to the run being appended to */
static int		original_length; /* of text */

#define OUTPUT(c)	{ *write_pointer++ = (c); \
	if (write_pointer==write_limit) {end_output(); append_start_block(); }}
#define OUTPUTS(string)	{const char * p; for(p=(string);*p;p++) OUTPUT(*p);}
#define START_OUTPUT    append_begin()
#define FINISH_OUTPUT	finish_output()
#define LOADPLAINTEXT	loadPlainText()
#define SET_STYLE(s) set_style(s)


//	Allocate a text block to accumulate text
//
// Bugs:
// It might seem logical to set the "malloced" bit to 1, because the text block
// has been allocted with malloc(). However, this crashes the program as at the
// next edit of the text, the text object frees the block while still using it.
// Chaos results, sometimes corrupting the stack and/or looping for ages. @@
// We therefore set it to zero! (This might have been something else -TBL)
//
void append_start_block()
{	
    NXTextBlock *previous_block=write_block;	/* to previous write block */
    
    if (TRACE)printf("    Starting to append new block.\n");
        
    lastRun = ((NXRun*) ((char*)HT->theRuns->runs +
    				HT->theRuns->chunk.used))-1;
    write_block = (NXTextBlock*)malloc(sizeof(*write_block));
    write_block->tbFlags.malloced=0;		/* See comment above */
    write_block->text = (unsigned char *)malloc(BLOCK_SIZE);
    write_block->chars = 0;			// For completeness: not used.
    write_pointer = write_block->text;
    write_limit = write_pointer + BLOCK_SIZE;

//	Add the block into the linked list after previous block:

    write_block->prior = previous_block;
    write_block->next = previous_block->next;
    if (write_block->next) write_block->next->prior = write_block;
        else HT->lastTextBlock = write_block;
    previous_block->next = write_block;
     

}

// 	Start the output process altogether
//
void append_begin()
{
    if (TRACE)printf("Begin append to text.\n");
    
    [HT setText:""];				// Delete everything there
    original_length = HT->textLength; 
    if (TRACE) printf("Text now contains %i characters\n", original_length);

        
    lastRun = ((NXRun*) ((char*)HT->theRuns->runs +
    			HT->theRuns->chunk.used))-1;

//	Use the last existing text block:

    write_block = HT->lastTextBlock;
    
//	It seems that the Text object doesn't like to be empty: it always wants to
//	have a newline in at leats. However, we need it seriously empty and so we
//	forcible empty it. CalcLine will crash if called with it in this state.

    if (original_length==1) {
        if (TRACE) printf("HT: Clearing out single character from Text.\n");
        lastRun->chars =  0;		/* Empty the run */
	write_block->chars = 0;		/* Empty the text block */
	HT->textLength = 0;		/* Empty the whole Text object */
	original_length = 0;		/* Note we have cleared it */
    }

    write_pointer = write_block->text+write_block->chars;
    write_limit = write_pointer + BLOCK_SIZE;
}


//	Set a style for new text
//
void set_style(HTStyle *style)
{
    if (!style) {
        if (TRACE) printf("set_style: style is null!\n");
	return;
    }
    if (TRACE) printf("    Changing to style `%s' -- %s change.\n",
    	style->name, willChange(style, lastRun) ? "will" : "won't");
    if (willChange(style, lastRun)) {
	int size = (write_pointer - write_block->text);
	lastRun->chars = lastRun->chars + size - write_block->chars;
	write_block->chars = size;
        if (lastRun->chars) {
	    int new_used = (((char *)(lastRun+2)) - (char*)HT->theRuns->runs);
	    if (new_used > HT->theRuns->chunk.allocated) {
	    	if (TRACE) printf("    HT: Extending runs.\n"); 
		HT->theRuns = (NXRunArray*)NXChunkGrow(
			&HT->theRuns->chunk, new_used);
		lastRun = ((NXRun*) ((char*)HT->theRuns->runs +
					 HT->theRuns->chunk.used))-1;
	    }
	    lastRun[1]=lastRun[0];
	    lastRun++;
	    HT->theRuns->chunk.used = new_used; 
	}
	apply(style, lastRun);
	lastRun->chars = 0;		/* For now */
    }
}


//	Transfer text to date to the Text object
//	----------------------------------------
void end_output()
{
    int size = (write_pointer - write_block->text);
    if (TRACE)printf(
    	"    HT: Adding block of %i characters, starts: `%.20s...'\n",
    	size, write_block->text);
    lastRun->chars = lastRun->chars + size - write_block->chars;
    write_block->chars = size;
    HT->textLength = HT->textLength + size;

}


//	Finish altogether
//	-----------------

void finish_output()
{
    int size = write_pointer - write_block->text;
    if (size==0) {
        HT->lastTextBlock = write_block->prior;	/* Remove empty text block */
	write_block->prior->next = 0;
	free(write_block->text);
	free(write_block);
    } else {
	end_output();
    }

// get rid of zero length run if any

    if (lastRun->chars==0) {		/* Chop off last run */
        HT->theRuns->chunk.used= (char*)lastRun - (char*)HT->theRuns;
    }
    
//	calcLine requires that the last character be a newline!
    {
        unsigned char * p = HT->lastTextBlock->text +
			    HT->lastTextBlock->chars - 1;
	if (*p != '\n') {
	    if (TRACE)
	    printf(
	    "HT: Warning: Last character was %i not newline: overwriting!\n",
	    	*p);
	    *p = '\n';
	}
    }

    [HT adjustWindow];			/* Adjustscrollers and window size */

}

//	Loading plain text

void loadPlainText()
{
    [HT setMonoFont:YES];
    [HT setHorizResizable:YES];
    [HT setNoWrap];
    [HT readText:sgmlStream];	/* will read to end */
    [HT adjustWindow];		/* Fix scrollers */
}


//	Methods enabling an external parser to add styled data
//	------------------------------------------------------
//
//	These use the macros above in the same way as a built-in parser would.
//
- appendBegin
{
    HT = self;
    START_OUTPUT;
    return self;
}

- appendStyle:(HTStyle *) style
{
    SET_STYLE(style);
    return self;
}
- appendText: (const char *)text
{
    OUTPUTS(text);
    return self;
}

- appendEnd
{
    FINISH_OUTPUT;
    return self;
}

//	Begin an anchor

- (Anchor *)appendBeginAnchor: (const char *)name to:(const char *)reference
{
    HTStyle * style = HTStyleNew();
    char * parsed_address;
    Anchor * a =  *name ? [Anchor newParent:nodeAnchor tag:name]
    			: [self anchor];

    style->anchor = a;
    [(Anchor *)style->anchor isLastChild];	/* Put in correct order */	      
    if (*reference) {			/* Link only if href */
	parsed_address = HTParse(reference, [nodeAnchor address], PARSE_ALL);
	[(Anchor *)(style->anchor) linkTo: [Anchor newAddress:parsed_address]];
	free(parsed_address);
    }
    SET_STYLE(style);		/* Start anchor here */
    free(style);
    return a;
}


- appendEndAnchor			// End it
{
    HTStyle * style = HTStyleNew();
    style->anchor = CLEAR_POINTER;
    SET_STYLE(style);		/* End anchor here */
    free(style);
    return self;
}

//	Reading from a NeXT stream
//	--------------------------

#define END_OF_FILE	NXAtEOS(sgmlStream)
#define NEXT_CHAR	NXGetc(sgmlStream)
#define BACK_UP		NXUngetc(sgmlStream)

#include "ParseHTML.h"



//			Methods overriding Text methods
//			===============================
//
//	Respond to mouse events
//	-----------------------
//
// The first click will have set the selection point.  On the second click,
// we follow a link if possible, otherwise we allow Text to select a word as usual.
//
- mouseDown:(NXEvent*)theEvent
{
    if (theEvent->data.mouse.click != 2) return [super mouseDown:theEvent];
    if (![self followLink]) return [super mouseDown:theEvent];
    return self;
}


//	The following are necessary to undo damage done by the Text object
//	in version 2.0 of NeXTStep. For some reason, iff the "info" is
//	nonzero, text typed in is given
//	a different copy of the typingRun parastyle, and zero anchor info.
//	Otherwise, the current run is broken in two at the insertion point,
//	but no changes made to the run contents.
//	The problem with simply repairing is that many runs will be made inside
//	an anchor.
//	We have to use a "dummy" flag to mean "This has an anchor: be careful!"
//	This is horrible.

- keyDown:(NXEvent*)theEvent
#ifdef TRY1
{
    id result;
    NXTextStyle *typingPara = typingRun.paraStyle;
    int originalLength = textLength;
    int originalStart = sp0.cp;
    int originalEnd = spN.cp;
    result = [super keyDown:theEvent];
    
    {
	int inserted = originalEnd-originalStart +
			textLength-originalLength;
	
	if (TRACE) printf(
    "KeyDown, size(sel) %i (%i-%i)before, %i (%i-%i)after.\n",
	    originalLength, originalStart, originalEnd,
	    textLength, sp0.cp, spN.cp);
	    
	if (inserted>0) {
	    NXRun * s;
	    int pos;
	    int start = sp0.cp-inserted;
	    for (pos=0, s=theRuns->runs; pos+s->chars<=start;
		    pos = pos+((s++)->chars)) /*loop*/;

//	s points to run containing first char of insertion

	    if (pos!=start)
		    printf(
	    "HT: Strange: inserted %i at %i, start of run=%i !!\n",
				    inserted, start, pos);
				    
	    if (s > theRuns->runs) {	/* ie s-1 is valid */
		s->paraStyle = typingPara;	/* Repair damage to runs */
		/* What about freeing the old paragraph style? @@ */
		s->info = (s-1)->info;
		s->rFlags.dummy = 1;	/* Pass on flag */
	    }
	    
	}
    }
    return result;
}
#else
//	The typingRun field does not seem to reliably reflect the
//	format which would be appropriate if typing were to occur.
//	We have to use our own.
{
    NXRun run;
    {
	NXRun * s;	/* To point to run BEFORE selection */
	int pos;

/* 	If there is a nonzero selection, take the run containing the
**	first character. If the selection is empty, take the run containing the
**	character before the selection.
*/
	if (sp0.cp == spN.cp) {
	    for (pos=0, s=theRuns->runs; pos+s->chars<sp0.cp;	/* Before */
		pos = pos+((s++)->chars)) /*loop*/;
	} else {
	    for (pos=0, s=theRuns->runs; pos+s->chars<=sp0.cp;	/* First ch */
		pos = pos+((s++)->chars)) /*loop*/;
	}

/*	Check our understanding */

	if (typingRun.paraStyle != 0) {
	    if  (typingRun.paraStyle != s->paraStyle)
	        printf("WWW: Strange: Typing run has bad style.\n");
	    if ((s->info != 0)
	        && (typingRun.info != s->info))
	        printf(
		"WWW: Strange: Typing run has bad anchor info.\n");
	}
	
	typingRun = *s;		/* Copy run to be used for insertion */
	run = *s;		/* save a copy */
    }
    
    if (!run.rFlags.dummy) return [super keyDown:theEvent]; // OK!

    {
	id result;
	int originalLength = textLength;
	int originalStart = sp0.cp;
	int originalEnd = spN.cp;
	result = [super keyDown:theEvent];
	
/* 	Does it really change? YES!
*/    
	if (TRACE) {
	    if (typingRun.info != run.info) printf(
		"Typing run info was %p, now %p !!\n",
		run.info, typingRun.info);
	    if (typingRun.paraStyle != run.paraStyle) printf(
		"Typing run paraStyle was %p, now %p !!\n",
		run.paraStyle, typingRun.paraStyle);
	}
/*	Patch the new run if necessary:
*/
	{
	    int inserted = originalEnd-originalStart +
	    		 textLength-originalLength;
	    
	    if (TRACE) printf(
	"KeyDown, size(sel) %i (%i-%i)before, %i (%i-%i)after.\n",
		originalLength, originalStart, originalEnd,
		textLength, sp0.cp, spN.cp);

	    if (inserted>0) {
	    	NXRun * s;
		int pos;
		int start = sp0.cp-inserted;
    		for (pos=0, s=theRuns->runs; pos+s->chars<=start;
    			pos = pos+((s++)->chars)) /*loop*/;

//	s points to run containing first char of insertion

		if (pos!=start) {	/* insert in middle of run */
		    if (TRACE) printf(
			"HT: Inserted %i at %i, in run starting at=%i\n",
					inserted, start, pos);
					
		} else {	/* inserted stuff starts run */
		    if (TRACE) printf ("Patching info from %d to %d\n",
			    s->info, run.info);
	            s->info = run.info;
		    s->paraStyle = run.paraStyle;	/* free old one? */
		    s->rFlags.dummy = 1;
		}
	    } /* if inserted>0 */

	} /* block */
	return result;
    }
}
#endif
//	After paste, determine paragraph styles for pasted material:
//	------------------------------------------------------------

- paste:sender;
{
    id result;
    int originalLength = textLength;
    int originalStart = sp0.cp;
    int originalEnd = spN.cp;
    Anchor * typingInfo;
    
    result = [super paste:sender];		// Do the paste
        
    {
	int inserted = originalEnd-originalStart +
			textLength-originalLength;
	
	if (TRACE) printf(
    "Paste, size(sel) %i (%i-%i)before, %i (%i-%i)after.\n",
	    originalLength, originalStart, originalEnd,
	    textLength, sp0.cp, spN.cp);
	    
	if (inserted>0) {
	    NXRun *s, *r;
	    int pos;
	    int start = sp0.cp-inserted;
	    for (pos=0, s=theRuns->runs; pos+s->chars<=start;
		    pos = pos+((s++)->chars)) /*loop*/;
//		s points to run containing first char of insertion

	    if (pos!=sp0.cp-inserted)
		    printf("HT paste: Strange: insert@%i != run@%i !!\n",
				    start, pos);
				    
	    if (s > theRuns->runs) typingInfo = (s-1)->info;
	    else typingInfo = 0;
	    
	    for (r=s; pos+r->chars<sp0.cp; pos=pos+(r++)->chars) {
	        r->paraStyle = HTStyleForRun(styleSheet, r)->paragraph;
		r->info = typingInfo;
	    }
	    
	}
    }
    
    return result;
}

@end
