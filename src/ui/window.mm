#include <Cocoa/Cocoa.h>
#include "window.h"

@implementation LauncherWindow : NSWindow

  -  (instancetype) initWithWidth : (CGFloat) width height: (CGFloat)height {
    NSRect frame = NSMakeRect(0,0, width, height);

    // call to superclass
    self = [super initWithContentRect:frame
		  styleMask:NSWindowStyleMaskBorderless
		  backing: NSBackingStoreBuffered
		  defer:NO
		  ];

    if (self) {
        [self setOpaque:NO];
        [self setBackgroundColor:[NSColor clearColor]];
        [self setHasShadow:YES];
        [self setLevel:NSFloatingWindowLevel];
        [self center];

	NSView *contentView = [[NSView alloc] initWithFrame:frame];

	contentView.wantsLayer = YES;
	contentView.layer.backgroundColor = [
	  [ NSColor colorWithCalibratedWhite:0.15 alpha:0.95] CGColor];
	contentView.layer.cornerRadius = 16.0;

	[self setContentView:contentView];
    }
    
    // returning the NSWindow obj
    return self;
  }

- (BOOL) canBecomeMainWindow {
  return YES;
}

- (BOOL) canBecomeKeyWindow{
  return YES;
}



@end
