#import "VCHotkeyManager.h"
#import <Carbon/Carbon.h>

@interface VCHotkeyManager () {
    EventHotKeyRef _hotkeyRefs[3];
    EventHandlerRef _handlerRef;
}
@end

static OSStatus VCHotkeyEventHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotkeyID;
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                      NULL, sizeof(hotkeyID), NULL, &hotkeyID);
    VCHotkeyManager *manager = (__bridge VCHotkeyManager *)userData;
    UInt32 identifier = hotkeyID.id;
    dispatch_async(dispatch_get_main_queue(), ^{
        [manager.delegate hotkeyPressed:(VCHotkey)identifier];
    });
    return noErr;
}

@implementation VCHotkeyManager

- (void)registerHotkeys {
    EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallEventHandler(GetApplicationEventTarget(), VCHotkeyEventHandler, 1, &spec,
                        (__bridge void *)self, &_handlerRef);
    [self registerKeyCode:kVK_Space hotkey:VCHotkeyAnalyze slot:0];
    [self registerKeyCode:kVK_ANSI_D hotkey:VCHotkeyDrawAsk slot:1];
    [self registerKeyCode:kVK_ANSI_H hotkey:VCHotkeyHide slot:2];
}

- (void)registerKeyCode:(UInt32)keyCode hotkey:(VCHotkey)hotkey slot:(int)slot {
    EventHotKeyID hotkeyID = { .signature = 'VCAG', .id = (UInt32)hotkey };
    RegisterEventHotKey(keyCode, controlKey + optionKey, hotkeyID,
                        GetApplicationEventTarget(), 0, &_hotkeyRefs[slot]);
}

- (void)dealloc {
    for (int i = 0; i < 3; i++) {
        if (_hotkeyRefs[i]) UnregisterEventHotKey(_hotkeyRefs[i]);
    }
    if (_handlerRef) RemoveEventHandler(_handlerRef);
}

@end
