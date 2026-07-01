#import <Cocoa/Cocoa.h>

/// One captured screen plus foreground-app metadata.
@interface VCScreenSnapshot : NSObject
@property (nonatomic, readonly) CGImageRef image;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *windowTitle;
@property (nonatomic) CGDirectDisplayID displayID;

- (instancetype)initWithImage:(CGImageRef)image;
/// Key used to scope learned context; window titles keep unrelated browser tabs apart.
- (NSString *)contextKey;
/// PNG for the model, downscaled so the longest side is at most maxDimension pixels.
- (NSData *)pngDataWithMaxDimension:(CGFloat)maxDimension;
@end

@interface VCScreenCapture : NSObject
/// Captures the display currently under the mouse pointer with ScreenCaptureKit.
/// Completion runs on the main queue.
+ (void)captureDisplayUnderPointerWithCompletion:(void (^)(VCScreenSnapshot *snapshot, NSError *error))completion;
+ (NSScreen *)screenForDisplayID:(CGDirectDisplayID)displayID;
@end
