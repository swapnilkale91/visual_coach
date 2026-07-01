#import "VCScreenCapture.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>

@implementation VCScreenSnapshot {
    CGImageRef _image;
}

- (instancetype)initWithImage:(CGImageRef)image {
    if ((self = [super init])) {
        _image = CGImageRetain(image);
    }
    return self;
}

- (CGImageRef)image {
    return _image;
}

- (void)dealloc {
    if (_image) CGImageRelease(_image);
}

- (NSString *)contextKey {
    NSString *app = self.bundleID.length ? self.bundleID : (self.appName ?: @"unknown");
    return [NSString stringWithFormat:@"%@|%@", app, self.windowTitle ?: @""];
}

- (NSData *)pngDataWithMaxDimension:(CGFloat)maxDimension {
    size_t width = CGImageGetWidth(_image);
    size_t height = CGImageGetHeight(_image);
    CGFloat scale = MIN(1.0, maxDimension / (CGFloat)MAX(width, height));
    CGImageRef toEncode = _image;
    CGContextRef context = NULL;

    if (scale < 1.0) {
        size_t targetWidth = (size_t)(width * scale);
        size_t targetHeight = (size_t)(height * scale);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        context = CGBitmapContextCreate(NULL, targetWidth, targetHeight, 8, 0, colorSpace,
                                        (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colorSpace);
        if (context) {
            CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
            CGContextDrawImage(context, CGRectMake(0, 0, targetWidth, targetHeight), _image);
            toEncode = CGBitmapContextCreateImage(context);
        }
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:toEncode];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (toEncode != _image) CGImageRelease(toEncode);
    if (context) CGContextRelease(context);
    return png;
}

@end

@implementation VCScreenCapture

+ (void)captureDisplayUnderPointerWithCompletion:(void (^)(VCScreenSnapshot *, NSError *))completion {
    // NSEvent.mouseLocation is bottom-left origin; CGGetDisplaysWithPoint wants top-left.
    NSPoint mouse = [NSEvent mouseLocation];
    CGFloat primaryHeight = CGDisplayBounds(CGMainDisplayID()).size.height;
    CGPoint cgPoint = CGPointMake(mouse.x, primaryHeight - mouse.y);

    CGDirectDisplayID displayID = CGMainDisplayID();
    uint32_t matchCount = 0;
    CGGetDisplaysWithPoint(cgPoint, 1, &displayID, &matchCount);
    if (matchCount == 0) displayID = CGMainDisplayID();

    NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
    NSString *windowTitle = [self frontWindowTitleForPID:front.processIdentifier];

    void (^fail)(NSError *) = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
    };

    [SCShareableContent getShareableContentExcludingDesktopWindows:YES
                                                onScreenWindowsOnly:YES
                                                  completionHandler:^(SCShareableContent *content, NSError *error) {
        if (!content) {
            fail(error);
            return;
        }
        SCDisplay *target = nil;
        for (SCDisplay *display in content.displays) {
            if (display.displayID == displayID) {
                target = display;
                break;
            }
        }
        if (!target) target = content.displays.firstObject;
        if (!target) {
            fail([NSError errorWithDomain:@"VisualCoach" code:10 userInfo:@{
                NSLocalizedDescriptionKey: @"No shareable display found. Check Screen Recording permission."
            }]);
            return;
        }

        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:target excludingWindows:@[]];
        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(target.displayID);
        config.width = mode ? CGDisplayModeGetPixelWidth(mode) : (size_t)target.width;
        config.height = mode ? CGDisplayModeGetPixelHeight(mode) : (size_t)target.height;
        if (mode) CGDisplayModeRelease(mode);
        config.showsCursor = NO;

        [SCScreenshotManager captureImageWithFilter:filter
                                      configuration:config
                                  completionHandler:^(CGImageRef image, NSError *captureError) {
            if (!image) {
                fail(captureError);
                return;
            }
            VCScreenSnapshot *snapshot = [[VCScreenSnapshot alloc] initWithImage:image];
            snapshot.appName = front.localizedName;
            snapshot.bundleID = front.bundleIdentifier;
            snapshot.windowTitle = windowTitle;
            snapshot.displayID = target.displayID;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(snapshot, nil); });
        }];
    }];
}

+ (NSString *)frontWindowTitleForPID:(pid_t)pid {
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!windowList) return nil;

    NSArray *windows = CFBridgingRelease(windowList);
    for (NSDictionary *info in windows) {
        if ([info[(__bridge NSString *)kCGWindowOwnerPID] intValue] != pid) continue;
        if ([info[(__bridge NSString *)kCGWindowLayer] intValue] != 0) continue;
        NSString *name = info[(__bridge NSString *)kCGWindowName];
        if (name.length) return name;
    }
    return nil;
}

+ (NSScreen *)screenForDisplayID:(CGDirectDisplayID)displayID {
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
        if (number.unsignedIntValue == displayID) return screen;
    }
    return nil;
}

@end
