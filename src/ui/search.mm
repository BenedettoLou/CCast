#import "search.h"
#import "resultViews.h"

#include <string>
#include <vector>

static const CGFloat    kRowHeight  = 44.0;
static const std::size_t kMaxResults = 20;

// "FileMode" badge, on the left of the search box
static const CGFloat kBadgeWidth  = 78.0;
static const CGFloat kBadgeHeight = 22.0;
static const CGFloat kBadgeGap    = 8.0;   // space between badge and text

@implementation SearchController {
  SearchEngine _engine;
  SearchFile _fileEngine;
  std::vector<AppDetail> _results;   // apps or files, depending on _fileMode
  BOOL _fileMode;                    // entered by typing '/' in the empty box
  NSRect _fieldFrame;                // search box frame in app mode
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
      _fieldFrame = frame;
      [self setupSearchField:frame];
      [self setupModeBadge:frame];
      [self setupResultsView:frame.size.width];

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

    field.placeholderAttributedString = [self placeholder:@"Search applications..."
                                                     font:field.font];

    field.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    field.delegate = self;

    _searchField = field;
  }

  - (NSAttributedString *) placeholder: (NSString *) text font: (NSFont *) font {
    return [[NSAttributedString alloc]
      initWithString:text
      attributes:@{
        NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:1.0 alpha:0.35],
        NSFontAttributeName : font
      }];
  }

  // small rounded "FileMode" label, hidden in app mode
  - (void) setupModeBadge: (NSRect) fieldFrame {
    NSRect frame = NSMakeRect(NSMinX(fieldFrame),
                              NSMidY(fieldFrame) - kBadgeHeight / 2.0,
                              kBadgeWidth, kBadgeHeight);

    NSView *badge = [[NSView alloc] initWithFrame:frame];
    badge.wantsLayer = YES;
    badge.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.85].CGColor;
    badge.layer.cornerRadius = kBadgeHeight / 2.0;
    badge.autoresizingMask = NSViewMinYMargin;   // stays at the top, like the box
    badge.hidden = YES;

    NSTextField *label = [NSTextField labelWithString:@"FileMode"];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    label.textColor = [NSColor whiteColor];
    label.alignment = NSTextAlignmentCenter;
    [label sizeToFit];
    label.frame = NSMakeRect(0, (kBadgeHeight - NSHeight(label.frame)) / 2.0,
                             kBadgeWidth, NSHeight(label.frame));
    [badge addSubview:label];

    _modeBadge = badge;
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

  // switches between app search and file browsing:
  // shows / hides the badge and makes room for it next to the text
  - (void) setFileMode: (BOOL) on {
    if (_fileMode == on) return;
    _fileMode = on;

    // only x / width change: the vertical position is kept as it is, because
    // the box follows the window when it grows / shrinks (autoresizing) and
    // the y saved at init time is only valid for the compact window
    const CGFloat shift = on ? kBadgeWidth + kBadgeGap : 0.0;
    NSRect frame = _searchField.frame;
    frame.origin.x = NSMinX(_fieldFrame) + shift;
    frame.size.width = NSWidth(_fieldFrame) - shift;
    _searchField.frame = frame;
    _modeBadge.hidden = !on;

    _searchField.placeholderAttributedString =
      [self placeholder:(on ? @"~/path/to/file" : @"Search applications...")
                   font:_searchField.font];

    // the field editor (cursor + typed text) does not follow the new frame:
    // restart the editing session so the box stays usable
    NSWindow *window = _searchField.window;
    if (window && _searchField.currentEditor) {
      [window makeFirstResponder:_searchField];
      [_searchField.currentEditor moveToEndOfLine:nil];
    }
  }

  - (void) updateResults {

    const char *text = _searchField.stringValue.UTF8String;

    if (_fileMode) {
      // find file: the box contains a clean path ("~/bin/", "/usr/", "Desktop")
      _results = _fileEngine.query(text ? text : "", kMaxResults);
    } else {
      // search
      _results = _engine.query(text ? text : "", kMaxResults);
    }

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
    if (_fileMode) [self revealRow:_tableView.clickedRow];
    else [self launchRow:_tableView.clickedRow];
  }

  #pragma mark - Files

  // Enter in file mode: the typed path wins if it exists ("complete" path),
  // otherwise the selected result is used
  - (void) revealTypedPathOrSelection {
    const char *text = _searchField.stringValue.UTF8String;

    // empty box: there is no typed path, use the selection
    const std::string path = (text && text[0]) ? SearchFile::expand(text) : std::string();

    if (!path.empty() && SearchFile::exists(path)) {
      [self revealPath:[NSString stringWithUTF8String:path.c_str()]];
    } else {
      [self revealRow:_tableView.selectedRow];
    }
  }

  - (void) revealRow: (NSInteger) row {
    if (row < 0 || row >= static_cast<NSInteger>(_results.size())) {
      NSBeep();
      return;
    }
    [self revealPath:[NSString stringWithUTF8String:_results[row].path.c_str()]];
  }

  // opens a Finder window with the file selected
  - (void) revealPath: (NSString *) path {
    NSURL *url = [NSURL fileURLWithPath:path.stringByStandardizingPath];

    if (self.onWillLaunch) self.onWillLaunch();
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
    if (self.onDidLaunch) self.onDidLaunch(YES);
  }

  // Tab in file mode: completes the box with the selected entry
  // (folders get a trailing '/', so their content is listed right away)
  - (void) completeSelection {
    const NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= static_cast<NSInteger>(_results.size())) {
      NSBeep();
      return;
    }

    std::string path = _results[row].path;
    if (SearchFile::isDirectory(path)) path += "/";

    // "/Users/me/bin/" is shown as "~/bin/"
    NSString *full = [NSString stringWithUTF8String:path.c_str()] ?: @"";
    _searchField.stringValue = full.stringByAbbreviatingWithTildeInPath;
    if ([full hasSuffix:@"/"] && ![_searchField.stringValue hasSuffix:@"/"]) {
      _searchField.stringValue = [_searchField.stringValue stringByAppendingString:@"/"];
    }
    [_searchField.currentEditor moveToEndOfLine:nil];   // cursor after the text
    [self updateResults];
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

  // back to the initial state: empty box, app mode
  - (void) reset {
    [self setFileMode:NO];
    _searchField.stringValue = @"";
    [self updateResults];
  }

  #pragma mark - NSTextFieldDelegate

  // called on every keystroke inside the box
  - (void) controlTextDidChange: (NSNotification *) notification {
    (void)notification;

    // '/' as first character: enter file mode, the '/' itself is consumed
    // so the box starts with a clean path ("~/bin/", "/usr/", ...).
    // A pasted absolute path ("/usr/bin") is kept as it is.
    if (!_fileMode && [_searchField.stringValue hasPrefix:@"/"]) {
      NSString *text = _searchField.stringValue;
      [self setFileMode:YES];
      _searchField.stringValue = (text.length == 1) ? @"" : text;
      [_searchField.currentEditor moveToEndOfLine:nil];
    }

    [self updateResults];
  }

  // special keys while editing (arrows / Esc / Enter / Tab / Backspace)
  - (BOOL) control: (NSControl *) control
           textView: (NSTextView *) textView
           doCommandBySelector: (SEL) commandSelector {
    (void)control; (void)textView;

    const BOOL empty = (_searchField.stringValue.length == 0);

    if (commandSelector == @selector(moveDown:)) {
      [self moveSelectionBy:1];
      return YES;
    }

    if (commandSelector == @selector(moveUp:)) {
      [self moveSelectionBy:-1];
      return YES;
    }

    // Backspace on the empty box leaves file mode
    if (commandSelector == @selector(deleteBackward:) && _fileMode && empty) {
      [self reset];
      return YES;
    }

    if (commandSelector == @selector(cancelOperation:)) {
      // Esc: clear the box, then leave file mode, then close the launcher
      if (!empty) {
        _searchField.stringValue = @"";
        [self updateResults];
      } else if (_fileMode) {
        [self reset];
      } else if (self.onDismiss) {
        self.onDismiss();
      }
      return YES;
    }

    if (commandSelector == @selector(insertNewline:)) {
      if (_fileMode) [self revealTypedPathOrSelection];
      else [self launchRow:_tableView.selectedRow];
      return YES;
    }

    if (commandSelector == @selector(insertTab:) && _fileMode) {
      [self completeSelection];
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
