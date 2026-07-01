#import "VCOverlayController.h"
#import "VCCoachingResult.h"

#pragma mark - Overlay view

@interface VCOverlayView : NSView
@property (nonatomic, strong) VCCoachingResult *result;
@property (nonatomic, copy) NSString *progressText;
@end

@implementation VCOverlayView

- (void)drawRect:(NSRect)dirtyRect {
    if (self.progressText.length) {
        [self drawPillWithText:self.progressText];
    }
    if (!self.result) return;

    [self drawInfoCard];

    NSInteger index = 1;
    for (VCAnnotation *annotation in self.result.annotations) {
        NSPoint point = NSMakePoint(annotation.target.x * self.bounds.size.width,
                                    (1.0 - annotation.target.y) * self.bounds.size.height);
        if ([annotation.type isEqualToString:@"highlight"]) {
            [self drawHighlightAt:point annotation:annotation];
            if (annotation.label.length) {
                [self drawLabelChipAt:NSMakePoint(point.x, point.y + 30)
                                 text:annotation.label
                                index:index];
            }
        } else if ([annotation.type isEqualToString:@"ring"]) {
            [self drawRingAt:point annotation:annotation];
            if (annotation.label.length) {
                [self drawLabelChipAt:NSMakePoint(point.x, point.y + 40)
                                 text:annotation.label
                                index:index];
            }
        } else if ([annotation.type isEqualToString:@"label"]) {
            [self drawLabelChipAt:point text:annotation.label index:index];
        } else { // arrow
            [self drawArrowTo:point label:annotation.label index:index];
        }
        index++;
    }
}

#pragma mark Drawing helpers

- (void)drawPillWithText:(NSString *)text {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };
    NSSize size = [text sizeWithAttributes:attrs];
    NSRect pill = NSMakeRect((self.bounds.size.width - size.width - 44) / 2, 48,
                             size.width + 44, 34);
    [[NSColor colorWithWhite:0 alpha:0.72] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:17 yRadius:17] fill];
    [text drawAtPoint:NSMakePoint(NSMidX(pill) - size.width / 2, NSMidY(pill) - size.height / 2)
       withAttributes:attrs];
}

- (void)drawInfoCard {
    CGFloat cardWidth = 400;
    CGFloat padding = 14;
    CGFloat textWidth = cardWidth - padding * 2;

    NSDictionary *headingAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor systemOrangeColor],
    };
    NSDictionary *bodyAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };

    NSMutableArray<NSArray *> *sections = [NSMutableArray array];
    if (self.result.context.length) [sections addObject:@[@"CONTEXT", self.result.context]];
    if (self.result.inferredGoal.length) [sections addObject:@[@"LIKELY GOAL", self.result.inferredGoal]];
    if (self.result.message.length) [sections addObject:@[@"NEXT STEP", self.result.message]];
    if (sections.count == 0) return;

    CGFloat totalHeight = padding;
    NSMutableArray<NSNumber *> *bodyHeights = [NSMutableArray array];
    for (NSArray *section in sections) {
        NSRect bodyRect = [section[1] boundingRectWithSize:NSMakeSize(textWidth, 600)
                                                   options:NSStringDrawingUsesLineFragmentOrigin
                                                attributes:bodyAttrs];
        [bodyHeights addObject:@(ceil(bodyRect.size.height))];
        totalHeight += 15 + ceil(bodyRect.size.height) + 10;
    }
    totalHeight += padding - 10;

    NSRect card = NSMakeRect(24, self.bounds.size.height - totalHeight - 24, cardWidth, totalHeight);
    [[NSColor colorWithWhite:0.08 alpha:0.85] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:card xRadius:12 yRadius:12] fill];

    CGFloat y = NSMaxY(card) - padding;
    for (NSUInteger i = 0; i < sections.count; i++) {
        y -= 15;
        [sections[i][0] drawAtPoint:NSMakePoint(card.origin.x + padding, y) withAttributes:headingAttrs];
        CGFloat bodyHeight = bodyHeights[i].doubleValue;
        y -= bodyHeight + 2;
        [sections[i][1] drawInRect:NSMakeRect(card.origin.x + padding, y, textWidth, bodyHeight)
                    withAttributes:bodyAttrs];
        y -= 8;
    }
}

- (void)drawArrowTo:(NSPoint)target label:(NSString *)label index:(NSInteger)index {
    // Start the arrow 160 px back toward the screen center so it points inward.
    NSPoint center = NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds));
    CGFloat dx = target.x - center.x, dy = target.y - center.y;
    CGFloat length = MAX(1, hypot(dx, dy));
    NSPoint start = NSMakePoint(target.x - dx / length * 160, target.y - dy / length * 160);

    NSPoint mid = NSMakePoint((start.x + target.x) / 2, (start.y + target.y) / 2);
    NSPoint perpendicular = NSMakePoint(-(target.y - start.y), target.x - start.x);
    CGFloat perpendicularLength = MAX(1, hypot(perpendicular.x, perpendicular.y));
    NSPoint control = NSMakePoint(mid.x + perpendicular.x / perpendicularLength * 40,
                                  mid.y + perpendicular.y / perpendicularLength * 40);

    NSBezierPath *curve = [NSBezierPath bezierPath];
    curve.lineWidth = 4;
    curve.lineCapStyle = NSLineCapStyleRound;
    [curve moveToPoint:start];
    [curve curveToPoint:target controlPoint1:control controlPoint2:control];
    [[NSColor systemOrangeColor] setStroke];
    [curve stroke];

    CGFloat angle = atan2(target.y - control.y, target.x - control.x);
    NSBezierPath *head = [NSBezierPath bezierPath];
    head.lineWidth = 4;
    head.lineCapStyle = NSLineCapStyleRound;
    [head moveToPoint:NSMakePoint(target.x - 16 * cos(angle - 0.45), target.y - 16 * sin(angle - 0.45))];
    [head lineToPoint:target];
    [head lineToPoint:NSMakePoint(target.x - 16 * cos(angle + 0.45), target.y - 16 * sin(angle + 0.45))];
    [head stroke];

    if (label.length) {
        [self drawLabelChipAt:start text:label index:index];
    }
}

- (void)drawRingAt:(NSPoint)point annotation:(VCAnnotation *)annotation {
    CGFloat radius = MAX(20, annotation.size.width * self.bounds.size.width / 2 + 12);
    for (CGFloat r = radius; r <= radius + 8; r += 8) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:
                              NSMakeRect(point.x - r, point.y - r, r * 2, r * 2)];
        ring.lineWidth = 3;
        [[[NSColor systemOrangeColor] colorWithAlphaComponent:r == radius ? 0.9 : 0.4] setStroke];
        [ring stroke];
    }
}

- (void)drawHighlightAt:(NSPoint)point annotation:(VCAnnotation *)annotation {
    CGFloat width = MAX(48, annotation.size.width * self.bounds.size.width + 16);
    CGFloat height = MAX(28, annotation.size.height * self.bounds.size.height + 12);
    NSRect rect = NSMakeRect(point.x - width / 2, point.y - height / 2, width, height);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:6 yRadius:6];
    [[[NSColor systemYellowColor] colorWithAlphaComponent:0.18] setFill];
    [path fill];
    path.lineWidth = 3;
    [[[NSColor systemOrangeColor] colorWithAlphaComponent:0.9] setStroke];
    [path stroke];
}

- (void)drawLabelChipAt:(NSPoint)point text:(NSString *)text index:(NSInteger)index {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };
    NSString *display = text.length ? text : [NSString stringWithFormat:@"Step %ld", (long)index];
    NSSize textSize = [display sizeWithAttributes:attrs];
    CGFloat badge = 22;

    NSRect pill = NSMakeRect(point.x - (textSize.width + badge + 26) / 2, point.y + 14,
                             textSize.width + badge + 26, 28);
    pill.origin.x = MIN(MAX(8, pill.origin.x), self.bounds.size.width - pill.size.width - 8);
    pill.origin.y = MIN(MAX(8, pill.origin.y), self.bounds.size.height - pill.size.height - 8);

    [[NSColor colorWithWhite:0 alpha:0.78] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:14 yRadius:14] fill];

    NSRect badgeRect = NSMakeRect(pill.origin.x + 4, pill.origin.y + 3, badge, badge);
    [[NSColor systemOrangeColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:badgeRect] fill];
    NSString *number = [NSString stringWithFormat:@"%ld", (long)index];
    NSSize numberSize = [number sizeWithAttributes:attrs];
    [number drawAtPoint:NSMakePoint(NSMidX(badgeRect) - numberSize.width / 2,
                                    NSMidY(badgeRect) - numberSize.height / 2)
         withAttributes:attrs];

    [display drawAtPoint:NSMakePoint(pill.origin.x + badge + 12, NSMidY(pill) - textSize.height / 2)
          withAttributes:attrs];
}

@end

#pragma mark - Overlay controller

@interface VCOverlayController ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) VCOverlayView *view;
@end

@implementation VCOverlayController

- (void)ensureWindowForScreen:(NSScreen *)screen {
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:screen.frame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        self.window.opaque = NO;
        self.window.backgroundColor = [NSColor clearColor];
        self.window.hasShadow = NO;
        self.window.ignoresMouseEvents = YES; // click-through
        self.window.level = NSScreenSaverWindowLevel;
        self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                       | NSWindowCollectionBehaviorStationary
                                       | NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.view = [[VCOverlayView alloc] initWithFrame:(NSRect){NSZeroPoint, screen.frame.size}];
        self.window.contentView = self.view;
    } else {
        [self.window setFrame:screen.frame display:NO];
    }
}

- (void)showProgress:(NSString *)text onScreen:(NSScreen *)screen {
    [self ensureWindowForScreen:screen];
    self.view.result = nil;
    self.view.progressText = text;
    [self.view setNeedsDisplay:YES];
    [self.window orderFrontRegardless];
}

- (void)showResult:(VCCoachingResult *)result onScreen:(NSScreen *)screen {
    [self ensureWindowForScreen:screen];
    self.view.progressText = nil;
    self.view.result = result;
    [self.view setNeedsDisplay:YES];
    [self.window orderFrontRegardless];
}

- (void)hide {
    [self.window orderOut:nil];
    self.view.result = nil;
    self.view.progressText = nil;
}

- (void)hideIfShowingOnlyProgress {
    if (!self.view.result) {
        [self hide];
    } else {
        self.view.progressText = nil;
        [self.view setNeedsDisplay:YES];
    }
}

@end
