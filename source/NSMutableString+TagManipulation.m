//
//  NSMutableString+TagManipulation.m
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

#import "NSMutableString+TagManipulation.h"

@implementation NSMutableString (TagManipulationAdditions)

- (NSUInteger)replaceOccurrencesOfString:(NSString *)target withString:(NSString *)replacement {
	return [self replaceOccurrencesOfString:target
								 withString:replacement
									options:NSLiteralSearch
									  range:NSMakeRange(0, [self length])];
}

- (NSUInteger)replaceStartTag:(NSString *)oldStart endTag:(NSString *)oldEnd withStartTag:(NSString *)newStart endTag:(NSString *)newEnd {
	// Find the first starting tag
	NSRange startRange = [self rangeOfString:oldStart
									 options:NSLiteralSearch
									   range:NSMakeRange(0, [self length])];
	if (startRange.location == NSNotFound)
		return 0;
	
	// Find the first ending tag following the first starting tag
	int endSearchStart = startRange.location + startRange.length;
	NSRange endRange = [self rangeOfString:oldEnd
								   options:NSLiteralSearch
									 range:NSMakeRange(endSearchStart, [self length] - endSearchStart)];
	if (endRange.location == NSNotFound)
		return 0;
	
	// If we've found both, then replace each (work backwards to preserve range calculations)
	[self replaceCharactersInRange:endRange withString:newEnd];
	[self replaceCharactersInRange:startRange withString:newStart];
	
	// Recurse to get the next set
	return (1 + [self replaceStartTag:oldStart endTag:oldEnd withStartTag:newStart endTag:newEnd]);
}

@end
