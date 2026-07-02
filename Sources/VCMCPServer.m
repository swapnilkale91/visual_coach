#import "VCMCPServer.h"
#import <Cocoa/Cocoa.h>
#import <sys/socket.h>
#import <sys/un.h>
#import "VCScreenCapture.h"
#import "VCOCRService.h"
#import "VCCoachingResult.h"
#import "VCOverlayController.h"
#import "VCDrawCanvasController.h"

typedef void (^VCToolFinish)(NSArray<NSDictionary *> *content, BOOL isError);

static NSDictionary *VCTextBlock(NSString *text) {
    return @{@"type": @"text", @"text": text ?: @""};
}

static NSDictionary *VCImageBlock(NSData *png) {
    return @{@"type": @"image",
             @"data": [png base64EncodedStringWithOptions:0],
             @"mimeType": @"image/png"};
}

@interface VCMCPServer () {
    int _listenFD;
}
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_source_t listenSource;
@property (nonatomic, strong) NSMutableSet *connectionSources;
@property (nonatomic, strong) VCOverlayController *overlay;
@property (nonatomic, strong) VCDrawCanvasController *canvas;
// Last capture, kept for OCR grounding of show_guidance and screen targeting.
@property (nonatomic, strong) VCScreenSnapshot *lastSnapshot;
@property (nonatomic, strong) NSArray<VCOCRLine *> *lastOCRLines;
@property (nonatomic) NSUInteger markGeneration;
@end

@implementation VCMCPServer

+ (NSString *)socketPath {
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *directory = [appSupport stringByAppendingPathComponent:@"VisualCoach"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return [directory stringByAppendingPathComponent:@"mcp.sock"];
}

- (instancetype)initWithOverlay:(VCOverlayController *)overlay {
    if ((self = [super init])) {
        _overlay = overlay;
        _canvas = [[VCDrawCanvasController alloc] init];
        _queue = dispatch_queue_create("local.codex.visualcoach.mcp", DISPATCH_QUEUE_SERIAL);
        _connectionSources = [NSMutableSet set];
        _listenFD = -1;
    }
    return self;
}

#pragma mark - Socket server

- (BOOL)start {
    NSString *path = [VCMCPServer socketPath];
    unlink(path.fileSystemRepresentation);

    _listenFD = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_listenFD < 0) return NO;

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));

    if (bind(_listenFD, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(_listenFD, 4) != 0) {
        close(_listenFD);
        _listenFD = -1;
        return NO;
    }

    self.listenSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _listenFD, 0, self.queue);
    __weak typeof(self) weakSelf = self;
    int listenFD = _listenFD;
    dispatch_source_set_event_handler(self.listenSource, ^{
        int client = accept(listenFD, NULL, NULL);
        if (client >= 0) [weakSelf startConnection:client];
    });
    dispatch_resume(self.listenSource);
    return YES;
}

- (void)startConnection:(int)fd {
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

    NSMutableData *buffer = [NSMutableData data];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.queue);
    [self.connectionSources addObject:source];

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        char chunk[65536];
        ssize_t count = read(fd, chunk, sizeof(chunk));
        if (count <= 0) {
            dispatch_source_cancel(source);
            return;
        }
        [buffer appendBytes:chunk length:(NSUInteger)count];
        [weakSelf drainBuffer:buffer fd:fd];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
        [weakSelf.connectionSources removeObject:source];
    });
    dispatch_resume(source);
}

- (void)drainBuffer:(NSMutableData *)buffer fd:(int)fd {
    while (YES) {
        NSRange newline = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                      options:0
                                        range:NSMakeRange(0, buffer.length)];
        if (newline.location == NSNotFound) return;

        NSData *line = [buffer subdataWithRange:NSMakeRange(0, newline.location)];
        [buffer replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
        if (line.length == 0) continue;

        NSDictionary *message = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
        if ([message isKindOfClass:[NSDictionary class]]) {
            [self handleMessage:message fd:fd];
        }
    }
}

- (void)sendResult:(id)result error:(NSDictionary *)error forID:(id)messageID fd:(int)fd {
    if (!messageID) return; // notification — no response
    NSMutableDictionary *response = [@{@"jsonrpc": @"2.0", @"id": messageID} mutableCopy];
    if (error) response[@"error"] = error;
    else response[@"result"] = result ?: @{};

    NSData *json = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    if (!json) return;
    dispatch_async(self.queue, ^{
        NSMutableData *out = [json mutableCopy];
        [out appendBytes:"\n" length:1];
        const uint8_t *bytes = out.bytes;
        NSUInteger length = out.length, offset = 0;
        while (offset < length) {
            ssize_t written = write(fd, bytes + offset, length - offset);
            if (written <= 0) break;
            offset += (NSUInteger)written;
        }
    });
}

#pragma mark - JSON-RPC dispatch

- (void)handleMessage:(NSDictionary *)message fd:(int)fd {
    NSString *method = [message[@"method"] isKindOfClass:[NSString class]] ? message[@"method"] : nil;
    id messageID = message[@"id"];
    if (!method) return;
    NSDictionary *params = [message[@"params"] isKindOfClass:[NSDictionary class]] ? message[@"params"] : @{};

    if ([method isEqualToString:@"initialize"]) {
        NSString *protocolVersion = [params[@"protocolVersion"] isKindOfClass:[NSString class]]
            ? params[@"protocolVersion"] : @"2024-11-05";
        [self sendResult:@{
            @"protocolVersion": protocolVersion,
            @"capabilities": @{@"tools": @{}},
            @"serverInfo": @{@"name": @"visual-coach", @"version": @"1.0.1"},
        } error:nil forID:messageID fd:fd];
    } else if ([method hasPrefix:@"notifications/"]) {
        // initialized, cancelled, … — nothing to do
    } else if ([method isEqualToString:@"ping"]) {
        [self sendResult:@{} error:nil forID:messageID fd:fd];
    } else if ([method isEqualToString:@"tools/list"]) {
        [self sendResult:@{@"tools": [self toolDefinitions]} error:nil forID:messageID fd:fd];
    } else if ([method isEqualToString:@"tools/call"]) {
        [self handleToolCall:params messageID:messageID fd:fd];
    } else if (messageID) {
        [self sendResult:nil
                   error:@{@"code": @(-32601), @"message": [@"Method not found: " stringByAppendingString:method]}
                   forID:messageID
                      fd:fd];
    }
}

#pragma mark - Tool definitions

- (NSArray *)toolDefinitions {
    NSDictionary *pointSchema = @{
        @"type": @"object",
        @"properties": @{@"x": @{@"type": @"number"}, @"y": @{@"type": @"number"}},
        @"required": @[@"x", @"y"],
    };
    NSDictionary *annotationSchema = @{
        @"type": @"object",
        @"properties": @{
            @"type": @{@"type": @"string", @"enum": @[@"arrow", @"ring", @"highlight", @"label"]},
            @"label": @{@"type": @"string",
                        @"description": @"Short action text. When pointing at visible on-screen text, "
                                         "use that exact text so OCR can snap the position."},
            @"target": pointSchema,
            @"size": pointSchema,
        },
        @"required": @[@"type", @"target"],
    };
    return @[
        @{@"name": @"capture_screen",
          @"description": @"Capture the display under the user's mouse pointer on their Mac, with the "
                           "frontmost application and window title. Call this before show_guidance so "
                           "annotation coordinates refer to the current screen.",
          @"inputSchema": @{@"type": @"object", @"properties": @{}}},
        @{@"name": @"get_marked_region",
          @"description": @"Open a full-screen drawing canvas on the user's Mac and wait for them to "
                           "circle or mark a region (they press Return to confirm, Esc to cancel). "
                           "Returns the marked region as an image. Use when the user wants to show "
                           "you a specific part of their screen. Waits up to 2 minutes.",
          @"inputSchema": @{@"type": @"object", @"properties": @{}}},
        @{@"name": @"show_guidance",
          @"description": @"Draw visual guidance on the user's screen via a transparent, click-through "
                           "overlay: a next-step message card plus optional arrows, rings, highlights, "
                           "and labels. Coordinates are fractions 0-1 of the most recently captured "
                           "screen, origin at the TOP-LEFT. Annotations whose label matches visible "
                           "text are snapped to it via OCR; labeled annotations that cannot be "
                           "verified on screen are dropped. Requires message and/or annotations.",
          @"inputSchema": @{
              @"type": @"object",
              @"properties": @{
                  @"context": @{@"type": @"string", @"description": @"What the user is doing."},
                  @"inferred_goal": @{@"type": @"string", @"description": @"Their likely objective."},
                  @"message": @{@"type": @"string", @"description": @"The recommended next step."},
                  @"annotations": @{@"type": @"array", @"items": annotationSchema},
              },
              @"required": @[@"message"]}},
        @{@"name": @"hide_guidance",
          @"description": @"Hide the guidance overlay on the user's screen.",
          @"inputSchema": @{@"type": @"object", @"properties": @{}}},
    ];
}

#pragma mark - Tool calls

- (void)handleToolCall:(NSDictionary *)params messageID:(id)messageID fd:(int)fd {
    NSString *name = [params[@"name"] isKindOfClass:[NSString class]] ? params[@"name"] : @"";
    NSDictionary *arguments = [params[@"arguments"] isKindOfClass:[NSDictionary class]]
        ? params[@"arguments"] : @{};

    __block BOOL responded = NO;
    __weak typeof(self) weakSelf = self;
    VCToolFinish finish = ^(NSArray<NSDictionary *> *content, BOOL isError) {
        dispatch_async(weakSelf.queue ?: dispatch_get_main_queue(), ^{
            if (responded) return;
            responded = YES;
            [weakSelf sendResult:@{@"content": content ?: @[], @"isError": @(isError)}
                           error:nil
                           forID:messageID
                              fd:fd];
        });
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([name isEqualToString:@"capture_screen"]) {
            [self toolCaptureScreen:finish];
        } else if ([name isEqualToString:@"get_marked_region"]) {
            [self toolGetMarkedRegion:finish];
        } else if ([name isEqualToString:@"show_guidance"]) {
            [self toolShowGuidance:arguments finish:finish];
        } else if ([name isEqualToString:@"hide_guidance"]) {
            [self.overlay hide];
            finish(@[VCTextBlock(@"Guidance hidden.")], NO);
        } else {
            finish(@[VCTextBlock([@"Unknown tool: " stringByAppendingString:name])], YES);
        }
    });
}

- (void)stashSnapshot:(VCScreenSnapshot *)snapshot {
    self.lastSnapshot = snapshot;
    self.lastOCRLines = nil;
    __weak typeof(self) weakSelf = self;
    [VCOCRService recognizeTextInImage:snapshot.image
                            completion:^(NSArray<VCOCRLine *> *lines, NSError *error) {
        weakSelf.lastOCRLines = lines;
    }];
}

- (void)toolCaptureScreen:(VCToolFinish)finish {
    [self.overlay hide]; // clean screenshot
    [VCScreenCapture captureDisplayUnderPointerWithCompletion:^(VCScreenSnapshot *snapshot, NSError *error) {
        if (!snapshot) {
            finish(@[VCTextBlock(error.localizedDescription
                                 ?: @"Screen capture failed. Check Screen Recording permission.")], YES);
            return;
        }
        [self stashSnapshot:snapshot];
        NSString *meta = [NSString stringWithFormat:
                          @"Screenshot of the display under the pointer. Foreground app: %@. Window: %@.",
                          snapshot.appName ?: @"Unknown", snapshot.windowTitle ?: @"Unknown"];
        finish(@[VCTextBlock(meta), VCImageBlock([snapshot pngDataWithMaxDimension:1600])], NO);
    }];
}

- (void)toolGetMarkedRegion:(VCToolFinish)finish {
    if (self.canvas.isActive) {
        finish(@[VCTextBlock(@"A drawing canvas is already open on the user's screen.")], YES);
        return;
    }
    [self.overlay hide]; // clean screenshot before the canvas appears
    [VCScreenCapture captureDisplayUnderPointerWithCompletion:^(VCScreenSnapshot *snapshot, NSError *error) {
        if (!snapshot) {
            finish(@[VCTextBlock(error.localizedDescription
                                 ?: @"Screen capture failed. Check Screen Recording permission.")], YES);
            return;
        }
        [self stashSnapshot:snapshot];

        self.markGeneration += 1;
        NSUInteger generation = self.markGeneration;
        NSScreen *screen = [VCScreenCapture screenForDisplayID:snapshot.displayID] ?: NSScreen.mainScreen;

        [self.canvas beginOnScreen:screen completion:^(BOOL submitted, CGRect region, BOOL hasRegion) {
            if (!submitted) {
                finish(@[VCTextBlock(@"The user cancelled without marking anything.")], NO);
                return;
            }
            if (hasRegion) {
                NSData *crop = [snapshot pngDataForNormalizedRect:region maxDimension:1400];
                if (crop) {
                    NSString *meta = [NSString stringWithFormat:
                        @"Region the user marked in %@ — %@ (normalized, top-left origin: "
                         "x=%.3f y=%.3f w=%.3f h=%.3f).",
                        snapshot.appName ?: @"Unknown", snapshot.windowTitle ?: @"Unknown",
                        region.origin.x, region.origin.y, region.size.width, region.size.height];
                    finish(@[VCTextBlock(meta), VCImageBlock(crop)], NO);
                    return;
                }
            }
            finish(@[VCTextBlock(@"The user confirmed without drawing a mark; full screen attached."),
                     VCImageBlock([snapshot pngDataWithMaxDimension:1600])], NO);
        }];

        // Don't leave the chat hanging forever if the user walks away.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != self.markGeneration || !self.canvas.isActive) return;
            [self.canvas cancel]; // fires the completion; finish() below is a no-op if it won
            finish(@[VCTextBlock(@"Timed out waiting for the user to mark the screen.")], YES);
        });
    }];
}

- (void)toolShowGuidance:(NSDictionary *)arguments finish:(VCToolFinish)finish {
    NSArray *requestedAnnotations = [arguments[@"annotations"] isKindOfClass:[NSArray class]]
        ? arguments[@"annotations"] : @[];
    NSDictionary *payload = @{
        @"context": [arguments[@"context"] isKindOfClass:[NSString class]] ? arguments[@"context"] : @"",
        @"inferred_goal": [arguments[@"inferred_goal"] isKindOfClass:[NSString class]] ? arguments[@"inferred_goal"] : @"",
        @"message": [arguments[@"message"] isKindOfClass:[NSString class]] ? arguments[@"message"] : @"",
        @"annotations": requestedAnnotations,
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    VCCoachingResult *result = json
        ? [VCCoachingResult resultFromModelContent:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]
        : nil;
    if (!result) {
        finish(@[VCTextBlock(@"Nothing to display — provide a message and/or valid annotations "
                              "(coordinates must be within 0-1).")], YES);
        return;
    }

    if (self.lastOCRLines.count) {
        [result groundWithOCRLines:self.lastOCRLines];
    }
    NSScreen *screen = self.lastSnapshot
        ? ([VCScreenCapture screenForDisplayID:self.lastSnapshot.displayID] ?: NSScreen.mainScreen)
        : NSScreen.mainScreen;
    [self.overlay showResult:result onScreen:screen];

    NSString *note = @"";
    if (result.annotations.count < requestedAnnotations.count) {
        note = self.lastOCRLines.count
            ? @" Some annotations were dropped: invalid coordinates, or labels not found on screen by OCR."
            : @" Some annotations had invalid coordinates. Call capture_screen first for OCR grounding.";
    }
    finish(@[VCTextBlock([NSString stringWithFormat:
        @"Guidance shown on the user's screen with %lu of %lu annotations.%@",
        (unsigned long)result.annotations.count,
        (unsigned long)requestedAnnotations.count, note])], NO);
}

- (void)dealloc {
    if (_listenSource) dispatch_source_cancel(_listenSource);
    if (_listenFD >= 0) close(_listenFD);
}

@end
