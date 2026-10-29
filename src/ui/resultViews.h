#import <Cocoa/Cocoa.h>

/*
 *
 * Views used by the results list
 *
 */

// row with a rounded selection highlight that stays "active"
// even though the keyboard focus is in the search box
@interface ResultRowView : NSTableRowView
@end

// icon + app name + path
@interface ResultCellView : NSTableCellView

  @property (nonatomic, strong, readonly) NSImageView *iconView;
  @property (nonatomic, strong, readonly) NSTextField *nameLabel;
  @property (nonatomic, strong, readonly) NSTextField *pathLabel;

  + (NSUserInterfaceItemIdentifier) reuseIdentifier;

@end
