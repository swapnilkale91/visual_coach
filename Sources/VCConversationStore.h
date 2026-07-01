#import <Foundation/Foundation.h>

/// Rolling per-window conversation history for the Claude backend, persisted
/// in NSUserDefaults. Stores alternating user/assistant text turns (images are
/// not replayed) so follow-up coaching on the same window keeps its context.
@interface VCConversationStore : NSObject
+ (instancetype)shared;
/// Messages ready for the API: {"role": ..., "content": <text>}, oldest first.
- (NSArray<NSDictionary *> *)messagesForContextKey:(NSString *)key;
- (void)appendUserText:(NSString *)userText
         assistantText:(NSString *)assistantText
         forContextKey:(NSString *)key;
- (void)clearAll;
@end
