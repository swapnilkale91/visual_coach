#import <Foundation/Foundation.h>

@class VCOverlayController;

/// Orchestrates the capture → OCR → Ollama → overlay pipeline.
@interface VCCoachEngine : NSObject
/// Shared with the MCP server so chat-driven guidance uses the same overlay.
@property (nonatomic, strong, readonly) VCOverlayController *overlay;
- (void)analyzeAutomatically;   // Control-Option-Space
- (void)startDrawAndAsk;        // Control-Option-D
- (void)hideGuidance;           // Control-Option-H
- (void)askQuestionFromMenu;    // menu-bar prompt
- (void)clearLearnedContext;

/// Claude backend (optional cloud mode with persistent conversation context).
- (BOOL)claudeBackendEnabled;
- (BOOL)toggleClaudeBackend;    // returns the new state
- (void)configureClaudeAPIKey;
@end
