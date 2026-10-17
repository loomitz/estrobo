#import <Foundation/Foundation.h>
static NSString *mode;
@interface RejectProtocol : NSURLProtocol
@end
@implementation RejectProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { fprintf(stderr,"protocol-request %s\n", request.URL.absoluteString.UTF8String); return YES; }
+ (BOOL)canInitWithTask:(NSURLSessionTask *)task { fprintf(stderr,"protocol-task\n"); return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading { fprintf(stderr,"protocol-start\n"); [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:nil]]; }
- (void)stopLoading {}
@end
@interface InjectCache : NSURLCache
@end
@implementation InjectCache
- (NSCachedURLResponse *)injection:(NSURLRequest *)request { NSData *body=[@"CACHE_INJECTION" dataUsingEncoding:NSUTF8StringEncoding]; NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Cache-Control":@"max-age=3600",@"Content-Length":@"15"}]; return [[NSCachedURLResponse alloc] initWithResponse:response data:body]; }
- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request { fprintf(stderr,"cache-request policy=%lu\n",(unsigned long)request.cachePolicy); return [self injection:request]; }
- (void)getCachedResponseForDataTask:(NSURLSessionDataTask *)task completionHandler:(void (^)(NSCachedURLResponse *))completionHandler { fprintf(stderr,"cache-task policy=%lu\n", (unsigned long)task.currentRequest.cachePolicy); completionHandler([self injection:task.currentRequest]); }
@end
int main(int argc, const char *argv[]) { @autoreleasepool { mode=[NSString stringWithUTF8String:argv[1]]; NSURL *url=[NSURL URLWithString:[NSString stringWithUTF8String:argv[2]]];
 if ([mode containsString:@"protocol"]) [NSURLProtocol registerClass:RejectProtocol.class];
 if ([mode containsString:@"cache"]) NSURLCache.sharedURLCache=[[InjectCache alloc] initWithMemoryCapacity:256*1024*1024 diskCapacity:0 diskPath:nil];
 NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.defaultSessionConfiguration;
 if ([mode isEqualToString:@"explicit-protocol"]) configuration.protocolClasses=@[RejectProtocol.class];
 NSURLSession *session=[mode isEqualToString:@"shared-protocol"] ? NSURLSession.sharedSession : [NSURLSession sessionWithConfiguration:configuration];
 NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url]; request.cachePolicy=[mode isEqualToString:@"cache-only"] ? NSURLRequestReturnCacheDataDontLoad : NSURLRequestReloadIgnoringLocalCacheData;
 __block BOOL done=NO;
 [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){ fprintf(stderr,"result body=%s error=%ld\n",[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String], (long)error.code); done=YES; }] resume];
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
 while(!done && [deadline timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
 return done ? 0 : 2;
} }
