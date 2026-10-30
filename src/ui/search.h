#import <Cocoa/Cocoa.h>
#import "../core/appDetail.hpp"
#import "../core/searchEngine.hpp"
#import "../core/searchFile.hpp"

/*
 *
 * UI element for searching
 * - search box (always keeps the keyboard focus)
 * - results list (icon, name, path)
 * - owns the SearchEngine
 *
 * Keys: ↑/↓ move selection, Enter launches, Esc clears / closes
 *
 * File mode (enter it typing '/' in the empty box; the '/' disappears and a
 * "FileMode" badge is shown): the box takes a clean path ("~/bin/", "/usr/",
 * "Desktop" = relative to home) and lists its files.
 * Tab completes the selected entry, Enter reveals the file in Finder,
 * Backspace / Esc on the empty box go back to the app search.
 * 
 */

@interface SearchController : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>

  // the input box where the user types the application name
  @property (nonatomic, strong, readonly) NSTextField *searchField;

  // scrollable results list (the owner positions it)
  @property (nonatomic, strong, readonly) NSScrollView *resultsView;

  // "FileMode" badge, already placed next to the search box (the owner adds it)
  @property (nonatomic, strong, readonly) NSView *modeBadge;

  // called every time the results change (count = number of rows)
  @property (nonatomic, copy) void (^onResultsChanged)(NSUInteger count);

  // called right before an app is launched (e.g. to hide the launcher)
  @property (nonatomic, copy) void (^onWillLaunch)(void);

  // called when the launch completed (success = NO if it failed)
  @property (nonatomic, copy) void (^onDidLaunch)(BOOL success);

  // called when the user asks to close the launcher (Esc on empty box)
  @property (nonatomic, copy) void (^onDismiss)(void);

  // height of a single result row
  + (CGFloat) rowHeight;

  - (instancetype) initWithFrame: (NSRect) frame;

  // gives keyboard focus to the search box (window must be key)
  - (void) focusInWindow: (NSWindow *) window;

  // builds the application index, then refreshes the current query
  - (void) indexApplications;

  // empties the search box and the results
  - (void) reset;

@end
