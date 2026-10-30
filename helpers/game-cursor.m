// Automatic, process-local cursor suppression over focused Wine game renderers.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <crt_externs.h>

static NSCursor *transparentCursor, *requestedCursor;
static BOOL showingTransparent;
static void (*cursorSet)(id, SEL);
static NSTimer *cursorTimer;
static void (*wineUpdateCursor)(id, SEL, BOOL);
static Ivar wineWantsHidden;
static id wineController;

static NSCursor *makeTransparentCursor(void) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:1 pixelsHigh:1 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:4 bitsPerPixel:32];
    if (!bitmap) return nil;
    memset(bitmap.bitmapData, 0, 4);
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(1,1)];
    [image addRepresentation:bitmap];
    return [[NSCursor alloc] initWithImage:image hotSpot:NSZeroPoint];
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
            ![@[@"steam.exe", @"explorer.exe", @"winedbg.exe", @"services.exe", @"werfault.exe",
                 @"crashpad_handler.exe", @"steamwebhelper.exe"] containsObject:name] &&
            ![name hasPrefix:@"unitycrashhandler"] && ![name hasPrefix:@"crashreportclient"];
    }
    return NO;
}

static BOOL metalAtPoint(CALayer *layer, CGPoint point) {
    if (!layer || layer.hidden || layer.opacity <= 0 || !CGRectContainsPoint(layer.bounds, point)) return NO;
    for (CALayer *child in layer.sublayers.reverseObjectEnumerator) {
        if (metalAtPoint(child, [child convertPoint:point fromLayer:layer])) return YES;
    }
    return ([layer isKindOfClass:CAMetalLayer.class] && ((CAMetalLayer *)layer).device) ||
        [NSStringFromClass(layer.class) isEqualToString:@"CALayerHost"];
}
static BOOL renderedAtPoint(NSView *view, NSPoint point) {
    if (!view || view.hidden || view.alphaValue <= 0 || !NSPointInRect(point, view.bounds)) return NO;
    // A native control layered above a renderer keeps its normal cursor.
    for (NSView *child in view.subviews.reverseObjectEnumerator) {
        NSPoint local = [child convertPoint:point fromView:view];
        if (!child.hidden && child.alphaValue > 0 && NSPointInRect(local, child.bounds))
            return renderedAtPoint(child, local);
    }
    if ([view isKindOfClass:NSControl.class]) return NO;
    if (metalAtPoint(view.layer, NSPointToCGPoint(point))) return YES;
    SEL gl = NSSelectorFromString(@"hasGLDescendant");
    return [view respondsToSelector:gl] && ((BOOL (*)(id, SEL))objc_msgSend)(view, gl);
}
static BOOL cursorTarget(NSWindow *window, NSPoint screenPoint, NSInteger topNumber,
                         BOOL active, NSWindow *modal) {
    if (!active || !window || !window.isVisible || !window.isKeyWindow || window.isMiniaturized ||
        window.windowNumber != topNumber || modal || window.attachedSheet || window.parentWindow ||
        (window.styleMask & NSWindowStyleMaskUtilityWindow) ||
        [NSStringFromClass(window.class) rangeOfString:@"Wine"].location == NSNotFound) return NO;
    // WineWindow is an NSPanel, so exclude dialog-style windows by their features.
    if ((window.styleMask & NSWindowStyleMaskTitled) &&
        !(window.styleMask & (NSWindowStyleMaskResizable | NSWindowStyleMaskFullScreen))) return NO;
    NSView *view = window.contentView;
    NSPoint local = [view convertPoint:[window convertPointFromScreen:screenPoint] fromView:nil];
    return renderedAtPoint(view, local);
}
static BOOL overGameRenderer(void) {
    if (!NSApp.isActive) return NO;
    NSPoint point = NSEvent.mouseLocation;
    NSInteger top = [NSWindow windowNumberAtPoint:point belowWindowWithWindowNumber:0];
    return cursorTarget(NSApp.keyWindow, point, top, NSApp.isActive, NSApp.modalWindow);
}
static BOOL wineRequestsHidden(void) {
    if (!wineController || !wineWantsHidden) return NO;
    BOOL *wanted = (BOOL *)((char *)(__bridge void *)wineController + ivar_getOffset(wineWantsHidden));
    return *wanted;
}
static BOOL shouldHideCursor(void) {
    // A GPU view alone says nothing about whether the game uses a hardware cursor.
    return overGameRenderer() && wineRequestsHidden();
}
static void applyCursor(BOOL hide) {
    if (hide) {
        if (!showingTransparent || NSCursor.currentCursor != transparentCursor) {
            NSCursor *current = NSCursor.currentCursor;
            if (current != transparentCursor) requestedCursor = current;
            cursorSet(transparentCursor, @selector(set));
            showingTransparent = YES;
        }
    } else if (showingTransparent) {
        // Balance only our own cursor replacement; Wine owns its hide/unhide state.
        showingTransparent = NO;
        if (NSCursor.currentCursor == transparentCursor)
            cursorSet(requestedCursor ?: NSCursor.arrowCursor, @selector(set));
        requestedCursor = nil;
    }
}
static void setCursor(id cursor, SEL selector) {
    if (!NSThread.isMainThread) { cursorSet(cursor, selector); return; }
    if (cursor == transparentCursor) cursor = requestedCursor ?: NSCursor.arrowCursor;
    requestedCursor = cursor;
    BOOL hide = shouldHideCursor();
    showingTransparent = hide;
    cursorSet(hide ? transparentCursor : cursor, selector);
}
// Wine can carry SetCursor(NULL) from a splash/game into a modal dialog.
// Let Wine balance its own hide count while temporarily suspending that request.
static void updateWineCursorForTarget(id controller, SEL selector, BOOL force, BOOL gameTarget) {
    BOOL *wanted = (BOOL *)((char *)(__bridge void *)controller + ivar_getOffset(wineWantsHidden));
    BOOL requestedHidden = *wanted;
    if (!gameTarget) *wanted = NO;
    @try { wineUpdateCursor(controller, selector, force); }
    @finally { *wanted = requestedHidden; }
    if (!gameTarget && requestedHidden && NSApp.isActive && NSApp.keyWindow &&
        [NSStringFromClass(NSApp.keyWindow.class) rangeOfString:@"Wine"].location != NSNotFound) {
        // There is no game-provided cursor to restore while SetCursor(NULL) is pending.
        cursorSet(NSCursor.arrowCursor, @selector(set));
    }
}
static void applyWineCursorPolicy(BOOL gameTarget) {
    applyCursor(gameTarget && wineRequestsHidden());
}
static void updateWineCursor(id controller, SEL selector, BOOL force) {
    BOOL gameTarget = overGameRenderer();
    updateWineCursorForTarget(controller, selector, force, gameTarget);
    applyWineCursorPolicy(gameTarget);
}
static void watchWineCursor(void) {
    if (wineUpdateCursor) return;
    Class cls = NSClassFromString(@"WineApplicationController");
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(@"updateCursor:"));
    Ivar wanted = class_getInstanceVariable(cls, "clientWantsCursorHidden");
    if (!method || !wanted || ivar_getOffset(wanted) < 0 ||
        (size_t)ivar_getOffset(wanted) + sizeof(BOOL) > class_getInstanceSize(cls)) return;
    SEL shared = NSSelectorFromString(@"sharedController");
    if (![cls respondsToSelector:shared]) return;
    wineController = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    if (!wineController) return;
    wineWantsHidden = wanted;
    wineUpdateCursor = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)updateWineCursor);
}
static void refreshCursor(void) {
    watchWineCursor();
    BOOL gameTarget = overGameRenderer();
    applyWineCursorPolicy(gameTarget);
    if (wineController) updateWineCursorForTarget(wineController, NSSelectorFromString(@"updateCursor:"), NO, gameTarget);
}
static void startWatching(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            (void)note; [cursorTimer invalidate]; cursorTimer = nil; refreshCursor();
        }];
    void (^activate)(void) = ^{
        if (!cursorTimer && NSApp.isActive) {
            cursorTimer = [NSTimer timerWithTimeInterval:.1 repeats:YES block:^(NSTimer *timer) {
                (void)timer; refreshCursor();
            }];
            [NSRunLoop.mainRunLoop addTimer:cursorTimer forMode:NSRunLoopCommonModes];
        }
        refreshCursor();
    };
    [center addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { (void)note; activate(); }];
    for (NSString *name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification,
        NSWindowDidMiniaturizeNotification, NSWindowWillCloseNotification, NSWindowDidUpdateNotification,
        NSWindowWillBeginSheetNotification, NSWindowDidEndSheetNotification])
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            if ([note.name isEqualToString:NSWindowDidResignKeyNotification] ||
                [note.name isEqualToString:NSWindowWillCloseNotification] ||
                [note.name isEqualToString:NSWindowWillBeginSheetNotification]) {
                applyCursor(NO);
                if (wineController) updateWineCursorForTarget(wineController, NSSelectorFromString(@"updateCursor:"), NO, NO);
            }
            else refreshCursor();
        }];
    [center addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { (void)note; applyCursor(NO); }];
    NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged |
        NSEventMaskOtherMouseDragged | NSEventMaskMouseEntered | NSEventMaskMouseExited |
        NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskScrollWheel;
    [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        refreshCursor(); return event;
    }];
    activate();
}
#ifndef NP_CURSOR_TEST
__attribute__((constructor)) static void setupCursor(void) {
    @autoreleasepool {
        // Capture argv before Wine rewrites it. No hooks in Wine helpers or native apps.
        if (!gameProcess()) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            transparentCursor = makeTransparentCursor();
            if (!transparentCursor) return;
            Method method = class_getInstanceMethod(NSCursor.class, @selector(set));
            cursorSet = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)setCursor);
            startWatching();
        });
    }
}
#endif
