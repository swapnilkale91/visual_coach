#import <Foundation/Foundation.h>

/// Lightweight per-window coaching memory, persisted in NSUserDefaults.
/// Keeps at most six entries per foreground window context.
@interface VCMemoryStore : NSObject
+ (instancetype)shared;
- (NSArray<NSDictionary *> *)entriesForContextKey:(NSString *)key;
- (void)addContext:(NSString *)context
              goal:(NSString *)goal
           message:(NSString *)message
     forContextKey:(NSString *)key;
- (void)clearAll;
@end
