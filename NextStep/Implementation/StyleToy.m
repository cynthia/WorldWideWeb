/*	Style Toy:	Allows user manipulation of styles	StyleToy.m
**	---------	----------------------------------
*/

#import "StyleToy.h"
#import "HTParse.h"
#import "HTStyle.h"
#import "HTUtils.h"

#import "HyperText.h"
#define THIS_TEXT  (HyperText *)[[[NXApp mainWindow] contentView] docView]

/*	Field numbers in the parameter form:
*/
#define	SGMLTAG_FIELD		4
#define FONT_NAME_FIELD		2
#define FONT_SIZE_FIELD		3
#define FIRST_INDENT_FIELD	0
#define	SECOND_INDENT_FIELD	1

@implementation StyleToy

extern char * appDirectory;		/* Pointer to directory for application */

//	Global styleSheet available to every one:

       HTStyleSheet * styleSheet = 0;

static HTStyle * style;			/* Current Style */
static OpenPanel * open_panel;		/* Keep the open panel alive */
static SavePanel * save_panel;		/* Keep a Save panel too */

//	Create new one:

+ new
{
    self = [super new];
    [self loadDefaultStyleSheet];
    return self;
}

//	Set connections to other objects:

- setTabForm:anObject
{
    TabForm = anObject;
    return self;
}

- setParameterForm:anObject
{
    ParameterForm = anObject;
    return self;
}

- setStylePanel:anObject
{
    StylePanel = anObject;
    return self;
}

- setNameForm:anObject
{
    NameForm = anObject;
    return self;
}


//			ACTION METHODS
//			==============

//	Display style in the panel

- display_style
{
    if(style->name) [NameForm setStringValue:style->name at:0];
    else [NameForm setStringValue:"" at:0];
    
    if(style->SGMLTag) [ParameterForm setStringValue:style->SGMLTag at:SGMLTAG_FIELD];
    else [ParameterForm setStringValue:"" at:SGMLTAG_FIELD];
    
    [ParameterForm setStringValue:[style->font name] at:FONT_NAME_FIELD];

    [ParameterForm setFloatValue:style->fontSize at:FONT_SIZE_FIELD];
    
    if(style->paragraph) {
    	char tabstring[255];
	int i;
       	[ParameterForm setFloatValue:style->paragraph->indent1st
       				at:FIRST_INDENT_FIELD];
        [ParameterForm setFloatValue:style->paragraph->indent2nd 
				at:SECOND_INDENT_FIELD];
	tabstring[0]=0;
	for(i=0; i < style->paragraph->numTabs; i++) {
	    sprintf(tabstring+strlen(tabstring), "%.0f ", style->paragraph->tabs[i].x);
	}
	[TabForm setStringValue:tabstring at:0];
    }     
    return self;
}


//	Load style from Panel
//
//	@@ Tabs not loaded

-load_style
{
    char * name = 0;
    char * stripped;
    
    style->fontSize=[ParameterForm floatValueAt:FONT_SIZE_FIELD];
    StrAllocCopy(name, [NameForm stringValueAt:0]);
    stripped = HTStrip(name);
    if (*stripped) {
        id font;
	font = [Font newFont:stripped size:style->fontSize];
	if (font) style->font = font;
    }
    free(name);
    name = 0;
    
    StrAllocCopy(name, [ParameterForm stringValueAt:SGMLTAG_FIELD]);
    stripped = HTStrip(name);
    if (*stripped) {
        StrAllocCopy(style->SGMLTag, stripped);
    }
    free(name);
    name = 0;
    
    if (!style->paragraph) style->paragraph = malloc(sizeof(*(style->paragraph)));
    style->paragraph->indent1st = [ParameterForm floatValueAt: FIRST_INDENT_FIELD];
    style->paragraph->indent2nd = [ParameterForm floatValueAt: SECOND_INDENT_FIELD];

    return self;
}


//	Open a style sheet from a file
//	------------------------------
//
//	We overlay any previously defined styles with new ones, but leave
//	old ones which are not redefined.

- open:sender
{  
    NXStream * s;			//	The file stream
    const char * filename;		//	The name of the file
    char *typelist[2] = {"style",(char *)0};	//	Extension must be ".style."

    if (!open_panel) {
    	open_panel = [OpenPanel new];
        [open_panel allowMultipleFiles:NO];
    }
    
    if (![open_panel runModalForTypes:typelist]) {
    	if (TRACE) printf("No file selected.\n");
	return nil;
    }

    filename = [open_panel filename];
    s = NXMapFile(filename, NX_READONLY);
    if (!s) {
        if(TRACE) printf("Styles: Can't open file %s\n", filename);
        return nil;
    }
    if (!styleSheet) styleSheet = HTStyleSheetNew();
    StrAllocCopy(styleSheet->name, filename);
    if (TRACE) printf("Stylesheet: New one called %s.\n", styleSheet->name);
    (void)HTStyleSheetRead(styleSheet, s);
    NXCloseMemory(s, NX_FREEBUFFER);
    style = styleSheet->styles;
    [self display_style];
    return self;
}


//	Load default style sheet
//	------------------------
//
//	We load EITHER the user's style sheet (if it exists) OR the system one.
//	This saves a bit of time on load. An alternative would be to load the
//	system style sheet and then overload the styles in the user's, so that
//	he could redefine a subset only of the styles.
//	If the HOME directory is defined, then it is always used a the
//	style sheet name, so that any changes will be saved in the user's
//	$(HOME)/WWW directory.

- loadDefaultStyleSheet
{
    NXStream * stream;
    
    if (!styleSheet) styleSheet = HTStyleSheetNew();
    styleSheet->name = malloc(strlen(appDirectory)+13+1);
    strcpy(styleSheet->name, appDirectory);
    strcat(styleSheet->name, "default.style");

    if (getenv("HOME")) {
        char name[256];
	strcpy(name, getenv("HOME"));
	strcat(name, "/WWW/default.style");
    	StrAllocCopy(styleSheet->name, name);
        stream = NXMapFile(name, NX_READONLY);
    } else stream = 0;

    if (!stream) {
        char name[256];
	strcpy(name, appDirectory);
	strcat(name, "default.style");
    	if (TRACE) printf("Couldn't open $(HOME)/WWW/default.style\n");
	stream = NXMapFile(name, NX_READONLY);
	if (!stream)
	    printf("Couldn't open %s, errno=%i\n", name, errno);
    }
    
    if (stream) {
	(void)HTStyleSheetRead(styleSheet, stream);
	NXCloseMemory(stream, NX_FREEBUFFER);
	style = styleSheet->styles;
	[self display_style];
    }
    return self;
}


//	Save style sheet to a file
//	--------------------------

- saveAs:sender
{  
    NXStream * s;			//	The file stream
    char * slash;
    int status;
    char * suggestion=0;		//	The name of the file to suggest
    const char * filename;		//	The name chosen

    if (!save_panel) {
        save_panel = [SavePanel new];	//	Keep between invocations
    }
    
    StrAllocCopy(suggestion,styleSheet->name);
    slash = rindex(suggestion, '/');	//	Point to last slash
    if (slash) {
    	*slash++ = 0;			/* Separate directory and filename */
	status = [save_panel runModalForDirectory:suggestion file:slash];
    } else {
	status = [save_panel runModalForDirectory:"." file:suggestion];
    }
    free(suggestion);
    
    if (!status) {
    	if (TRACE) printf("No file selected.\n");
	return nil;
    }
    
    filename = [save_panel filename];
    s = NXMapFile(filename, NX_WRITEONLY);
    if (!s) {
        if(TRACE) printf("Styles: Can't open file %s for write\n", filename);
        return nil;
    }
    StrAllocCopy(styleSheet->name, filename);
    if (TRACE) printf("StylestyleSheet: Saving as `%s'.\n", styleSheet->name);
    (void)HTStyleSheetWrite(styleSheet, s);
    NXSaveToFile(s, styleSheet->name);
    NXCloseMemory(s, NX_FREEBUFFER);
    style = styleSheet->styles;
    [self display_style];
    return self;
}


//	Move to next style
//	------------------

- NextButton:sender
{
    if (styleSheet->styles)
        if (styleSheet->styles->next)
            if (style->next) {
	        style = style->next;
            } else {
	        style = styleSheet->styles;
            }
    [self display_style];
    return self;
}


- FindUnstyledButton:sender
{
    [THIS_TEXT selectUnstyled: styleSheet];
    return self;
}

//	Apply current style to selection
//	--------------------------------

- ApplyButton:sender
{
    [THIS_TEXT applyStyle:style];
    return self;
}

- applyStyleNamed: (const char *)name
{
     HTStyle * thisStyle = HTStyleNamed(styleSheet, name);
     if (!thisStyle) return nil;
     return [THIS_TEXT applyStyle:thisStyle];
}

- heading1Button:sender	{ return [self applyStyleNamed:"Heading1" ]; }
- heading2Button:sender	{ return [self applyStyleNamed:"Heading2" ]; }
- heading3Button:sender	{ return [self applyStyleNamed:"Heading3" ]; }
- heading4Button:sender	{ return [self applyStyleNamed:"Heading4" ]; }
- heading5Button:sender	{ return [self applyStyleNamed:"Heading5" ]; }
- heading6Button:sender	{ return [self applyStyleNamed:"Heading6" ]; }
- normalButton:sender	{ return [self applyStyleNamed:"Normal" ]; }
- addressButton:sender	{ return [self applyStyleNamed:"Address" ]; }
- exampleButton:sender	{ return [self applyStyleNamed:"Example" ]; }
- listButton:sender	{ return [self applyStyleNamed:"List" ]; }
- glossaryButton:sender	{ return [self applyStyleNamed:"Glossary" ]; }


//	Move to previous style
//	----------------------

- PreviousButton:sender
{
    HTStyle * scan;
    for (scan = styleSheet->styles; scan; scan=scan->next) {
        if ((scan->next==style) || (scan->next==0)){
	    style = scan;
	    break;
	}
    }
    [self display_style];
    return self;
}

- SetButton:sender
{
    [self load_style];
    [THIS_TEXT updateStyle:style];
    return self;
}

- PickButton:sender
{
    HTStyle * st = [THIS_TEXT selectionStyle:styleSheet];
    if (st) {
    	style = st;
	[self display_style];
    }
    return self;
}

- ApplyToSimilar:sender
{
    return [THIS_TEXT applyToSimilar:style];
}


@end
