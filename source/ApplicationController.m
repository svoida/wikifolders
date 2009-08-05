//
//  ApplicationController.m
//  WikiFolders
//
//  Created by Stephen Voida (svoida@ucalgary.ca) on 9/9/08.
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

#import "ApplicationController.h"
#import "Constants.h"
#import "EditorController.h"
#import "SCEvents.h"
#import "SCEvent.h"


@implementation ApplicationController

#pragma mark Constructors

+ (void)initialize;
{
	// Register the user preferences that we'll be storing
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
	
	// Put the default value of the flag for drawing icon borders into the dictionary (NO)
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:WF_DRAW_ICON_BORDERS_KEY];
	
	// Put the default watch delay into the dictionary (30 seconds)
	[defaultValues setObject:[NSNumber numberWithDouble:30.0] forKey:WF_FOLDER_WATCH_TIME_DELAY_KEY];
	
	// Put the default font size used to render the HTML body text into the dictionary (11pt)
	[defaultValues setObject:@"11" forKey:WF_RENDERED_FONT_SIZE_KEY];
	
	// Put an empty list of wiki folders into the dictionary
	NSArray *emptyArray = [NSArray array];
	[defaultValues setObject:emptyArray forKey:WF_WIKIFOLDERS_KEY];
	
	// Register the dictionary of defaults
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

- (id)init;
{
	self = [super init];
	if (self) {
		folderArray = [[NSMutableArray alloc] init];
		refreshWhiteList = [[NSMutableArray alloc] init];
		selectionStatusString = nil;

		// Set up our FSEvents hook
		watcher = [SCEvents sharedPathWatcher]; 
		[watcher setNotificationLatency:[[[NSUserDefaults standardUserDefaults] objectForKey:WF_FOLDER_WATCH_TIME_DELAY_KEY] doubleValue]];
		[watcher setDelegate:self];
		
		// Tiny bit of self-maintenance
		// Sometimes the "hide extension" bit on our internal copy of the
		// "Edit Wiki Formatting" icon gets toggled off. This just forces
		// it off before we go trying to copy it anywhere else...
		[EditorController hideFileExtension:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:WIKITEXT_EDITOR_FILENAME]];
	}
	
	return self;
}

#pragma mark Property method synthesis

@synthesize currentStatusString;
@synthesize folderArray;

- (NSString *)versionString;
{
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}

#pragma mark Lifecycle methods

- (void)awakeFromNib;
{
	NSLog(@"application started up");
	
	// Tell the table to forward double-clicks on the table back to us
	[tableView setTarget:self];
	[tableView setDoubleAction:@selector(editWikiTextAction:)];

	// Prep the editor; we'll need it almost immediately
	if (editor == nil)
		editor = [[EditorController alloc] init];
	
	// Re-load and refresh the prior list of "watched" folders (if any)
	NSArray *storedFolderArray = [[NSUserDefaults standardUserDefaults] objectForKey:WF_WIKIFOLDERS_KEY];
	NSLog(@"loading stored wiki folder data");
	for (NSString *storedFolder in storedFolderArray) {
		if (![editor isActiveWikiFolder:storedFolder]) {
			NSString *message = [NSString stringWithFormat:@"The folder %@ no longer has its WikiFolders formatting in place.\n\nWould you like the WikiFolders application to stop monitoring this for further changes?", storedFolder];
			int result = NSRunAlertPanel(@"Monitored Folder Missing WikiFolders Components",
										 message,
										 @"Yes",
										 @"No, please restore the formatting",
										 nil);
			if (result == NSOKButton)
				continue;
		}
			
		[self addFolder:storedFolder skipWatcherUpdate:YES];
	}
	
	// Start up the watcher once everything's assembled
	[watcher startWatchingPaths:folderArray];
	
	// Clear the table's selection (if any)
	// This will also set the status bar string by proxy
	[folderArrayController setSelectionIndexes:[NSIndexSet indexSet]];
	
	NSLog(@"initialization complete.");
}

#pragma mark NSApplication delegate methods

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename;
{
	NSLog(@"opening %@", filename);
	
	// Check to make sure it's a folder we already know about
	NSString *folderPath = [filename stringByDeletingLastPathComponent];
	if (![folderArray containsObject:folderPath]) {
		NSString *message = [NSString stringWithFormat:@"The folder %@ is not currently being monitored by the WikiFolders application for changes.\n\nWould you like WikiFolders to keep this folder's wikitext and formatting up-to-date as its files change?", folderPath];
		int result = NSRunAlertPanel(@"Unmonitored Folder Detected",
									 message,
									 @"Yes",
									 @"No",
									 nil);
		if (result == NSOKButton)
			[self addFolder:folderPath skipWatcherUpdate:NO];
	}
	[self editFolder:folderPath];
	
	return YES;
}

#pragma mark NSWindow delegate methods

- (void)windowWillClose:(NSNotification *)notification;
{
	[self shutDown];
}

#pragma mark NSTableView delegate methods

- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
	if ([folderArrayController selectionIndex] == NSNotFound)
		selectionStatusString = nil;
	else
		selectionStatusString = [NSString stringWithFormat:@"Selected folder \"%@\"", [[folderArrayController selectedObjects] objectAtIndex:0]];
	
	[self updateStatusBar];
}

#pragma mark SCEvents delegate methods

- (void)pathWatcher:(SCEvents *)pathWatcher eventOccurred:(SCEvent *)event;
{
	NSString *folderPath = [event eventPath];
	if ([folderArray containsObject:folderPath])
		[self refreshFolder:folderPath forceUpdate:NO];
}

#pragma mark Interface IBAction callback methods

- (IBAction)addWikiFolderAction:(id)sender;
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setCanChooseFiles:NO];
	[panel setCanChooseDirectories:YES];
	[panel setAllowsMultipleSelection:NO];
	[panel setMessage:@"Select a folder you would like to annotate as a WikiFolder:"];
	if (NSOKButton == [panel runModalForDirectory:NSHomeDirectory() file:nil types:nil] &&
		[[panel filenames] count] > 0)
	{
		NSString *folderPath = [[panel filenames] objectAtIndex:0];
		[self addFolder:folderPath skipWatcherUpdate:NO];
	}
	
}

- (IBAction)editWikiTextAction:(id)sender;
{
	NSString* folderPath = [[folderArrayController selectedObjects] objectAtIndex:0];
	[self editFolder:folderPath];
}

- (IBAction)forceRefreshAction:(id)sender;
{
	NSString *folderPath = [[folderArrayController selectedObjects] objectAtIndex:0];
	[self refreshFolder:folderPath forceUpdate:YES];
}

- (IBAction)removeWikiFolderAction:(id)sender;
{
	NSString *folderPath = [[folderArrayController selectedObjects] objectAtIndex:0];
	[self removeFolder:folderPath];
}

#pragma mark Worker functions

- (void)addFolder:(NSString *)folderPath skipWatcherUpdate:(BOOL)skip;
{
	// Avoid duplicates
	if ([folderArray containsObject:folderPath])
		return;
	
	// Add the folder to our watchlist
	[folderArrayController addObject:folderPath];
	
	// And refesh it
	[editor refreshWikiTextForFolder:folderPath forceUpdate:NO];
	
	// And re-set the FSEvents watcher (optionally)
	if (!skip) {
		if ([watcher isWatchingPaths])
			[watcher stopWatchingPaths];
		[watcher startWatchingPaths:folderArray];
	}
	
	NSLog(@"added folder: %@", folderPath);
}

- (void)editFolder:(NSString *)folderPath;
{
	NSLog(@"started editing folder: %@", folderPath);
	int result = [editor editWikiTextForFolder:folderPath withParentWindow:mainWindow];
	if (result == WFE_MADE_CHANGES) {
		// Add the folder to a change whitelist, as we'll get a notification shortly that
		// an edit has taken place -- which we already know about and have handled
		[refreshWhiteList addObject:folderPath];
		
		NSLog(@"editing completed; results saved.");
	} else
		NSLog(@"editing aborted.");
}

- (void)refreshFolder:(NSString *)folderPath forceUpdate:(BOOL)useForce;
{
	// Skip the refresh if the path is whitelisted
	// (prevents endless updates due to our own updating of files)
	if (!useForce && [refreshWhiteList containsObject:folderPath]) {
		[refreshWhiteList removeObject:folderPath];
		return;
	}

	// If we're asked to refresh a folder that doesn't have any wiki content,
	// maybe we should be removing it from our list instead...
	if ([folderArray containsObject:folderPath] &&
		![editor isActiveWikiFolder:folderPath]) {
		NSString *message = [NSString stringWithFormat:@"The folder %@ no longer has its WikiFolders formatting in place.\n\nWould you like the WikiFolders application to stop monitoring this for further changes?", folderPath];
		int result = NSRunAlertPanel(@"Monitored Folder Missing WikiFolders Components",
									 message,
									 @"Yes",
									 @"No, please restore the formatting",
									 nil);
		if (result == NSOKButton) {
			[folderArrayController removeObject:folderPath];
			return;
		}
	}
	
	// Otherwise, carry on with that update!
	[editor refreshWikiTextForFolder:folderPath forceUpdate:useForce];
	
	NSLog(@"refreshed folder: %@", folderPath);
}

- (void)removeFolder:(NSString *)folderPath;
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *removeAppPath = [folderPath stringByAppendingPathComponent:WIKITEXT_REMOVAL_FILENAME];
	
	// Make sure a removal app is in the target folder
	if (![fm fileExistsAtPath:removeAppPath]) {
		if (![fm copyPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:WIKITEXT_REMOVAL_FILENAME]
				   toPath:removeAppPath
				  handler:nil]) {
			NSRunCriticalAlertPanel(@"Problem removing WikiFolder formatting",
									@"The application does not have write access to the folder.",
									@"OK", nil, nil);
			return;
		}
	}
	
	// Call the removal app to actually take care of business
	[[NSWorkspace sharedWorkspace] launchApplication:removeAppPath];
	
	BOOL stillRunning = YES;
	while (stillRunning) {
		// Sleep a bit
		[NSThread sleepForTimeInterval:1.0];
		
		// See if it's done
		stillRunning = NO;
		NSLog(@"looking for %@", removeAppPath);
		for (NSDictionary *appInfo in [[NSWorkspace sharedWorkspace] launchedApplications]) {
			NSLog(@"found %@", (NSString *)[appInfo objectForKey:@"NSApplicationPath"]);
			if([(NSString *)[appInfo objectForKey:@"NSApplicationPath"] compare:removeAppPath] == NSOrderedSame)
				stillRunning = YES;
		}
	}
	
	// Check to see if the removal worked; if it did, then pull the folder off of our list
	if (![fm fileExistsAtPath:removeAppPath]) {
		[folderArrayController removeObject:folderPath];
		NSLog(@"removed folder: %@", folderPath);
	}
	
	// Grab the input focus back!
	[mainWindow makeKeyAndOrderFront:self];
}

- (void)shutDown;
{
	NSLog(@"application shutting down");
	
	// Turn off the watcher
	if ([watcher isWatchingPaths])
		[watcher stopWatchingPaths];
	
	// Write out our current list of "watched" folders
	NSLog(@"writing out the current wiki folder list for next time");
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:folderArray forKey:WF_WIKIFOLDERS_KEY];
	[defaults synchronize];
	
	// And quit
	[NSApp terminate:self];
}

- (void)updateStatusBar;
{
	if (selectionStatusString != nil)
		[self setCurrentStatusString:selectionStatusString];
	else
		[self setCurrentStatusString:[NSString stringWithFormat:@"WikiFolders version %@ ready",
									  [self versionString]]];
}

@end
