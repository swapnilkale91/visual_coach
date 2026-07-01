#import <Foundation/Foundation.h>

/// Optional cloud backend: the Claude API (api.anthropic.com).
/// Unlike the Ollama path, supports multi-turn conversation history so
/// coaching context persists across triggers for the same window.
@interface VCClaudeClient : NSObject

/// Keychain-stored key, falling back to the ANTHROPIC_API_KEY environment variable.
+ (NSString *)storedAPIKey;
+ (BOOL)saveAPIKey:(NSString *)key;

/// Sends a multimodal message with prior conversation turns.
/// `history` is an array of {"role": "user"|"assistant", "content": <text>} dicts,
/// alternating and starting with "user". Completion runs on the main queue with
/// the assistant's JSON text (schema-enforced via structured outputs).
+ (void)sendChatWithSystemPrompt:(NSString *)systemPrompt
                         history:(NSArray<NSDictionary *> *)history
                      userPrompt:(NSString *)userPrompt
                        imagePNG:(NSData *)imagePNG
                      completion:(void (^)(NSString *content, NSError *error))completion;
@end
