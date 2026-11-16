#import "search.h"
#import "resultViews.h"

#include <cstdint>
#include <string>
#include <vector>

static const CGFloat    kRowHeight  = 44.0;
static const std::size_t kMaxResults = 20;

// mode badge ("FileMode" / "Clipboard")
static const CGFloat kBadgeWidth  = 80.0;
static const CGFloat kBadgeHeight = 22.0;
static const CGFloat kBadgeGap    = 8.0;   // space between badge and text

static const NSTimeInterval kClipboardPollInterval = 0.5;

@interface ClipboardImageItem : NSObject
  @property (nonatomic, strong) NSImage *thumbnail;
  @property (nonatomic, strong) NSData *pngData;
  @property (nonatomic, copy) NSString *title;
  @property (nonatomic, copy) NSString *subtitle;
@end

@implementation ClipboardImageItem
@end

@implementation SearchController {
  SearchApplication _searchApplication;
  SearchFile _fileEngine;
  SearchClipboard _clipboardEngine;
  std::vector<AppDetail> _results;   // apps, files, or clipboard entries, depending on _mode
  SearchMode _mode;                  // current application mode (APPMODE by default)
  NSRect _fieldFrame;                // search box frame in app mode
  NSTextField *_modeBadgeLabel;
  NSTableView *_tableView;
  NSCache<NSString *, NSImage *> *_iconCache;
  NSMutableDictionary<NSString *, ClipboardImageItem *> *_clipboardImages;
  NSImage *_clipboardIcon;
  NSTimer *_clipboardTimer;
  NSInteger _lastChangeCount;
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
      _lastChangeCount = -1;
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

      [self pollClipboard];
      __weak SearchController *weakSelf = self;
      _clipboardTimer = [NSTimer scheduledTimerWithTimeInterval:kClipboardPollInterval
                                                        repeats:YES
                                                          block:^(NSTimer *timer) {
        (void)timer;
        SearchController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([strongSelf pollClipboard] && strongSelf->_mode == CLIPBOARD) {
          [strongSelf updateResults];
        }
      }];
      // set a tolerance for the clipboard timer to improve power efficiency (MacOS guidelines)
      _clipboardTimer.tolerance = 0.2;
    }

    return self;
  }

  - (void) dealloc {
    [_clipboardTimer invalidate];
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
  }

  #pragma mark - Search

  - (void) updateResults {
    const char *text = _searchField.stringValue.UTF8String;

    switch (_mode) {
      case FILEMODE:
        _results = _fileEngine.query(text ? text : "", kMaxResults);
        break;
      case CLIPBOARD:
        [self pollClipboard];
        _results = _clipboardEngine.query(text ? text : "", kMaxResults);
        break;
      case APPMODE:
      default:
        _results = _searchApplication.query(text ? text : "", kMaxResults);
        break;
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
    if (_mode == FILEMODE) [self revealRow:_tableView.clickedRow];
    else if (_mode == CLIPBOARD) [self copyRow:_tableView.clickedRow];
    else [self launchRow:_tableView.clickedRow];
  }

  #pragma mark - Clipboard

  - (void) pruneEvictedKey: (const std::string &) evicted {
    if (evicted.empty()) return;
    NSString *evictedKey = [NSString stringWithUTF8String:evicted.c_str()];
    if (evictedKey) [_clipboardImages removeObjectForKey:evictedKey];
  }

  // polls NSPasteboard.generalPasteboard for changes; returns YES if a new item was added
  - (BOOL) pollClipboard {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    const NSInteger changeCount = pb.changeCount;
    if (changeCount == _lastChangeCount) return NO;
    _lastChangeCount = changeCount;

    // Ignore password managers / concealed / transient pasteboard items (nspasteboard.org)
    NSArray<NSPasteboardType> *types = pb.types;
    if ([types containsObject:@"org.nspasteboard.ConcealedType"] ||
        [types containsObject:@"org.nspasteboard.TransientType"]) {
      return NO;
    }

    // Copied files from Finder
    if ([types containsObject:NSPasteboardTypeFileURL]) {
      NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                                 options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
      NSURL *fileURL = urls.firstObject;
      if (fileURL.isFileURL && fileURL.path.length > 0) {
        NSString *filePath = fileURL.path;
        NSString *fileName = filePath.lastPathComponent;
        const char *pathUtf8 = filePath.UTF8String;
        const char *nameUtf8 = fileName.UTF8String;
        if (pathUtf8 && pathUtf8[0] && nameUtf8 && nameUtf8[0]) {
          const std::string key = std::string("\x01file:") + pathUtf8;
          const std::string extra = std::string("file ") + pathUtf8;
          [self pruneEvictedKey:_clipboardEngine.addEntry(nameUtf8, key, extra)];
          return YES;
        }
      }
      return NO;
    }

    // Screenshots / copied images
    NSData *pngData = [pb dataForType:NSPasteboardTypePNG];
    NSData *tiffData = [pb dataForType:NSPasteboardTypeTIFF];

    if (pngData.length > 0 || tiffData.length > 0) {
      NSImage *img = [[NSImage alloc] initWithData:(pngData ?: tiffData)];
      if (img) {
        if (!pngData && tiffData) {
          NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:tiffData];
          if (!rep && img.TIFFRepresentation) {
            rep = [[NSBitmapImageRep alloc] initWithData:img.TIFFRepresentation];
          }
          if (rep) {
            pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
          }
        }

        NSData *hashData = pngData ?: tiffData;
        if (hashData.length > 0) {
          // 64-bit FNV-1a hash for deterministic deduplication
          uint64_t hash = 14695981039346656037ULL;
          const auto *bytes = static_cast<const uint8_t *>(hashData.bytes);
          for (NSUInteger i = 0; i < hashData.length; ++i) {
            hash ^= bytes[i];
            hash *= 1099511628211ULL;
          }

          NSString *nsKey = [NSString stringWithFormat:@"\x01img:%016llx",
                             static_cast<unsigned long long>(hash)];
          const char *keyUtf8 = nsKey.UTF8String;
          if (keyUtf8 && keyUtf8[0]) {
            NSInteger width = static_cast<NSInteger>(img.size.width);
            NSInteger height = static_cast<NSInteger>(img.size.height);
            NSBitmapImageRep *dimRep = nil;
            for (NSImageRep *r in img.representations) {
              if ([r isKindOfClass:[NSBitmapImageRep class]]) {
                dimRep = static_cast<NSBitmapImageRep *>(r);
                break;
              }
            }
            if (!dimRep) {
              dimRep = [NSBitmapImageRep imageRepWithData:hashData];
            }
            if (dimRep && dimRep.pixelsWide > 0 && dimRep.pixelsHigh > 0) {
              width = dimRep.pixelsWide;
              height = dimRep.pixelsHigh;
            }

            const NSUInteger kb = MAX(static_cast<NSUInteger>(1), hashData.length / 1024);
            ClipboardImageItem *existing = _clipboardImages[nsKey];
            NSString *title = existing ? existing.title : nil;
            if (!title) {
              NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
              fmt.dateFormat = @"HH:mm:ss";
              title = [NSString stringWithFormat:@"Screenshot %@",
                       [fmt stringFromDate:[NSDate date]]];
            }

            // Downscale to a compact 32x32 thumbnail to avoid retaining full size bitmaps
            NSImage *thumb = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
            [thumb lockFocus];
            [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
            const NSSize srcSize = img.size;
            const CGFloat scale = (srcSize.width > 0 && srcSize.height > 0)
              ? MIN(32.0 / srcSize.width, 32.0 / srcSize.height) : 1.0;
            const CGFloat drawW = srcSize.width * scale;
            const CGFloat drawH = srcSize.height * scale;
            const NSRect dstRect = NSMakeRect((32.0 - drawW) / 2.0,
                                              (32.0 - drawH) / 2.0,
                                              drawW, drawH);
            [img drawInRect:dstRect
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:1.0];
            [thumb unlockFocus];

            ClipboardImageItem *item = [[ClipboardImageItem alloc] init];
            item.thumbnail = thumb;
            item.pngData = hashData;
            item.title = title;
            item.subtitle = [NSString stringWithFormat:@"Image · %ld × %ld · %lu KB",
                             static_cast<long>(width),
                             static_cast<long>(height),
                             static_cast<unsigned long>(kb)];

            _clipboardImages[nsKey] = item;
            const std::string evicted = _clipboardEngine.addEntry(
              title.UTF8String ? title.UTF8String : "Screenshot",
              keyUtf8,
              "screenshot image png");
            [self pruneEvictedKey:evicted];
            return YES;
          }
        }
      }
    }

    NSString *str = [pb stringForType:NSPasteboardTypeString];
    if (!str || str.length == 0) return NO;

    const char *utf8 = str.UTF8String;
    if (!utf8 || !utf8[0]) return NO;

    [self pruneEvictedKey:_clipboardEngine.add(utf8)];
    return YES;
  }

  // Enter / click in clipboard mode: copies the selected entry back to NSPasteboard
  - (void) copyRow: (NSInteger) row {
    if (row < 0 || row >= static_cast<NSInteger>(_results.size())) {
      NSBeep();
      return;
    }

    const AppDetail &entry = _results[row];
    NSString *nsKey = [NSString stringWithUTF8String:entry.path.c_str()];
    ClipboardImageItem *imgItem = nsKey ? _clipboardImages[nsKey] : nil;

    if (imgItem) {
      NSPasteboard *pb = [NSPasteboard generalPasteboard];
      [pb clearContents];
      NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
      if (imgItem.pngData) {
        [pbItem setData:imgItem.pngData forType:NSPasteboardTypePNG];
        NSImage *decoded = [[NSImage alloc] initWithData:imgItem.pngData];
        NSData *tiffData = [decoded TIFFRepresentation];
        if (tiffData) [pbItem setData:tiffData forType:NSPasteboardTypeTIFF];
      }
      [pb writeObjects:@[pbItem]];
      _lastChangeCount = pb.changeCount;

      [self pruneEvictedKey:_clipboardEngine.addEntry(entry.name, entry.path, "screenshot image png")];

      if (self.onDismiss) self.onDismiss();
      return;
    }

    if (entry.path.compare(0, 6, "\x01file:") == 0) {
      const std::string filePath = entry.path.substr(6);
      NSString *nsFilePath = [NSString stringWithUTF8String:filePath.c_str()];
      NSURL *fileURL = nsFilePath ? [NSURL fileURLWithPath:nsFilePath] : nil;
      if (!fileURL) {
        NSBeep();
        return;
      }

      NSPasteboard *pb = [NSPasteboard generalPasteboard];
      [pb clearContents];
      [pb writeObjects:@[fileURL]];
      _lastChangeCount = pb.changeCount;

      [self pruneEvictedKey:_clipboardEngine.addEntry(entry.name, entry.path, "file " + filePath)];

      if (self.onDismiss) self.onDismiss();
      return;
    }

    const std::string &rawText = entry.path;
    NSString *content = [NSString stringWithUTF8String:rawText.c_str()];
    if (!content) {
      NSBeep();
      return;
    }

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    NSPasteboardItem *textItem = [[NSPasteboardItem alloc] init];
    [textItem setString:content forType:NSPasteboardTypeString];
    [pb writeObjects:@[textItem]];
    _lastChangeCount = pb.changeCount;

    [self pruneEvictedKey:_clipboardEngine.add(rawText)];

    if (self.onDismiss) self.onDismiss();
  }

  // Cmd+Backspace / Fn+Backspace in clipboard mode: removes the selected entry
  - (void) deleteSelectedClipboardRow {
    const NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= static_cast<NSInteger>(_results.size())) {
      NSBeep();
      return;
    }

    const std::string path = _results[row].path;
    NSString *nsKey = [NSString stringWithUTF8String:path.c_str()];
    if (nsKey) [_clipboardImages removeObjectForKey:nsKey];
    _clipboardEngine.remove(path);

    [self updateResults];
    if (!_results.empty()) {
      const NSInteger nextRow = MIN(row, static_cast<NSInteger>(_results.size()) - 1);
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
      NSString *text = _searchField.stringValue;
      [self setMode:CLIPBOARD];
      _searchField.stringValue = [text substringFromIndex:1];
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
    cell.nameLabel.stringValue = [NSString stringWithUTF8String:app.name.c_str()] ?: @"";

    if (_mode == CLIPBOARD) {
      if (app.path.compare(0, 6, "\x01file:") == 0) {
        NSString *filePath = [NSString stringWithUTF8String:app.path.c_str() + 6];
        cell.pathLabel.stringValue = [NSString stringWithFormat:@"File · %@",
          filePath.stringByAbbreviatingWithTildeInPath ?: @""];
        cell.iconView.image = filePath ? [self iconForPath:filePath] : [self clipboardIcon];
      } else {
        NSString *key = [NSString stringWithUTF8String:app.path.c_str()];
        ClipboardImageItem *imgItem = key ? _clipboardImages[key] : nil;
        if (imgItem) {
          cell.pathLabel.stringValue = imgItem.subtitle ?: @"Image";
          cell.iconView.image = imgItem.thumbnail ?: [self clipboardIcon];
        } else {
          cell.pathLabel.stringValue = [self subtitleForClipboardText:app.path];
          cell.iconView.image = [self clipboardIcon];
        }
      }
    } else {
      NSString *path = [NSString stringWithUTF8String:app.path.c_str()];
      cell.pathLabel.stringValue = path.stringByAbbreviatingWithTildeInPath ?: @"";
      cell.iconView.image = [self iconForPath:path];
    }

    return cell;
  }

  - (NSString *) subtitleForClipboardText: (const std::string &) text {
    std::size_t lines = 1;
    for (char c : text) {
      if (c == '\n') ++lines;
    }
    NSString *nsText = [NSString stringWithUTF8String:text.c_str()];
    const NSUInteger chars = nsText ? nsText.length : text.size();
    return [NSString stringWithFormat:@"%zu %@ · %lu %@",
            lines, (lines == 1 ? @"line" : @"lines"),
            (unsigned long)chars, (chars == 1 ? @"char" : @"chars")];
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
