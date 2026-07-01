#import <Foundation/Foundation.h>

@interface VCOllamaClient : NSObject
/// Sends a multimodal chat request to local Ollama with format:"json".
/// Completion runs on the main queue with the assistant message content string.
+ (void)sendChatWithSystemPrompt:(NSString *)systemPrompt
                      userPrompt:(NSString *)userPrompt
                        imagePNG:(NSData *)imagePNG
                      completion:(void (^)(NSString *content, NSError *error))completion;
@end
