#import <Cocoa/Cocoa.h>

/*
 *
 * System-wide hotkey (works while other apps are in front).
 * Based on Carbon RegisterEventHotKey: no Accessibility permission needed.
 *
 */
@interface GlobalHotKey : NSObject

  // keyCode: virtual key code (e.g. kVK_Space)
  // modifiers: Carbon modifier mask (e.g. optionKey, cmdKey | shiftKey)
  // returns nil if the combination can't be registered (e.g. already taken)
  - (instancetype) initWithKeyCode: (UInt32) keyCode
                         modifiers: (UInt32) modifiers
                           handler: (void (^)(void)) handler;

@end
