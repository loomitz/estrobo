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
@property(nonatomic) BOOL interactive;
@property(nonatomic) BOOL preflighting;
@property(nonatomic) BOOL commitRequested;
@property(nonatomic) BOOL committing;
@property(nonatomic) BOOL vetoClose;
@property(nonatomic) NSUInteger uiSnapshotNumber;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *buttons;
@property(nonatomic, strong) NSTextField *statusLabel;
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
- (void)buildInteractiveControls {
    self.window.title=@"Isolated Sparkle consent — real AppKit events";
    self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self.window.contentView.wantsLayer=YES;
    self.window.contentView.layer.backgroundColor=[NSColor colorWithSRGBRed:0.96 green:0.96 blue:0.97 alpha:1].CGColor;
    [self.window setContentSize:NSMakeSize(640,450)];
    self.buttons=[NSMutableDictionary new];
    self.statusLabel=[NSTextField labelWithString:[NSString stringWithFormat:@"Build %@ · Downloading never authorizes installation",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]]];
    self.statusLabel.textColor=NSColor.blackColor;
    self.statusLabel.frame=NSMakeRect(24,390,590,42);
    self.statusLabel.accessibilityIdentifier=@"consent-status";
    [self.window.contentView addSubview:self.statusLabel];
    NSArray *items=@[@[@"download",@"Download update"],@[@"confirm-hold",@"Install and restart (pause)"],@[@"cancel",@"Cancel installation"],@[@"continue",@"Continue approved install"],@[@"block",@"Block AppKit close"],@[@"unblock",@"Resolve close blocker"],@[@"confirm",@"Install and restart"],@[@"quit",@"Quit normally"],@[@"last-window",@"Close last window"],@[@"veto",@"Veto next AppKit quit"],@[@"confirm-evict",@"Install with cache evicted"]];
    for (NSUInteger index=0;index<items.count;index++) {
        NSString *identifier=items[index][0];
        NSButton *button=[NSButton buttonWithTitle:items[index][1] target:self action:@selector(buttonPressed:)];
        button.frame=NSMakeRect(24+(index%3)*204,320-(index/3)*72,194,44);
        button.attributedTitle=[[NSAttributedString alloc] initWithString:items[index][1] attributes:@{NSForegroundColorAttributeName:NSColor.blackColor,NSFontAttributeName:[NSFont systemFontOfSize:13]}];
        button.identifier=identifier; button.accessibilityIdentifier=identifier;
        button.accessibilityLabel=items[index][1];
        if ([identifier isEqualToString:@"cancel"]) button.keyEquivalent=@"\033";
        [self.window.contentView addSubview:button]; self.buttons[identifier]=button;
    }
    NSMenu *menu=[NSMenu new]; NSMenuItem *applicationItem=[NSMenuItem new]; [menu addItem:applicationItem];
    NSMenu *applicationMenu=[NSMenu new];
    NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@"Quit ConsentSpike" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target=NSApp; [applicationMenu addItem:quit]; applicationItem.submenu=applicationMenu; NSApp.mainMenu=menu;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp activateIgnoringOtherApps:YES];
    Log(@"ui-controls-ready"); [self presentStatus:@"Download is separate from installation consent" snapshot:@"controls"];
}
- (void)presentStatus:(NSString *)text snapshot:(NSString *)stage {
    if (!self.interactive) return;
    self.statusLabel.stringValue=[NSString stringWithFormat:@"Build %@ · %@",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"],text];
    self.buttons[@"cancel"].enabled=!self.committing;
    BOOL transferring=self.cacheTask != nil && self.cacheTask.state == NSURLSessionTaskStateRunning;
    self.buttons[@"download"].enabled=!transferring && !self.confirmed && !self.committing && !self.updater.sessionInProgress;
    self.buttons[@"block"].enabled=!self.committing;
    self.buttons[@"continue"].enabled=self.readyReply != nil && self.confirmed && !self.committing;
    self.buttons[@"confirm"].enabled=!transferring && !self.confirmed && !self.committing && !self.updater.sessionInProgress;
    self.buttons[@"confirm-hold"].enabled=self.buttons[@"confirm"].enabled;
    self.buttons[@"confirm-evict"].enabled=self.buttons[@"confirm"].enabled;
    NSString *directory=[root stringByAppendingPathComponent:@"ui"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableDictionary *controls=[NSMutableDictionary new];
    for (NSString *identifier in self.buttons) { NSButton *button=self.buttons[identifier]; controls[identifier]=@{@"title":button.title,@"enabled":@(button.enabled),@"accessibilityIdentifier":button.accessibilityIdentifier}; }
    NSDictionary *snapshot=@{@"status":self.statusLabel.stringValue,@"stage":stage,@"controls":controls};
    NSData *json=[NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *name=[NSString stringWithFormat:@"%d-%04lu-%@",NSProcessInfo.processInfo.processIdentifier,(unsigned long)++self.uiSnapshotNumber,stage];
    [json writeToFile:[[directory stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"json"] atomically:YES];
    [self.window displayIfNeeded];
    NSView *view=self.window.contentView;
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[[directory stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"] atomically:YES];
}
- (void)requestCommit {
    if (self.interactive && self.confirmed && self.readyReply != nil && !self.committing) {
        self.commitRequested=YES; [NSApp terminate:nil];
    }
}
- (void)finishOrdinaryQuit { if (!self.confirmed && !self.blocked && !self.vetoClose && !self.updater.sessionInProgress) { self.ordinaryQuitAfterCancellation=NO; [NSApp terminate:nil]; } }
- (void)buttonPressed:(NSButton *)button { Log([@"ui-action " stringByAppendingString:button.identifier]); [self handleAction:button.identifier]; }
- (void)queueMouseClick:(NSString *)identifier {
    NSButton *button=[identifier isEqualToString:@"window-close"] ? [self.window standardWindowButton:NSWindowCloseButton] : self.buttons[identifier];
    if (button == nil || !button.enabled) { Log([@"ui-control-unavailable " stringByAppendingString:identifier]); return; }
    NSPoint point=[button convertPoint:NSMakePoint(NSMidX(button.bounds),NSMidY(button.bounds)) toView:nil];
    for (NSNumber *kind in @[@(NSEventTypeLeftMouseDown),@(NSEventTypeLeftMouseUp)]) {
        NSEvent *event=[NSEvent mouseEventWithType:kind.unsignedIntegerValue location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
        [NSApp postEvent:event atStart:NO];
    }
    Log([@"ui-mouse-events-queued " stringByAppendingString:identifier]);
}
- (void)queueQuitKey {
    NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil characters:@"q" charactersIgnoringModifiers:@"q" isARepeat:NO keyCode:12];
    [NSApp postEvent:event atStart:NO]; Log(@"ui-command-q-event-queued");
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.baseline = [[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"mode"] encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"baseline"];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,500,220) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.interactive = [[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"mode"] encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"ui"];
    self.window.releasedWhenClosed = NO;
    self.window.title = @"Isolated Sparkle consent fixture";
    if (self.interactive) [self buildInteractiveControls];
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
        if (error != nil) { dispatch_async(dispatch_get_main_queue(), ^{ Log(@"cache-download-cancelled-or-failed"); [self presentStatus:@"Download cancelled or failed; no installation approved" snapshot:@"transfer-cancelled"]; }); return; }
        NSError *moveError = nil;
        [NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"cache.dmg"]] error:&moveError];
        dispatch_async(dispatch_get_main_queue(), ^{ Log(moveError == nil ? @"cache-complete-without-consent" : @"cache-write-failed"); [self presentStatus:moveError == nil ? @"Download completed; explicit installation confirmation required" : @"Download could not be saved" snapshot:@"downloaded"]; });
    }];
    [self.cacheTask resume];
    Log(@"cache-download-started"); [self presentStatus:@"Downloading; cancellation remains available" snapshot:@"downloading"];
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
    if (self.interactive && self.committing) { Log(@"commit-already-accepted"); return; }
    self.confirmed = NO; self.preflighting=NO; self.commitRequested=NO;
    [self.cacheTask cancel];
    if (self.readyReply != nil) { void (^reply)(SPUUserUpdateChoice) = self.readyReply; self.readyReply = nil; reply(SPUUserUpdateChoiceSkip); }
    else if (self.downloadCancellation != nil) { self.downloadCancellation(); self.downloadCancellation = nil; }
    else if (self.pendingTermination && !self.updater.sessionInProgress) { self.pendingTermination=NO; [NSApp replyToApplicationShouldTerminate:NO]; }
    Log(@"consent-cancelled"); [self presentStatus:@"Cancelled; installation requires a new confirmation" snapshot:@"cancelled"];
}
- (void)poll:(NSTimer *)timer {
    NSString *command = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"command"] encoding:NSUTF8StringEncoding error:NULL];
    if (command == nil || [command isEqualToString:self.lastCommand]) return;
    self.lastCommand = command;
    NSString *action = [command componentsSeparatedByString:@" "].lastObject;
    Log([@"command " stringByAppendingString:action]);
    if ([action hasPrefix:@"mouse:"]) { [self queueMouseClick:[action substringFromIndex:6]]; return; }
    if ([action isEqualToString:@"key:quit"]) { [self queueQuitKey]; return; }
    [self handleAction:action];
}
- (void)handleAction:(NSString *)action {
    if ([action isEqualToString:@"download"]) { if (self.baseline) [self.updater checkForUpdates]; else [self downloadArchive]; }
    if ([action hasPrefix:@"confirm"]) {
        if (self.interactive && (self.confirmed || self.committing || self.updater.sessionInProgress)) { Log(@"duplicate-confirmation-ignored"); return; }
        self.holdAtReady = [action isEqualToString:@"confirm-hold"] || [action isEqualToString:@"confirm-cancel"] || [action isEqualToString:@"confirm-block"] || [action isEqualToString:@"confirm-quit"];
        self.readyAction = action;
        if ([self populateCache]) { if ([action isEqualToString:@"confirm-evict"]) [NSURLCache.sharedURLCache removeAllCachedResponses];
            self.confirmed=YES; self.preflighting=self.interactive; Log(@"confirmed-specific-offer"); [NSApp terminate:nil]; }
    }
    if ([action isEqualToString:@"cancel"]) [self cancelAttempt];
    if ([action isEqualToString:@"block"]) { if (self.interactive && self.committing) { Log(@"new-work-rejected-during-commit"); return; } self.blocked=YES; if (self.pendingTermination || (self.interactive && self.confirmed)) [self cancelAttempt]; Log(@"blocked"); [self presentStatus:@"New unsafe work blocks installation" snapshot:@"blocked"]; }
    if ([action isEqualToString:@"unblock"]) { self.blocked=NO; self.vetoClose=NO; Log(@"unblocked"); [self presentStatus:@"Close blocker resolved; confirm again to install" snapshot:@"unblocked"]; }
    if ([action isEqualToString:@"veto"]) { self.vetoClose=YES; Log(@"appkit-veto-armed"); [self presentStatus:@"The next AppKit close will be vetoed" snapshot:@"veto-armed"]; }
    if ([action isEqualToString:@"evict"]) { [NSURLCache.sharedURLCache removeAllCachedResponses]; Log(@"cache-evicted"); }
    if ([action isEqualToString:@"continue"]) {
        self.holdAtReady=NO;
        if (self.interactive) { [self requestCommit]; return; }
        if (self.readyReply != nil) { void (^reply)(SPUUserUpdateChoice)=self.readyReply; self.readyReply=nil; reply(self.confirmed && !self.blocked ? SPUUserUpdateChoiceInstall : SPUUserUpdateChoiceSkip); }
    }
    if ([action isEqualToString:@"quit"]) {
        if (self.interactive) { [NSApp terminate:nil]; return; }
        if (self.pendingTermination) { self.ordinaryQuitAfterCancellation=YES; [self cancelAttempt]; }
        else { self.confirmed=NO; [NSApp terminate:nil]; }
    }
    if ([action isEqualToString:@"last-window"]) [self.window performClose:nil];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { Log(@"last-window-closed"); return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.interactive) {
        if (self.blocked || self.vetoClose) {
            [self cancelAttempt]; [self.window makeKeyAndOrderFront:nil];
            Log(@"appkit-veto-consent-invalidated"); [self presentStatus:@"AppKit vetoed closing; window restored, consent invalidated" snapshot:@"vetoed"];
            return NSTerminateCancel;
        }
        if (self.preflighting) {
            self.preflighting=NO;
            // A real AppKit preflight evaluates the close gate but deliberately
            // cancels termination, leaving normal input available while preparing.
            dispatch_async(dispatch_get_main_queue(), ^{ if (self.confirmed && !self.blocked) [self.updater checkForUpdates]; });
            Log(@"appkit-preflight-accepted-termination-cancelled"); [self presentStatus:@"Preparing approved update; Cancel remains available" snapshot:@"preparing"];
            return NSTerminateCancel;
        }
        if (self.commitRequested && self.confirmed && self.readyReply != nil) {
            void (^reply)(SPUUserUpdateChoice)=self.readyReply; self.readyReply=nil;
            self.commitRequested=NO; self.committing=YES; self.pendingTermination=YES;
            // Only this accepted final commitment enters terminateLater. The
            // retained ready reply is consumed once, after the real AppKit veto.
            dispatch_async(dispatch_get_main_queue(), ^{ reply(SPUUserUpdateChoiceInstall); });
            Log(@"appkit-final-commit-accepted"); [self presentStatus:@"Installing the explicitly approved update" snapshot:@"committing"];
            return NSTerminateLater;
        }
        if (self.readyReply != nil || self.confirmed || self.updater.sessionInProgress) {
            self.ordinaryQuitAfterCancellation=YES; [self cancelAttempt];
            [self.window makeKeyAndOrderFront:nil]; Log(@"ordinary-quit-awaits-installer-cancellation");
            return NSTerminateCancel;
        }
        Log(@"ordinary-termination-allowed"); return NSTerminateNow;
    }
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
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error {
    if (self.interactive) { Log(@"ui-cycle-finished"); [self presentStatus:error == nil ? @"Ready for a new explicit installation confirmation" : @"Update attempt failed; review and retry explicitly" snapshot:@"cycle-finished"]; if (self.ordinaryQuitAfterCancellation) [self performSelector:@selector(finishOrdinaryQuit) withObject:nil afterDelay:0]; }
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
    if (self.interactive) {
        if (!self.confirmed || self.blocked) { Log(@"cancel-prepared-installer"); reply(SPUUserUpdateChoiceSkip); }
        else {
            self.readyReply=reply;
            Log(self.holdAtReady ? @"ready-held-after-consent" : @"ready-after-consent");
            [self presentStatus:@"Approved update prepared; Cancel is still usable" snapshot:@"ready"];
            if (!self.holdAtReady) [self performSelector:@selector(requestCommit) withObject:nil afterDelay:0];
        }
        return;
    }
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
    if (self.interactive) {
        self.readyReply=nil; self.downloadCancellation=nil; self.confirmed=NO;
        self.preflighting=NO; self.commitRequested=NO; self.committing=NO;
        if (!self.window.visible) [self.window makeKeyAndOrderFront:nil];
        Log(@"attempt-dismissed-window-restored"); [self presentStatus:@"Attempt cancelled; retry requires new explicit confirmation" snapshot:@"dismissed"];
        if (self.ordinaryQuitAfterCancellation) [self performSelector:@selector(finishOrdinaryQuit) withObject:nil afterDelay:0];
        return;
    }
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
