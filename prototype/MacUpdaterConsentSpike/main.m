// Isolated mechanism experiment. Never linked to Estrobo or its radio session.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

static NSString *root;
static void Log(NSString *event) {
    NSString *line = [NSString stringWithFormat:@"%@ pid=%d build=%@ %@\n", NSDate.date, NSProcessInfo.processInfo.processIdentifier, [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"], event];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:[root stringByAppendingPathComponent:@"events.log"]];
    [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [file closeFile];
}

// Diagnostic only: a globally registered, public protocol rejects a forbidden
// origin. Sparkle's internally created default session does not consult it.
@interface RejectUnexpectedOriginProtocol : NSURLProtocol
@end
@implementation RejectUnexpectedOriginProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    Log([@"global-protocol-consulted " stringByAppendingString:request.URL.absoluteString]);
    return [request.URL.host isEqualToString:@"localhost"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    Log(@"global-protocol-rejected-forbidden-origin");
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:nil]];
}
- (void)stopLoading {}
@end

@interface Spike : NSObject <NSApplicationDelegate, SPUUpdaterDelegate, SPUUserDriver>
@property(nonatomic, strong) SPUUpdater *updater;
@property(nonatomic, strong) NSTimer *commandTimer;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSString *lastCommand;
@property(nonatomic, strong) NSURLSessionDownloadTask *cacheTask;
@property(nonatomic, copy) void (^readyReply)(SPUUserUpdateChoice);
@property(nonatomic, copy) void (^downloadCancellation)(void);
@property(nonatomic) BOOL confirmed;
@property(nonatomic) BOOL baseline;
@property(nonatomic) BOOL blocked;
@property(nonatomic) BOOL holdAtReady;
@property(nonatomic, copy) NSString *readyAction;
@property(nonatomic) BOOL pendingTermination;
@property(nonatomic) BOOL ordinaryQuitAfterCancellation;
@end
@implementation Spike
- (NSURL *)archiveURL { return [NSURL URLWithString:[NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@"offer.plist"]][@"url"]]; }
- (BOOL)identityMatches:(SUAppcastItem *)item {
    NSDictionary *offer = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@"offer.plist"]];
    NSDictionary *enclosure = item.propertiesDictionary[@"enclosure"];
    return [item.versionString isEqualToString:offer[@"build"]] && [item.fileURL.absoluteString isEqualToString:offer[@"url"]] && item.contentLength == [offer[@"length"] unsignedLongLongValue] && [enclosure[@"sparkle:edSignature"] isEqualToString:offer[@"signature"]] && item.signingValidationStatus == SPUAppcastSigningValidationStatusSucceeded;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.baseline = [[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"mode"] encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"baseline"];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,500,220) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed = NO;
    self.window.title = @"Isolated Sparkle consent fixture";
    [self.window makeKeyAndOrderFront:nil];
    self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:self delegate:self];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) Log([NSString stringWithFormat:@"start-error %@",error]);
    self.lastCommand=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"command"] encoding:NSUTF8StringEncoding error:NULL];
    Log(@"launched");
    self.commandTimer=[NSTimer timerWithTimeInterval:0.05 target:self selector:@selector(poll:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.commandTimer forMode:NSRunLoopCommonModes];
    [NSRunLoop.mainRunLoop addTimer:self.commandTimer forMode:NSModalPanelRunLoopMode];
}
- (void)downloadArchive {
    [NSFileManager.defaultManager removeItemAtPath:[root stringByAppendingPathComponent:@"cache.dmg"] error:NULL];
    self.cacheTask = [NSURLSession.sharedSession downloadTaskWithURL:self.archiveURL completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error != nil) { dispatch_async(dispatch_get_main_queue(), ^{ Log(@"cache-download-cancelled-or-failed"); }); return; }
        NSError *moveError = nil;
        [NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"cache.dmg"]] error:&moveError];
        dispatch_async(dispatch_get_main_queue(), ^{ Log(moveError == nil ? @"cache-complete-without-consent" : @"cache-write-failed"); });
    }];
    [self.cacheTask resume];
    Log(@"cache-download-started");
}
- (BOOL)populateCache {
    NSData *bytes = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"cache.dmg"] options:NSDataReadingMappedIfSafe error:NULL];
    if (bytes == nil) { Log(@"cache-missing"); return NO; }
    // A new, bounded cache avoids dependence on unrelated app traffic or default item limits.
    // The file remains on disk across process launches. Only the approved attempt is primed.
    [NSURLCache setSharedURLCache:[[NSURLCache alloc] initWithMemoryCapacity:MAX(32*bytes.length, 256*1024*1024) diskCapacity:0 diskPath:nil]];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.archiveURL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Length":[NSString stringWithFormat:@"%lu",(unsigned long)bytes.length],@"Content-Type":@"application/octet-stream",@"Cache-Control":@"private, max-age=3600",@"Content-Disposition":@"attachment; filename=update.dmg"}];
    [NSURLCache.sharedURLCache storeCachedResponse:[[NSCachedURLResponse alloc] initWithResponse:response data:bytes] forRequest:[NSURLRequest requestWithURL:self.archiveURL]];
    BOOL cached = [NSURLCache.sharedURLCache cachedResponseForRequest:[NSURLRequest requestWithURL:self.archiveURL]] != nil;
    Log([NSString stringWithFormat:@"cache-primed bytes=%lu lookup=%@",(unsigned long)bytes.length,cached ? @"YES" : @"NO"]);
    return cached;
}
- (void)cancelAttempt {
    self.confirmed = NO;
    [self.cacheTask cancel];
    if (self.readyReply != nil) { void (^reply)(SPUUserUpdateChoice) = self.readyReply; self.readyReply = nil; reply(SPUUserUpdateChoiceSkip); }
    else if (self.downloadCancellation != nil) { self.downloadCancellation(); self.downloadCancellation = nil; }
    else if (self.pendingTermination && !self.updater.sessionInProgress) { self.pendingTermination=NO; [NSApp replyToApplicationShouldTerminate:NO]; }
    Log(@"consent-cancelled");
}
- (void)poll:(NSTimer *)timer {
    NSString *command = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"command"] encoding:NSUTF8StringEncoding error:NULL];
    if (command == nil || [command isEqualToString:self.lastCommand]) return;
    self.lastCommand = command;
    NSString *action = [command componentsSeparatedByString:@" "].lastObject;
    Log([@"command " stringByAppendingString:action]);
    if ([action isEqualToString:@"download"]) { if (self.baseline) [self.updater checkForUpdates]; else [self downloadArchive]; }
    if ([action hasPrefix:@"confirm"]) {
        self.holdAtReady = [action isEqualToString:@"confirm-hold"] || [action isEqualToString:@"confirm-cancel"] || [action isEqualToString:@"confirm-block"] || [action isEqualToString:@"confirm-quit"];
        self.readyAction = action;
        if ([self populateCache]) { if ([action isEqualToString:@"confirm-evict"]) [NSURLCache.sharedURLCache removeAllCachedResponses];
            self.confirmed=YES; Log(@"confirmed-specific-offer"); [NSApp terminate:nil]; }
    }
    if ([action isEqualToString:@"cancel"]) [self cancelAttempt];
    if ([action isEqualToString:@"block"]) { self.blocked=YES; if (self.pendingTermination) [self cancelAttempt]; Log(@"blocked"); }
    if ([action isEqualToString:@"unblock"]) { self.blocked=NO; Log(@"unblocked"); }
    if ([action isEqualToString:@"evict"]) { [NSURLCache.sharedURLCache removeAllCachedResponses]; Log(@"cache-evicted"); }
    if ([action isEqualToString:@"continue"]) {
        self.holdAtReady=NO;
        if (self.readyReply != nil) { void (^reply)(SPUUserUpdateChoice)=self.readyReply; self.readyReply=nil; reply(self.confirmed && !self.blocked ? SPUUserUpdateChoiceInstall : SPUUserUpdateChoiceSkip); }
    }
    if ([action isEqualToString:@"quit"]) {
        if (self.pendingTermination) { self.ordinaryQuitAfterCancellation=YES; [self cancelAttempt]; }
        else { self.confirmed=NO; [NSApp terminate:nil]; }
    }
    if ([action isEqualToString:@"last-window"]) [self.window performClose:nil];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { Log(@"last-window-closed"); return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.blocked) { self.confirmed=NO; [self.window makeKeyAndOrderFront:nil]; Log(@"appkit-veto-consent-invalidated"); return NSTerminateCancel; }
    if (self.confirmed && !self.baseline) {
        // Ask AppKit's normal close gate BEFORE Sparkle prepares an installer. Hold the
        // accepted termination while Sparkle validates/prepares the approved archive.
        self.pendingTermination=YES;
        dispatch_async(dispatch_get_main_queue(), ^{ [self.updater checkForUpdates]; });
        Log(@"appkit-termination-deferred"); return NSTerminateLater;
    }
    Log(@"ordinary-termination-allowed"); return NSTerminateNow;
}
- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(SUAppcastItem *)item updateCheck:(SPUUpdateCheck)check error:(NSError *__autoreleasing *)error {
    if ([self identityMatches:item] && (self.baseline || (self.confirmed && !self.blocked))) { Log(@"fresh-signed-offer-matches"); return YES; }
    *error=[NSError errorWithDomain:@"ConsentSpike" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Confirmed signed offer changed or consent became invalid."}];
    self.confirmed=NO; Log(@"fresh-offer-rejected"); return NO;
}
- (void)updater:(SPUUpdater *)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request {
    if (!self.baseline) {
        request.cachePolicy=NSURLRequestReturnCacheDataDontLoad;
        Log([NSString stringWithFormat:@"strict-cache-only lookup=%@", [NSURLCache.sharedURLCache cachedResponseForRequest:request] != nil ? @"YES" : @"NO"]);
    }
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply { reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation { Log(@"checking"); }
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { Log(@"offer-found"); reply(self.baseline || self.confirmed ? SPUUserUpdateChoiceInstall : SPUUserUpdateChoiceDismiss); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement { Log([NSString stringWithFormat:@"no-update %@",error]); acknowledgement(); }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement { Log([NSString stringWithFormat:@"error %@",error]); acknowledgement(); }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation { self.downloadCancellation=cancellation; Log(@"sparkle-cache-copy-started"); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { self.downloadCancellation=nil; Log(@"extracting-after-consent"); }
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {
    if (self.baseline) { Log(@"prepared-without-consent"); return; }
    if (!self.confirmed || self.blocked) { Log(@"cancel-prepared-installer"); reply(SPUUserUpdateChoiceSkip); }
    else if (self.holdAtReady) {
        self.readyReply=reply; Log(@"ready-held-after-consent");
        // AppKit's pending termination changes the runloop mode. Schedule the
        // test's next public action from the actual ready callback, never from
        // forced process cleanup or synthetic Sparkle lifecycle events.
        if (![self.readyAction isEqualToString:@"confirm-hold"]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if ([self.readyAction isEqualToString:@"confirm-block"]) { self.blocked=YES; Log(@"new-unsafe-work"); }
            if ([self.readyAction isEqualToString:@"confirm-quit"]) { self.ordinaryQuitAfterCancellation=YES; Log(@"ordinary-quit-requested-during-preparation"); }
            [self cancelAttempt];
        });
    }
    else { Log(@"ready-after-consent"); reply(SPUUserUpdateChoiceInstall); }
}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {
    Log(@"installing-approved-offer");
    if (self.pendingTermination) { self.pendingTermination=NO; [NSApp replyToApplicationShouldTerminate:YES]; }
}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { Log(@"installed"); acknowledgement(); }
- (void)dismissUpdateInstallation {
    self.readyReply=nil; self.downloadCancellation=nil;
    if (self.pendingTermination) { self.pendingTermination=NO; [NSApp replyToApplicationShouldTerminate:self.ordinaryQuitAfterCancellation]; }
    self.confirmed=NO; self.ordinaryQuitAfterCancellation=NO;
    if (!self.window.visible) [self.window makeKeyAndOrderFront:nil];
    Log(@"attempt-dismissed-window-restored");
}
@end
int main(int argc, const char *argv[]) { @autoreleasepool {
    root = argc == 2 ? [NSString stringWithUTF8String:argv[1]] : [NSBundle.mainBundle objectForInfoDictionaryKey:@"ConsentSpikeRoot"];
    if (root == nil) return 64;
    if ([[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"mode"] encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"redirect"]) [NSURLProtocol registerClass:RejectUnexpectedOriginProtocol.class];
    [NSApplication sharedApplication];
    Spike *delegate = [Spike new]; NSApp.delegate=delegate;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp run];
} return 0; }
