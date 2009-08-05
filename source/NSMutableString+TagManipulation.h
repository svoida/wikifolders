//
//  NSMutableString+TagManipulation.h
//  WikiThinking
//
//  Created by Stephen Voida (svoida@ucalgary.ca) on 8/28/08.
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


@interface NSMutableString (TagManipulationAdditions)

- (NSUInteger)replaceOccurrencesOfString:(NSString *)target withString:(NSString *)replacement;
- (NSUInteger)replaceStartTag:(NSString *)oldStart endTag:(NSString *)oldEnd withStartTag:(NSString *)newStart endTag:(NSString *)newEnd;

@end
