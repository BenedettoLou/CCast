#include <Cocoa/Cocoa.h>
#include "window.h"

// layout constants
static const CGFloat kPadding      = 20.0;  // space around the search box
static const CGFloat kFieldHeight  = 36.0;  // search box height
static const CGFloat kResultsGap   = 8.0;   // space between search box and results
static const CGFloat kResultsInset = 8.0;   // left/right/bottom margin of the results
static const CGFloat kAnimTime     = 0.15;  // resize animation duration (seconds)

@implementation LauncherWindow {
  CGFloat _maxHeight;   // height when fully expanded
  BOOL _launching;      // an app is being opened (window already hidden)
  BOOL _dismissing;     // guards against re-entrant dismiss
}

  -  (instancetype) initWithWidth : (CGFloat) width height: (CGFloat)height {
    // start compact: only the search box is visible
    const CGFloat compact = [LauncherWindow compactHeight];
    NSRect frame = NSMakeRect(0,0, width, compact);

    // call to superclass
    self = [super initWithContentRect:frame
		  styleMask:NSWindowStyleMaskBorderless
		  backing: NSBackingStoreBuffered
		  defer:NO
		  ];

    if (self) {
        _maxHeight = MAX(height, compact);

        [self setOpaque:NO];
        [self setBackgroundColor:[NSColor clearColor]];
        [self setHasShadow:YES];
        [self setLevel:NSFloatingWindowLevel];
        [self setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [self positionOnScreen];

	NSView *contentView = [[NSView alloc] initWithFrame:frame];

	contentView.wantsLayer = YES;
	contentView.layer.backgroundColor = [
	  [ NSColor colorWithCalibratedWhite:0.15 alpha:0.95] CGColor];
	contentView.layer.cornerRadius = 16.0;
	contentView.layer.masksToBounds = YES;

	[self setContentView:contentView];

	// search box pinned to the top of the window
	// (autoresizing keeps it at the top when the window grows downward)
	NSRect fieldFrame = NSMakeRect(kPadding,
				       compact - kPadding - kFieldHeight,
				       width - 2 * kPadding,
				       kFieldHeight);

	_search = [[SearchController alloc] initWithFrame:fieldFrame];
	[contentView addSubview:_search.searchField];
	[contentView addSubview:_search.modeBadge];

	// results list, also pinned to the top, right below the search box
	_search.resultsView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
	[contentView addSubview:_search.resultsView];

	// grow / shrink following the number of results
	__weak LauncherWindow *weakSelf = self;
	_search.onResultsChanged = ^(NSUInteger count) {
	  LauncherWindow *strongSelf = weakSelf;
	  if (!strongSelf) return;
	  if (count == 0) [strongSelf collapse];
	  else [strongSelf setResultsHeight:count * [SearchController rowHeight]];
	};

	// hide immediately when an app is being launched
	_search.onWillLaunch = ^{
	  LauncherWindow *strongSelf = weakSelf;
	  if (!strongSelf) return;
	  strongSelf->_launching = YES;
	  [strongSelf orderOut:nil];
	};

	// launched: back to the initial state, the launched app has the focus.
	// failed: show the launcher again
	_search.onDidLaunch = ^(BOOL success) {
	  LauncherWindow *strongSelf = weakSelf;
	  if (!strongSelf) return;
	  strongSelf->_launching = NO;
	  if (success) [strongSelf dismissRestoringFocus:NO];
	  else [strongSelf show];
	};

	// Esc on empty box
	_search.onDismiss = ^{
	  [weakSelf dismiss];
	};

	// the field is the first thing to receive keystrokes
	[self setInitialFirstResponder:_search.searchField];
    }
    
    // returning the NSWindow obj
    return self;
  }

+ (CGFloat) compactHeight {
  return kFieldHeight + 2 * kPadding;
}

// space taken by the window chrome above and below the results list
+ (CGFloat) chromeHeightWithResults {
  return kPadding + kFieldHeight + kResultsGap + kResultsInset;
}

+ (CGFloat) heightForVisibleRows: (NSUInteger) rows {
  return [self chromeHeightWithResults] + rows * [SearchController rowHeight];
}

// centered horizontally, top edge at ~2/3 of the screen (Spotlight-like),
// so the window has room to expand downward
- (void) positionOnScreen {
  NSScreen *screen = [NSScreen mainScreen];
  if (!screen) { [self center]; return; }

  NSRect visible = screen.visibleFrame;
  NSRect frame = self.frame;
  CGFloat top = NSMinY(visible) + NSHeight(visible) * 2.0 / 3.0;

  frame.origin.x = NSMidX(visible) - NSWidth(frame) / 2.0;
  frame.origin.y = top - NSHeight(frame);
  [self setFrame:frame display:NO];
}

- (void) setResultsHeight: (CGFloat) resultsHeight {
  const CGFloat chrome = [LauncherWindow chromeHeightWithResults];
  CGFloat target = chrome + MAX(resultsHeight, 0.0);
  target = MIN(target, _maxHeight);

  // place the list in the CURRENT content coordinates, pinned below the box:
  // the window then grows/shrinks around it while it stays still
  const CGFloat listHeight = target - chrome;
  const CGFloat currentHeight = NSHeight(self.contentView.bounds);
  const CGFloat listTop = currentHeight - kPadding - kFieldHeight - kResultsGap;
  _search.resultsView.frame = NSMakeRect(kResultsInset,
					 listTop - listHeight,
					 NSWidth(self.contentView.bounds) - 2 * kResultsInset,
					 listHeight);

  [self resizeToHeight:target];
}

- (void) collapse {
  [self resizeToHeight:[LauncherWindow compactHeight]];
}

- (void) resizeToHeight: (CGFloat) target {
  NSRect frame = self.frame;
  if (NSHeight(frame) == target) return;

  // keep the top edge fixed: grow / shrink downward
  CGFloat top = NSMaxY(frame);
  frame.size.height = target;
  frame.origin.y = top - target;

  if (self.isVisible) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
      ctx.duration = kAnimTime;
      [[self animator] setFrame:frame display:YES];
    }];
  } else {
    [self setFrame:frame display:NO];
  }
}

- (BOOL) canBecomeMainWindow {
  return YES;
}

- (BOOL) canBecomeKeyWindow{
  return YES;
}

- (void) show {
  // the launcher appears on the screen currently in use
  [self positionOnScreen];

  [NSApp activateIgnoringOtherApps:YES];
  [self makeKeyAndOrderFront:nil];
  [_search focusInWindow:self];
}

- (void) dismiss {
  [self dismissRestoringFocus:YES];
}

- (void) dismissRestoringFocus: (BOOL) restoreFocus {
  if (_dismissing) return;
  _dismissing = YES;

  [self orderOut:nil];
  [_search reset];   // empty box + collapse, ready for the next show

  // give the focus back to the app that was in front before
  if (restoreFocus) [NSApp hide:nil];

  _dismissing = NO;
}

// clicking on another app / window hides the launcher (Spotlight-like)
- (void) resignKeyWindow {
  [super resignKeyWindow];
  if (!_launching && self.isVisible) [self dismiss];
}



@end
