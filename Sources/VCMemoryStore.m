#import "VCMemoryStore.h"

static NSString * const kVCMemoryDefaultsKey = @"VCLearnedContext";
static const NSUInteger kVCMemoryMaxEntriesPerContext = 6;

@implementation VCMemoryStore

+ (instancetype)shared {
    static VCMemoryStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[VCMemoryStore alloc] init]; });
    return shared;
}

- (NSArray<NSDictionary *> *)entriesForContextKey:(NSString *)key {
    if (key.length == 0) return @[];
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVCMemoryDefaultsKey];
    NSArray *entries = all[key];
    return [entries isKindOfClass:[NSArray class]] ? entries : @[];
}

- (void)addContext:(NSString *)context
              goal:(NSString *)goal
           message:(NSString *)message
     forContextKey:(NSString *)key {
    if (key.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all = [([defaults dictionaryForKey:kVCMemoryDefaultsKey] ?: @{}) mutableCopy];
    NSMutableArray *entries = [[self entriesForContextKey:key] mutableCopy];

    [entries addObject:@{
        @"context": context ?: @"",
        @"goal": goal ?: @"",
        @"message": message ?: @"",
        @"timestamp": @([NSDate date].timeIntervalSince1970),
    }];
    while (entries.count > kVCMemoryMaxEntriesPerContext) {
        [entries removeObjectAtIndex:0];
    }
    all[key] = entries;
    [defaults setObject:all forKey:kVCMemoryDefaultsKey];
}

- (void)clearAll {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVCMemoryDefaultsKey];
}

@end
