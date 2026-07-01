#import <Foundation/Foundation.h>

/// Orchestrates the capture → OCR → Ollama → overlay pipeline.
@interface VCCoachEngine : NSObject
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
