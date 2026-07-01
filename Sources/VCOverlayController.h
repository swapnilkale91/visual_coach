#import <Cocoa/Cocoa.h>

@class VCCoachingResult;

/// Transparent, always-on-top, click-through guidance overlay.
/// Never controls or modifies the underlying application.
@interface VCOverlayController : NSObject
- (void)showProgress:(NSString *)text onScreen:(NSScreen *)screen;
- (void)showResult:(VCCoachingResult *)result onScreen:(NSScreen *)screen;
- (void)hide;
/// Hides only if nothing but a progress/error pill is showing.
- (void)hideIfShowingOnlyProgress;
@end
