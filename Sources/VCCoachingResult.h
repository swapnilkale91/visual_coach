#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "VCOCRService.h"

/// One visual annotation. Coordinates are normalized (0–1), top-left origin.
@interface VCAnnotation : NSObject
@property (nonatomic, copy) NSString *type; // arrow | ring | highlight | label
@property (nonatomic, copy) NSString *label;
@property (nonatomic) CGPoint target;
@property (nonatomic) CGSize size;
@property (nonatomic) BOOL verified; // OCR confirmed the label text on screen
@end

@interface VCCoachingResult : NSObject
@property (nonatomic, copy) NSString *context;
@property (nonatomic, copy) NSString *inferredGoal;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSArray<VCAnnotation *> *annotations;

/// Parses the assistant message content (a JSON string, possibly fenced).
/// Returns nil if no usable JSON object is found. Invalid coordinates are discarded.
+ (instancetype)resultFromModelContent:(NSString *)content;

/// Grounds annotations against OCR: when a label matches visible text, OCR
/// coordinates replace the model's. Text-based annotations that OCR cannot
/// verify are dropped.
- (void)groundWithOCRLines:(NSArray<VCOCRLine *> *)lines;
@end
