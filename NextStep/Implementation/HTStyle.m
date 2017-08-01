/*	Style Implementation for Hypertext			HTStyle.m
**	==================================
**
**	Styles allow the translation between a logical property
**	of a piece of text and its physical representation.
**
**	A StyleSheet is a collection of styles, defining the
**	translation necessary to
**	represent a document. It is a linked list of styles.
*/
#import "HTStyle.h"
#import "HTUtils.h"

/*	Create a new style
*/
HTStyle* HTStyleNew()
{
    HTStyle * self = malloc(sizeof(*self));
    bzero(self, sizeof(*self));
    self->SGMLTag = 0;
    self->textGray = NX_BLACK;
    self->textRGBColor = -1;		// Not used
    return self;
}

/*	Create a new style with a name
*/
HTStyle* HTStyleNewNamed(const char * name)
{
    HTStyle * self = HTStyleNew();
    StrAllocCopy(self->name, name);
    return self;
}


/*	Free a style
*/
HTStyle * HTStyleFree(HTStyle * self)
{
    if (self->name) free(self->name);
    if (self->SGMLTag) free(self->SGMLTag);
    if (self->paragraph) free(self->paragraph);
    free(self);
    return 0;
}


/*	Read a style from a typed stream	(without its name)
**	--------------------------------
**
**	Reads a style with paragraph information from a stream.
**	The style name is not read or written by these routines.
*/
#define NONE_STRING "(None)"

HTStyle * HTStyleRead(HTStyle * style, NXStream * stream)
{
    char myTag[STYLE_NAME_LENGTH];
    char fontName[STYLE_NAME_LENGTH];
    NXTextStyle *p;
    int	tab;
    int gotpara;		/* flag: have we got a paragraph definition? */
	
    NXScanf(stream, "%s%i%s%f%i",
	myTag,
	&style->SGMLType,
	fontName,
	&style->fontSize,
	&gotpara);
    if (gotpara) {
	if (!style->paragraph) {
	    style->paragraph = malloc(sizeof(*(style->paragraph)));
	    style->paragraph->tabs = 0;
	}
	p = style->paragraph;
	NXScanf(stream, "%f%f%f%f%hd%f%f%hd",
	    &p->indent1st,
	    &p->indent2nd,
	    &p->lineHt,
	    &p->descentLine,
	    &p->alignment,
	    &style->spaceBefore,
	    &style->spaceAfter,
	    &p->numTabs);
	if (p->tabs) free(p->tabs);
	p->tabs = malloc(p->numTabs * sizeof(p->tabs[0]));
	for (tab=0; tab < p->numTabs; tab++) {
	    NXScanf(stream, "%hd%f",
		    &p->tabs[tab].kind,
		    &p->tabs[tab].x);
	}
    } else { /* No paragraph */
        if (style->paragraph) {
    	    free(style->paragraph);
    	    style->paragraph = 0;
	}
    } /* if no paragraph */
    StrAllocCopy(style->SGMLTag, myTag);
    if (strcmp(fontName, NONE_STRING)==0)
        style->font = 0;
    else
        style->font = [Font newFont:fontName size:style->fontSize];
    return 0;
}


/*	Write a style to a stream in a compatible way
*/
HTStyle * HTStyleWrite(HTStyle * style, NXStream * stream)
{
    int tab;
    NXTextStyle *p = style->paragraph;
    NXPrintf(stream, "%s %i %s %f %i\n",
	style->SGMLTag,
	style->SGMLType,
	style->font ? [style->font name] : NONE_STRING,
	style->fontSize,
	p!=0);

    if (p) {
	NXPrintf(stream, "\t%f %f %f %f %i %f %f\t%i\n",
	    p->indent1st,
	    p->indent2nd,
	    p->lineHt,
	    p->descentLine,
	    p->alignment,
	    style->spaceBefore,
	    style->spaceAfter,
	    p->numTabs);
	    
	for (tab=0; tab < p->numTabs; tab++)
	    NXPrintf(stream, "\t%i %f\n",
		    p->tabs[tab].kind,
		    p->tabs[tab].x);
	}
    return style;
}


/*	Write a style to stdout for diagnostics
*/
HTStyle * HTStyleDump(HTStyle * style)
{
    int tab;
    NXTextStyle *p = style->paragraph;
    printf("Style %i `%s' SGML:%s, type=%i. Font %s %.1f point.\n",
    	style,
	style->name,
	style->SGMLTag,
	style->SGMLType,
	[style->font name],
	style->fontSize);
    if (p) {
        printf(
    	"\tIndents: first=%.0f others=%.0f, Height=%.1f Desc=%.1f\n"
	"\tAlign=%i, %i tabs. (%.0f before, %.0f after)\n",
	    p->indent1st,
	    p->indent2nd,
	    p->lineHt,
	    p->descentLine,
	    p->alignment,
	    p->numTabs,
	    style->spaceBefore,
	    style->spaceAfter);
	    
	for (tab=0; tab < p->numTabs; tab++) {
	    printf("\t\tTab kind=%i at %.0f\n",
		    p->tabs[tab].kind,
		    p->tabs[tab].x);
    	}
	printf("\n");
    } /* if paragraph */
    return style;
}


/*			StyleSheet Functions
**			====================
*/

/*	Searching for styles:
*/
HTStyle * HTStyleNamed(HTStyleSheet * self, const char * name)
{
    HTStyle * scan;
    for (scan=self->styles; scan; scan=scan->next)
        if (0==strcmp(scan->name, name)) return scan;
    if (TRACE) printf("StyleSheet: No style named `%s'\n", name);
    return 0;
}

HTStyle * HTStyleForParagraph(HTStyleSheet * self, NXTextStyle *para)
{
    HTStyle * scan;
    for (scan=self->styles; scan; scan=scan->next)
        if (scan->paragraph == para) return scan;
    return 0;
}

/*	Find the style which best fits a given run
**	------------------------------------------
**
**	This heuristic is used for guessing the style for a run of
**	text which has been pasted in. In order, we try:
**
**	A style whose paragraph structure is actually used by the run.
**	A style matching in font
**	A style matching in paragraph style exactly
**	A style matching in paragraph to a degree
*/
HTStyle * HTStyleForRun(HTStyleSheet *self, NXRun *run)
{
    HTStyle * scan;
    HTStyle * best = 0;
    int	bestMatch = 0;
    NXTextStyle * rp = run->paraStyle;
    for (scan=self->styles; scan; scan=scan->next)
        if (scan->paragraph == run->paraStyle) return scan;	/* Exact */

    for (scan=self->styles; scan; scan=scan->next){
    	NXTextStyle * sp = scan->paragraph;
    	if (sp) {
	    int match = 0;
	    if (sp->indent1st ==	rp->indent1st)	match = match+1;
	    if (sp->indent2nd ==	rp->indent2nd)	match = match+2;
	    if (sp->lineHt ==		rp->lineHt)	match = match+1;
	    if (sp->numTabs ==		rp->numTabs)	match = match+1;
	    if (sp->alignment ==	rp->alignment)	match = match+3;
	    if (scan->font ==		run->font)	match = match+10;
	    if (match>bestMatch) {
		    best=scan;
		    bestMatch=match;
	    }
	}
    }
    if (TRACE) printf("HTStyleForRun: Best match for style is %i out of 18\n",
    			 bestMatch);
    return best;
}



/*	Add a style to a sheet
**	----------------------
*/
HTStyleSheet * HTStyleSheetAddStyle(HTStyleSheet * self, HTStyle * style)
{
    style->next = 0;		/* The style will go on the end */
    if (!self->styles) {
    	self->styles = style;
    } else {
    	HTStyle * scan;
        for(scan=self->styles; scan->next; scan=scan->next); /* Find end */
	scan->next=style;
    }
    return self;
}


/*	Remove the given object from a style sheet if it exists
*/
HTStyleSheet * HTStyleSheetRemoveStyle(HTStyleSheet * self, HTStyle * style)
{
    if (self->styles = style) {
    	self->styles = style->next;
	return self;
    } else {
    	HTStyle * scan;
	for(scan = self->styles; scan; scan = scan->next) {
	    if (scan->next = style) {
	        scan->next = style->next;
		return self;
	    }
	}
    }
    return 0;
}

/*	Create new style sheet
*/

HTStyleSheet * HTStyleSheetNew()
{
    HTStyleSheet * self = malloc(sizeof(*self));
    bzero(self, sizeof(*self));
    return self;
}


/*	Free off a style sheet pointer
*/
HTStyleSheet * HTStyleSheetFree(HTStyleSheet * self)
{
    HTStyle * style;
    while((style=self->styles)!=0) {
        self->styles = style->next;
	HTStyleFree(style);
    }
    free(self);
    return 0;
}


/*	Read a stylesheet from a typed stream
**	-------------------------------------
**
**	Reads a style sheet from a stream.  If new styles have the same names
**	as existing styles, they replace the old ones without changing the ids.
*/

HTStyleSheet * HTStyleSheetRead(HTStyleSheet * self, NXStream * stream)
{
    int numStyles;
    int i;
    HTStyle * style;
    char styleName[80];
    NXScanf(stream, " %i ", &numStyles);
    if (TRACE) printf("Stylesheet: Reading %i styles\n", numStyles);
    for (i=0; i<numStyles; i++) {
        NXScanf(stream, "%s", styleName);
        style = HTStyleNamed(self, styleName);
	if (!style) {
	    style = HTStyleNewNamed(styleName);
	    (void) HTStyleSheetAddStyle(self, style);
	}
	(void) HTStyleRead(style, stream);
	if (TRACE) HTStyleDump(style);
    }
    return self;
}

/*	Write a stylesheet to a typed stream
**	------------------------------------
**
**	Writes a style sheet to a stream.
*/

HTStyleSheet * HTStyleSheetWrite(HTStyleSheet * self, NXStream * stream)
{
    int numStyles = 0;
    HTStyle * style;
    
    for(style=self->styles; style; style=style->next) numStyles++;
    NXPrintf(stream, "%i\n", numStyles);
    
    if (TRACE) printf("StyleSheet: Writing %i styles\n", numStyles);
    for (style=self->styles; style; style=style->next) {
        NXPrintf(stream, "%s ", style->name);
	(void) HTStyleWrite(style, stream);
    }
    return self;
}
