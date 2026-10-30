// A process-local virtual display for Wine, with a real native fullscreen Space.
// AppKit keeps physical screen geometry; only the Wine Mac driver's queries lie.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <crt_externs.h>
#include "../dylib/feats/displayconfig.h"

static unsigned npWidth, npHeight;
static BOOL npGameProcess;
static CGDirectDisplayID npDisplay;
static CGDisplayModeRef npMode;
static char npManagedWindow, npAttemptedWindow;

static BOOL wineCaller(void *address) {
    if (!npWidth) return NO;
    Dl_info info;
    if (!dladdr(address, &info) || !info.dli_fname) return NO;
    const char *name = strrchr(info.dli_fname, '/');
    name = name ? name + 1 : info.dli_fname;
    return !strcmp(name, "winemac.so") || !strcmp(name, "winemac.drv.so");
}
#define WINE_CALLER() wineCaller(__builtin_return_address(0))
#define INTERPOSE(replacement, original) \
    __attribute__((used, section("__DATA,__interpose"))) static const struct { \
        const void *new_function, *old_function; \
    } np_interpose_##original = { (const void *)&replacement, (const void *)&original }

static CGRect displayBounds(CGDirectDisplayID display) {
    CGRect bounds = CGDisplayBounds(display);
    if (display == npDisplay && WINE_CALLER()) bounds.size = CGSizeMake(npWidth, npHeight);
    return bounds;
}
static CGDisplayModeRef copyDisplayMode(CGDirectDisplayID display) {
    if (display == npDisplay && WINE_CALLER()) return CGDisplayModeRetain(npMode);
    return CGDisplayCopyDisplayMode(display);
}
static CFArrayRef copyDisplayModes(CGDirectDisplayID display, CFDictionaryRef options) {
    if (display == npDisplay && WINE_CALLER()) {
        const void *mode = npMode;
        return CFArrayCreate(kCFAllocatorDefault, &mode, 1, &kCFTypeArrayCallBacks);
    }
    return CGDisplayCopyAllDisplayModes(display, options);
}
static size_t modeWidth(CGDisplayModeRef mode) {
    return mode == npMode && WINE_CALLER() ? npWidth : CGDisplayModeGetWidth(mode);
}
static size_t modeHeight(CGDisplayModeRef mode) {
    return mode == npMode && WINE_CALLER() ? npHeight : CGDisplayModeGetHeight(mode);
}
static size_t modePixelWidth(CGDisplayModeRef mode) {
    return mode == npMode && WINE_CALLER() ? npWidth : CGDisplayModeGetPixelWidth(mode);
}
static size_t modePixelHeight(CGDisplayModeRef mode) {
    return mode == npMode && WINE_CALLER() ? npHeight : CGDisplayModeGetPixelHeight(mode);
}
static size_t displayPixelWidth(CGDirectDisplayID display) {
    return display == npDisplay && WINE_CALLER() ? npWidth : CGDisplayPixelsWide(display);
}
static size_t displayPixelHeight(CGDirectDisplayID display) {
    return display == npDisplay && WINE_CALLER() ? npHeight : CGDisplayPixelsHigh(display);
}
static CGError setDisplayMode(CGDirectDisplayID display, CGDisplayModeRef mode, CFDictionaryRef options) {
    // Wine's exclusive-mode requests operate on our virtual mode, never the desktop.
    if (display == npDisplay && WINE_CALLER()) return kCGErrorSuccess;
    return CGDisplaySetDisplayMode(display, mode, options);
}
static CGError captureDisplays(void) {
    return WINE_CALLER() ? kCGErrorSuccess : CGCaptureAllDisplays();
}
static CGError releaseDisplays(void) {
    return WINE_CALLER() ? kCGErrorSuccess : CGReleaseAllDisplays();
}
INTERPOSE(displayBounds, CGDisplayBounds);
INTERPOSE(copyDisplayMode, CGDisplayCopyDisplayMode);
INTERPOSE(copyDisplayModes, CGDisplayCopyAllDisplayModes);
INTERPOSE(modeWidth, CGDisplayModeGetWidth);
INTERPOSE(modeHeight, CGDisplayModeGetHeight);
INTERPOSE(modePixelWidth, CGDisplayModeGetPixelWidth);
INTERPOSE(modePixelHeight, CGDisplayModeGetPixelHeight);
INTERPOSE(displayPixelWidth, CGDisplayPixelsWide);
INTERPOSE(displayPixelHeight, CGDisplayPixelsHigh);
INTERPOSE(setDisplayMode, CGDisplaySetDisplayMode);
INTERPOSE(captureDisplays, CGCaptureAllDisplays);
INTERPOSE(releaseDisplays, CGReleaseAllDisplays);

static NSRect (*screenFrame)(id, SEL), (*screenVisibleFrame)(id, SEL), (*windowFrame)(id, SEL);
static CGFloat (*screenScale)(id, SEL);
static BOOL targetScreen(NSScreen *screen) {
    return [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == npDisplay;
}
static NSRect virtualScreenFrame(id screen, SEL selector) {
    NSRect frame = screenFrame(screen, selector);
    if (WINE_CALLER() && targetScreen(screen)) frame.size = NSMakeSize(npWidth, npHeight);
    return frame;
}
static NSRect virtualVisibleFrame(id screen, SEL selector) {
    if (WINE_CALLER() && targetScreen(screen)) {
        NSRect frame = screenFrame(screen, @selector(frame));
        frame.size = NSMakeSize(npWidth, npHeight);
        return frame;
    }
    return screenVisibleFrame(screen, selector);
}
static CGFloat virtualScreenScale(id screen, SEL selector) {
    return WINE_CALLER() && targetScreen(screen) ? 1 : screenScale(screen, selector);
}
static NSRect virtualWindowFrame(id window, SEL selector) {
    NSRect frame = windowFrame(window, selector);
    if (WINE_CALLER() && objc_getAssociatedObject(window, &npManagedWindow) &&
        ([window styleMask] & NSWindowStyleMaskFullScreen)) frame.size = NSMakeSize(npWidth, npHeight);
    return frame;
}

static void replaceMethod(Class cls, SEL selector, IMP replacement, void *previous) {
    Method method = class_getInstanceMethod(cls, selector);
    *(IMP *)previous = method_getImplementation(method);
    method_setImplementation(method, replacement);
}

static NSWindowCollectionBehavior fullscreenBehavior(NSWindowCollectionBehavior behavior) {
    behavior &= ~(NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorFullScreenNone |
                  NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorMoveToActiveSpace);
    return behavior | NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorParticipatesInCycle;
}
static void (*adjustBehavior)(id, SEL, NSWindowCollectionBehavior);
static void managedBehavior(id window, SEL selector, NSWindowCollectionBehavior behavior) {
    if (!objc_getAssociatedObject(window, &npManagedWindow)) { adjustBehavior(window, selector, behavior); return; }
    IMP setter = class_getMethodImplementation(NSWindow.class, @selector(setCollectionBehavior:));
    ((void (*)(id, SEL, NSWindowCollectionBehavior))setter)(window, @selector(setCollectionBehavior:), fullscreenBehavior(behavior));
}

static void scaleContent(NSWindow *window) {
    if (!objc_getAssociatedObject(window, &npManagedWindow) || !(window.styleMask & NSWindowStyleMaskFullScreen)) return;
    NSView *view = window.contentView;
    NSSize physical = view.frame.size;
    CGFloat scale = MIN(physical.width / npWidth, physical.height / npHeight);
    if (scale <= 0) return;
    // Center the virtual canvas and preserve aspect ratio on differently shaped displays.
    NSSize canvas = NSMakeSize(physical.width / scale, physical.height / scale);
    view.bounds = NSMakeRect(((CGFloat)npWidth - canvas.width) / 2,
                             ((CGFloat)npHeight - canvas.height) / 2, canvas.width, canvas.height);
}

static BOOL gameProcess(void) {
    int argc = *_NSGetArgc(); char **argv = *_NSGetArgv();
    for (int i = 0; argv && i < argc; i++) {
        if (!argv[i] || !*argv[i]) continue;
        NSString *path = [[[NSString stringWithUTF8String:argv[i]]
            stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lowercaseString];
        if (![path.pathExtension isEqualToString:@"exe"]) continue;
        NSString *name = path.lastPathComponent;
        return ![path containsString:@"/windows/"] && ![path containsString:@"/legacycompat/"] &&
            ![@[@"steam.exe", @"explorer.exe", @"winedbg.exe", @"services.exe"] containsObject:name];
    }
    return NO;
}

static void considerWindow(NSWindow *window) {
    if (!npGameProcess || !window.isVisible || window.parentWindow ||
        [NSStringFromClass(window.class) rangeOfString:@"Wine"].location == NSNotFound ||
        objc_getAssociatedObject(window, &npAttemptedWindow)) return;
    NSSize size = window.contentView.frame.size;
    if (size.width < 320 || size.height < 240 || (window.styleMask & NSWindowStyleMaskUtilityWindow)) return;
    objc_setAssociatedObject(window, &npAttemptedWindow, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &npManagedWindow, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Wine otherwise reclassifies maximized/borderless windows as fullscreen auxiliaries.
    if (!adjustBehavior) {
        Method method = class_getInstanceMethod(window.class, NSSelectorFromString(@"adjustFullScreenBehavior:"));
        if (method) replaceMethod(window.class, NSSelectorFromString(@"adjustFullScreenBehavior:"), (IMP)managedBehavior, &adjustBehavior);
    }
    window.collectionBehavior = fullscreenBehavior(window.collectionBehavior);
    window.backgroundColor = NSColor.blackColor;
    if (window.styleMask & NSWindowStyleMaskFullScreen) { scaleContent(window); return; }
    for (NSScreen *screen in NSScreen.screens) {
        if (!targetScreen(screen)) continue;
        NSRect physical = screenFrame(screen, @selector(frame));
        NSRect frame = windowFrame(window, @selector(frame));
        frame.origin = NSMakePoint(NSMidX(physical) - frame.size.width / 2, NSMidY(physical) - frame.size.height / 2);
        [window setFrame:frame display:YES];
        break;
    }
    window.styleMask |= NSWindowStyleMaskTitled | NSWindowStyleMaskResizable;
    // Invoke AppKit's native implementation, including its real fullscreen Space.
    IMP toggle = class_getMethodImplementation(NSWindow.class, @selector(toggleFullScreen:));
    ((void (*)(id, SEL, id))toggle)(window, @selector(toggleFullScreen:), nil);
}

__attribute__((constructor)) static void setupDisplay(void) {
    @autoreleasepool {
        unsigned width, height;
        if (!np_display_parse(getenv("NOTPROTON_DISPLAY_RESOLUTION"), &width, &height)) return;
        npDisplay = CGMainDisplayID();
        npMode = CGDisplayCopyDisplayMode(npDisplay);
        if (!npMode) { fprintf(stderr, "NotProton display: no active display mode; enforcement unavailable\n"); return; }
        npWidth = width; npHeight = height;
        // Wine rewrites argv in place after its Unix loader starts. Capture the
        // executable classification while dyld still supplies the original args.
        npGameProcess = gameProcess();
        replaceMethod(NSScreen.class, @selector(frame), (IMP)virtualScreenFrame, &screenFrame);
        replaceMethod(NSScreen.class, @selector(visibleFrame), (IMP)virtualVisibleFrame, &screenVisibleFrame);
        replaceMethod(NSScreen.class, @selector(backingScaleFactor), (IMP)virtualScreenScale, &screenScale);
        replaceMethod(NSWindow.class, @selector(frame), (IMP)virtualWindowFrame, &windowFrame);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSString *name in @[NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification, NSWindowDidChangeOcclusionStateNotification])
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try { considerWindow(note.object); }
                        @catch (NSException *error) {
                            objc_setAssociatedObject(note.object, &npManagedWindow, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            fprintf(stderr, "NotProton display: fullscreen transition failed: %s\n", error.reason.UTF8String);
                        }
                    });
                }];
            for (NSString *name in @[NSWindowDidEnterFullScreenNotification, NSWindowDidResizeNotification])
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    scaleContent(note.object);
                    if ([note.name isEqualToString:NSWindowDidEnterFullScreenNotification] &&
                        objc_getAssociatedObject(note.object, &npManagedWindow))
                        fprintf(stderr, "NotProton display: entered native fullscreen at %ux%u\n", npWidth, npHeight);
                }];
            [center addObserverForName:NSWindowDidExitFullScreenNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                NSWindow *window = note.object;
                if (objc_getAssociatedObject(window, &npManagedWindow))
                    window.contentView.bounds = NSMakeRect(0, 0, window.contentView.frame.size.width, window.contentView.frame.size.height);
            }];
            fprintf(stderr, "NotProton display: virtual %ux%u on display %u; native fullscreen enabled\n", npWidth, npHeight, npDisplay);
        });
    }
}
