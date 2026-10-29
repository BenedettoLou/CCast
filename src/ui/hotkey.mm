#import "hotkey.h"
#import <Carbon/Carbon.h>

@interface GlobalHotKey ()
  @property (nonatomic, copy) void (^handler)(void);
@end

static OSStatus hotKeyEventHandler(EventHandlerCallRef next, EventRef event, void *userData) {
  (void)next; (void)event;
  GlobalHotKey *hotKey = (__bridge GlobalHotKey *)userData;
  if (hotKey.handler) hotKey.handler();
  return noErr;
}

@implementation GlobalHotKey {
  EventHotKeyRef _hotKeyRef;
  EventHandlerRef _handlerRef;
}

  - (instancetype) initWithKeyCode: (UInt32) keyCode
                         modifiers: (UInt32) modifiers
                           handler: (void (^)(void)) handler {
    self = [super init];
    if (!self) return nil;

    _handler = [handler copy];

    // each instance has its own event handler, filtered on its own hotkey ref
    EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
    OSStatus err = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler,
                                       1, &spec, (__bridge void *)self, &_handlerRef);
    if (err != noErr) {
      NSLog(@"CCast: InstallEventHandler failed (%d)", (int)err);
      return nil;
    }

    EventHotKeyID hotKeyID = { 'ccst', 1 };
    err = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                              GetApplicationEventTarget(), 0, &_hotKeyRef);
    if (err != noErr) {
      NSLog(@"CCast: unable to register hotkey (%d), already in use?", (int)err);
      RemoveEventHandler(_handlerRef);
      _handlerRef = NULL;
      return nil;
    }

    return self;
  }

  - (void) dealloc {
    if (_hotKeyRef) UnregisterEventHotKey(_hotKeyRef);
    if (_handlerRef) RemoveEventHandler(_handlerRef);
  }

@end
