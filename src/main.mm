#import <Cocoa/Cocoa.h> 
#import "ui/window.h"
/*
 *
 * ENTRY POINT
 * 
 */
int main(int argc, const char * argv[]) {
    @autoreleasepool {
      NSApplication *app = [NSApplication sharedApplication];
      [app setActivationPolicy:NSApplicationActivationPolicyRegular];

      LauncherWindow *w = [[LauncherWindow alloc] initWithWidth:600 height:350];

      [w makeKeyAndOrderFront:nil];
      [app activateIgnoringOtherApps:YES];

      [app run];
    }
    return 0;
}
