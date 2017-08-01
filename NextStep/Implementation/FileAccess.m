//		File Access					FileAccess.m
//		===========
//
// A HyperAccess object provides access to hyperinformation, using particular
// protocols and data format transformations. This one provides access to
// files in mounted filesystems.

#define takeBackup YES		// Take backup when saving existing file Cmd/S

#import "FileAccess.h"
#import <appkit/appkit.h>
#import <stdio.h>
#import <sys/types.h>
#import <sys/stat.h>		// For fstat()
#import <libc.h>		// For getgroups()
#import "HTUtils.h"
#import "WWW.h"			// For WWW_ constants etc
#import "HTParse.h"
#import "HTTCP.h"		// TCP utilities, like getting host name
#import "HTFTP.h"		// FTP protocol routines
#import "HTFile.h"		// File access routines


#define THIS_TEXT  (HyperText *)[[[NXApp mainWindow] contentView] docView]

@implementation FileAccess : HyperAccess

#define LENGTH 256
extern char * appDirectory;		/* Pointer to directory for application */


//	Initialize this class
//
+ initialize
{
    return [super initialize];
}


//	Overlay method returning the name of the access.

- (const char *)name
{
    return "file";
}

//////////////////////////////////////////////////////////////////////////////////////

//					S A V I N G

//	Save as an HTML file of given name (any format)
//	----------------------------------
//


- save: (HyperText *)HT inFile:(const char *)filename format:(int)format
{
    NXStream * s;				//	The file stream
    
    s = NXOpenMemory(NULL, 0, NX_WRITEONLY);

    if (format==WWW_HTML) {
    	char *saveName = WWW_nameOfFile(filename);	//	The WWW address
        [HT writeSGML:s relativeTo:saveName];
        free(saveName);
    }
    else if (format==WWW_RICHTEXT) [HT writeRichText:s];
    else if (format==WWW_PLAINTEXT || format==WWW_SOURCE) [HT writeText:s];
    else fprintf(stderr, "HT/File: Unknown format!\n"); 
    
    if (TRACE) printf("HT file: %li bytes in file `%s' format %i.\n",
    	NXTell(s), filename, format);
	
    NXFlush(s);			/* Try to get over missing end */
    NXSaveToFile(s, filename);
    NXCloseMemory(s, NX_FREEBUFFER);
    return self;
}


//	Get Filename near a "hint" node
//	-------------------------------
//
// On entry,
//	hint		is a hypertext whose name is to be used as a hint for
//			the user when selecting the name.
// On exit,
//	returns		0 if no file selected
//			pointer to static string with filename if ok
//
const char * ask_name(HyperText * hint, int format)
{
    char * 		suggestion;
    char * 		slash;
    int			status;
    static SavePanel * 	save_panel;		/* Keep a Save panel alive  */
    
    if (!hint) return 0;
    if (!save_panel) {
        save_panel = [SavePanel new];	//	Keep between invocations
    }
    
    if (format==WWW_HTML) [save_panel setRequiredFileType: "html"];
    else if (format==WWW_RICHTEXT) [save_panel setRequiredFileType: "rtf"];
    else if (format==WWW_PLAINTEXT) [save_panel setRequiredFileType: "txt"];
    else if (format==WWW_POSTSCRIPT) [save_panel setRequiredFileType: "ps"];
    else [save_panel setRequiredFileType: ""];
    
    suggestion = HTLocalName([[hint nodeAnchor]address]);
    slash = strrchr(suggestion, '/');	//	Point to last slash
    if (slash) {
    	*slash++ = 0;			/* Separate directory and filename */
	status = [save_panel runModalForDirectory:suggestion file:slash];
    } else {
        if (TRACE) printf ("No slash in directory!!\n");
	status = [save_panel runModalForDirectory:"." file:suggestion];
    }
    free(suggestion);
    
    if (!status) {
    	if (TRACE) printf("Save cancelled.\n");
	return 0;
    }
    return [save_panel filename];
}


//	Save as a file	using save panel	(any format)
//	--------------------------------
// On entry,
//	format	Gives the file format to be used (see WWW.h)
//	hint	is a node to be used for a suggested name.
//
- saveIn:(int)format like:(HyperText *)hint
{  
    const char * filename;		//	The name of the file selected
    HyperText * HT;
    
    HT = THIS_TEXT;
    if (!HT) return HT;			//	No main window!
    
    filename = ask_name(HT, format);
    if (!filename) return nil;		//	Save clancelled.
    
    return [self save:HT inFile:filename format:format]; 
}

//	Save as an HTML file	using save panel
//	--------------------
//
- saveAs:sender
{
    return [self saveIn:WWW_HTML like:THIS_TEXT];
}

//	Save as an RTF file	using save panel
//	--------------------
//
- saveAsRichText:sender
{
    return [self saveIn:WWW_RICHTEXT like:THIS_TEXT];
}

//	Save as a plain text file	using save panel
//	-------------------------
//
- saveAsPlainText:sender
{
    return [self saveIn:WWW_PLAINTEXT like:THIS_TEXT];
}


//	Save as an HTML file of same name
//	---------------------------------
//
//	We don't use a suffix for the backup filename, because some file systems
//	(which may be NFS mounted) truncate filenames and can chop the suffix off!
//
- saveNode:(HyperText *) HT
{  
    char * filename;		//	The name chosen
    id		status;
    FILE * fp;
    const char * addr = [[HT nodeAnchor]address];

    filename = HTLocalName(addr);

/*	Take a backup before we do anything silly
*/        
    if (takeBackup) {
    	char * backup_filename = 0;
	char * p = backup_filename;
	backup_filename = malloc(strlen(filename)+2);
	strcpy(backup_filename, filename);
	for(p=backup_filename+strlen(backup_filename);; p--) {// Start at null
	    if ((*p=='/') || (p<backup_filename)) {
	        p[1]=',';		/* Insert comma after slash */
		break;
	    }
	    p[1] = p[0];	/* Move up everything to the right of it */
	}
	
	if (fp=fopen(filename, "r")) {			/* File exists */
	    fclose(fp);
	    if (TRACE) printf("File `%s' exists\n", filename);
	    if (remove(backup_filename)) {
		if (TRACE) printf("Backup file `%s' removed\n",
			 backup_filename);
	    }
	    if (rename(filename, backup_filename)) {	/* != 0 => Failure */
		if (TRACE) printf("Rename `%s' to `%s' FAILED!\n",
				    filename, backup_filename);
	    } else {					/* Success */
		if (TRACE) printf("Renamed `%s' to `%s'\n", filename,
				backup_filename);
	    }
	}
    	free(backup_filename);
    } /* if take backup */    
    

    status = [self save:HT inFile:filename format:[HT format]];
    if (status) [[HT window] setDocEdited: NO];
    free(filename);
    return status;
}

//////////////////////////////////////////////////////////////////////////////////
//
//				O P E N I N G


//			LOAD ANCHOR
//
//	Returns	If successful, the anchor of the node loaded or found.
//		If failed, nil.
 
- loadAnchor: (Anchor *) anAnchor Diagnostic:(int)diagnostic
{
    const char * addr = [anAnchor address];
    
    NXStream * s;			//	The file stream
    HyperText * HT;			//	The new node
    char * filename;			//	The name of the file
    char * newname =  0;		//	The simplified name
    int format;				//	The file format
    int file_number = -1;		//	File number if FTP

//	First, we TRY to reduce the name to a unique one.

    if (!addr) return nil;
    StrAllocCopy(newname, addr);
    HTSimplify(newname);
    [anAnchor setAddress:newname];
    filename = HTLocalName(newname);
    addr = [anAnchor address];
	
    if ([anAnchor node]) {
        if (TRACE) printf("Anchor %p already has a node\n", anAnchor);
	
    } else {
	s = NXMapFile(filename, NX_READONLY);	// Map file into memory
	
	if (!s) {
	    if (TRACE) printf("Could not open file `%s', errno=%i.\n",
		    filename, errno);
	    file_number = HTFTP_open_file_read(newname);	// Try FTP
	    if (file_number>=0) {
	        s = NXOpenFile(file_number, NX_READONLY);
	    }
	}
	
	if (!s) {
	    if (TRACE) printf("Could not open `%s' with FTP either.\n",
		    newname);
	    NXRunAlertPanel(NULL, "Could not open `%s'\n",
	    	NULL,NULL,NULL,
		newname   /*, strerror(errno) */ );
	    free(filename);
    	    free(newname);
	    return nil;
	}
    	free(newname);


//	For unrecognised types, open in the Workspace:
	
	format = HTFileFormat(filename);
	if (format == WWW_INVALID) {
	        
	    char command[255];			/* Open in the workspace */
	    sprintf(command, "open %s", filename);
	    system(command);
	
	} else {	/* Known format */
	
//	Make the new node:

	    HT = [HyperText newAnchor:anAnchor Server:self];
	    [HT setupWindow];			
	    [[HT window]setTitle:filename];	 // Show something's happening

	    if (file_number<0)
	        [HT setEditable:HTEditable(filename)]; // This is editable?
	    else
	        [HT setEditable: NO];			// AFTP data.
		
	    switch(format) {
	    case WWW_HTML:
			if (diagnostic==2) {
			    [HT readText:s];
			    [HT setFormat: WWW_SOURCE]; 
			} else  {  
			    [HT readSGML:s diagnostic:diagnostic];
			}
			break;
			
	    case WWW_RICHTEXT:   
			if (diagnostic > 0) {
			    [HT readText:s];
			    [HT setFormat: WWW_SOURCE]; 
			} else {   
			    [HT readRichText:s];
			}
			break;
			
	    case WWW_PLAINTEXT:
			[HT readText:s];
    			break;
	    }
	}
	
//	Clean up now it's on the screen:
	
	if (TRACE) printf("Closing file stream\n");
	if (file_number>=0) {
	    NXClose(s);
	    HTFTP_close_file(file_number);
	} else {
	    NXCloseMemory(s, NX_FREEBUFFER);
	}
	
    } /* If anAnchor not loaded before */

    free(filename);
    return anAnchor;
}


//	Open a file of a given name
//	---------------------------
//
//
// On exit,
//	Returns	If successful, the anchor of the node loaded or found.
//		If failed, nil.

- openFile:(const char *)filename diagnostic:(BOOL)diagnostic
{
    Anchor * a;
    char * node_address = WWW_nameOfFile(filename);
    a = [self loadAnchor:[Anchor newAddress:node_address]
    		 Diagnostic:diagnostic];
    free(node_address);
    return a;
}


//	Ask the User for the name of a file
//	-----------------------------------
//

const char * existing_filename()
{
    HyperText * HT;			//	The new node
    char * suggestion = 0;
    char * slash;
    int	status;
    char * typelist = 0;		//	Any extension.
    static OpenPanel * openPanel=0;


//	Get The Filename from the User
    
    if (!openPanel) {
    	openPanel = [OpenPanel new];
    	[openPanel allowMultipleFiles:NO];
    }

    HT = THIS_TEXT;			// Hypertext in main window, if selected.
    if (HT) {
	suggestion = HTLocalName([[HT nodeAnchor]address]);
	slash = strrchr(suggestion, '/');	//	Point to last slash
	if (slash) {
	    *slash++ = 0;			/* Separate directory and filename */
	    status = [openPanel runModalForDirectory:suggestion
	    			file:""
				types:&typelist];
	    // (was: file:slash but this is silly as that is already open.)
	} else {
            if (TRACE) printf ("No slash in directory!!\n");
	    status = [openPanel runModalForDirectory:"."
	    	file:"" types:&typelist];
	    // (was: file:suggestion but this is silly as above)
	}
	free(suggestion);
    } else {
        status = [openPanel runModalForTypes:&typelist];
    }

    if (!status) {
    	if (TRACE) printf("Open cancelled\n");
	return NULL;
    }
    return [openPanel filename];
}


//	Link to a given file
//	--------------------

- linkToFile:sender
{
    const char * filename = existing_filename();	// Ask for filename
    if (filename) {
    	char * node_address = WWW_nameOfFile(filename);
    	Anchor * a =  [Anchor newAddress:node_address];
	free(node_address);
	
	return [THIS_TEXT linkSelTo:a];
    }
    return nil;
}


//	Open A File using the panel			openDiagnostic:
//	---------------------------
//
// On exit,
//	Returns	If successful, the anchor of the node loaded or found.
//		If failed, nil.

- openDiagnostic:(int)diagnostic
{
    
    const char * filename = existing_filename();

    if (!filename) {
    	if (TRACE) printf("Open cancelled\n");
	return nil;
    }

    return [self openFile:filename diagnostic:diagnostic];
}



//	Load a personal or system-wide version of a file
//	------------------------------------------------
//
//	This accesses the personal copy for the user or, failing that,
//	for the system. It is important that this name is fully qualified
//	as other names will be generated relative to it.
//	We check whether the local version is there before loading it
//	in order to prevent error messages being given to the user if
//	it is not.
//
// On exit,
//	Returns	If successful, the anchor of the node loaded or found.
//		If failed, nil.

- openMy:(const char *)filename diagnostic:(int)diagnostic
{
    Anchor * a;
    char name[256];
    char template[256];
    
    if (getenv("HOME")) {
	int status;
	struct stat buf;			/* status buffer */
	strcpy(name, getenv("HOME"));
	strcat(name, "/WWW/");
	strcat(name, filename);
        status = stat(name, &buf);		/* Does file exist? */
	if (status>=0) {			/* If it does, load it */
	    if (TRACE) printf("File: stat() returned %d\n", status);
	    a = [self openFile:name diagnostic:diagnostic];
            if (a) {
	    	if ([a node]) [a select];
		return a;		/* Found local copy */
	    }
        }
    }

    strcpy(template, appDirectory);
    strcat(template, filename);
    a = [self openFile:template diagnostic:diagnostic];
    if (!a) return nil;
    
    [a setAddress:name];		/* For later save back */
    [[a node] setEditable:YES];		/* This is editable data? */
    if ([a node]) [a select];		/* Bring to front */
    return a;
}


//	Go Home
//	-------
//
//	This accesses the default page of text for the user or, failing that,
//	for the system. 
//
- goHome:sender
{
    return [self openMy:"default.html" diagnostic:0];
}


//	Make a new blank node named like the current node
//	-------------------------------------------------
//
// On exit,
//	Returns	If successful, the anchor of the node loaded or found.
//		If failed, nil.
- makeNew:sender
{
    id		status;
    HyperText * hint = THIS_TEXT;	//	The old hypertext
    char *	node_address;		//	of the new hypertext
    Anchor *	a;			//	The new anchor
    const char * filename;		//	The name of the file selected
    HyperText * HT;			//	The new hypertext
    
    if (!hint) return nil;		//	No main window!

    a = [self openMy:"blank.html" diagnostic:0];
    if (!a) return nil;			//	Couldn't find blank node
    
    [a select];
    HT = [a node];
    if (!HT) return HT;			//	No node?!
    
    filename = ask_name(hint, WWW_HTML);
    if (!filename) return nil;		//	Save cancelled.
    
    node_address = WWW_nameOfFile(filename);
    [a setAddress:node_address];	// 	Adopt new address as node name


/*	Make a default title for the document from the file name:
**
** On entry,
**	node_address must be valid and have a colon in it
** On exit,
**	Title is set
**	This is destructive of the node_address string.
*/
    {
	char * pDir = 0;			/* Last Directory name */
        char * pTitle = strrchr(node_address, '/');	/* File name */

	if (pTitle) {
	    *pTitle++ = 0;			/* Chop in two */
	    pDir = strrchr(node_address, '/');
	    if (!pDir) pDir = strchr(node_address, ':');
	    pDir++;	/* After delimiter 921122 */
	} else {
	    pTitle  = strrchr(node_address, ':')+1;
	    pDir = "";
	}
	if (strrchr(pTitle, '.')) *strrchr(pTitle, '.') = 0;// Kill filetype */

	if (pDir) {
    	    char title[255];
	    sprintf(title, "%s -- %s", pTitle, pDir);
	    [HT setTitle:title];		/* Default title is filename */
	} else {
	    [HT setTitle:pTitle];    
	}
    }
    
    free(node_address);
    
    status = [self save:HT inFile:filename format:WWW_HTML]; 
    if (!status) return nil;		//	Save failed!
    
    [[a node] setEditable:YES];		// This is editable data.

    return a;
}


//	Make a new blank node named like the current node and link to it
//	----------------------------------------------------------------
//
- linkToNew:sender
{
    HyperText * HT = THIS_TEXT;
    Anchor * a;
    if (![HT isEditable]) return nil;		/* Won't be able to link to it */
    
    a = [self makeNew:sender];	/* Make the new node */
    if (!a) return nil;
    
    return [HT linkSelTo:a];			/* Link the selection to it */
}


//		Actions:
//
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
   return [self openDiagnostic:0];
}

- openRTF:sender
{
    return [self openDiagnostic:1];
}

- openSGML:sender
{
    return [self openDiagnostic:2];
}

@end
