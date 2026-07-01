#import "VCOCRService.h"
#import <Vision/Vision.h>

@implementation VCOCRLine
@end

@implementation VCOCRService

+ (void)recognizeTextInImage:(CGImageRef)image
                  completion:(void (^)(NSArray<VCOCRLine *> *, NSError *))completion {
    CGImageRetain(image);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
        NSError *error = nil;
        [handler performRequests:@[request] error:&error];
        CGImageRelease(image);

        NSMutableArray<VCOCRLine *> *lines = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *top = [observation topCandidates:1].firstObject;
            if (!top || top.confidence < 0.3) continue;

            VCOCRLine *line = [[VCOCRLine alloc] init];
            line.text = top.string;
            // Vision uses a bottom-left origin; flip to top-left.
            CGRect box = observation.boundingBox;
            line.bounds = CGRectMake(box.origin.x,
                                     1.0 - box.origin.y - box.size.height,
                                     box.size.width,
                                     box.size.height);
            [lines addObject:line];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(lines, error);
        });
    });
}

@end
