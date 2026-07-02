#import "VCDrawCanvasController.h"

#pragma mark - Key-capable borderless window

@interface VCDrawCanvasWindow : NSWindow
@end

@implementation VCDrawCanvasWindow
- (BOOL)canBecomeKeyWindow {
    return YES;
}
@end

#pragma mark - Canvas view

@interface VCDrawCanvasView : NSView
@property (nonatomic, strong) NSMutableArray<NSBezierPath *> *strokes;
@property (nonatomic, strong) NSBezierPath *currentStroke;
@property (nonatomic, copy) void (^onSubmit)(void);
@property (nonatomic, copy) void (^onCancel)(void);
@end

@implementation VCDrawCanvasView

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _strokes = [NSMutableArray array];
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    self.currentStroke = [NSBezierPath bezierPath];
    self.currentStroke.lineWidth = 4;
    self.currentStroke.lineCapStyle = NSLineCapStyleRound;
    self.currentStroke.lineJoinStyle = NSLineJoinStyleRound;
    [self.currentStroke moveToPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseDragged:(NSEvent *)event {
    [self.currentStroke lineToPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (self.currentStroke && !self.currentStroke.isEmpty) {
        [self.strokes addObject:self.currentStroke];
    }
    self.currentStroke = nil;
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) { // Escape
        if (self.onCancel) self.onCancel();
    } else if (event.keyCode == 36 || event.keyCode == 76) { // Return / Enter
        if (self.onSubmit) self.onSubmit();
    } else {
        [super keyDown:event];
    }
}

- (BOOL)hasMark {
    return self.strokes.count > 0;
}

/// Union of all stroke bounds, normalized 0–1 with a top-left origin.
- (CGRect)normalizedMarkedRegion {
    if (!self.hasMark) return CGRectZero;
    NSRect unionRect = NSZeroRect;
    for (NSBezierPath *stroke in self.strokes) {
        unionRect = NSIsEmptyRect(unionRect) ? stroke.bounds : NSUnionRect(unionRect, stroke.bounds);
    }
    unionRect = NSIntersectionRect(NSInsetRect(unionRect, -12, -12), self.bounds);
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    return CGRectMake(unionRect.origin.x / width,
                      1.0 - (unionRect.origin.y + unionRect.size.height) / height,
                      unionRect.size.width / width,
                      unionRect.size.height / height);
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0 alpha:0.15] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    [[NSColor systemOrangeColor] setStroke];
    for (NSBezierPath *stroke in self.strokes) {
        [stroke stroke];
    }
    [self.currentStroke stroke];

    NSString *hint = @"Draw to mark a region — Return to ask, Esc to cancel";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };
    NSSize size = [hint sizeWithAttributes:attrs];
    NSRect pill = NSMakeRect((self.bounds.size.width - size.width - 40) / 2,
                             self.bounds.size.height - 72, size.width + 40, 36);
    [[NSColor colorWithWhite:0 alpha:0.68] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:18 yRadius:18] fill];
    [hint drawAtPoint:NSMakePoint(NSMidX(pill) - size.width / 2, NSMidY(pill) - size.height / 2)
       withAttributes:attrs];
}

@end

#pragma mark - Controller

@interface VCDrawCanvasController ()
@property (nonatomic, strong) VCDrawCanvasWindow *window;
@property (nonatomic, strong) VCDrawCanvasView *canvasView;
@property (nonatomic, copy) VCDrawCompletion completion;
@end

@implementation VCDrawCanvasController

- (BOOL)isActive {
    return self.window != nil;
}

- (void)cancel {
    [self finishSubmitted:NO];
}

- (void)beginOnScreen:(NSScreen *)screen completion:(VCDrawCompletion)completion {
    if (self.window) return; // already active
    self.completion = completion;

    self.window = [[VCDrawCanvasWindow alloc] initWithContentRect:screen.frame
                                                        styleMask:NSWindowStyleMaskBorderless
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
    self.window.opaque = NO;
    self.window.backgroundColor = [NSColor clearColor];
    self.window.hasShadow = NO;
    self.window.level = NSScreenSaverWindowLevel;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                   | NSWindowCollectionBehaviorFullScreenAuxiliary;

    VCDrawCanvasView *view = [[VCDrawCanvasView alloc] initWithFrame:(NSRect){NSZeroPoint, screen.frame.size}];
    __weak typeof(self) weakSelf = self;
    view.onSubmit = ^{ [weakSelf finishSubmitted:YES]; };
    view.onCancel = ^{ [weakSelf finishSubmitted:NO]; };
    self.canvasView = view;
    self.window.contentView = view;

    CGFloat midX = screen.frame.size.width / 2;
    NSButton *ask = [NSButton buttonWithTitle:@"Ask About Mark" target:self action:@selector(askPressed:)];
    ask.frame = NSMakeRect(midX - 170, 24, 160, 32);
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelPressed:)];
    cancel.frame = NSMakeRect(midX + 10, 24, 160, 32);
    [view addSubview:ask];
    [view addSubview:cancel];

    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:view];
}

- (void)askPressed:(id)sender {
    [self finishSubmitted:YES];
}

- (void)cancelPressed:(id)sender {
    [self finishSubmitted:NO];
}

- (void)finishSubmitted:(BOOL)submitted {
    if (!self.window) return;
    BOOL hasMark = self.canvasView.hasMark;
    CGRect region = self.canvasView.normalizedMarkedRegion;
    VCDrawCompletion completion = self.completion;

    self.completion = nil;
    [self.window orderOut:nil];
    self.window = nil;
    self.canvasView = nil;

    if (completion) completion(submitted, region, hasMark);
}

@end
