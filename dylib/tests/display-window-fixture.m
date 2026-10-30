#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>

@interface WineWindow : NSPanel
@end
@implementation WineWindow
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        void *driver = dlopen(getenv("NP_DISPLAY_TEST_DRIVER"), RTLD_NOW);
        NSDictionary *(*probe)(void) = dlsym(driver, "np_display_probe");
        if (!probe) return 2;
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        CGDirectDisplayID display = CGMainDisplayID();
        CGRect original = CGDisplayBounds(display);
        NSDictionary *virtual = probe();
        BOOL fullscreen = argc > 1 && strcmp(argv[1], "--window") == 0;
        void (^report)(NSWindow *) = ^(NSWindow *window) {
            CGRect actual = CGDisplayBounds(display);
            NSRect frame = window ? window.frame : NSZeroRect;
            NSRect canvas = window ? window.contentView.bounds : NSZeroRect;
            NSDictionary *state = @{@"virtual": virtual, @"policy": @(app.activationPolicy), @"physicalWidth": @(actual.size.width),
                @"physicalHeight": @(actual.size.height), @"physicalUnchanged": @(CGRectEqualToRect(original, actual)),
                @"fullscreen": @((window.styleMask & NSWindowStyleMaskFullScreen) != 0),
                @"windowWidth": @(frame.size.width), @"windowHeight": @(frame.size.height),
                @"canvasWidth": @(canvas.size.width), @"canvasHeight": @(canvas.size.height),
                @"category": [NSBundle.mainBundle objectForInfoDictionaryKey:@"LSApplicationCategoryType"] ?: @""};
            puts([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:state options:0 error:nil]
                encoding:NSUTF8StringEncoding].UTF8String);
            fflush(stdout);
        };
        if (!fullscreen) { report(nil); return 0; }
        // Like Wine, replace an argv slot after dyld constructors have run.
        // Fullscreen classification must retain the original executable identity.
        if (argc > 2) argv[2] = NULL;
        __block WineWindow *window;
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidEnterFullScreenNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                    report(note.object); [app terminate:nil];
                });
            }];
        dispatch_async(dispatch_get_main_queue(), ^{
            window = [[WineWindow alloc] initWithContentRect:NSMakeRect(100, 100, 800, 600)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                backing:NSBackingStoreBuffered defer:NO];
            window.releasedWhenClosed = NO;
            window.title = @"NotProton resolution test";
            [window makeKeyAndOrderFront:nil];
            [app activateIgnoringOtherApps:YES];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            report(window); exit(3);
        });
        [app run];
        return 0;
    }
}
