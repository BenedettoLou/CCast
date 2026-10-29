#import <Cocoa/Cocoa.h> 
#import <Carbon/Carbon.h>   // kVK_Space, optionKey
#import "ui/window.h"
#import "ui/hotkey.h"

/*
 *
 * APP DELEGATE
 * shows the window only once the app has finished launching,
 * so activation + keyboard focus are reliable.
 * CCast then stays resident: Opt+Space shows / hides the launcher.
 *
 */
@interface AppDelegate : NSObject <NSApplicationDelegate>
  @property (nonatomic, strong) LauncherWindow *window;
  @property (nonatomic, strong) GlobalHotKey *hotKey;
@end

@implementation AppDelegate

  - (void) applicationDidFinishLaunching: (NSNotification *) notification {
    (void)notification;
    // expands up to 8 visible results, then the list scrolls
    self.window = [[LauncherWindow alloc] initWithWidth:600
                                                 height:[LauncherWindow heightForVisibleRows:8]];

    // global hotkey: Opt+Space
    __weak AppDelegate *weakSelf = self;
    self.hotKey = [[GlobalHotKey alloc] initWithKeyCode:kVK_Space
                                              modifiers:optionKey
                                                handler:^{ [weakSelf toggleLauncher]; }];
    if (!self.hotKey) {
      NSLog(@"CCast: Opt+Space is not available, the launcher can't be recalled");
    }

    [self showLauncher];
  }

  - (void) showLauncher {
    [self.window show];

    // (re)index on the next run loop turn: the window appears immediately,
    // keystrokes typed meanwhile are queued and searched right after.
    // Re-indexing at every show picks up newly installed apps (takes a few ms).
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.window.search indexApplications];
    });
  }

  - (void) toggleLauncher {
    if (self.window.isVisible && self.window.isKeyWindow) {
      [self.window dismiss];
    } else {
      [self showLauncher];
    }
  }

  // the window is only hidden, never closed: keep running in background
  - (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *) sender {
    (void)sender;
    return NO;
  }

@end

/*
 * Minimal main menu: without an Edit menu, Cmd+C/V/X/A/Z
 * would not work inside the search box. Cmd+Q quits.
 */
static void setupMainMenu(void) {
  NSMenu *mainMenu = [[NSMenu alloc] init];

  NSMenuItem *appItem = [[NSMenuItem alloc] init];
  NSMenu *appMenu = [[NSMenu alloc] init];
  [appMenu addItemWithTitle:@"Quit CCast" action:@selector(terminate:) keyEquivalent:@"q"];
  appItem.submenu = appMenu;
  [mainMenu addItem:appItem];

  NSMenuItem *editItem = [[NSMenuItem alloc] init];
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  editItem.submenu = editMenu;
  [mainMenu addItem:editItem];

  [NSApp setMainMenu:mainMenu];
}

/*
 *
 * ENTRY POINT
 * 
 */
int main(int argc, const char * argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
      NSApplication *app = [NSApplication sharedApplication];
      // background utility: no Dock icon, no menu bar
      // (Cmd+Q still quits while the launcher is visible)
      [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

      AppDelegate *delegate = [[AppDelegate alloc] init];
      [app setDelegate:delegate];
      setupMainMenu();

      [app run];
    }
    return 0;
}
