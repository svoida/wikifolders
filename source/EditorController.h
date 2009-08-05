//
//  EditorController.h
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

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

// Return value constants
#define WFE_MADE_CHANGES	0
#define WFE_NO_CHANGE		-1


@interface EditorController : NSWindowController {
	IBOutlet NSWindow *editorWindow;
	IBOutlet NSTextField *editorTitle;
	IBOutlet NSTextView *editorContent;
	IBOutlet NSButton* editorCheckbox;
	IBOutlet NSButton *editorOKButton;
	
	NSWindow *webKitWindow;
	WebView *webKitView;
	
	CGFloat dx;
	CGFloat dy;
	CGFloat dw;
	CGFloat dh;
	int folderWindowWidth;
}

#pragma mark Interface IBAction callback methods
- (IBAction)editorSaveAndClose:(id)sender;
- (IBAction)editorCancel:(id)sender;

#pragma mark Public methods
- (BOOL)isActiveWikiFolder:(NSString *)folder;
- (int)editWikiTextForFolder:(NSString *)folder withParentWindow:(NSWindow *)parent;
- (int)refreshWikiTextForFolder:(NSString *)folder forceUpdate:(BOOL)useForce;
+ (BOOL)hideFileExtension:(NSString *)path;

@end
