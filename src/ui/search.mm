#import "search.h"
#import "resultViews.h"
#import "clipboardMonitor.h"

#include <string>
#include <vector>

static const CGFloat    kRowHeight  = 44.0;
static const std::size_t kMaxResults = 20;

// mode badge ("FileMode" / "Clipboard")
static const CGFloat kBadgeWidth  = 80.0;
static const CGFloat kBadgeHeight = 22.0;
static const CGFloat kBadgeGap    = 8.0;   // space between badge and text

// extra words that make an entry match by type ("image", "file")
static const char *const kImageSearchTerms = "image screenshot picture png";
static const char *const kFileSearchTerms  = "file";

@implementation SearchController {
  SearchApplication _searchApplication;
  SearchFile _fileEngine;
  SearchClipboard _clipboardEngine;
  std::vector<AppDetail> _results;                 // apps or files (APPMODE / FILEMODE)
  std::vector<ClipboardItem> _clipboardResults;    // clipboard entries (CLIPBOARD)
  SearchMode _mode;                  // current application mode (APPMODE by default)
  NSRect _fieldFrame;                // search box frame in app mode
  NSTextField *_modeBadgeLabel;
  NSTableView *_tableView;
  NSCache<NSString *, NSImage *> *_iconCache;
  ClipboardMonitor *_clipboardMonitor;
  NSMutableDictionary<NSString *, ClipboardCapture *> *_clipboardImages;   // image id -> data
  NSImage *_clipboardIcon;
}

  + (CGFloat) rowHeight {
    return kRowHeight;
  }

  - (instancetype) initWithFrame: (NSRect) frame {
    self = [super init];

    if (self) {
      _iconCache = [[NSCache alloc] init];
      _clipboardImages = [[NSMutableDictionary alloc] init];
      _fieldFrame = frame;
      _mode = APPMODE;
      [self setupSearchField:frame];
      [self setupModeBadge:frame];
      [self setupResultsView:frame.size.width];

      _searchApplication.setNameResolver([](const std::string &path) -> std::string {
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

      __weak SearchController *weakSelf = self;
      _clipboardMonitor = [[ClipboardMonitor alloc] initWithHandler:^(ClipboardCapture *capture) {
        SearchController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([strongSelf recordCapture:capture] && strongSelf->_mode == CLIPBOARD) {
          [strongSelf updateResults];
        }
      }];
      [_clipboardMonitor pollUserInitiated:NO];
      [_clipboardMonitor start];
    }

    return self;
  }

  - (void) setupSearchField: (NSRect) frame {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];

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

  // "FileMode" / "Clipboard" label, hidden in app mode
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

    _modeBadgeLabel = label;
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
    _searchApplication.indexApplications();
    [self updateResults];
  }

  #pragma mark - Search Mode

  - (SearchMode) mode {
    return _mode;
  }

  - (void) setMode: (SearchMode) mode {
    if (_mode == mode) return;
    _mode = mode;

    // only x / width change: the vertical position is kept as it is, because
    // the box follows the window when it grows / shrinks (autoresizing) and
    // the y saved at init time is only valid for the compact window
    const BOOL hasBadge = (_mode != APPMODE);
    const CGFloat shift = hasBadge ? kBadgeWidth + kBadgeGap : 0.0;
    NSRect frame = _searchField.frame;
    frame.origin.x = NSMinX(_fieldFrame) + shift;
    frame.size.width = NSWidth(_fieldFrame) - shift;
    _searchField.frame = frame;
    _modeBadge.hidden = !hasBadge;

    NSString *placeholderText = @"Search applications...";
    if (_mode == FILEMODE) {
      _modeBadgeLabel.stringValue = @"FileMode";
      placeholderText = @"~/path/to/file";
    } else if (_mode == CLIPBOARD) {
      _modeBadgeLabel.stringValue = @"Clipboard";
      placeholderText = @"Search clipboard...";
    }
    _searchField.placeholderAttributedString =
      [self placeholder:placeholderText font:_searchField.font];

    NSWindow *window = _searchField.window;
    if (window && _searchField.currentEditor) {
      [window makeFirstResponder:_searchField];
      [_searchField.currentEditor moveToEndOfLine:nil];
    }

    // opening clipboard mode is a user action: read a pending clipboard change
    // (background polling skips it when CCast is not always allowed to paste)
    if (_mode == CLIPBOARD) [_clipboardMonitor pollUserInitiated:YES];
  }

  #pragma mark - Search

  - (NSInteger) resultCount {
    const std::size_t n = (_mode == CLIPBOARD) ? _clipboardResults.size() : _results.size();
    return static_cast<NSInteger>(n);
  }

  - (void) updateResults {
    const char *text = _searchField.stringValue.UTF8String;
    const std::string query = text ? text : "";

    _results.clear();
    _clipboardResults.clear();

    switch (_mode) {
      case FILEMODE:
        _results = _fileEngine.query(query, kMaxResults);
        break;
      case CLIPBOARD:
        _clipboardResults = _clipboardEngine.query(query, kMaxResults);
        break;
      case APPMODE:
      default:
        _results = _searchApplication.query(query, kMaxResults);
        break;
    }

    const NSInteger count = [self resultCount];
    [_tableView reloadData];
    if (count > 0) {
      [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
      [_tableView scrollRowToVisible:0];
    }

    _resultsView.hidden = (count == 0);
    if (self.onResultsChanged) self.onResultsChanged(static_cast<NSUInteger>(count));
  }

  - (void) moveSelectionBy: (NSInteger) delta {
    const NSInteger count = [self resultCount];
    if (count == 0) return;

    NSInteger row = _tableView.selectedRow + delta;
    row = ((row % count) + count) % count;   // wrap around

    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_tableView scrollRowToVisible:row];
  }

  #pragma mark - Launch

  - (void) rowClicked: (id) sender {
    (void)sender;
    if (_mode == FILEMODE) [self revealRow:_tableView.clickedRow];
    else if (_mode == CLIPBOARD) [self copyRow:_tableView.clickedRow];
    else [self launchRow:_tableView.clickedRow];
  }

  #pragma mark - Clipboard

  // stores a new capture in the history; returns YES if the history changed
  - (BOOL) recordCapture: (ClipboardCapture *) capture {
    ClipboardItem item;
    item.kind = capture.kind;
    std::string extra;

    switch (capture.kind) {
      case ClipboardKind::Text: {
        const char *text = capture.text.UTF8String;
        if (!text) return NO;
        item.payload = text;
        break;
      }
      case ClipboardKind::File: {
        NSString *display = capture.filePath.stringByAbbreviatingWithTildeInPath;
        const char *path = capture.filePath.UTF8String;
        if (!path) return NO;
        item.payload = path;
        item.title = capture.filePath.lastPathComponent.UTF8String ?: "";
        item.subtitle = [NSString stringWithFormat:@"File · %@", display].UTF8String ?: "";
        extra = std::string(kFileSearchTerms) + " " + path;
        break;
      }
      case ClipboardKind::Image: {
        // same image copied again keeps its first title
        ClipboardCapture *existing = _clipboardImages[capture.imageID];
        if (existing.title) {
          capture.title = existing.title;
        } else {
          NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
          fmt.dateFormat = @"HH:mm:ss";
          capture.title = [NSString stringWithFormat:@"Image %@", [fmt stringFromDate:[NSDate date]]];
        }
        _clipboardImages[capture.imageID] = capture;
        item.payload = capture.imageID.UTF8String;
        item.title = capture.title.UTF8String;
        item.subtitle = capture.subtitle.UTF8String ?: "";
        extra = kImageSearchTerms;
        break;
      }
    }

    std::vector<ClipboardItem> evicted;
    const BOOL added = _clipboardEngine.add(std::move(item), extra, &evicted);
    if (!added && capture.kind == ClipboardKind::Image) {
      [_clipboardImages removeObjectForKey:capture.imageID];
    }
    [self forgetImagesOf:evicted];
    return added;
  }

  // drops the image data of entries no longer in the history
  - (void) forgetImagesOf: (const std::vector<ClipboardItem> &) items {
    for (const auto &item : items) {
      if (item.kind != ClipboardKind::Image) continue;
      NSString *imageID = [NSString stringWithUTF8String:item.payload.c_str()];
      if (imageID) [_clipboardImages removeObjectForKey:imageID];
    }
  }

  // Enter / click in clipboard mode: puts the entry back on the clipboard
  - (void) copyRow: (NSInteger) row {
    if (row < 0 || row >= static_cast<NSInteger>(_clipboardResults.size())) {
      NSBeep();
      return;
    }

    const ClipboardItem item = _clipboardResults[row];
    NSString *payload = [NSString stringWithUTF8String:item.payload.c_str()];
    if (!payload) {
      NSBeep();
      return;
    }

    switch (item.kind) {
      case ClipboardKind::Text:
        [_clipboardMonitor writeText:payload];
        break;
      case ClipboardKind::File:
        [_clipboardMonitor writeFileURL:[NSURL fileURLWithPath:payload]];
        break;
      case ClipboardKind::Image: {
        ClipboardCapture *image = _clipboardImages[payload];
        if (!image.imageData) {
          NSBeep();
          return;
        }
        [_clipboardMonitor writeImageData:image.imageData type:image.imageType];
        break;
      }
    }

    _clipboardEngine.promote(item.kind, item.payload);
    if (self.onDismiss) self.onDismiss();
  }

  // Cmd+Backspace / Fn+Backspace in clipboard mode: removes the selected entry
  - (void) deleteSelectedClipboardRow {
    const NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= static_cast<NSInteger>(_clipboardResults.size())) {
      NSBeep();
      return;
    }

    const ClipboardItem item = _clipboardResults[row];
    _clipboardEngine.remove(item.kind, item.payload);
    [self forgetImagesOf:{item}];

    [self updateResults];
    const NSInteger count = [self resultCount];
    if (count > 0) {
      const NSInteger nextRow = MIN(row, count - 1);
      [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:nextRow] byExtendingSelection:NO];
      [_tableView scrollRowToVisible:nextRow];
    }
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
    [self setMode:APPMODE];
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
    if (_mode == APPMODE && [_searchField.stringValue hasPrefix:@"/"]) {
      NSString *text = _searchField.stringValue;
      [self setMode:FILEMODE];
      _searchField.stringValue = (text.length == 1) ? @"" : text;
      [_searchField.currentEditor moveToEndOfLine:nil];
    } else if (_mode == APPMODE && [_searchField.stringValue hasPrefix:@":"]) {
      // ':' as first character: enter clipboard mode, the ':' itself is consumed
      // before setMode: triggers an immediate clipboard poll
      NSString *text = _searchField.stringValue;
      _searchField.stringValue = [text substringFromIndex:1];
      [self setMode:CLIPBOARD];
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

    // Cmd+Backspace or Fn+Backspace (when empty) in clipboard mode deletes selected entry
    if (_mode == CLIPBOARD &&
        (commandSelector == @selector(deleteToBeginningOfLine:) ||
         (commandSelector == @selector(deleteForward:) && empty))) {
      [self deleteSelectedClipboardRow];
      return YES;
    }

    // Backspace on the empty box leaves file/clipboard mode (returns to default APPMODE)
    if (commandSelector == @selector(deleteBackward:) && _mode != APPMODE && empty) {
      [self reset];
      return YES;
    }

    if (commandSelector == @selector(cancelOperation:)) {
      // Esc: clear the box, then leave file/clipboard mode, then close the launcher
      if (!empty) {
        _searchField.stringValue = @"";
        [self updateResults];
      } else if (_mode != APPMODE) {
        [self reset];
      } else if (self.onDismiss) {
        self.onDismiss();
      }
      return YES;
    }

    if (commandSelector == @selector(insertNewline:)) {
      if (_mode == FILEMODE) [self revealTypedPathOrSelection];
      else if (_mode == CLIPBOARD) [self copyRow:_tableView.selectedRow];
      else [self launchRow:_tableView.selectedRow];
      return YES;
    }

    if (commandSelector == @selector(insertTab:) && _mode == FILEMODE) {
      [self completeSelection];
      return YES;
    }

    return NO;
  }

  #pragma mark - NSTableViewDataSource / Delegate

  - (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
    (void)tableView;
    return [self resultCount];
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

    if (_mode == CLIPBOARD) {
      const ClipboardItem &item = _clipboardResults[row];
      cell.nameLabel.stringValue = [NSString stringWithUTF8String:item.title.c_str()] ?: @"";
      cell.pathLabel.stringValue = [NSString stringWithUTF8String:item.subtitle.c_str()] ?: @"";
      cell.iconView.image = [self iconForClipboardItem:item];
    } else {
      const AppDetail &app = _results[row];
      NSString *path = [NSString stringWithUTF8String:app.path.c_str()];
      cell.nameLabel.stringValue = [NSString stringWithUTF8String:app.name.c_str()] ?: @"";
      cell.pathLabel.stringValue = path.stringByAbbreviatingWithTildeInPath ?: @"";
      cell.iconView.image = [self iconForPath:path];
    }

    return cell;
  }

  - (NSImage *) iconForClipboardItem: (const ClipboardItem &) item {
    switch (item.kind) {
      case ClipboardKind::File: {
        NSString *path = [NSString stringWithUTF8String:item.payload.c_str()];
        return path ? [self iconForPath:path] : [self clipboardIcon];
      }
      case ClipboardKind::Image: {
        NSString *imageID = [NSString stringWithUTF8String:item.payload.c_str()];
        ClipboardCapture *image = imageID ? _clipboardImages[imageID] : nil;
        return image.thumbnail ?: [self clipboardIcon];
      }
      case ClipboardKind::Text:
      default:
        return [self clipboardIcon];
    }
  }

  - (NSImage *) clipboardIcon {
    if (!_clipboardIcon) {
      NSImage *img = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard"
                               accessibilityDescription:@"Clipboard"];
      if (img) {
        NSImageSymbolConfiguration *cfg =
          [NSImageSymbolConfiguration configurationWithPointSize:18
                                                          weight:NSFontWeightRegular];
        _clipboardIcon = [img imageWithSymbolConfiguration:cfg];
      } else {
        _clipboardIcon = [NSImage imageNamed:NSImageNameMultipleDocuments];
      }
    }
    return _clipboardIcon;
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
