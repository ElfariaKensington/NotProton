#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static BOOL (*originalPolicy)(id, SEL, NSApplicationActivationPolicy);

static BOOL clientPolicy(id application, SEL selector, NSApplicationActivationPolicy policy) {
    if (policy == NSApplicationActivationPolicyRegular) policy = NSApplicationActivationPolicyAccessory;
    return originalPolicy(application, selector, policy);
}

static void announceClient(BOOL windowed) {
    NSString *channel = NSProcessInfo.processInfo.environment[@"NOTPROTON_GAME_CHANNEL"];
    if (!channel.length) return;
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:channel object:nil
        userInfo:@{@"pid": @(getpid()), @"executable": NSProcessInfo.processInfo.processName, @"windowed": @(windowed)} deliverImmediately:YES];
}

__attribute__((constructor)) static void setupClient(void) {
    @autoreleasepool {
        if (!getenv("NOTPROTON_GAME_CHANNEL")) return;
        // Wine promotes its UI processes to regular apps as windows appear.
        Method method = class_getInstanceMethod(NSApplication.class, @selector(setActivationPolicy:));
        originalPolicy = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)clientPolicy);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            announceClient(NO);
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
                    announceClient(NO);
                }];
            [center addObserverForName:NSWindowDidBecomeKeyNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                    announceClient(YES);
                }];
        });
    }
}
