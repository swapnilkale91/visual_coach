#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// One recognized text line. Bounds are normalized (0–1) with a top-left origin,
/// matching the coordinate space the model is asked to use.
@interface VCOCRLine : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) CGRect bounds;
@end

@interface VCOCRService : NSObject
/// Runs Vision OCR on a background queue; completion runs on the main queue.
+ (void)recognizeTextInImage:(CGImageRef)image
                  completion:(void (^)(NSArray<VCOCRLine *> *lines, NSError *error))completion;
@end
