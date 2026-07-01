#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, VCHotkey) {
    VCHotkeyAnalyze = 1, // Control-Option-Space
    VCHotkeyDrawAsk = 2, // Control-Option-D
    VCHotkeyHide    = 3, // Control-Option-H
};

@protocol VCHotkeyManagerDelegate <NSObject>
- (void)hotkeyPressed:(VCHotkey)hotkey;
@end

@interface VCHotkeyManager : NSObject
@property (nonatomic, weak) id<VCHotkeyManagerDelegate> delegate;
- (void)registerHotkeys;
@end
