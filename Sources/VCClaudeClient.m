#import "VCClaudeClient.h"
#import <Security/Security.h>

static NSString * const kVCClaudeEndpoint = @"https://api.anthropic.com/v1/messages";
static NSString * const kVCClaudeModel = @"claude-opus-4-8";
static NSString * const kVCKeychainService = @"local.codex.visualcoach.agent";
static NSString * const kVCKeychainAccount = @"anthropic-api-key";

@implementation VCClaudeClient

#pragma mark - API key (Keychain)

+ (NSDictionary *)keychainQuery {
    return @{
        (__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrService: kVCKeychainService,
        (__bridge NSString *)kSecAttrAccount: kVCKeychainAccount,
    };
}

+ (NSString *)storedAPIKey {
    NSMutableDictionary *query = [[self keychainQuery] mutableCopy];
    query[(__bridge NSString *)kSecReturnData] = @YES;
    query[(__bridge NSString *)kSecMatchLimit] = (__bridge NSString *)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == errSecSuccess && result) {
        NSString *key = [[NSString alloc] initWithData:CFBridgingRelease(result)
                                              encoding:NSUTF8StringEncoding];
        if (key.length) return key;
    }
    const char *env = getenv("ANTHROPIC_API_KEY");
    return env ? [NSString stringWithUTF8String:env] : nil;
}

+ (BOOL)saveAPIKey:(NSString *)key {
    SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
    if (key.length == 0) return YES;

    NSMutableDictionary *attributes = [[self keychainQuery] mutableCopy];
    attributes[(__bridge NSString *)kSecValueData] = [key dataUsingEncoding:NSUTF8StringEncoding];
    return SecItemAdd((__bridge CFDictionaryRef)attributes, NULL) == errSecSuccess;
}

#pragma mark - Structured output schema

/// Mirrors the guidance JSON the overlay renders; enforced server-side so the
/// response is always valid JSON of this shape.
+ (NSDictionary *)guidanceSchema {
    NSDictionary *point = @{
        @"type": @"object",
        @"additionalProperties": @NO,
        @"required": @[@"x", @"y"],
        @"properties": @{@"x": @{@"type": @"number"}, @"y": @{@"type": @"number"}},
    };
    NSDictionary *annotation = @{
        @"type": @"object",
        @"additionalProperties": @NO,
        @"required": @[@"type", @"label", @"target"],
        @"properties": @{
            @"type": @{@"type": @"string", @"enum": @[@"arrow", @"ring", @"highlight", @"label"]},
            @"label": @{@"type": @"string"},
            @"target": point,
            @"size": point,
        },
    };
    return @{
        @"type": @"object",
        @"additionalProperties": @NO,
        @"required": @[@"context", @"inferred_goal", @"message", @"annotations"],
        @"properties": @{
            @"context": @{@"type": @"string"},
            @"inferred_goal": @{@"type": @"string"},
            @"message": @{@"type": @"string"},
            @"annotations": @{@"type": @"array", @"items": annotation},
        },
    };
}

#pragma mark - Request

+ (void)sendChatWithSystemPrompt:(NSString *)systemPrompt
                         history:(NSArray<NSDictionary *> *)history
                      userPrompt:(NSString *)userPrompt
                        imagePNG:(NSData *)imagePNG
                      completion:(void (^)(NSString *, NSError *))completion {
    void (^finish)(NSString *, NSError *) = ^(NSString *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(content, error); });
    };

    NSString *apiKey = [self storedAPIKey];
    if (apiKey.length == 0) {
        finish(nil, [NSError errorWithDomain:@"VisualCoach" code:30 userInfo:@{
            NSLocalizedDescriptionKey: @"No Claude API key. Use the menu: Set Claude API Key…"
        }]);
        return;
    }

    NSMutableArray *messages = [NSMutableArray arrayWithArray:history ?: @[]];
    [messages addObject:@{
        @"role": @"user",
        @"content": @[
            @{@"type": @"image",
              @"source": @{@"type": @"base64",
                           @"media_type": @"image/png",
                           @"data": [imagePNG base64EncodedStringWithOptions:0]}},
            @{@"type": @"text", @"text": userPrompt},
        ],
    }];

    NSDictionary *payload = @{
        @"model": kVCClaudeModel,
        @"max_tokens": @2048,
        @"system": systemPrompt,
        @"messages": messages,
        @"output_config": @{@"format": @{@"type": @"json_schema", @"schema": [self guidanceSchema]}},
    };

    NSError *jsonError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (!body) {
        finish(nil, jsonError);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kVCClaudeEndpoint]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    request.timeoutInterval = 120;
    [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    [request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data) {
            finish(nil, error ?: [NSError errorWithDomain:@"VisualCoach" code:31 userInfo:@{
                NSLocalizedDescriptionKey: @"No response from the Claude API."
            }]);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            finish(nil, [NSError errorWithDomain:@"VisualCoach" code:32 userInfo:@{
                NSLocalizedDescriptionKey: @"Unreadable response from the Claude API."
            }]);
            return;
        }

        if ([json[@"type"] isEqual:@"error"]) {
            NSDictionary *apiError = [json[@"error"] isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
            NSString *message = [apiError[@"message"] isKindOfClass:[NSString class]]
                ? apiError[@"message"] : @"Claude API error.";
            finish(nil, [NSError errorWithDomain:@"VisualCoach" code:33 userInfo:@{
                NSLocalizedDescriptionKey: message
            }]);
            return;
        }

        if ([json[@"stop_reason"] isEqual:@"refusal"]) {
            finish(nil, [NSError errorWithDomain:@"VisualCoach" code:34 userInfo:@{
                NSLocalizedDescriptionKey: @"Claude declined to analyze this screen."
            }]);
            return;
        }

        NSString *text = nil;
        for (id block in ([json[@"content"] isKindOfClass:[NSArray class]] ? json[@"content"] : @[])) {
            if ([block isKindOfClass:[NSDictionary class]] &&
                [block[@"type"] isEqual:@"text"] &&
                [block[@"text"] isKindOfClass:[NSString class]]) {
                text = block[@"text"];
                break;
            }
        }
        if (text.length == 0) {
            finish(nil, [NSError errorWithDomain:@"VisualCoach" code:35 userInfo:@{
                NSLocalizedDescriptionKey: @"Empty response from the Claude API."
            }]);
            return;
        }
        finish(text, nil);
    }];
    [task resume];
}

@end
