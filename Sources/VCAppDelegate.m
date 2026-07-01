#import "VCAppDelegate.h"
#import "VCHotkeyManager.h"
#import "VCCoachEngine.h"

@interface VCAppDelegate () <VCHotkeyManagerDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) VCHotkeyManager *hotkeys;
@property (nonatomic, strong) VCCoachEngine *engine;
@property (nonatomic, strong) NSMenuItem *claudeToggleItem;
@end

@implementation VCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.engine = [[VCCoachEngine alloc] init];
    self.hotkeys = [[VCHotkeyManager alloc] init];
    self.hotkeys.delegate = self;
    [self.hotkeys registerHotkeys];
    [self setUpStatusItem];
}

- (void)setUpStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"sparkles"
                                             accessibilityDescription:@"Visual Coach"];

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *analyze = [menu addItemWithTitle:@"Analyze Screen  (⌃⌥Space)"
                                          action:@selector(analyzeScreen:)
                                   keyEquivalent:@""];
    NSMenuItem *draw = [menu addItemWithTitle:@"Draw && Ask  (⌃⌥D)"
                                       action:@selector(drawAndAsk:)
                                keyEquivalent:@""];
    NSMenuItem *hide = [menu addItemWithTitle:@"Hide Guidance  (⌃⌥H)"
                                       action:@selector(hideGuidance:)
                                keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *ask = [menu addItemWithTitle:@"Ask a Question…"
                                      action:@selector(askQuestion:)
                               keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *claude = [menu addItemWithTitle:@"Use Claude (Cloud)"
                                         action:@selector(toggleClaude:)
                                  keyEquivalent:@""];
    claude.state = self.engine.claudeBackendEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.claudeToggleItem = claude;
    NSMenuItem *apiKey = [menu addItemWithTitle:@"Set Claude API Key…"
                                         action:@selector(setClaudeAPIKey:)
                                  keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clear = [menu addItemWithTitle:@"Clear Learned Context"
                                        action:@selector(clearContext:)
                                 keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit Visual Coach" action:@selector(terminate:) keyEquivalent:@"q"];

    for (NSMenuItem *item in @[analyze, draw, hide, ask, claude, apiKey, clear]) {
        item.target = self;
    }
    self.statusItem.menu = menu;
}

#pragma mark - VCHotkeyManagerDelegate

- (void)hotkeyPressed:(VCHotkey)hotkey {
    switch (hotkey) {
        case VCHotkeyAnalyze:
            [self.engine analyzeAutomatically];
            break;
        case VCHotkeyDrawAsk:
            [self.engine startDrawAndAsk];
            break;
        case VCHotkeyHide:
            [self.engine hideGuidance];
            break;
    }
}

#pragma mark - Menu actions

- (void)analyzeScreen:(id)sender {
    [self.engine analyzeAutomatically];
}

- (void)drawAndAsk:(id)sender {
    [self.engine startDrawAndAsk];
}

- (void)hideGuidance:(id)sender {
    [self.engine hideGuidance];
}

- (void)askQuestion:(id)sender {
    [self.engine askQuestionFromMenu];
}

- (void)toggleClaude:(id)sender {
    BOOL enabled = [self.engine toggleClaudeBackend];
    self.claudeToggleItem.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)setClaudeAPIKey:(id)sender {
    [self.engine configureClaudeAPIKey];
}

- (void)clearContext:(id)sender {
    [self.engine clearLearnedContext];
}

@end
