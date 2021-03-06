/*
 * Copyright (c) 2008-2012 Martin Hedenfalk <martin@vicoapp.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "TestViSnippet.h"
#include "logging.h"

@interface MockDelegate : NSObject <ViSnippetDelegate>
{
	NSMutableString *storage;
}
@end

@implementation MockDelegate
- (id)init
{
	if ((self = [super init]) != nil)
		storage = [NSMutableString string];
	return self;
}

- (void)snippet:(ViSnippet *)snippet replaceCharactersInRange:(NSRange)range withString:(NSString *)string forTabstop:(ViTabstop *)tabstop
{
	[storage replaceCharactersInRange:range withString:string];
}

- (void)beginUpdatingSnippet:(ViSnippet *)snippet
{
}

- (void)endUpdatingSnippet:(ViSnippet *)snippet
{
}

- (NSString *)string
{
	return storage;
}
@end

@implementation TestViSnippet

- (void)setUp
{
	env = [NSDictionary dictionaryWithObjectsAndKeys:
	    @"this is the selected text", @"TM_SELECTED_TEXT",
	    @"this selection\nspans\n\nseveral\nlines", @"TM_SELECTED_TEXT2",
	    @"martinh", @"USER",
	    @"TestViSnippet.m", @"TM_FILENAME",
	    nil
	];
	delegate = [[MockDelegate alloc] init];
}

- (void)makeSnippet:(NSString *)snippetString
{
	err = nil;
	snippet = [[ViSnippet alloc] initWithString:snippetString
	                                 atLocation:0
	                                   delegate:delegate
	                                environment:env
	                                      error:&err];
	if (err)
		INFO(@"error: %@", [err localizedDescription]);
	STAssertNotNil(snippet, nil);
	STAssertNil(err, nil);
}

- (void)test001_simpleAbbreviation
{
	[self makeSnippet:@"a long string"];
	STAssertEqualObjects([snippet string], @"a long string", nil);
	STAssertEquals([snippet caret], 13ULL, nil);
}

- (void)test002_escapeReservedCharacters
{
	[self makeSnippet:@"a dollar sign: \\$, \\a bactick: \\`, and a \\\\"];
	STAssertEqualObjects([snippet string], @"a dollar sign: $, \\a bactick: `, and a \\", nil);
	STAssertEquals([snippet caret], 40ULL, nil);
}

- (void)test003_simpleVariable
{
	[self makeSnippet:@"\\textbf{$TM_SELECTED_TEXT}"];
	STAssertEqualObjects([snippet string], @"\\textbf{this is the selected text}", nil);
}

- (void)test004_simpleUndefinedVariable
{
	[self makeSnippet:@"\\textbf{$THIS_VARIABLE_IS_UNDEFINED}"];
	STAssertEqualObjects([snippet string], @"\\textbf{}", nil);
}

- (void)test005_defaultValue
{
	[self makeSnippet:@"\\textbf{${THIS_VARIABLE_IS_UNDEFINED:the variable is undefined}}"];
	STAssertEqualObjects([snippet string], @"\\textbf{the variable is undefined}", nil);
}

- (void)test006_emptyDefaultValue
{
	[self makeSnippet:@"\\textbf{${THIS_VARIABLE_IS_UNDEFINED:}}"];
	STAssertEqualObjects([snippet string], @"\\textbf{}", nil);
}

- (void)test007_missingClosingBrace
{
	snippet = [[ViSnippet alloc] initWithString:@"foo(${THIS_VARIABLE_IS_UNDEFINED:default value)"
	                                 atLocation:0
	                                   delegate:delegate
	                                environment:env
	                                      error:&err];
	STAssertNil(snippet, nil);
	STAssertNotNil(err, nil);
	INFO(@"expected error: %@", [err localizedDescription]);
}

- (void)test008_defaultValueWithEscapedClosingBrace
{
	[self makeSnippet:@"foo(${THIS_VARIABLE_IS_UNDEFINED:\\{braces\\}})"];
	STAssertEqualObjects([snippet string], @"foo(\\{braces})", nil);
}

/* The default value can itself contain variables or shell code. */
- (void)test009_defaultValueContainingSimpleVariable
{
	[self makeSnippet:@"User is ${THIS_VARIABLE_IS_UNDEFINED:$USER}"];
	STAssertEqualObjects([snippet string], @"User is martinh", nil);
}

- (void)test010_defaultValueContainingUndefinedVariable
{
	[self makeSnippet:@"User is ${THIS_VARIABLE_IS_UNDEFINED:$ALSO_UNDEFINED}"];
	STAssertEqualObjects([snippet string], @"User is ", nil);
}

- (void)test011_defaultValueContainingDefaultValue
{
	[self makeSnippet:@"User is ${THIS_VARIABLE_IS_UNDEFINED:${ALSO_UNDEFINED:nobody}}"];
	STAssertEqualObjects([snippet string], @"User is nobody", nil);
}

- (void)test012_regexpReplacement
{
	[self makeSnippet:@"{'user': '${USER/mar/tin/}'}"];
	STAssertEqualObjects([snippet string], @"{'user': 'tintinh'}", nil);
}

- (void)test013_multipleRegexpReplacements
{
	[self makeSnippet:@"{'text': '${TM_SELECTED_TEXT/s/ESS/g}'}"];
	STAssertEqualObjects([snippet string], @"{'text': 'thiESS iESS the ESSelected text'}", nil);
}

- (void)test014_regexpMissingSlash
{
	snippet = [[ViSnippet alloc] initWithString:@"{'user': '${USER/mar/tin}'}"
	                                 atLocation:0
	                                   delegate:delegate
	                                environment:env
	                                      error:&err];
	STAssertNil(snippet, nil);
	STAssertNotNil(err, nil);
	INFO(@"expected error: %@", [err localizedDescription]);
}

- (void)test015_regexpNoMatch
{
	[self makeSnippet:@"{'user': '${USER/foo/bar/}'}"];
	STAssertEqualObjects([snippet string], @"{'user': 'martinh'}", nil);
}

- (void)test016_regexpEmptyFormat
{
	[self makeSnippet:@"{'user': '${USER/h$//}'}"];
	STAssertEqualObjects([snippet string], @"{'user': 'martin'}", nil);
}

- (void)test017_defaultValueContainingRegexp
{
	[self makeSnippet:@"User is ${THIS_VARIABLE_IS_UNDEFINED:${USER/tin/mor/}}"];
	STAssertEqualObjects([snippet string], @"User is marmorh", nil);
}

- (void)test018_invalidRegexp
{
	snippet = [[ViSnippet alloc] initWithString:@"${USER/[x/bar/}"
	                                 atLocation:0
	                                   delegate:delegate
	                                environment:env
	                                      error:&err];
	STAssertNil(snippet, nil);
	STAssertNotNil(err, nil);
	INFO(@"expected error: %@", [err localizedDescription]);
}

- (void)test019_regexpPrepend
{
	[self makeSnippet:@"${TM_SELECTED_TEXT/^.+$/* $0/}"];
	STAssertEqualObjects([snippet string], @"* this is the selected text", nil);
}

- (void)test020_regexpPrependMultipleLines
{
	[self makeSnippet:@"${TM_SELECTED_TEXT2/^.+$/* $0/g}"];
	STAssertEqualObjects([snippet string], @"* this selection\n* spans\n\n* several\n* lines", nil);
}

- (void)test021_regexpCaptures
{
	[self makeSnippet:@"${TM_SELECTED_TEXT/^this (.*) the (.*)$/$1 $2/}"];
	STAssertEqualObjects([snippet string], @"is selected text", nil);
}

- (void)test022_simpleShellCodeInterpolation
{
	[self makeSnippet:@"<a href=\"`echo \"bacon\"`.html\">what's chunky?</a>"];
	STAssertEqualObjects([snippet string], @"<a href=\"bacon.html\">what's chunky?</a>", nil);
}

- (void)test023_nonexistantShellCommand
{
	[self makeSnippet:@"`doesntexist`"];
	STAssertEqualObjects([snippet string], @"/bin/bash: doesntexist: command not found", nil);
}

- (void)test024_shebangShellCommand
{
	[self makeSnippet:@"`#!/usr/bin/env perl\nprint(\"\\`hej\\`\");\n`"];
	STAssertEqualObjects([snippet string], @"`hej`", nil);
}

- (void)test024_shebangShellCommandWithDoubleEscapes
{
	[self makeSnippet:@"`#!/usr/bin/env perl\nprint(\"\\\\\\`hej\\\\\\`\");\n`"];
	STAssertEqualObjects([snippet string], @"\\`hej\\`", nil);
}

/* Shell commands have access to the environment variables. */
- (void)test024_shellCommandWithEnvironment
{
	[self makeSnippet:@"filename is `echo \"${TM_FILENAME}\"`"];
	STAssertEqualObjects([snippet string], @"filename is TestViSnippet.m", nil);
}

- (void)test025_simpleTabStop
{
	[self makeSnippet:@"<div>\n    $0\n</div>"];
	STAssertEqualObjects([snippet string], @"<div>\n    \n</div>", nil);
	STAssertEquals([snippet caret], 10ULL, nil);
}

- (void)test026_tabStopWithDefaultValue
{
	[self makeSnippet:@"#include \"${1:${TM_FILENAME/\\..+$/.h/}}\""];
	STAssertEqualObjects([snippet string], @"#include \"TestViSnippet.h\"", nil);
	STAssertEquals([snippet range].location, 0ULL, nil);
	STAssertEquals([snippet range].length, 26ULL, nil);
	NSRange r = [snippet tabRange];
	STAssertEquals(r.location, 10ULL, nil);
	STAssertEquals(r.length, 15ULL, nil);
}

- (void)test027_multipleTabStops
{
	[self makeSnippet:@"<div$1>\n    $0\n</div>"];
	STAssertEqualObjects([snippet string], @"<div>\n    \n</div>", nil);
	STAssertEquals([snippet tabRange].location, 4ULL, nil);
	STAssertEquals([snippet tabRange].length, 0ULL, nil);
	STAssertTrue([snippet advance], nil);
}

- (void)test028_updatePlaceHolders
{
	[self makeSnippet:@"if (${1:/* condition */})\n{\n    ${0:/* code */}\n}"];
	STAssertEqualObjects([snippet string], @"if (/* condition */)\n{\n    /* code */\n}", nil);
	STAssertEquals([snippet tabRange].location, 4ULL, nil);
	STAssertEquals([snippet tabRange].length, 15ULL, nil);

	STAssertEquals(snippet.selectedRange.location, 4ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 15ULL, nil);
	[snippet deselect];
	STAssertEquals(snippet.selectedRange.location, (NSUInteger)NSNotFound, nil);
	STAssertEquals(snippet.selectedRange.length, 0ULL, nil);

	STAssertTrue([snippet replaceRange:NSMakeRange(4, 15) withString:@"p"], nil);
	STAssertEqualObjects([snippet string], @"if (p)\n{\n    /* code */\n}", nil);
	STAssertEquals([snippet tabRange].location, 4ULL, nil);
	STAssertEquals([snippet tabRange].length, 1ULL, nil);

	// advance to tab stop 0, which finishes the snippet
	STAssertTrue([snippet advance], nil);
	STAssertFalse([snippet replaceRange:NSMakeRange(13, 10) withString:@""], nil);
}

- (void)test029_mirror
{
	[self makeSnippet:@"\\begin{${1:enumerate}}$0\\end{$1}"];
	STAssertEqualObjects([snippet string], @"\\begin{enumerate}\\end{enumerate}", nil);
	STAssertEquals([snippet tabRange].location, 7ULL, nil);
	STAssertEquals([snippet tabRange].length, 9ULL, nil);
	STAssertEquals(snippet.range.location, 0ULL, nil);
	STAssertEquals(snippet.range.length, 32ULL, nil);
	STAssertTrue([snippet replaceRange:NSMakeRange(7, 9) withString:@"itemize"], nil);
	STAssertEqualObjects([snippet string], @"\\begin{itemize}\\end{itemize}", nil);
	STAssertEquals([snippet tabRange].location, 7ULL, nil);
	STAssertEquals([snippet tabRange].length, 7ULL, nil);
	STAssertEquals(snippet.range.location, 0ULL, nil);
	STAssertEquals(snippet.range.length, 28ULL, nil);
}

/* If there are mirrors, the first tabstop with a default value
 * (placeholder) is where the caret is placed.
 */
- (void)test030_reverseMirror
{
	[self makeSnippet:@"\\begin{$1}$0\\end{${1:enumerate}}"];
	STAssertEqualObjects([snippet string], @"\\begin{enumerate}\\end{enumerate}", nil);
	STAssertEquals([snippet tabRange].location, 22ULL, nil);
	STAssertEquals([snippet tabRange].length, 9ULL, nil);
}

- (void)test031_tabstopOrdering
{
	[self makeSnippet:@"2:$2 0:$0 1:$1 4:$4 2.2:$2 2.3:$2"];
	STAssertEqualObjects([snippet string], @"2: 0: 1: 4: 2.2: 2.3:", nil);
	STAssertEquals(snippet.caret, 8ULL, nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 2ULL, nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 11ULL, nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 5ULL, nil);
}

/* A tabstop can't be placed inside a default value for a shell variable. */
- (void)test032_invalidTabstopInVariable
{
	snippet = [[ViSnippet alloc] initWithString:@"hello ${USER:$1}"
	                                 atLocation:0
	                                   delegate:delegate
	                                environment:env
	                                      error:&err];
	STAssertNil(snippet, nil);
	STAssertNotNil(err, nil);
	INFO(@"expected error: %@", [err localizedDescription]);
}

/* A mirror can be transformed by a regular expression. */
- (void)test033_mirrorWithTransformation
{
	[self makeSnippet:@"tabstop:${1:bacon}\nmirror:${1/[aouåeiyäö]/$0$0/g}"];
	STAssertEqualObjects([snippet string], @"tabstop:bacon\nmirror:baacoon", nil);
	STAssertEquals(snippet.caret, 8ULL, nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"chunky"], nil);
	STAssertEqualObjects([snippet string], @"tabstop:chunky\nmirror:chuunkyy", nil);
}

/* Tabstops can be nested. */
- (void)test037_nestedTabstops
{
	[self makeSnippet:@"x: ${1:nested ${2:tabstop}}"];
	STAssertEqualObjects([snippet string], @"x: nested tabstop", nil);
	STAssertEquals(snippet.caret, 3ULL, nil);
	STAssertEquals(snippet.selectedRange.location, 3ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 14ULL, nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 10ULL, nil);
	STAssertEquals(snippet.selectedRange.location, 10ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 7ULL, nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"placeholder"], nil);
	STAssertEqualObjects([snippet string], @"x: nested placeholder", nil);
}

/* Nested tabstops can have mirrors outside of the containing tabstop. */
- (void)test038_nestedTabstopWithMirrors
{
	[self makeSnippet:@"foo: ${1:nested ${2:tabstop}}, ${2/^.*$/mirror: $0/}"];
	STAssertEqualObjects([snippet string], @"foo: nested tabstop, mirror: tabstop", nil);
}

- (void)test039_updateNestedBaseLocation
{
	[self makeSnippet:@"for(size_t ${2:i} = 0; $2 < ${1:count}; ${3:++$2})"];
	STAssertEqualObjects([snippet string], @"for(size_t i = 0; i < count; ++i)", nil);
}

- (void)test040_nestedTabstopCancelledIfParentEdited
{
	[self makeSnippet:@"${1:hello ${2:world}${3:!}}"];
	STAssertEqualObjects([snippet string], @"hello world!", nil);
	STAssertEquals(snippet.selectedRange.location, 0ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 12ULL, nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"goodbye"], nil);
	STAssertEqualObjects([snippet string], @"goodbye", nil);
	STAssertFalse([snippet advance], nil);
}

- (void)test041_nestedTabstopCancelledIfParentEdited_2
{
	[self makeSnippet:@"${2:hello ${1:world}}$0"];
	STAssertEqualObjects([snippet string], @"hello world", nil);
	STAssertEquals(snippet.selectedRange.location, 6ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 5ULL, nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"chunky bacon"], nil);
	STAssertEqualObjects([snippet string], @"hello chunky bacon", nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.selectedRange.location, 0ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 18ULL, nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"goodbye"], nil);
	STAssertEqualObjects([snippet string], @"goodbye", nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 7ULL, nil);
	STAssertFalse([snippet advance], nil);
}

- (void)test042_nestedTabstopWithMultipleLocations
{
	[self makeSnippet:@"${3:Send $2 to $1, if $1 supports it}\n[${1:self} respondsToSelector:@selector(${2:someSelector:})]"];
	STAssertEqualObjects([snippet string], @"Send someSelector: to self, if self supports it\n[self respondsToSelector:@selector(someSelector:)]", nil);
	STAssertEquals(snippet.selectedRange.location, 49ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 4ULL, nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"bacon"], nil);
	STAssertEqualObjects([snippet string], @"Send someSelector: to bacon, if bacon supports it\n[bacon respondsToSelector:@selector(someSelector:)]", nil);
	STAssertEquals([snippet tabRange].location, 51ULL, nil);
	STAssertEquals([snippet tabRange].length, 5ULL, nil);
}

- (void)test043_escapedDollarInRegexFormat
{
	[self makeSnippet:@"${1:hello} ${1/./\\$0/g}"];
	STAssertEqualObjects([snippet string], @"hello $0$0$0$0$0", nil);
}

- (void)test044_unescapedDollarAtEnd
{
	[self makeSnippet:@"${1:hello} ${1/(.)/1$/g}"];
	STAssertEqualObjects([snippet string], @"hello 1$1$1$1$1$", nil);
}

- (void)test045_nonNumericCaptureGroup
{
	[self makeSnippet:@"${1:hello} ${1/(.)/$a/g}"];
	STAssertEqualObjects([snippet string], @"hello $a$a$a$a$a", nil);
}

/* Opening parenthesis are also escapable. But not closing parens, WTF? */
- (void)test046_validCaptureGroupWithEscapedParens
{
	[self makeSnippet:@"${1:hello} ${1/(.)/\\($1\\)/g}"];
	STAssertEqualObjects([snippet string], @"hello (h\\)(e\\)(l\\)(l\\)(o\\)", nil);
}

- (void)test047_unmatchedCaptureGroup
{
	[self makeSnippet:@"${1:hello} ${1/(.)/$10/g}"];
	STAssertEqualObjects([snippet string], @"hello ", nil);
}

/* A capture group must be positiv or zero. */
- (void)test048_negativeCaptureGroup
{
	snippet = [[ViSnippet alloc] initWithString:@"${1:hello} ${1/(.)/$-1/g}"
	                                 atLocation:0
	                                   delegate:delegate
	                                environment:env
	                                      error:&err];
	STAssertNil(snippet, nil);
	STAssertNotNil(err, nil);
	INFO(@"expected error: %@", [err localizedDescription]);
}

- (void)test049_escapedNewlinesInRegexFormat
{
	[self makeSnippet:@"${TM_FILENAME/(?!^)[A-Z]/\\n$0/g}"];
	STAssertEqualObjects([snippet string], @"Test\nVi\nSnippet.m", nil);
}

- (void)test050_escapedTabsInRegexFormat
{
	[self makeSnippet:@"${TM_FILENAME/(?!^)[A-Z]/\\t$0/g}"];
	STAssertEqualObjects([snippet string], @"Test\tVi\tSnippet.m", nil);
}

- (void)test051_uppercaseNextChar
{
	[self makeSnippet:@"${USER/.*/\\u$0/}"];
	STAssertEqualObjects([snippet string], @"Martinh", nil);
}

- (void)test052_uppercaseString
{
	[self makeSnippet:@"${1:Straße} ${1/.*/\\U$0/}"];
	STAssertEqualObjects([snippet string], @"Straße STRASSE", nil);
}

- (void)test053_upperLowerCaseMix
{
	[self makeSnippet:@"${USER/(.*)(r)(.*)/\\U$1\\L$2\\u$3/}"];
	STAssertEqualObjects([snippet string], @"MArTinh", nil);
}

- (void)test054_endCaseFolding
{
	[self makeSnippet:@"${USER/(.*)(r)(.*)/\\U$1\\E$2$3\\l/}"];
	STAssertEqualObjects([snippet string], @"MArtinh", nil);
}

- (void)test055_conditionalInsertion
{
	[self makeSnippet:@"${1:void} ${1/void$|(.+)/(?1:return nil;)/}"];
	STAssertEqualObjects([snippet string], @"void ", nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"id"], nil);
	STAssertEqualObjects([snippet string], @"id return nil;", nil);
}

- (void)test056_conditionalInsertionOtherwise
{
	[self makeSnippet:@"${1:void} ${1/void$|(.+)/(?1:return nil;:return;)/}"];
	STAssertEqualObjects([snippet string], @"void return;", nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"id"], nil);
	STAssertEqualObjects([snippet string], @"id return nil;", nil);
}

/* Ugh. Of course you can nest 'em. */
- (void)test057_nestedConditionalInsertion
{
	[self makeSnippet:@"${1:void} ${1/void$|(.+)/(?1:return (?1:$1:embedded\\:colon and paren\\));:;)/}"];
	STAssertEqualObjects([snippet string], @"void ;", nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"id"], nil);
	STAssertEqualObjects([snippet string], @"id return id;", nil);
}

/* Quick! What does this snippet do? */
- (void)test058_printf
{
	[self makeSnippet:@"printf(\"${1:%s}\\n\"${1/([^%]|%%)*(%.)?.*/(?2:, :\\);)/}$2${1/([^%]|%%)*(%.)?.*/(?2:\\);)/}"];
	STAssertEqualObjects([snippet string], @"printf(\"%s\\n\", );", nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"hello"], nil);
	STAssertEqualObjects([snippet string], @"printf(\"hello\\n\");", nil);
}

- (void)test058_printfAdvance
{
	[self makeSnippet:@"printf(\"${1:%s}\\n\"${1/([^%]|%%)*(%.)?.*/(?2:, :\\);)/}$2${1/([^%]|%%)*(%.)?.*/(?2:\\);)/}"];
	STAssertEqualObjects([snippet string], @"printf(\"%s\\n\", );", nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 15ULL, nil);
}

/* http://e-texteditor.com/blog/2008/snippet-pipes */
- (void)test059_snippetPipe
{
	[self makeSnippet:@"${1:ruby code|ruby -e \"print eval STDIN.read\"}$0"];
	STAssertEqualObjects([snippet string], @"ruby code", nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"17+42"], nil);
	STAssertEqualObjects([snippet string], @"17+42", nil);
	STAssertTrue([snippet advance], nil);
	STAssertEqualObjects([snippet string], @"59", nil);
	STAssertEquals(snippet.caret, 2ULL, nil);
}

- (void)test060_mirrorPipe
{
	[self makeSnippet:@"${1:expression} = ${1/$/\\n/|bc}"];
	STAssertEqualObjects([snippet string], @"expression = 0", nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"17+42"], nil);
	STAssertEqualObjects([snippet string], @"17+42 = 59", nil);
}

- (void)test061_updateLocationZeroLengthZero
{
	[self makeSnippet:@"$1$0"];
	STAssertEqualObjects([snippet string], @"", nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"bacon"], nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 5ULL, nil);
}

- (void)test062_nestedTabstopsMultipleLevels
{
	[self makeSnippet:@"x: ${1:nested ${2:tab${3:stop}}}"];
	STAssertEqualObjects([snippet string], @"x: nested tabstop", nil);
	STAssertEquals(snippet.caret, 3ULL, nil);
	STAssertEquals(snippet.selectedRange.location, 3ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 14ULL, nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 10ULL, nil);
	STAssertEquals(snippet.selectedRange.location, 10ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 7ULL, nil);
	STAssertTrue([snippet advance], nil);
	STAssertEquals(snippet.caret, 13ULL, nil);
	STAssertEquals(snippet.selectedRange.location, 13ULL, nil);
	STAssertEquals(snippet.selectedRange.length, 4ULL, nil);
	STAssertTrue([snippet replaceRange:snippet.selectedRange withString:@"le"], nil);
	STAssertEqualObjects([snippet string], @"x: nested table", nil);
}

/* Handle (ignore) unknown regexp options.
 */
- (void)test063_unknownRegexOptions
{
	[self makeSnippet:@"${0:${TM_SELECTED_TEXT/\\A<strong>(.*)<\\/strong>\\z|.*/(?1:$1:<strong>$0<\\/strong>)/m}}"];
}

@end
