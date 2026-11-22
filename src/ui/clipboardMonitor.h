#import <Cocoa/Cocoa.h>
#import "../core/searchClipboard.hpp"

/*
 *
 * Something new found on the system clipboard.
 * Only the fields matching `kind` are set.
 *
 */
@interface ClipboardCapture : NSObject

  @property (nonatomic, assign) ClipboardKind kind;

  // Text
  @property (nonatomic, copy) NSString *text;

  // File
  @property (nonatomic, copy) NSString *filePath;

  // Image: id = content hash, data = PNG (or TIFF if it could not be converted),
  // small thumbnail for the list, "Image · W × H · N KB"
  @property (nonatomic, copy) NSString *imageID;
  @property (nonatomic, strong) NSData *imageData;
  @property (nonatomic, copy) NSPasteboardType imageType;
  @property (nonatomic, strong) NSImage *thumbnail;
  @property (nonatomic, copy) NSString *subtitle;
  @property (nonatomic, copy) NSString *title;   // set by the owner (kept across duplicates)

@end

/*
 *
 * Watches the general pasteboard and reports new copies.
 *
 * macOS has no "clipboard changed" notification: changeCount is polled
 * (cheap integer read, timer with tolerance) and the content is only read
 * when it changed. Images are decoded / converted / thumbnailed on a
 * background queue. Password managers (nspasteboard.org concealed,
 * transient and auto-generated types) are ignored.
 *
 * macOS 15.4+ may ask the user before an app reads the pasteboard
 * programmatically. If the system switches CCast to "Ask" or "Always Deny",
 * background polling pauses so it won't trigger repeated alerts; the
 * clipboard is then read only on explicit user actions (opening clipboard mode).
 *
 */
@interface ClipboardMonitor : NSObject

  // called on the main thread for every new clipboard content
  - (instancetype) initWithHandler: (void (^)(ClipboardCapture *capture)) handler;

  // YES if the content can be read in the background without alerts
  @property (nonatomic, readonly) BOOL backgroundCaptureAllowed;

  - (void) start;
  - (void) stop;

  // reads the pasteboard if it changed since the last read.
  // userInitiated = YES when triggered by an explicit user action
  - (void) pollUserInitiated: (BOOL) userInitiated;

  // put an entry back on the pasteboard (not reported as a new capture)
  - (void) writeText: (NSString *) text;
  - (void) writeFileURL: (NSURL *) url;
  - (void) writeImageData: (NSData *) data type: (NSPasteboardType) type;

@end
