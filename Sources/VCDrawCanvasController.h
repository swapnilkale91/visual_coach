#import <Cocoa/Cocoa.h>

typedef void (^VCDrawCompletion)(BOOL submitted, CGRect normalizedRegion, BOOL hasRegion);

/// Full-screen interactive Draw & Ask canvas. The user circles, underlines, or
/// marks a region; Return / "Ask About Mark" continues, Escape / Cancel exits.
/// The normalized bounds of the mark (top-left origin) are handed back —
/// the clean screenshot must be captured before this canvas appears.
@interface VCDrawCanvasController : NSObject
- (void)beginOnScreen:(NSScreen *)screen completion:(VCDrawCompletion)completion;
@end
