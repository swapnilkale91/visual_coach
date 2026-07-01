#import "VCConversationStore.h"

static NSString * const kVCConversationDefaultsKey = @"VCClaudeConversations";
// Six exchanges (12 messages), matching the coaching-memory cap.
static const NSUInteger kVCConversationMaxMessages = 12;

@implementation VCConversationStore

+ (instancetype)shared {
    static VCConversationStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[VCConversationStore alloc] init]; });
    return shared;
}

- (NSArray<NSDictionary *> *)messagesForContextKey:(NSString *)key {
    if (key.length == 0) return @[];
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVCConversationDefaultsKey];
    NSArray *messages = all[key];
    return [messages isKindOfClass:[NSArray class]] ? messages : @[];
}

- (void)appendUserText:(NSString *)userText
         assistantText:(NSString *)assistantText
         forContextKey:(NSString *)key {
    if (key.length == 0 || userText.length == 0 || assistantText.length == 0) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all = [([defaults dictionaryForKey:kVCConversationDefaultsKey] ?: @{}) mutableCopy];
    NSMutableArray *messages = [[self messagesForContextKey:key] mutableCopy];

    [messages addObject:@{@"role": @"user", @"content": userText}];
    [messages addObject:@{@"role": @"assistant", @"content": assistantText}];
    // Trim in pairs so the history keeps alternating and starts with "user".
    while (messages.count > kVCConversationMaxMessages) {
        [messages removeObjectAtIndex:0];
        [messages removeObjectAtIndex:0];
    }
    all[key] = messages;
    [defaults setObject:all forKey:kVCConversationDefaultsKey];
}

- (void)clearAll {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVCConversationDefaultsKey];
}

@end
