// A process-local virtual display for Wine, with a real native fullscreen Space.
// AppKit keeps physical screen geometry; only the Wine Mac driver's queries lie.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <crt_externs.h>
#include "../dylib/feats/displayconfig.h"

static unsigned npWidth, npHeight;
static BOOL npGameProcess;
static CGDirectDisplayID npDisplay;
static CGDisplayModeRef npMode;
static char npManagedWindow, npAttemptedWindow, npOriginalWindow;
static void scheduleWindow(NSWindow *window);
static _Thread_local unsigned npHandlingInput;
static _Thread_local void *npInputWindow;

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
static CGFloat (*eventDeltaX)(id, SEL), (*eventDeltaY)(id, SEL);
static void (*windowBackground)(id, SEL, NSColor *);
static void managedBackground(id window, SEL selector, NSColor *color) {
    if (objc_getAssociatedObject(window, &npManagedWindow) && color.alphaComponent > 0)
        color = NSColor.blackColor;
    windowBackground(window, selector, color);
}
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
    if (!npHandlingInput && WINE_CALLER() && objc_getAssociatedObject(window, &npManagedWindow) &&
        ([window styleMask] & NSWindowStyleMaskFullScreen)) frame.size = NSMakeSize(npWidth, npHeight);
    return frame;
}

static void replaceMethod(Class cls, SEL selector, IMP replacement, void *previous) {
    Method method = class_getInstanceMethod(cls, selector);
    *(IMP *)previous = method_getImplementation(method);
    method_setImplementation(method, replacement);
}

// Wine places windows in Cocoa coordinates using its virtual screen height,
// but Quartz events arrive in the physical desktop's top-left coordinate space.
// Keep native hit testing physical and translate only the coordinates sent to Wine.
static CGFloat physicalScreenTop(void) {
    return NSMaxY(screenFrame(NSScreen.screens.firstObject, @selector(frame)));
}
static BOOL managedFullscreen(NSWindow *window) {
    return window && objc_getAssociatedObject(window, &npManagedWindow) &&
        (window.styleMask & NSWindowStyleMaskFullScreen);
}
static NSWindow *inputWindow(void) {
    if (npHandlingInput) return (__bridge NSWindow *)npInputWindow;
    NSWindow *key = NSApp.keyWindow;
    return key ?: NSApp.mainWindow;
}
static NSPoint wineWindowOrigin(NSWindow *window) {
    NSRect frame = windowFrame(window, @selector(frame));
    frame.size = NSMakeSize(npWidth, npHeight);
    return NSMakePoint(frame.origin.x, npHeight - NSMaxY(frame));
}
static CGPoint winePoint(CGPoint physical, NSWindow *window) {
    if (!managedFullscreen(window)) {
        physical.y += npHeight - physicalScreenTop();
        return physical;
    }
    NSView *view = window.contentView;
    NSPoint cocoa = NSMakePoint(physical.x, physicalScreenTop() - physical.y);
    NSPoint local = [view convertPoint:[window convertPointFromScreen:cocoa] fromView:nil];
    NSPoint origin = wineWindowOrigin(window);
    return CGPointMake(origin.x + local.x, origin.y + (view.isFlipped ? local.y : npHeight - local.y));
}
static CGPoint physicalPoint(CGPoint virtual, NSWindow *window) {
    if (!managedFullscreen(window)) {
        virtual.y -= npHeight - physicalScreenTop();
        return virtual;
    }
    NSView *view = window.contentView;
    NSPoint origin = wineWindowOrigin(window);
    NSPoint local = NSMakePoint(virtual.x - origin.x, virtual.y - origin.y);
    if (!view.isFlipped) local.y = npHeight - local.y;
    NSPoint cocoa = [window convertPointToScreen:[view convertPoint:local toView:nil]];
    return CGPointMake(cocoa.x, physicalScreenTop() - cocoa.y);
}
static CGPoint eventLocation(CGEventRef event) {
    CGPoint point = CGEventGetLocation(event);
    return WINE_CALLER() && NSThread.isMainThread ? winePoint(point, inputWindow()) : point;
}
static CGError warpCursor(CGPoint point) {
    if (WINE_CALLER() && NSThread.isMainThread) point = physicalPoint(point, inputWindow());
    return CGWarpMouseCursorPosition(point);
}
static void eventSetLocation(CGEventRef event, CGPoint point) {
    if (WINE_CALLER() && NSThread.isMainThread) point = physicalPoint(point, inputWindow());
    CGEventSetLocation(event, point);
}
INTERPOSE(eventLocation, CGEventGetLocation);
INTERPOSE(warpCursor, CGWarpMouseCursorPosition);
INTERPOSE(eventSetLocation, CGEventSetLocation);

static NSPoint (*flippedMouseLocation)(id, SEL, NSPoint);
static NSPoint flippedLocation(id controller, SEL selector, NSPoint point) {
    (void)controller; (void)selector;
    if (npHandlingInput) {
        CGPoint physical = physicalPoint(NSPointToCGPoint(point), inputWindow());
        return NSMakePoint(physical.x, physicalScreenTop() - physical.y);
    }
    CGPoint physical = CGPointMake(point.x, physicalScreenTop() - point.y);
    return NSPointFromCGPoint(winePoint(physical, inputWindow()));
}
static void (*mouseButton)(id, SEL, NSEvent *), (*mouseMove)(id, SEL, NSEvent *), (*mouseScroll)(id, SEL, NSEvent *);
static void handleInput(id controller, SEL selector, NSEvent *event) {
    unsigned previousDepth = npHandlingInput;
    void *previousWindow = npInputWindow;
    NSWindow *window = event.window;
    // Mouse-moved events can name the main window even over a dialog.
    if (event.type == NSEventTypeMouseMoved) {
        CGPoint point = CGEventGetLocation(event.CGEvent);
        NSPoint cocoa = NSMakePoint(point.x, physicalScreenTop() - point.y);
        NSInteger number = [NSWindow windowNumberAtPoint:cocoa belowWindowWithWindowNumber:0];
        window = [NSApp windowWithWindowNumber:number];
    }
    Ivar capture = class_getInstanceVariable([controller class], "mouseCaptureWindow");
    NSWindow *captured = capture ? object_getIvar(controller, capture) : nil;
    if (captured) window = captured;
    npInputWindow = (__bridge void *)window;
    npHandlingInput++;
    @try {
        if (selector == NSSelectorFromString(@"handleMouseButton:")) mouseButton(controller, selector, event);
        else if (selector == NSSelectorFromString(@"handleMouseMove:")) mouseMove(controller, selector, event);
        else mouseScroll(controller, selector, event);
    } @finally {
        npHandlingInput = previousDepth;
        npInputWindow = previousWindow;
    }
}
static CGFloat mappedDelta(id event, SEL selector) {
    BOOL horizontal = selector == @selector(deltaX);
    CGFloat delta = horizontal ? eventDeltaX(event, selector) : eventDeltaY(event, selector);
    if (!npHandlingInput || !WINE_CALLER()) return delta;
    NSWindow *window = inputWindow();
    if (managedFullscreen(window)) {
        NSView *view = window.contentView;
        NSSize frame = view.frame.size, bounds = view.bounds.size;
        CGFloat length = horizontal ? frame.width : frame.height;
        if (length > 0) delta *= (horizontal ? bounds.width : bounds.height) / length;
    }
    return delta;
}
static void watchInput(void) {
    if (flippedMouseLocation) return;
    Class controller = NSClassFromString(@"WineApplicationController");
    if (!controller) return;
    const char *names[] = {"flippedMouseLocation:", "handleMouseButton:", "handleMouseMove:", "handleScrollWheel:"};
    for (unsigned i = 0; i < 4; i++)
        if (!class_getInstanceMethod(controller, NSSelectorFromString(@(names[i])))) return;
    replaceMethod(controller, NSSelectorFromString(@"flippedMouseLocation:"), (IMP)flippedLocation, &flippedMouseLocation);
    replaceMethod(controller, NSSelectorFromString(@"handleMouseButton:"), (IMP)handleInput, &mouseButton);
    replaceMethod(controller, NSSelectorFromString(@"handleMouseMove:"), (IMP)handleInput, &mouseMove);
    replaceMethod(controller, NSSelectorFromString(@"handleScrollWheel:"), (IMP)handleInput, &mouseScroll);
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

// Require an actual game rendering surface; ordinary GDI dialogs and bitmap splashes stay windowed.
static BOOL metalSurface(CALayer *layer) {
    if (!layer) return NO;
    if ([layer isKindOfClass:CAMetalLayer.class] && ((CAMetalLayer *)layer).device) return YES;
    if ([NSStringFromClass(layer.class) isEqualToString:@"CALayerHost"]) return YES;
    for (CALayer *child in layer.sublayers) if (metalSurface(child)) return YES;
    return NO;
}
static BOOL graphicsSurface(NSView *view) {
    if (!view || view.isHidden) return NO;
    if (metalSurface(view.layer)) return YES;
    SEL hasGL = NSSelectorFromString(@"hasGLDescendant");
    if ([view respondsToSelector:hasGL] && ((BOOL (*)(id, SEL))objc_msgSend)(view, hasGL)) return YES;
    for (NSView *child in view.subviews) if (graphicsSurface(child)) return YES;
    return NO;
}
static void (*wineWindowDrawn)(id, SEL);
static void windowDrawn(id window, SEL selector) {
    wineWindowDrawn(window, selector);
    scheduleWindow(window);
}
static void watchRendering(NSWindow *window) {
    if (wineWindowDrawn) return;
    SEL selector = NSSelectorFromString(@"windowDidDrawContent");
    Method method = class_getInstanceMethod(window.class, selector);
    if (method) replaceMethod(window.class, selector, (IMP)windowDrawn, &wineWindowDrawn);
}
static void restoreWindow(NSWindow *window) {
    NSDictionary *state = objc_getAssociatedObject(window, &npOriginalWindow);
    objc_setAssociatedObject(window, &npManagedWindow, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!state) return;
    window.styleMask = [state[@"style"] unsignedIntegerValue];
    window.collectionBehavior = [state[@"behavior"] unsignedIntegerValue];
    window.titleVisibility = [state[@"titleVisibility"] integerValue];
    window.titlebarAppearsTransparent = [state[@"transparentTitle"] boolValue];
    window.titlebarSeparatorStyle = [state[@"separator"] integerValue];
    window.hasShadow = [state[@"shadow"] boolValue];
    window.backgroundColor = state[@"background"];
    window.contentView.bounds = [state[@"bounds"] rectValue];
    window.contentView.layer.backgroundColor = [state[@"layerBackground"] CGColor];
    objc_setAssociatedObject(window, &npOriginalWindow, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void scaleContent(NSWindow *window) {
    if (!objc_getAssociatedObject(window, &npManagedWindow) || !(window.styleMask & NSWindowStyleMaskFullScreen)) return;
    NSView *view = window.contentView;
    // Wine's transparency checks may repaint the uncovered canvas after entry.
    // Leave OpenGL underlays transparent; Metal letterboxes must be solid black.
    BOOL metal = metalSurface(view.layer);
    window.backgroundColor = metal ? NSColor.blackColor : NSColor.clearColor;
    if (metal) view.layer.backgroundColor = NSColor.blackColor.CGColor;
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
            ![@[@"steam.exe", @"explorer.exe", @"winedbg.exe", @"services.exe", @"werfault.exe", @"crashpad_handler.exe"] containsObject:name] &&
            ![name hasPrefix:@"unitycrashhandler"] && ![name hasPrefix:@"crashreportclient"];
    }
    return NO;
}

static void considerWindow(NSWindow *window) {
    watchInput();
    if (!npGameProcess || !window.isVisible || window.parentWindow ||
        [NSStringFromClass(window.class) rangeOfString:@"Wine"].location == NSNotFound ||
        objc_getAssociatedObject(window, &npAttemptedWindow)) return;
    NSSize size = window.contentView.frame.size;
    watchRendering(window);
    if (size.width < 64 || size.height < 64 || (window.styleMask & NSWindowStyleMaskUtilityWindow) ||
        !graphicsSurface(window.contentView)) return;
    NSColor *layerBackground = window.contentView.layer.backgroundColor
        ? [NSColor colorWithCGColor:window.contentView.layer.backgroundColor] : NSColor.clearColor;
    NSDictionary *state = @{@"style": @(window.styleMask & ~NSWindowStyleMaskFullScreen), @"behavior": @(window.collectionBehavior),
        @"titleVisibility": @(window.titleVisibility), @"transparentTitle": @(window.titlebarAppearsTransparent),
        @"separator": @(window.titlebarSeparatorStyle), @"shadow": @(window.hasShadow),
        @"background": window.backgroundColor ?: NSColor.clearColor,
        @"bounds": [NSValue valueWithRect:window.contentView.bounds], @"layerBackground": layerBackground};
    objc_setAssociatedObject(window, &npOriginalWindow, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &npAttemptedWindow, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &npManagedWindow, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Wine otherwise reclassifies maximized/borderless windows as fullscreen auxiliaries.
    if (!adjustBehavior) {
        Method method = class_getInstanceMethod(window.class, NSSelectorFromString(@"adjustFullScreenBehavior:"));
        if (method) replaceMethod(window.class, NSSelectorFromString(@"adjustFullScreenBehavior:"), (IMP)managedBehavior, &adjustBehavior);
    }
    window.collectionBehavior = fullscreenBehavior(window.collectionBehavior);
    window.backgroundColor = metalSurface(window.contentView.layer) ? NSColor.blackColor : NSColor.clearColor;
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.hasShadow = NO;
    if (window.styleMask & NSWindowStyleMaskFullScreen) { scaleContent(window); return; }
    for (NSScreen *screen in NSScreen.screens) {
        if (!targetScreen(screen)) continue;
        NSRect physical = screenFrame(screen, @selector(frame));
        NSRect frame = windowFrame(window, @selector(frame));
        frame.origin = NSMakePoint(NSMidX(physical) - frame.size.width / 2, NSMidY(physical) - frame.size.height / 2);
        [window setFrame:frame display:YES];
        break;
    }
    window.styleMask |= NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.hasShadow = NO;
    // Invoke AppKit's native implementation, including its real fullscreen Space.
    IMP toggle = class_getMethodImplementation(NSWindow.class, @selector(toggleFullScreen:));
    ((void (*)(id, SEL, id))toggle)(window, @selector(toggleFullScreen:), nil);
}

static void scheduleWindow(NSWindow *window) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { considerWindow(window); }
        @catch (NSException *error) {
            restoreWindow(window);
            fprintf(stderr, "NotProton display: fullscreen transition failed: %s\n", error.reason.UTF8String);
        }
    });
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
        replaceMethod(NSEvent.class, @selector(deltaX), (IMP)mappedDelta, &eventDeltaX);
        replaceMethod(NSEvent.class, @selector(deltaY), (IMP)mappedDelta, &eventDeltaY);
        replaceMethod(NSWindow.class, @selector(setBackgroundColor:), (IMP)managedBackground, &windowBackground);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSString *name in @[NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification, NSWindowDidChangeOcclusionStateNotification, NSWindowDidUpdateNotification])
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    NSWindow *window = note.object;
                    if (npGameProcess && !objc_getAssociatedObject(window, &npAttemptedWindow)) scheduleWindow(window);
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
                if (objc_getAssociatedObject(window, &npManagedWindow)) restoreWindow(window);
            }];
            fprintf(stderr, "NotProton display: virtual %ux%u on display %u; native fullscreen enabled\n", npWidth, npHeight, npDisplay);
        });
    }
}
