#import <AppKit/AppKit.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "--quit") == 0) {
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:atoi(argv[2])];
            return app && [app terminate] ? 0 : 1;
        }
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Repeated promotion must still leave the Wine client off the Dock.
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];
            NSDictionary *state = @{
                @"pid": @(getpid()),
                @"policy": @(app.activationPolicy),
                @"arguments": NSProcessInfo.processInfo.arguments,
                @"libraries": NSProcessInfo.processInfo.environment[@"DYLD_INSERT_LIBRARIES"] ?: @""
            };
            NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
            [data writeToFile:NSProcessInfo.processInfo.environment[@"NP_GAME_TEST_STATE"] atomically:YES];
        });
        [app run];
    }
    return 0;
}
