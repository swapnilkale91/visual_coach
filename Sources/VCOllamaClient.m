#import "VCOllamaClient.h"

// Local Ollama only — no cloud model integration.
static NSString * const kVCOllamaEndpoint = @"http://127.0.0.1:11434/api/chat";
static NSString * const kVCOllamaModel = @"gemma4";

@implementation VCOllamaClient

+ (void)sendChatWithSystemPrompt:(NSString *)systemPrompt
                      userPrompt:(NSString *)userPrompt
                        imagePNG:(NSData *)imagePNG
                      completion:(void (^)(NSString *, NSError *))completion {
    void (^finish)(NSString *, NSError *) = ^(NSString *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(content, error); });
    };

    NSDictionary *payload = @{
        @"model": kVCOllamaModel,
        @"stream": @NO,
        @"format": @"json",
        @"options": @{ @"temperature": @0.2 },
        @"messages": @[
            @{ @"role": @"system", @"content": systemPrompt },
            @{ @"role": @"user",
               @"content": userPrompt,
               @"images": @[ [imagePNG base64EncodedStringWithOptions:0] ] },
        ],
    };

    NSError *jsonError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (!body) {
        finish(nil, jsonError);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kVCOllamaEndpoint]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    request.timeoutInterval = 180;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data) {
            finish(nil, error ?: [NSError errorWithDomain:@"VisualCoach" code:20 userInfo:@{
                NSLocalizedDescriptionKey: @"No response from Ollama. Is it running on 127.0.0.1:11434?"
            }]);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *content = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSDictionary *message = json[@"message"];
            if ([message isKindOfClass:[NSDictionary class]] &&
                [message[@"content"] isKindOfClass:[NSString class]]) {
                content = message[@"content"];
            }
        }

        if (content.length == 0) {
            NSString *detail = [json[@"error"] isKindOfClass:[NSString class]]
                ? json[@"error"]
                : @"Empty response from Ollama.";
            finish(nil, [NSError errorWithDomain:@"VisualCoach" code:21 userInfo:@{
                NSLocalizedDescriptionKey: detail
            }]);
            return;
        }
        finish(content, nil);
    }];
    [task resume];
}

@end
