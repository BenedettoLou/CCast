#import "search.h"
#import "resultViews.h"

#include <string>
#include <vector>

static const CGFloat    kRowHeight  = 44.0;
static const std::size_t kMaxResults = 20;

@implementation SearchController {
  SearchEngine _engine;
  std::vector<AppDetail> _results;
  NSTableView *_tableView;
  NSCache<NSString *, NSImage *> *_iconCache;
}

  + (CGFloat) rowHeight {
    return kRowHeight;
  }

  - (instancetype) initWithFrame: (NSRect) frame {
    self = [super init];

    if (self) {
      _iconCache = [[NSCache alloc] init];
      [self setupSearchField:frame];
      [self setupResultsView:frame.size.width];

      // localized names from Finder ("Calcolatrice" instead of "Calculator")
      _engine.setNameResolver([](const std::string &path) -> std::string {
        @autoreleasepool {
          NSString *p = [NSString stringWithUTF8String:path.c_str()];
          NSString *name = [[NSFileManager defaultManager] displayNameAtPath:p];
          if ([name.pathExtension isEqualToString:@"app"]) {
            name = name.stringByDeletingPathExtension;
          }
          name = name.precomposedStringWithCanonicalMapping;
          return name ? std::string(name.UTF8String) : std::string();
        }
      });
    }

    return self;
  }

  - (void) setupSearchField: (NSRect) frame {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];

    // plain look: no border, no background, drawn over the window's dark layer
    field.bordered = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.editable = YES;
    field.selectable = YES;

    field.font = [NSFont systemFontOfSize:26 weight:NSFontWeightLight];
    field.textColor = [NSColor whiteColor];
    field.cell.usesSingleLineMode = YES;
    field.cell.wraps = NO;
    field.cell.scrollable = YES;

    field.placeholderAttributedString = [[NSAttributedString alloc]
      initWithString:@"Search applications..."
      attributes:@{
        NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:1.0 alpha:0.35],
        NSFontAttributeName : field.font
      }];

    field.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    field.delegate = self;

    _searchField = field;
  }

  - (void) setupResultsView: (CGFloat) width {
    NSRect frame = NSMakeRect(0, 0, width, kRowHeight);

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"app"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    column.width = width;

    NSTableView *table = [[NSTableView alloc] initWithFrame:frame];
    [table addTableColumn:column];
    table.headerView = nil;
    table.style = NSTableViewStylePlain;
    table.rowHeight = kRowHeight;
    table.intercellSpacing = NSMakeSize(0, 0);
    table.backgroundColor = [NSColor clearColor];
    table.gridStyleMask = NSTableViewGridNone;
    table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    table.focusRingType = NSFocusRingTypeNone;
    table.refusesFirstResponder = YES;    // keyboard focus stays in the search box
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.action = @selector(rowClicked:);  // single click launches

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.scrollerStyle = NSScrollerStyleOverlay;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hidden = YES;

    _tableView = table;
    _resultsView = scroll;
  }

  - (void) focusInWindow: (NSWindow *) window {
    [window makeFirstResponder:_searchField];
  }

  - (void) indexApplications {
    _engine.indexApplications();
    [self updateResults];
  }

  #pragma mark - Search

  - (void) updateResults {
    const char *text = _searchField.stringValue.UTF8String;
    _results = _engine.query(text ? text : "", kMaxResults);

    [_tableView reloadData];
    if (!_results.empty()) {
      [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
      [_tableView scrollRowToVisible:0];
    }

    _resultsView.hidden = _results.empty();
    if (self.onResultsChanged) self.onResultsChanged(_results.size());
  }

  - (void) moveSelectionBy: (NSInteger) delta {
    const NSInteger count = static_cast<NSInteger>(_results.size());
    if (count == 0) return;

    NSInteger row = _tableView.selectedRow + delta;
    row = ((row % count) + count) % count;   // wrap around

    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_tableView scrollRowToVisible:row];
  }

  #pragma mark - Launch

  - (void) rowClicked: (id) sender {
    (void)sender;
    [self launchRow:_tableView.clickedRow];
  }

  - (void) launchRow: (NSInteger) row {
    if (row < 0 || row >= static_cast<NSInteger>(_results.size())) {
      NSBeep();
      return;
    }

    NSString *path = [NSString stringWithUTF8String:_results[row].path.c_str()];
    NSURL *url = [NSURL fileURLWithPath:path];

    NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
    config.activates = YES;

    if (self.onWillLaunch) self.onWillLaunch();

    [[NSWorkspace sharedWorkspace] openApplicationAtURL:url
      configuration:config
      completionHandler:^(NSRunningApplication *app, NSError *error) {
        (void)app;
        dispatch_async(dispatch_get_main_queue(), ^{
          if (error) {
            NSLog(@"CCast: unable to launch %@: %@", path, error.localizedDescription);
            NSBeep();
          }
          // launcher job done (or failed: the owner shows the window again)
          if (self.onDidLaunch) self.onDidLaunch(error == nil);
        });
      }];
  }

  - (void) reset {
    _searchField.stringValue = @"";
    [self updateResults];
  }

  #pragma mark - NSTextFieldDelegate

  // called on every keystroke inside the box
  - (void) controlTextDidChange: (NSNotification *) notification {
    (void)notification;
    [self updateResults];
  }

  // special keys while editing (arrows / Esc / Enter)
  - (BOOL) control: (NSControl *) control
           textView: (NSTextView *) textView
           doCommandBySelector: (SEL) commandSelector {
    (void)control; (void)textView;

    if (commandSelector == @selector(moveDown:)) {
      [self moveSelectionBy:1];
      return YES;
    }

    if (commandSelector == @selector(moveUp:)) {
      [self moveSelectionBy:-1];
      return YES;
    }

    if (commandSelector == @selector(cancelOperation:)) {
      // Esc: clear the box, or close the launcher if already empty
      if (_searchField.stringValue.length > 0) {
        [self reset];
      } else if (self.onDismiss) {
        self.onDismiss();
      }
      return YES;
    }

    if (commandSelector == @selector(insertNewline:)) {
      [self launchRow:_tableView.selectedRow];
      return YES;
    }

    return NO;
  }

  #pragma mark - NSTableViewDataSource / Delegate

  - (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
    (void)tableView;
    return static_cast<NSInteger>(_results.size());
  }

  - (NSTableRowView *) tableView: (NSTableView *) tableView rowViewForRow: (NSInteger) row {
    (void)tableView; (void)row;
    return [[ResultRowView alloc] init];
  }

  - (NSView *) tableView: (NSTableView *) tableView
           viewForTableColumn: (NSTableColumn *) tableColumn
                          row: (NSInteger) row {
    ResultCellView *cell = [tableView makeViewWithIdentifier:[ResultCellView reuseIdentifier]
                                                       owner:self];
    if (!cell) {
      cell = [[ResultCellView alloc] initWithFrame:
        NSMakeRect(0, 0, tableColumn.width, kRowHeight)];
    }

    const AppDetail &app = _results[row];
    NSString *path = [NSString stringWithUTF8String:app.path.c_str()];

    cell.nameLabel.stringValue = [NSString stringWithUTF8String:app.name.c_str()] ?: @"";
    cell.pathLabel.stringValue = path.stringByAbbreviatingWithTildeInPath ?: @"";
    cell.iconView.image = [self iconForPath:path];

    return cell;
  }

  - (NSImage *) iconForPath: (NSString *) path {
    NSImage *icon = [_iconCache objectForKey:path];
    if (!icon) {
      icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
      [_iconCache setObject:icon forKey:path];
    }
    return icon;
  }

@end
