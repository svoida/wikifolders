//
//  EditorController.m
//  WikiFolders
//
//  Created by Stephen Voida (svoida@ucalgary.ca) on 9/11/08.
//  Copyright (c) 2008 Stephen Voida, University of Calgary.
//  All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <http://www.gnu.org/licenses/>.
//

#import "EditorController.h"
#import "Constants.h"
#import "NSMutableString+TagManipulation.h"

#import <ScriptingBridge/ScriptingBridge.h>
#import "Finder.h"


@interface EditorController (PrivateAPI)

- (BOOL)convertToWikiFolder:(NSString *)folder;
- (NSString *)loadAndValidateWikiText:(NSString *)folder;
- (BOOL)isViewOptimalForFolder:(NSString *)folder;
- (void)setOptimalViewForFolder:(NSString *)folder;
- (NSString *)createHTMLFromWikiText:(NSString *)wikiText forFolder:(NSString *)folder;
- (void)renderHTML:(NSString *)html toFolder:(NSString *)folder;

- (BOOL)cleanUpFolder:(NSString *)path;
- (BOOL)retrieveDisplayParametersForFolder:(NSString *)path;
- (void)webView:(WebView *)sender resource:(id)identifier didFinishLoadingFromDataSource:(WebDataSource *)dataSource;
- (BOOL)setBackgroundPictureUsingData:(NSData *)imageData forFolder:(NSString *)path;
- (BOOL)setInvisibility:(BOOL)invisibility ofFile:(NSString *)path;

@end



@implementation EditorController

NSString *folderPathRendering;

#pragma mark Constructor

- (id)init;
{
	if (![super initWithWindowNibName:@"Editor"])
		return nil;
	
	return self;
}

#pragma mark NSWindow delegate methods

- (void)windowWillClose:(NSNotification *)notification;
{
	[self editorCancel:[notification object]];
}

#pragma mark Interface IBAction callback methods

- (IBAction)editorSaveAndClose:(id)sender;
{
	[editorWindow setIsVisible:NO];
	[NSApp stopModalWithCode:NSOKButton];
}

- (IBAction)editorCancel:(id)sender;
{
	[editorWindow setIsVisible:NO];
	[NSApp stopModalWithCode:NSCancelButton];
}

#pragma mark Public methods

- (BOOL)isActiveWikiFolder:(NSString *)folder;
{
	NSFileManager *fm = [NSFileManager defaultManager];
	
	// Check to make sure we are pointed at a file that (a) exsits and (b) is a directory
	BOOL isDirectory;
	if ([fm fileExistsAtPath:folder isDirectory:&isDirectory] && isDirectory) {
		// Check that there is an editor placeholder icon in the directory
		if (![fm fileExistsAtPath:[folder stringByAppendingPathComponent:WIKITEXT_EDITOR_FILENAME]]) {
			return NO;
		}
		
		// Check that there is a wikitext removal app in the directory
		if (![fm fileExistsAtPath:[folder stringByAppendingPathComponent:WIKITEXT_REMOVAL_FILENAME]]) {
			return NO;
		}
		
		// Check that there is a wikitext file in the directory
		if (![fm fileExistsAtPath:[folder stringByAppendingPathComponent:WIKITEXT_FILENAME]]) {
			return NO;
		}
		
		// All set; ready to proceed
		return YES;
	}
	
	return NO;
}

- (int)editWikiTextForFolder:(NSString *)folder withParentWindow:(NSWindow *)parent;
{
	// Make sure everything is loaded and ready to go
	(void)[self window];

	// Make sure the folder is valid and has all the WikiFolder contents we need to see
	// (this should force an update only rarely; most of the time, this has been done previously)
	if (![self isActiveWikiFolder:folder]) {
		BOOL conversionResult = [self convertToWikiFolder:folder];
		if (!conversionResult)
			return WFE_NO_CHANGE;
	}
	
	// Load up (and validate) the folder's wikitext
	NSString *wikiText = [self loadAndValidateWikiText:folder];
	
	// Set up the editing dialog
	BOOL optimalBeforeEditing = [self isViewOptimalForFolder:folder];
	[editorTitle setStringValue:[NSString stringWithFormat:@"Wikitext editor for %@", folder]];
	[editorContent setString:wikiText];
	[editorCheckbox setState:optimalBeforeEditing];
	[editorWindow setDefaultButtonCell:[editorOKButton cell]];
	[editorWindow makeFirstResponder:editorOKButton];

	// And run it
	int result = [NSApp runModalForWindow:editorWindow];
	[parent makeKeyAndOrderFront:self];
	
	// If the user committed their changes, then remember them!
	if (result == NSOKButton) {
		wikiText = [editorContent string];
		
		if (!optimalBeforeEditing && [editorCheckbox state])
			[self setOptimalViewForFolder:folder];
	}

	// Finally, check to see if we actually changed anything
	NSString *wikiTextFilename = [folder stringByAppendingPathComponent:WIKITEXT_FILENAME];
    NSMutableString *originalWikiText = [NSString stringWithContentsOfFile:wikiTextFilename
                                                                  encoding:NSUTF8StringEncoding
                                                                     error:NULL];
	if ([originalWikiText compare:wikiText options:NSLiteralSearch] != NSOrderedSame ||
		(!optimalBeforeEditing && [editorCheckbox state])) {
		// If so, render the wikitext to HTML and rewrite the background
		NSString *html = [self createHTMLFromWikiText:wikiText forFolder:folder];
		//NSLog(@"HTML:\n%@\n********************", html);
		[self renderHTML:html toFolder:folder];

		// Save the revised wikitext file to disk		
		[wikiText writeToFile:wikiTextFilename
				   atomically:YES
					 encoding:NSUTF8StringEncoding
						error:NULL];
		
		// And return a code indicating that we did something
		return WFE_MADE_CHANGES;
	}
	
	// Otherwise, it was a wash
	return WFE_NO_CHANGE;
}

- (int)refreshWikiTextForFolder:(NSString *)folder forceUpdate:(BOOL)useForce;
{
	// Make sure everything is loaded and ready to go
	(void)[self window];
	
	// Make sure the folder is valid and has all the WikiFolder contents we need to see
	// (this should force an update only rarely; most of the time, this has been done previously)
	if (![self isActiveWikiFolder:folder]) {
		// Doing the conversion will, itself, force the rest of the refresh process
		// So we can just bail by passing the result back through to the caller
		BOOL conversionResult = [self convertToWikiFolder:folder];
		if (conversionResult)
			return WFE_MADE_CHANGES;
		else
			return WFE_NO_CHANGE;
	}
	
	// Load up (and validate) the folder's wikitext
	NSString *wikiText = [self loadAndValidateWikiText:folder];
	
	// Finally, check to see if we actually changed anything
	NSString *wikiTextFilename = [folder stringByAppendingPathComponent:WIKITEXT_FILENAME];
	NSMutableString *originalWikiText = [NSString stringWithContentsOfFile:wikiTextFilename
                                                                  encoding:NSUTF8StringEncoding
                                                                     error:NULL];
	if (useForce || [originalWikiText compare:wikiText options:NSLiteralSearch] != NSOrderedSame) {
		// If so, render the wikitext to HTML and rewrite the background
		NSString *html = [self createHTMLFromWikiText:wikiText forFolder:folder];
		//NSLog(@"HTML:\n%@\n********************", html);
		[self renderHTML:html toFolder:folder];
		
		// Save the revised wikitext file to disk		
		[wikiText writeToFile:wikiTextFilename
				   atomically:YES
					 encoding:NSUTF8StringEncoding
						error:NULL];
		
		// And return a code indicating that we did something
		return WFE_MADE_CHANGES;
	}
	
	// Otherwise, it was a wash
	return WFE_NO_CHANGE;
}

+ (BOOL)hideFileExtension:(NSString *)path;
{
	FinderApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
	
	// Get a reference to the specified file
	NSURL *pathURL = [NSURL fileURLWithPath:path];
	FinderItem* finderFile = [[finder items] objectAtLocation:pathURL];
	if (finderFile == nil) {
		return NO;
	}
	
	// Hide the file's extension
	[finderFile setExtensionHidden:YES];
	
	return YES;
}

@end



@implementation EditorController (PrivateAPI)

#pragma mark Highest-level building blocks

- (BOOL)convertToWikiFolder:(NSString *)folder;
{
	NSFileManager *fm = [NSFileManager defaultManager];
	
	// Check to make sure we are pointed at a file that (a) exsits and (b) is a directory
	BOOL isDirectory;
	if ([fm fileExistsAtPath:folder isDirectory:&isDirectory] && isDirectory) {
		// Check that there is an editor placeholder icon in the directory
		if (![fm fileExistsAtPath:[folder stringByAppendingPathComponent:WIKITEXT_EDITOR_FILENAME]]) {
            BOOL result = [fm copyItemAtPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:WIKITEXT_EDITOR_FILENAME]
                                      toPath:[folder stringByAppendingPathComponent:WIKITEXT_EDITOR_FILENAME]
                                       error:NULL];
			if (!result)
				return NO;
		}
		
		// Check that there is a wikitext removal app in the directory
		if (![fm fileExistsAtPath:[folder stringByAppendingPathComponent:WIKITEXT_REMOVAL_FILENAME]]) {
            BOOL result = [fm copyItemAtPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:WIKITEXT_REMOVAL_FILENAME]
                                      toPath:[folder stringByAppendingPathComponent:WIKITEXT_REMOVAL_FILENAME]
                                       error:NULL];
			if (!result)
				return NO;
		}
		
		// Check that there is a wikitext file in the directory
		if (![fm fileExistsAtPath:[folder stringByAppendingPathComponent:WIKITEXT_FILENAME]]) {
			BOOL result = [[NSString string] writeToFile:[folder stringByAppendingPathComponent:WIKITEXT_FILENAME]
											  atomically:YES
												encoding:NSUTF8StringEncoding
												   error:NULL];
			if (!result)
				return NO;
		}

		// Do a one-time refresh on the folder to bring it up to our wiki-fied standards
		if ([self refreshWikiTextForFolder:folder forceUpdate:NO] == WFE_MADE_CHANGES)
			return YES;
	}
	
	return NO;
}

- (NSString *)loadAndValidateWikiText:(NSString *)folder;
{
	NSString *wikiTextFilename = [folder stringByAppendingPathComponent:WIKITEXT_FILENAME];
	NSMutableString *wikiText = wikiText = [[NSString stringWithContentsOfFile:wikiTextFilename
                                                                      encoding:NSUTF8StringEncoding
                                                                         error:NULL] mutableCopy];
	
	FinderApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
	
	// Get a reference to the specified folder
	NSURL *folderURL = [NSURL fileURLWithPath:folder];
	FinderContainer* finderFolder = [[finder containers] objectAtLocation:folderURL];
	if (finderFolder == nil) {
		return NO;
	}
	
	// Load the directory contents of the wiki folder
	NSMutableArray *contents = [[NSMutableArray alloc] init];
	for (FinderItem *item in [finderFolder items])
		[contents addObject:[item name]];
	
	// Check to make sure that all the files in the wikitext are still in the folder
	int searchLocation = 0;
	NSRange searchRange = [wikiText rangeOfString:@"[["
										  options:NSLiteralSearch
											range:NSMakeRange(searchLocation, [wikiText length] - searchLocation)];
	while (searchRange.location != NSNotFound) {
		NSRange endRange = [wikiText rangeOfString:@"]]"
										   options:NSLiteralSearch
											 range:NSMakeRange(searchRange.location, [wikiText length] - searchRange.location)];
		if (endRange.location == NSNotFound)
			break;
		
		NSRange filenameRange = NSMakeRange(searchRange.location + 2, endRange.location - searchRange.location - 2);
		NSString *filename = [wikiText substringWithRange:filenameRange];
		if (![contents containsObject:filename]) {
			NSRange replacementRange = NSMakeRange(filenameRange.location - 2, filenameRange.length + 4);
			[wikiText replaceCharactersInRange:replacementRange
									withString:[NSString stringWithFormat:@"((File deleted: %@))", filename]];
		}
		
		searchLocation = endRange.location;	
		searchRange = [wikiText rangeOfString:@"[["
									  options:NSLiteralSearch
										range:NSMakeRange(searchLocation, [wikiText length] - searchLocation)];
	}
	
	// And make sure that all of the files in the folder (except for our special ones) appear in the wikitext
	for (NSString *key in contents) {
		if ([key compare:WIKITEXT_EDITOR_FILENAME] == NSOrderedSame ||
			[key compare:WIKITEXT_REMOVAL_FILENAME] == NSOrderedSame)
			continue;
		
		if ([wikiText rangeOfString:[NSString stringWithFormat:@"[[%@]]", key] options:NSLiteralSearch].location == NSNotFound)
			[wikiText appendFormat:@"[[%@]]\n", key];
	}
	
	// TODO: Remove deleted files and their surrounding blocks (?)
	// TODO: Convert between web links and URLs (?)
	
	return wikiText;
}

- (BOOL)isViewOptimalForFolder:(NSString *)folder;
{
	FinderApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
	
	// Get a reference to the specified folder
	NSURL *folderURL = [NSURL fileURLWithPath:folder];
	FinderContainer* finderFolder = [[finder containers] objectAtLocation:folderURL];
	if (folder == nil) {
		return NO;
	}
	
	// Display the folder's window and get a reference to it
	[finderFolder openUsing:finder withProperties:nil];
	FinderFinderWindow *folderWindow = [[finderFolder containerWindow] get];
	
	// Check some options...
	// ...icon size...
	if ([[folderWindow iconViewOptions] iconSize] != OPTIMAL_ICON_SIZE)
		return NO;
	// ...and text label positioning
	if ([[folderWindow iconViewOptions] labelPosition] != FinderEposRight)
		return NO;
	
	return YES;
}

- (void)setOptimalViewForFolder:(NSString *)folder;
{
	FinderApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
	
	// Get a reference to the specified folder
	NSURL *folderURL = [NSURL fileURLWithPath:folder];
	FinderContainer* finderFolder = [[finder containers] objectAtLocation:folderURL];
	if (finderFolder == nil) {
		return;
	}
	
	// Display the folder's window and get a reference to it
	[finderFolder openUsing:finder withProperties:nil];
	FinderFinderWindow *folderWindow = [[finderFolder containerWindow] get];
	
	// Set some options...
	// ...icon size...
	[[folderWindow iconViewOptions] setIconSize:OPTIMAL_ICON_SIZE];
	// ...and text label positioning
	[[folderWindow iconViewOptions] setLabelPosition:FinderEposRight];
}

- (NSString *)createHTMLFromWikiText:(NSString *)wikiText forFolder:(NSString *)folder;
{
	// Set the HTML layout variables based on the current window geometry
	if (![self retrieveDisplayParametersForFolder:folder])
		return nil;	
	
	// Load up the template HTML
	NSMutableString *templateHTML = [[NSString stringWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:HTML_TEMPLATE_FILENAME]
                                                               encoding:NSUTF8StringEncoding
                                                                  error:NULL] mutableCopy];
	
	// Set the height of the title stripe
	[templateHTML replaceOccurrencesOfString:@"%%HEIGHT%%"
								  withString:[NSString stringWithFormat:@"%d", (int)dh - (int)dy]];
	
	// Set the top margin (affects where the content starts below the title stripe)
	[templateHTML replaceOccurrencesOfString:@"%%TOP-MARGIN%%"
								  withString:[NSString stringWithFormat:@"%d", (int)dh - (int)dy + TITLESTRIPE_MARGIN_SPACING]];
	
	// Set the size of the body text based on the user preference value (default is 11pt)
	[templateHTML replaceOccurrencesOfString:@"%%BODY-TEXT-SIZE%%"
								  withString:[[NSUserDefaults standardUserDefaults] objectForKey:WF_RENDERED_FONT_SIZE_KEY]];
	
	// Set the date/time that the background was rendered
	[templateHTML replaceOccurrencesOfString:@"%%RENDER-TIME%%"
								  withString:[[NSCalendarDate date] descriptionWithCalendarFormat:@"%B %1d, %Y at %1I:%M%p"
																						   locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]]];
	
	// Make any wikitext->HTML conversions that we'd like to have...
	// (Bracket the text between newlines to make the parsing cleaner)
	NSMutableString *convertedWikiText = [[NSString stringWithFormat:@"\n%@\n", wikiText] mutableCopy];
	
	// First, do some basic wiki markup substitutions
	// Blank line starts new paragraph
	[convertedWikiText replaceOccurrencesOfString:@"\n\n" withString:@"\n<p>\n"];
	
	// Header 4
	[convertedWikiText replaceStartTag:@"\n!!!!"
								endTag:@"\n"
						  withStartTag:@"\n<h4>"
								endTag:@"</h4>\n"];
	
	// Header 3
	[convertedWikiText replaceStartTag:@"\n!!!"
								endTag:@"\n"
						  withStartTag:@"\n<h3>"
								endTag:@"</h3>\n"];
	
	// Header 2
	[convertedWikiText replaceStartTag:@"\n!!"
								endTag:@"\n"
						  withStartTag:@"\n<h2>"
								endTag:@"</h2>\n"];
	
	// Header 1
	[convertedWikiText replaceStartTag:@"\n!"
								endTag:@"\n"
						  withStartTag:@"\n<h1>"
								endTag:@"</h1>\n"];
	
	// Bulleted list item
	[convertedWikiText replaceStartTag:@"\n*"
								endTag:@"\n"
						  withStartTag:@"\n<ul><li>"
								endTag:@"</li></ul>\n"];
	
	// Horizontal line
	[convertedWikiText replaceOccurrencesOfString:@"\n----\n"
									   withString:@"\n<hr />\n"];
	
	// Convert newlines to spaces
	[convertedWikiText replaceOccurrencesOfString:@"\n" withString:@" "];
	
	// Specific line end
	[convertedWikiText replaceOccurrencesOfString:@"\\\\" withString:@"<br />"];
	
	// Strong emphasis
	[convertedWikiText replaceStartTag:@"'''''"
								endTag:@"'''''"
						  withStartTag:@"<strong><em>"
								endTag:@"</em></strong>"];
	
	// Strong
	[convertedWikiText replaceStartTag:@"'''"
								endTag:@"'''"
						  withStartTag:@"<strong>"
								endTag:@"</strong>"];
	
	// Emphasis
	[convertedWikiText replaceStartTag:@"''"
								endTag:@"''"
						  withStartTag:@"<em>"
								endTag:@"</em>"];
	
	// Monospace
	[convertedWikiText replaceStartTag:@"@@"
								endTag:@"@@"
						  withStartTag:@"<code>"
								endTag:@"</code>"];
	
	// Tint the file deleted warnings red
	// Have to do a temporary swap on the text so the replaceTag algorithm doesn't
	// go into an infinite recursion (ugh)
	[convertedWikiText replaceStartTag:@"((File deleted: "
								endTag:@"))"
						  withStartTag:@"<span style=\"color:red;\">((XXXXXFile deleted: "
								endTag:@"))</span>"];
	[convertedWikiText replaceOccurrencesOfString:@"((XXXXXFile deleted"
									   withString:@"((File deleted"];
	
	// And swap it into the template HTML
	[templateHTML replaceOccurrencesOfString:@"%%MAIN%%"
								  withString:convertedWikiText];
	
	// Convert files to their placeholder rects (have to do this late so that we can pick up the ones in the template, too)
	// (Draw the borders -- or not -- based on the corresponding user preference key)
	NSString *newEnd;
	if ([[[NSUserDefaults standardUserDefaults] objectForKey:WF_DRAW_ICON_BORDERS_KEY] boolValue] == YES)
		newEnd = [NSString stringWithFormat:@"\" style=\"border:1px solid #99c; width:%dpx; height:%dpx; vertical-align:middle;\" src=\"%%%%TEMPLATE-FOLDER%%%%\\placeholder.png\" />", (int)dw, (int)dh];
	else
		newEnd = [NSString stringWithFormat:@"\" style=\"border:0px; width:%dpx; height:%dpx; vertical-align:middle;\" src=\"%%%%TEMPLATE-FOLDER%%%%\\placeholder.png\" />", (int)dw, (int)dh];

	[templateHTML replaceStartTag:@"[["
						   endTag:@"]]"
					 withStartTag:@"<img id=\""
						   endTag:newEnd];
	
	// Also, replace the template folder path string with the actual path, since we need to set the
	// base URL for the render to the folder, itself (bug #2119594)
	// Set the height of the title stripe
	[templateHTML replaceOccurrencesOfString:@"%%TEMPLATE-FOLDER%%"
								  withString:[[NSBundle mainBundle] resourcePath]];
	
	
	//NSLog(@"HTML:\n%@", templateHTML);
	
	return templateHTML;
}

- (void)renderHTML:(NSString *)html toFolder:(NSString *)folder;
{
	// Construct an off-screen window to receive the WebKit rendering
	// (If it already exists, resize it so that it matches the width of
	//  the content portion of the folder window)
	NSRect startingBounds = NSMakeRect(0, 0, folderWindowWidth, 300);
	
	if (webKitView == nil)
		webKitView = [[WebView alloc] initWithFrame:startingBounds];
	
	if (webKitWindow == nil) {
		webKitWindow = [[NSWindow alloc] initWithContentRect:startingBounds
												   styleMask:NSBorderlessWindowMask
													 backing:NSBackingStoreBuffered
													   defer:NO];
		[webKitWindow setAlphaValue:(CGFloat)0.0];
		[webKitWindow setContentView:webKitView];
	}
	else
		[webKitWindow setContentSize:startingBounds.size];

	// Remember our folder (we'll need it later when WebKit calls us back)
	folderPathRendering = [folder copy];
	
	// Send the HTML to the WebView (and let us know when it's done!)
	[webKitView setResourceLoadDelegate:self];
	[[webKitView mainFrame] loadHTMLString:html baseURL:[NSURL fileURLWithPath:folder]];
}

#pragma mark Helpers

- (BOOL)cleanUpFolder:(NSString *)path;
{
	FinderApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
	
	// Get a reference to the specified folder
	NSURL *folderURL = [NSURL fileURLWithPath:path];
	FinderContainer* folder = [[finder containers] objectAtLocation:folderURL];
	if (folder == nil) {
		return NO;
	}
	
	// Display the folder's window and get a reference to it
	[folder openUsing:finder withProperties:nil];
	FinderFinderWindow *folderWindow = [[folder containerWindow] get];
	
	// Clean it up
	[folderWindow setCurrentView:FinderEcvwIconView];
	[[folderWindow iconViewOptions] setArrangement:FinderEarrNotArranged];
	[folderWindow cleanUpBy:@selector(name)];
	
	return YES;
}

- (BOOL)retrieveDisplayParametersForFolder:(NSString *)path;
{
	FinderApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
	
	// Get a reference to the specified folder
	NSURL *folderURL = [NSURL fileURLWithPath:path];
	FinderContainer* folder = [[finder containers] objectAtLocation:folderURL];
	if (folder == nil) {
		return NO;
	}
	
	// Load up the view preferences for the folder
	[folder openUsing:finder withProperties:nil];
	FinderFinderWindow *folderWindow = [[folder containerWindow] get];
	FinderIconViewOptions *ivo = [folderWindow iconViewOptions];
	BOOL showsTextBelow = ([ivo labelPosition] == FinderEposBottom);
	int iconSize = [ivo iconSize];
	
	// Make sure that we have at least a minimum number of items in the folder
	// (or else the positioning computations will fail!)
	NSMutableArray *placeholders = [[NSMutableArray alloc] init];
	int currentCount = [[folder items] count];
	if (currentCount < MINIMUM_FILES_FOR_POSITIONING) {
        int i;
		for (i = currentCount; i < MINIMUM_FILES_FOR_POSITIONING; i++) {
			NSString *tempFilename = [NSString stringWithFormat:PLACEHOLDER_FILENAME_FORMAT, i];
			[[[NSData alloc] init] writeToFile:[path stringByAppendingPathComponent:tempFilename] atomically:NO];
			[placeholders addObject:tempFilename];
		}
	}
	
	// Tidy everything up before we try to do the positioning computations
	[self cleanUpFolder:path];
	
	// Create a name->location dictionary based on the folder's contents
	NSMutableDictionary *pointMap = [[NSMutableDictionary alloc] init];
	for (FinderItem *item in [folder items])
	{
		[pointMap setObject:NSStringFromPoint([item position])
					 forKey:[item name]];
	}
	
	// Find the items positioned at row 1, column 1; row 2, column 1; and row 1, column 2
	NSPoint maxPoint, r1c1, r2c1, r1c2;
	maxPoint.x = CGFLOAT_MAX;
	maxPoint.y = CGFLOAT_MAX;
	r1c1 = maxPoint;
	r2c1 = maxPoint;
	r1c2 = maxPoint;
	// Find r1c1 first
	for (NSString *key in pointMap) {
		NSPoint candidate = NSPointFromString((NSString *)[pointMap objectForKey:key]);
		if (candidate.x <= r1c1.x &&
			candidate.y <= r1c1.y) {
			r1c1 = candidate;
		}
	}
	// Find r2c1 and r1c2 next
	for (NSString *key in pointMap) {
		NSPoint candidate = NSPointFromString((NSString *)[pointMap objectForKey:key]);
		if (candidate.x <= r1c2.x &&
			candidate.x > r1c1.x &&
			candidate.y == r1c1.y) {
			r1c2 = candidate;
		}
		if (candidate.x == r1c1.x &&
			candidate.y <= r2c1.y &&
			candidate.y > r1c1.y) {
			r2c1 = candidate;
		}
	}	
	
	// Compute the bounding box offsets
	if (showsTextBelow) {
		dy = iconSize * (CGFloat)-0.5;
		dx = (r1c1.x - r1c2.x) * (CGFloat)0.5 + (r1c1.y + dy);
		dw = dx * (CGFloat)-2.0;
		dh = r2c1.y - r1c1.y - (r1c1.y + dy);
	} else {
		dx = r1c1.x * (CGFloat)-1.0;
		dw = r1c2.x - r1c1.x;
		dh = r2c1.y - r1c1.y;
		dy = dh * (CGFloat)-0.5;
	}
	
	// Stretch the bounding boxes a bit to make it more readable
	dy -= (CGFloat)ICON_MARGIN;
	dx -= (CGFloat)ICON_MARGIN;
	dw += (CGFloat)(2 * ICON_MARGIN);
	dh += (CGFloat)(2 * ICON_MARGIN);
	
	// Store the window width variables for later
	folderWindowWidth = (int)([folderWindow bounds].size.width) - [folderWindow sidebarWidth];
	
	// Remove any temp files that we might have created
	for (NSString *tempFilename in placeholders) {
		[[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingPathComponent:tempFilename] error:NULL];
	}
	
	// Return success
	return YES;
}

- (void)webView:(WebView *)sender resource:(id)identifier didFinishLoadingFromDataSource:(WebDataSource *)dataSource;
{
	// If we're not actually ready, then just bail
	NSRect renderingBounds = [[[[webKitView mainFrame] frameView] documentView] bounds];
	if (renderingBounds.size.height == (CGFloat)0.0)
		return;

	// Get the Scripting Bridge references we need
    FinderApplication *finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
    NSURL *folderURL = [NSURL fileURLWithPath:folderPathRendering];
    FinderContainer *finderFolder = [[finder containers] objectAtLocation:folderURL];
    if (finderFolder == nil)
        return;
    
	// Move the files around first
	DOMDocument *document = [webKitView mainFrameDocument];
	if (document != nil) {
		for (FinderItem *item in [finderFolder items]) {
			DOMElement *element = [document getElementById:[item name]];
			if (element != nil)
				[item setPosition:NSMakePoint([element offsetLeft] - (int)dx, [element offsetTop] - (int)dy)];
		}
	}

	// Resize the window to make sure we capture the entire length of the rendered HTML
	[webKitWindow setContentSize:renderingBounds.size];
	
	// Grab the content as an image
	[webKitWindow orderFront:self];
	[webKitView lockFocus];
	// We stretch the window a little bit extra-tall and then crop out the resize thumbnail by
	// manipulating the part of the canvas that we're cropping down
	NSBitmapImageRep *webImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:[webKitView frame]];
	[webKitView unlockFocus];
	[webKitWindow orderOut:self];
	
	// Write the image and set it as the background of the folder
	[self setBackgroundPictureUsingData:[webImageRep representationUsingType:NSPNGFileType properties:nil]
							  forFolder:folderPathRendering];
    
    // Manually refresh Finder's view of the folder
    // (This is not very graceful and is due to a bug in the way that the 10.7 Finder works)
    [finderFolder close];
    [finderFolder openUsing:finder withProperties:nil];
}

- (BOOL)setBackgroundPictureUsingData:(NSData *)imageData forFolder:(NSString *)path;
{
	// Write out the image
	NSString *backgroundFilename = [path stringByAppendingPathComponent:BACKGROUND_IMAGE_FILENAME];
	NSURL *backgroundURL = [NSURL fileURLWithPath:backgroundFilename];
	[imageData writeToURL:backgroundURL atomically:YES];
	
	// Set the folder's background to point at it using the Scripting Bridge
	FinderApplication* finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
	NSURL *folderURL = [NSURL fileURLWithPath:path];
	FinderContainer* folder = [[finder containers] objectAtLocation:folderURL];
	if (folder == nil) {
		return NO;
	}
	[folder openUsing:finder withProperties:nil];
	[[[[folder containerWindow] get] iconViewOptions] setBackgroundPicture:[[finder files] objectAtLocation:backgroundURL]];
	
	// And then hide the image file
	[self setInvisibility:YES ofFile:backgroundFilename];
	
	return YES;
}

- (BOOL)setInvisibility:(BOOL)invisibility ofFile:(NSString *)path;
{
    CFURLRef urlRef;
    FSRef targetFolderFSRef;
    OSErr result;
    struct FSCatalogInfo catInfo;
	
    // Confirm that "path" exists.
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        return NO;
    
    // Create a CFURL with the specified POSIX path.
    urlRef = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
										   (CFStringRef) path,
										   kCFURLPOSIXPathStyle,
										   FALSE /* isDirectory */);
    if (urlRef == NULL) {
        return NO;
    }
    
    // Try to create an FSRef from the URL.  (If the specified file doesn't exist, this
    // function will return false, but if we've reached this code we've already insured
    // that the file exists.)
    CFURLGetFSRef(urlRef, &targetFolderFSRef);
    CFRelease(urlRef);
	
    result = FSGetCatalogInfo(&targetFolderFSRef,
							  kFSCatInfoFinderInfo,
							  &catInfo,
							  /*outName*/ NULL,
							  /*fsSpec*/ NULL,
							  /*parentRef*/ NULL);
    if (result != noErr)
        return NO;
	
    // Tell the Finder that the file should (or should not) be invisible.
	if (invisibility)
		((struct FolderInfo *)catInfo.finderInfo)->finderFlags =
		(((struct FolderInfo *)catInfo.finderInfo)->finderFlags | kIsInvisible);
	else
		((struct FolderInfo *)catInfo.finderInfo)->finderFlags =
		(((struct FolderInfo *)catInfo.finderInfo)->finderFlags & ~kIsInvisible);
	
    result = FSSetCatalogInfo(&targetFolderFSRef,
							  kFSCatInfoFinderInfo,
							  &catInfo);
    if (result != noErr)
        return NO;
	
    // Notify the system that the target directory has changed, to give Finder
    // the chance to find out that the file has "disappeared"
    result = FNNotify(&targetFolderFSRef, kFNDirectoryModifiedMessage, kNilOptions);
    if (result != noErr)
        return NO;
	
    return YES;
}
@end