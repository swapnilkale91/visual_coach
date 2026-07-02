#import <Foundation/Foundation.h>

@class VCOverlayController;

/// MCP (Model Context Protocol) server hosted inside the menu-bar app.
///
/// Listens on a local Unix socket for newline-delimited JSON-RPC. The Claude
/// desktop app connects through the `--mcp-relay` stdio shim, so tools called
/// from an existing Claude conversation run here — capture the screen, wait
/// for a Draw & Ask mark, and render guidance on the overlay — while the
/// conversation (and its context) stays in the Claude app.
///
/// Screen Recording permission remains attributed to Visual Coach itself:
/// the relay launches the app via LaunchServices rather than hosting capture.
@interface VCMCPServer : NSObject
+ (NSString *)socketPath;
- (instancetype)initWithOverlay:(VCOverlayController *)overlay;
- (BOOL)start;
@end
