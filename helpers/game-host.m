#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

@interface NPGameHost : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSTask *task;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSRunningApplication *> *clients;
@property(nonatomic, copy) NSString *channel;
@property(nonatomic) BOOL stopping;
@end

@implementation NPGameHost

- (void)focusGame {
    if (self.stopping) return;
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *window in windows) {
        NSNumber *pid = window[(id)kCGWindowOwnerPID];
        NSRunningApplication *client = self.clients[pid];
        if (client && !client.terminated && [window[(id)kCGWindowLayer] intValue] == 0) {
            [client activateWithOptions:NSApplicationActivateAllWindows];
            return;
        }
    }
}

- (void)registerClient:(NSNotification *)notification {
    NSNumber *pid = notification.userInfo[@"pid"];
    if (![pid isKindOfClass:NSNumber.class] || pid.intValue <= 0) return;
    NSRunningApplication *client = [NSRunningApplication runningApplicationWithProcessIdentifier:pid.intValue];
    if (client && !client.terminated) self.clients[pid] = client;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self focusGame];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    [self focusGame];
    return NO;
}

- (void)gameTaskDidExit {
    if (!self.stopping) [NSApp terminate:nil];
}

- (void)finishShutdown {
    if (self.task.running) [self.task terminate];
    [NSApp replyToApplicationShouldTerminate:YES];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)application {
    if (self.stopping) return NSTerminateLater;
    self.stopping = YES;
    // The outer run script also kills this prefix if the host is force quit.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *environment = NSProcessInfo.processInfo.environment;
        NSString *server = environment[@"WINESERVER"];
        if (server.length && [environment[@"WINEPREFIX"] length]) {
            NSTask *stop = [NSTask new];
            stop.executableURL = [NSURL fileURLWithPath:server];
            stop.arguments = @[@"-k"];
            NSError *error = nil;
            if ([stop launchAndReturnError:&error]) [stop waitUntilExit];
            else NSLog(@"NotProton could not stop the Wine session: %@", error);
        }
        [self performSelectorOnMainThread:@selector(finishShutdown) withObject:nil
            waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
    });
    return NSTerminateLater;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.clients = [NSMutableDictionary new];
    self.channel = [@"com.notproton.game." stringByAppendingString:NSUUID.UUID.UUIDString];
    [[NSDistributedNotificationCenter defaultCenter]
        addObserver:self selector:@selector(registerClient:) name:self.channel object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];

    NSMenu *menu = [NSMenu new];
    NSMenuItem *item = [NSMenuItem new];
    [menu addItem:item];
    NSMenu *appMenu = [NSMenu new];
    NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"Game";
    [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:name]
        action:@selector(terminate:) keyEquivalent:@"q"];
    item.submenu = appMenu;
    NSApp.mainMenu = menu;

    NSString *script = [NSBundle.mainBundle.bundlePath
        stringByAppendingPathComponent:@"Contents/MacOS/wine-launch.sh"];
    self.task = [NSTask new];
    self.task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    NSMutableArray *arguments = [NSMutableArray arrayWithObject:script];
    NSArray *incoming = NSProcessInfo.processInfo.arguments;
    if (incoming.count > 1) {
        [arguments addObjectsFromArray:[incoming subarrayWithRange:NSMakeRange(1, incoming.count - 1)]];
    }
    self.task.arguments = arguments;
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"NOTPROTON_GAME_CHANNEL"] = self.channel;
    self.task.environment = environment;
    __weak NPGameHost *weakSelf = self;
    self.task.terminationHandler = ^(NSTask *task) {
        // terminate: may run a nested event loop while awaiting the delegate's reply.
        // Keep it outside a main-queue block so shutdown callbacks can run.
        NPGameHost *host = weakSelf;
        [host performSelectorOnMainThread:@selector(gameTaskDidExit) withObject:nil
            waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
    };
    NSError *error = nil;
    if (![self.task launchAndReturnError:&error]) {
        NSLog(@"NotProton could not launch the Wine session: %@", error);
        [NSApp terminate:nil];
    }
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        NPGameHost *host __attribute__((objc_precise_lifetime)) = [NPGameHost new];
        application.delegate = host;
        BOOL hidden = [[NSBundle.mainBundle objectForInfoDictionaryKey:@"LSUIElement"] boolValue];
        [application setActivationPolicy:hidden ? NSApplicationActivationPolicyAccessory
                                                : NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
