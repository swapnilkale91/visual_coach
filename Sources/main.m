#import <Cocoa/Cocoa.h>
#import <string.h>
#import "VCAppDelegate.h"
#import "VCMCPRelay.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--mcp-relay") == 0) {
                // Spawned by an MCP client (e.g. the Claude desktop app):
                // act as a stdio shim to the running menu-bar app, no UI.
                return VCRunMCPRelay();
            }
        }

        NSApplication *app = [NSApplication sharedApplication];
        VCAppDelegate *delegate = [[VCAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
