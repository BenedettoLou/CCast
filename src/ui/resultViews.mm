#import "resultViews.h"

@implementation ResultRowView

  - (BOOL) isEmphasized {
    return YES;
  }

  - (void) drawSelectionInRect: (NSRect) dirtyRect {
    (void)dirtyRect;
    NSRect r = NSInsetRect(self.bounds, 4, 2);
    [[[NSColor controlAccentColor] colorWithAlphaComponent:0.85] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:r xRadius:8 yRadius:8] fill];
  }

@end


static NSTextField *makeLabel(CGFloat size, NSFontWeight weight, NSColor *color) {
  NSTextField *label = [NSTextField labelWithString:@""];
  label.font = [NSFont systemFontOfSize:size weight:weight];
  label.textColor = color;
  label.lineBreakMode = NSLineBreakByTruncatingMiddle;
  label.cell.usesSingleLineMode = YES;
  label.autoresizingMask = NSViewWidthSizable;
  return label;
}

@implementation ResultCellView

  + (NSUserInterfaceItemIdentifier) reuseIdentifier {
    return @"ResultCell";
  }

  - (instancetype) initWithFrame: (NSRect) frame {
    self = [super initWithFrame:frame];

    if (self) {
      self.identifier = [ResultCellView reuseIdentifier];

      const CGFloat h = NSHeight(frame);
      const CGFloat w = NSWidth(frame);
      const CGFloat iconSize = 32.0;
      const CGFloat textX = 12.0 + iconSize + 10.0;

      _iconView = [[NSImageView alloc] initWithFrame:
        NSMakeRect(12, (h - iconSize) / 2.0, iconSize, iconSize)];
      _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;

      _nameLabel = makeLabel(14, NSFontWeightRegular, [NSColor whiteColor]);
      _nameLabel.frame = NSMakeRect(textX, h / 2.0 - 1, w - textX - 12, 18);

      _pathLabel = makeLabel(11, NSFontWeightRegular,
                             [NSColor colorWithCalibratedWhite:1.0 alpha:0.5]);
      _pathLabel.frame = NSMakeRect(textX, h / 2.0 - 16, w - textX - 12, 14);

      [self addSubview:_iconView];
      [self addSubview:_nameLabel];
      [self addSubview:_pathLabel];

      self.imageView = _iconView;
      self.textField = _nameLabel;
    }

    return self;
  }

@end
