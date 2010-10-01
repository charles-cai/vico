#import "ViRegexp.h"
#import "logging.h"

@implementation ViRegexp

+ (ViRegexp *)regularExpressionWithString:(NSString *)aString options:(int)options syntax:(int)syntax
{
	return [[ViRegexp alloc] initWithString:aString options:options syntax:syntax];
}

+ (ViRegexp *)regularExpressionWithString:(NSString *)aString options:(int)options
{
	return [ViRegexp regularExpressionWithString:aString options:options syntax:0];
}

+ (ViRegexp *)regularExpressionWithString:(NSString *)aString
{
	return [ViRegexp regularExpressionWithString:aString options:0 syntax:0];
}

- (ViRegexp *)initWithString:(NSString *)aString options:(int)options syntax:(int)syntax
{
	self = [super init];

	size_t len = [aString length] * sizeof(unichar);
	unichar *pattern = malloc(len);
	[aString getCharacters:pattern];

	OnigEncoding enc;
#if defined(__BIG_ENDIAN__)
	enc = ONIG_ENCODING_UTF16_BE;
#else
	enc = ONIG_ENCODING_UTF16_LE;
#endif
	OnigErrorInfo einfo;
	int r = onig_new(&regex, (const UChar *)pattern, (const UChar *)pattern + len, options | ONIG_OPTION_CAPTURE_GROUP, enc, ONIG_SYNTAX_RUBY, &einfo);
	free(pattern);
	if (r != ONIG_NORMAL) {
#ifndef NO_DEBUG
		unsigned char s[ONIG_MAX_ERROR_MESSAGE_LEN];
		onig_error_code_to_str(s, r, &einfo);
		DEBUG(@"pattern failed: %s", s);
#endif
		return nil;
	}

	return self;
}

- (void)finalize
{
	if (regex)
	{
		onig_free(regex);
	}
	[super finalize];
}

- (ViRegexpMatch *)matchInCharacters:(const unichar *)chars options:(int)options range:(NSRange)aRange start:(NSUInteger)aLocation
{
	OnigRegion *region = onig_region_new();

	const unsigned char *str = (const unsigned char *)chars;
	const unsigned char *start = str + (aRange.location - aLocation) * sizeof(unichar);
	const unsigned char *end = start + aRange.length * sizeof(unichar);

	int r = onig_search(regex, str, end, start, end, region, ONIG_OPTION_FIND_NOT_EMPTY | options);
	if (r >= 0)
		return [ViRegexpMatch regexpMatchWithRegion:region startLocation:aLocation];
	onig_region_free(region, 1);
	return nil;
}

- (ViRegexpMatch *)matchInCharacters:(const unichar *)chars range:(NSRange)aRange start:(NSUInteger)aLocation
{
	return [self matchInCharacters:chars options:0 range:aRange start:aLocation];
}

- (ViRegexpMatch *)matchInString:(NSString *)aString range:(NSRange)aRange
{
	// INFO(@"matching string in range %u + %u", aRange.location, aRange.length);
	/* if ([aString fastestEncoding] != 30) */
		/* INFO(@"fastest encoding = %u (expecting 0x%08X)", [aString fastestEncoding], NSUTF16LittleEndianStringEncoding); */

	unichar *chars = malloc(aRange.length * sizeof(unichar));
	[aString getCharacters:chars range:aRange];
	ViRegexpMatch *match = [self matchInCharacters:chars range:NSMakeRange(0, aRange.length) start:aRange.location];
	
	free(chars);
	return match;
}

- (ViRegexpMatch *)matchInString:(NSString *)aString
{
	return [self matchInString:aString range:NSMakeRange(0, [aString length])];
}

- (NSArray *)allMatchesInCharacters:(const unichar *)chars options:(int)options range:(NSRange)aRange start:(NSUInteger)aLocation
{
	NSMutableArray *matches = nil;

	NSRange range = aRange;
	while (range.location < NSMaxRange(aRange))
	{
		ViRegexpMatch *match = [self matchInCharacters:chars options:options range:range start:aLocation];
		if (match == nil)
			break;

		if (matches == nil)
			matches = [[NSMutableArray alloc] init];
		[matches addObject:match];

		NSRange r = [match rangeOfMatchedString];
		if (r.length == 0)
			r.length = 1;
		range.location = NSMaxRange(r);
		range.length = NSMaxRange(aRange) - range.location;
	}

	return matches;
}

- (NSArray *)allMatchesInCharacters:(const unichar *)chars range:(NSRange)aRange start:(NSUInteger)aLocation
{
	return [self allMatchesInCharacters:chars options:0 range:aRange start:aLocation];
}

- (NSArray *)allMatchesInString:(NSString *)aString options:(int)options range:(NSRange)aRange
{
	unichar *chars = malloc(aRange.length * sizeof(unichar));
	[aString getCharacters:chars range:aRange];
	NSArray *matches = [self allMatchesInCharacters:chars options:options range:NSMakeRange(0, aRange.length) start:aRange.location];
	free(chars);
	return matches;
}

- (NSArray *)allMatchesInString:(NSString *)aString options:(int)options
{
	return [self allMatchesInString:aString options:0 range:NSMakeRange(0, [aString length])];
}

- (NSArray *)allMatchesInString:(NSString *)aString range:(NSRange)aRange
{
	return [self allMatchesInString:aString options:0 range:aRange];
}

- (NSArray *)allMatchesInString:(NSString *)aString range:(NSRange)aRange start:(NSUInteger)aLocation
{
	return [self allMatchesInString:aString range:aRange];
}

- (NSArray *)allMatchesInString:(NSString *)aString
{
	return [self allMatchesInString:aString options:0 range:NSMakeRange(0, [aString length])];
}

@end

@implementation ViRegexpMatch

@synthesize startLocation;

+ (ViRegexpMatch *)regexpMatchWithRegion:(OnigRegion *)aRegion startLocation:(NSUInteger)aLocation
{
	return [[ViRegexpMatch alloc] initWithRegion:aRegion startLocation:aLocation];
}

- (ViRegexpMatch *)initWithRegion:(OnigRegion *)aRegion startLocation:(NSUInteger)aLocation
{
	self = [super init];
	startLocation = aLocation;
	region = aRegion;
	return self;
}

- (NSRange)rangeOfMatchedString
{
	return [self rangeOfSubstringAtIndex:0];
}

- (NSRange)rangeOfSubstringAtIndex:(NSUInteger)idx
{
	if ((idx >= region->num_regs) || (region->beg[idx] == -1))
		return NSMakeRange(NSNotFound, 0);

	return NSMakeRange(startLocation + (region->beg[idx] / sizeof(unichar)), (region->end[idx] - region->beg[idx]) / sizeof(unichar));
}

- (NSUInteger)count
{
	return region->num_regs;
}

- (void)finalize
{
	if (region)
		onig_region_free(region, 1);

	[super finalize];
}

@end

