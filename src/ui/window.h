#import <Cocoa/Cocoa.h>
#import "search.h"

@interface LauncherWindow : NSWindow 

  @property (nonatomic, strong, readonly) SearchController *search;

  // width: window width
  // height: MAX height when expanded (the window starts compact,
  //         showing only the search box)
  - (instancetype) initWithWidth: (CGFloat) width height: (CGFloat) height;

  // height of the window with only the search box visible
  + (CGFloat) compactHeight;

  // window height needed to show `rows` results without scrolling
  + (CGFloat) heightForVisibleRows: (NSUInteger) rows;

  // brings the window to front and puts the keyboard focus in the search box
  - (void) show;

  // hides the launcher, resets the search and gives the focus back
  // to the previously active app (the process keeps running)
  - (void) dismiss;

  // expands the window downward to show a results list of the given height
  // (clamped to the max height, the list scrolls beyond that)
  - (void) setResultsHeight: (CGFloat) resultsHeight;

  // back to compact size (no results)
  - (void) collapse;

@end
