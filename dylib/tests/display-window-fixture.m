#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include "../feats/displayconfig.h"
#import <objc/runtime.h>

@interface WineContentView : NSView
@end
@implementation WineContentView
- (BOOL)isFlipped { return YES; }
@end
@interface WineWindow : NSPanel
- (void)windowDidDrawContent;
@end
@implementation WineWindow
- (void)windowDidDrawContent {}
@end
__attribute__((noinline, disable_tail_calls)) static CGPoint rawLocation(CGEventRef event) { return CGEventGetLocation(event); }
static BOOL black(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return rgb && rgb.redComponent < .01 && rgb.greenComponent < .01 && rgb.blueComponent < .01 && rgb.alphaComponent > .99;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        void *driver = dlopen(getenv("NP_DISPLAY_TEST_DRIVER"), RTLD_NOW);
        NSDictionary *(*probe)(void) = dlsym(driver, "np_display_probe");
        NSDictionary *(*inputProbe)(NSWindow *, CGPoint, CGFloat, CGPoint (*)(CGEventRef)) = dlsym(driver, "np_input_probe");
        if (!probe || !inputProbe) return 2;
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        CGDirectDisplayID display = CGMainDisplayID();
        CGRect original = CGDisplayBounds(display);
        NSDictionary *virtual = probe();
        BOOL fullscreen = argc > 1 && strcmp(argv[1], "--window") == 0;
        unsigned targetWidth = 1920, targetHeight = 1080;
        np_display_parse(getenv("NOTPROTON_DISPLAY_RESOLUTION"), &targetWidth, &targetHeight);
        BOOL exitSpace = getenv("NP_DISPLAY_TEST_EXIT") != NULL;
        __block BOOL dialogUnchanged = NO, dialogClickable = NO;
        __block NSWindowStyleMask originalStyle = 0;
        void (^report)(NSWindow *) = ^(NSWindow *window) {
            CGRect actual = CGDisplayBounds(display);
            NSRect frame = window ? window.frame : NSZeroRect;
            NSRect canvas = window ? window.contentView.bounds : NSZeroRect;
            NSPoint local = NSMakePoint(targetWidth*.8, targetHeight*.75);
            if (!window.contentView.isFlipped) local.y = targetHeight - local.y;
            NSPoint cocoa = window ? [window convertPointToScreen:[window.contentView convertPoint:local toView:nil]] : NSZeroPoint;
            NSDictionary *input = window ? inputProbe(window, CGPointMake(cocoa.x, original.size.height - cocoa.y), original.size.height, rawLocation) : @{};
            BOOL fullscreenInput = [input[@"hit"] boolValue] && [input[@"pollMatches"] boolValue] &&
                [input[@"warpMatches"] boolValue] && [input[@"scrollMatches"] boolValue] && fabs([input[@"x"] doubleValue] - targetWidth*.8) < 1 &&
                fabs([input[@"y"] doubleValue] - targetHeight*.75) < 1;
            NSColor *canvasColor = window.contentView.layer.backgroundColor ? [NSColor colorWithCGColor:window.contentView.layer.backgroundColor] : nil;
            NSDictionary *state = @{@"virtual": virtual, @"policy": @(app.activationPolicy), @"physicalWidth": @(actual.size.width),
                @"physicalHeight": @(actual.size.height), @"physicalUnchanged": @(CGRectEqualToRect(original, actual)),
                @"fullscreen": @((window.styleMask & NSWindowStyleMaskFullScreen) != 0),
                @"windowWidth": @(frame.size.width), @"windowHeight": @(frame.size.height),
                @"canvasWidth": @(canvas.size.width), @"canvasHeight": @(canvas.size.height),
                @"backgroundBlack": @(black(window.backgroundColor)), @"canvasBlack": @(black(canvasColor)),
                @"input": input, @"dialogClickable": @(dialogClickable), @"fullscreenInput": @(fullscreenInput),
                @"dialogUnchanged": @(dialogUnchanged), @"styleRestored": @(window.styleMask == originalStyle),
                @"separatorHidden": @(window.titlebarSeparatorStyle == NSTitlebarSeparatorStyleNone),
                @"titleHidden": @(window.titleVisibility == NSWindowTitleHidden),
                @"category": [NSBundle.mainBundle objectForInfoDictionaryKey:@"LSApplicationCategoryType"] ?: @""};
            puts([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:state options:0 error:nil]
                encoding:NSUTF8StringEncoding].UTF8String);
            fflush(stdout);
        };
        if (!fullscreen) { report(nil); return 0; }
        if (argc > 2) argv[2] = NULL; // Wine rewrites argument slots after constructors.
        __block WineWindow *window, *dialog;
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidEnterFullScreenNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                    // Reproduce Wine's late checkTransparency repaint of native chrome.
                    [note.object setBackgroundColor:NSColor.whiteColor];
                    if (exitSpace) {
                        IMP toggle = class_getMethodImplementation(NSWindow.class, @selector(toggleFullScreen:));
                        ((void (*)(id, SEL, id))toggle)(note.object, @selector(toggleFullScreen:), nil);
                    } else { report(note.object); [app terminate:nil]; }
                });
            }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidExitFullScreenNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                if (!exitSpace) return;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
                    report(note.object); [app terminate:nil];
                });
            }];
        dispatch_async(dispatch_get_main_queue(), ^{
            dialog = [[WineWindow alloc] initWithContentRect:NSMakeRect(100,100,640,320)
                styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
            dialog.releasedWhenClosed = NO;
            dialog.title = @"Graphics driver warning";
            NSTextField *text = [NSTextField labelWithString:@"The graphics driver has known issues. Continue?"];
            text.frame = NSMakeRect(20,200,580,30);[dialog.contentView addSubview:text];
            NSRect dialogFrame = dialog.frame, dialogBounds = dialog.contentView.bounds;
            [dialog makeKeyAndOrderFront:nil];[app activateIgnoringOtherApps:YES];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                dialogUnchanged = !(dialog.styleMask & NSWindowStyleMaskFullScreen) &&
                    NSEqualRects(dialog.frame, dialogFrame) && NSEqualRects(dialog.contentView.bounds, dialogBounds);
                NSPoint button = [dialog convertPointToScreen:NSMakePoint(500,40)];
                NSDictionary *input = inputProbe(dialog, CGPointMake(button.x, original.size.height - button.y), original.size.height, rawLocation);
                dialogClickable = [input[@"hit"] boolValue] && [input[@"pollMatches"] boolValue] &&
                    [input[@"warpMatches"] boolValue] && [input[@"scrollMatches"] boolValue] && fabs([input[@"x"] doubleValue] - button.x) < 1 &&
                    fabs([input[@"y"] doubleValue] - (targetHeight - button.y)) < 1;
                [dialog close];
                window = [[WineWindow alloc] initWithContentRect:NSMakeRect(100,100,800,600)
                    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
                window.contentView = [[WineContentView alloc] initWithFrame:window.contentView.frame];
                window.releasedWhenClosed = NO;window.title = @"NotProton rendering test";
                originalStyle = window.styleMask;
                [window makeKeyAndOrderFront:nil];
                // A renderer can appear after the first window/key notification.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
                    NSView *render = [[NSView alloc] initWithFrame:window.contentView.bounds];
                    CAMetalLayer *layer = [CAMetalLayer layer];layer.device = MTLCreateSystemDefaultDevice();
                    layer.drawableSize = CGSizeMake(1920,1080);render.wantsLayer=YES;render.layer=layer;
                    [window.contentView addSubview:render];[window.contentView setNeedsDisplay:YES];
                    [window windowDidDrawContent];
                });
            });
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 14*NSEC_PER_SEC),dispatch_get_main_queue(),^{report(window);exit(3);});
        [app run];return 0;
    }
}
