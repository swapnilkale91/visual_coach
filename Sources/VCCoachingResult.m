#import "VCCoachingResult.h"

static NSString *VCStringOrNil(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static double VCDoubleOrNAN(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return [value doubleValue];
    return NAN;
}

@implementation VCAnnotation

+ (NSArray<VCAnnotation *> *)annotationsFromJSONArray:(id)array {
    if (![array isKindOfClass:[NSArray class]]) return @[];
    NSSet *knownTypes = [NSSet setWithObjects:@"arrow", @"ring", @"highlight", @"label", nil];
    NSMutableArray<VCAnnotation *> *result = [NSMutableArray array];

    for (id item in (NSArray *)array) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *dict = item;
        NSDictionary *target = [dict[@"target"] isKindOfClass:[NSDictionary class]] ? dict[@"target"] : nil;
        double x = VCDoubleOrNAN(target[@"x"]);
        double y = VCDoubleOrNAN(target[@"y"]);
        if (isnan(x) || isnan(y) || x < 0 || x > 1 || y < 0 || y > 1) continue;

        VCAnnotation *annotation = [[VCAnnotation alloc] init];
        NSString *type = VCStringOrNil(dict[@"type"]);
        annotation.type = [knownTypes containsObject:type] ? type : @"arrow";
        annotation.label = VCStringOrNil(dict[@"label"]);
        annotation.target = CGPointMake(x, y);

        NSDictionary *size = [dict[@"size"] isKindOfClass:[NSDictionary class]] ? dict[@"size"] : nil;
        double width = VCDoubleOrNAN(size[@"x"]);
        double height = VCDoubleOrNAN(size[@"y"]);
        annotation.size = CGSizeMake(
            (isnan(width) || width <= 0 || width > 1) ? 0.03 : width,
            (isnan(height) || height <= 0 || height > 1) ? 0.03 : height);

        [result addObject:annotation];
        if (result.count >= 6) break;
    }
    return result;
}

@end

@implementation VCCoachingResult

+ (instancetype)resultFromModelContent:(NSString *)content {
    if (content.length == 0) return nil;

    // The model is asked for bare JSON, but strip fences and stray prose defensively.
    NSRange start = [content rangeOfString:@"{"];
    NSRange end = [content rangeOfString:@"}" options:NSBackwardsSearch];
    if (start.location == NSNotFound || end.location == NSNotFound || end.location < start.location) {
        return nil;
    }
    NSString *jsonString = [content substringWithRange:
                            NSMakeRange(start.location, end.location - start.location + 1)];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0
                                                           error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;

    VCCoachingResult *result = [[VCCoachingResult alloc] init];
    result.context = VCStringOrNil(json[@"context"]);
    result.inferredGoal = VCStringOrNil(json[@"inferred_goal"]);
    result.message = VCStringOrNil(json[@"message"]);
    result.annotations = [VCAnnotation annotationsFromJSONArray:json[@"annotations"]];
    if (result.message.length == 0 && result.annotations.count == 0) return nil;
    return result;
}

- (void)groundWithOCRLines:(NSArray<VCOCRLine *> *)lines {
    NSMutableArray<VCAnnotation *> *kept = [NSMutableArray array];
    for (VCAnnotation *annotation in self.annotations) {
        if (annotation.label.length == 0) {
            [kept addObject:annotation];
            continue;
        }
        VCOCRLine *match = [self bestOCRMatchForLabel:annotation.label inLines:lines];
        if (match) {
            annotation.target = CGPointMake(CGRectGetMidX(match.bounds), CGRectGetMidY(match.bounds));
            annotation.size = match.bounds.size;
            annotation.verified = YES;
            [kept addObject:annotation];
        }
        // Unverified text-based annotations are not displayed.
    }
    self.annotations = kept;
}

- (VCOCRLine *)bestOCRMatchForLabel:(NSString *)label inLines:(NSArray<VCOCRLine *> *)lines {
    NSString *needle = [label.lowercaseString stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (needle.length < 3) return nil;

    // Exact matches beat partial ones, and partial matches are scored by how
    // much of the longer string they cover — so a short fragment ("order")
    // can no longer hijack a long label from a better line elsewhere.
    VCOCRLine *best = nil;
    double bestScore = 0;
    for (VCOCRLine *line in lines) {
        NSString *hay = [line.text.lowercaseString stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (hay.length < 4) continue;

        double score = 0;
        if ([hay isEqualToString:needle]) {
            score = 3.0;
        } else if ([needle containsString:hay]) {
            score = 1.0 + (double)hay.length / (double)needle.length;
        } else if ([hay containsString:needle]) {
            score = 1.0 + (double)needle.length / (double)hay.length;
        }
        if (score > bestScore) {
            bestScore = score;
            best = line;
        }
    }
    return best;
}

@end
