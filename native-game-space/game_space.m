#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <mach-o/getsect.h>
#include <crt_externs.h>
#include <stdatomic.h>
#include <os/lock.h>
#include "../dylib/core/macho.h"
#include "config.h"
#include "display.h"
#include "input.h"

static NSSize pixels;
static Class wineClass;
static char stateKey;
static char frontedKey;
static atomic_bool installQueued;
static atomic_bool installed;
static atomic_bool installFailed;
static void install(void);
static NSMutableArray *observers;
static __weak NSWindow *managedWindow;
static atomic_bool compatibleDriver;
static os_unfair_lock mouseLock = OS_UNFAIR_LOCK_INIT;
static CGRect cursorLogical;
static CGAffineTransform cursorToLogical;
static CGAffineTransform cursorToPhysical;
static BOOL cursorMapped;
static CGFloat cursorScale;
static void updateCursorMapping(NSWindow *w);
static NSApplicationPresentationOptions savedChrome;
static BOOL changedPresentation;
static atomic_bool exclusiveMode;
static BOOL fullscreenFromWindowStyle;
static void scheduleEntry(NSWindow *w);
static void fitWindow(NSWindow *w);
static void promoteGameProcess(void);


static const NSApplicationPresentationOptions hiddenChrome = NSApplicationPresentationHideDock |
    NSApplicationPresentationHideMenuBar;
static const NSApplicationPresentationOptions chromeMask = NSApplicationPresentationHideDock |
    NSApplicationPresentationHideMenuBar | NSApplicationPresentationAutoHideDock |
    NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideToolbar;

@interface NPGameWindowState : NSObject
@property BOOL layout;
@property BOOL gameMutation;
@property BOOL nativeGeometry;
@property BOOL transitioning;
@property BOOL pendingEntry;
@property BOOL decorated;
@property BOOL fitPending;
@property BOOL requestedFullscreen;
@property BOOL modeToggle;
@property NSRect windowedFrame;
@property BOOL startupFocused;
@property unsigned activationAttempts;
@property BOOL activationQueued;
@property BOOL reclaimedLaunchFocus;
@property NSTimeInterval attachedAt;
@property BOOL entryQueued;
@property BOOL closed;
@property BOOL sentSize;
@property BOOL sentFullscreen;
@property CGFloat scale;
@property NSRect lastRejected;
@property NSRect reportedFrame;
// Where Wine itself last put the window (top-down points); it can differ from reportedFrame.
@property NSRect wineFrame;
@property BOOL hasWineFrame;
- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)frame;
- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)options;
@end
@implementation NPGameWindowState
- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)frame { return frame; }
- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)options { return options; }
@end

static NPGameWindowState *state(NSWindow *w) {
    return objc_getAssociatedObject(w, &stateKey);
}

static void syncPresentation(void) {
    NSWindow *w = managedWindow;
    NPGameWindowState *s = state(w);
    BOOL native = (w.styleMask & NSWindowStyleMaskFullScreen) != 0;
    NSScreen *screen = w.screen;
    BOOL borderless = w.keyWindow && !s.decorated && screen && NSContainsRect(w.frame, screen.frame);
    BOOL hide = s && !s.closed && NSApp.active && w.visible && w.onActiveSpace && (native || borderless);
    if (!hide && !changedPresentation) return;

    NSApplicationPresentationOptions options = NSApp.presentationOptions;
    NSApplicationPresentationOptions chrome = options & chromeMask;
    if (hide) {
        if (!changedPresentation) savedChrome = native ? 0 : chrome;
        changedPresentation = YES;
        options = (options & ~chromeMask) | hiddenChrome;
    } else {
        changedPresentation = NO;
        if (chrome != hiddenChrome) return;
        NSApplicationPresentationOptions restore = savedChrome;
        if (!(options & NSApplicationPresentationFullScreen)) restore &= ~NSApplicationPresentationAutoHideToolbar;
        options = (options & ~chromeMask) | restore;
    }
    if (options != NSApp.presentationOptions) {
        NSApp.presentationOptions = options;
    } else if (hide && !s.transitioning && w.keyWindow &&
               (NSApp.currentSystemPresentationOptions & hiddenChrome) != hiddenChrome) {
        // The system can reset presentation while AppKit retains the same request.
        // Change the request before reapplying it so AppKit publishes it again.
        NSApp.presentationOptions = (options & ~chromeMask) |
            NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
        NSApp.presentationOptions = options;
    }
}

static BOOL wantsFullscreen(NPGameWindowState *s) {
    // These games can show an undecorated fullscreen window without a
    // successful exclusive display-mode change.
    return fullscreenFromWindowStyle ? !s.decorated : atomic_load(&exclusiveMode);
}

static NSSize logicalSize(NPGameWindowState *s) {
    return NSMakeSize(pixels.width / s.scale, pixels.height / s.scale);
}

static BOOL eligible(NSWindow *w) {
    if (![w isKindOfClass:wineClass] || w.parentWindow || w.sheetParent ||
        (w.styleMask & (NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskNonactivatingPanel))) return NO;
    NSSize size = [w contentRectForFrameRect:w.frame].size;
    if (size.width < 160 || size.height < 100) return NO;
    if ([w respondsToSelector:NSSelectorFromString(@"latentParentWindow")] && [w valueForKey:@"latentParentWindow"]) return NO;
    for (NSString *key in @[@"disabled", @"noForeground", @"preventsAppActivation"])
        if ([w respondsToSelector:NSSelectorFromString(key)] && [[w valueForKey:key] boolValue]) return NO;
    return YES;
}

static void configure(NSWindow *w) {
    NPGameWindowState *s = state(w);
    if (!s || s.layout || s.closed) return;
    s.layout = YES;
    if (!s.transitioning) {
        NSWindowStyleMask style = w.styleMask;
        style &= ~(NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskNonactivatingPanel);
        NSWindowStyleMask chrome = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        if (s.decorated || s.requestedFullscreen || (style & NSWindowStyleMaskFullScreen)) style |= chrome;
        else style &= ~chrome;
        if (w.styleMask != style) w.styleMask = style;
        w.contentMinSize = NSMakeSize(160, 100);
        w.contentMaxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        w.contentAspectRatio = pixels;
        w.level = NSNormalWindowLevel;
        w.hidesOnDeactivate = NO;
        BOOL movable = !(style & NSWindowStyleMaskFullScreen);
        if (w.movable != movable) w.movable = movable;
        if (w.movableByWindowBackground) w.movableByWindowBackground = NO;
        w.hasShadow = s.decorated && !(style & NSWindowStyleMaskFullScreen);
        NSWindowCollectionBehavior behavior = w.collectionBehavior;
        behavior &= ~(NSWindowCollectionBehaviorCanJoinAllSpaces |
                      NSWindowCollectionBehaviorMoveToActiveSpace |
                      NSWindowCollectionBehaviorFullScreenAuxiliary |
                      NSWindowCollectionBehaviorFullScreenNone |
                      NSWindowCollectionBehaviorTransient |
                      NSWindowCollectionBehaviorIgnoresCycle);
        behavior |= NSWindowCollectionBehaviorManaged |
                    NSWindowCollectionBehaviorParticipatesInCycle |
                    NSWindowCollectionBehaviorFullScreenPrimary;
        if (w.collectionBehavior != behavior) w.collectionBehavior = behavior;
    }
    NSSize logical = logicalSize(s);
    if (!NSEqualSizes(w.contentView.bounds.size, logical)) w.contentView.boundsSize = logical;
    s.layout = NO;
}

static void (*originalPost)(id, SEL, NSRect, BOOL, BOOL, BOOL);
static void report(NSWindow *w, BOOL fullscreen, BOOL resizing, BOOL skip) {
    NPGameWindowState *s = state(w);
    if (!s || s.closed || s.layout || s.transitioning) return;
    configure(w);
    NSRect actual = [w contentRectForFrameRect:w.frame];
    NSPoint origin = NSMakePoint(NSMinX(actual), NSMaxY(actual) - logicalSize(s).height);
    if (!NSEqualPoints(s.reportedFrame.origin, origin)) s.sentSize = NO;
    s.reportedFrame = (NSRect){origin, logicalSize(s)};
    if (s.sentSize && s.sentFullscreen == fullscreen) {
        updateCursorMapping(w);
        return;
    }
    NSWindowStyleMask style = w.styleMask;
    style = fullscreen ? style | NSWindowStyleMaskFullScreen : style & ~NSWindowStyleMaskFullScreen;
    NSRect frame = [wineClass frameRectForContentRect:s.reportedFrame styleMask:style];
    s.sentSize = YES;
    s.hasWineFrame = NO;
    updateCursorMapping(w);
    s.sentFullscreen = fullscreen;
    originalPost(w, @selector(postWindowFrameChanged:fullscreen:resizing:skipSizeMove:),
                 frame, fullscreen, resizing, skip);
}

static void postFrame(NSWindow *w, SEL cmd, NSRect frame, BOOL fullscreen, BOOL resizing, BOOL skip) {
    if (!state(w)) return originalPost(w, cmd, frame, fullscreen, resizing, skip);
    report(w, fullscreen, resizing, skip);
}

// Launcher and driver-warning dialogs are Wine windows too, and must never be stretched to the
// game size. The game's own window either renders through a Metal/GL surface or already has the
// requested size.
static BOOL hasRenderSurface(NSView *view, int depth) {
    if (depth > 8) return NO;
    NSString *name = NSStringFromClass(view.class);
    if ([view.layer isKindOfClass:CAMetalLayer.class] || [name containsString:@"Metal"] ||
        [name containsString:@"OpenGL"]) return YES;
    for (CALayer *layer in view.layer.sublayers)
        if ([layer isKindOfClass:CAMetalLayer.class]) return YES;
    for (NSView *child in view.subviews)
        if (hasRenderSurface(child, depth + 1)) return YES;
    return NO;
}

// Games such as Unreal titles keep a titled 2-pixel-high guard window around. Windows draws
// nothing for it, but macOS shows its title as a floating pill on the desktop.
static void hideSliver(NSWindow *w) {
    NSSize size = [w contentRectForFrameRect:w.frame].size;
    if (![w isKindOfClass:wineClass] || size.height > 4 || w.alphaValue == 0) return;
    w.alphaValue = 0;
    w.hasShadow = NO;
    w.ignoresMouseEvents = YES;
}

static BOOL gameSized(NSWindow *w);
static BOOL looksLikeGame(NSWindow *w) {
    return gameSized(w) || hasRenderSurface(w.contentView, 0);
}

static void attach(NSWindow *w) {
    if (state(w).closed) objc_setAssociatedObject(w, &stateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (state(w) || (managedWindow && managedWindow != w) || !eligible(w) || !looksLikeGame(w)) return;
    NPGameWindowState *s = [NPGameWindowState new];
    s.attachedAt = NSProcessInfo.processInfo.systemUptime;
    // Wine uses a fixed 2x Retina mode independently of the screen's current scale.
    s.scale = w.contentView.layer.mask.contentsScale >= 2 ? 2 : 1;
    s.decorated = (w.styleMask & NSWindowStyleMaskTitled) != 0;
    s.requestedFullscreen = wantsFullscreen(s) || (w.styleMask & NSWindowStyleMaskFullScreen);
    s.pendingEntry = YES;
    s.fitPending = YES;
    managedWindow = w;
    s.reportedFrame = [w contentRectForFrameRect:w.frame];
    s.reportedFrame = NSMakeRect(NSMinX(s.reportedFrame), NSMaxY(s.reportedFrame) - pixels.height / s.scale,
                                pixels.width / s.scale, pixels.height / s.scale);
    objc_setAssociatedObject(w, &stateKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    fprintf(stderr, "[native-space] managing %s: %.0fx%.0f pixels, scale %.0f\n", w.title.UTF8String,
            pixels.width, pixels.height, s.scale);
    configure(w);
    fitWindow(w);
    report(w, !!(w.styleMask & NSWindowStyleMaskFullScreen), NO, NO);
    promoteGameProcess();
}

static void nativeToggle(NSWindow *w, id sender) {
    // Bypass Wine's maximized-window veto, not AppKit's fullscreen machinery.
    IMP implementation = class_getMethodImplementation(NSWindow.class, @selector(toggleFullScreen:));
    ((void (*)(id, SEL, id))implementation)(w, @selector(toggleFullScreen:), sender);
}

static BOOL overviewActive(void) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly |
                                                 kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!list) return NO;
    BOOL active = NO;
    for (NSDictionary *window in (__bridge NSArray *)list) {
        if ([window[(__bridge NSString *)kCGWindowOwnerName] isEqual:@"Dock"] &&
            [window[(__bridge NSString *)kCGWindowLayer] integerValue] == 18) {
            active = YES;
            break;
        }
    }
    CFRelease(list);
    return active;
}

static void fitWindow(NSWindow *w) {
    NPGameWindowState *s = state(w);
    if (!s.fitPending || s.transitioning || (w.styleMask & NSWindowStyleMaskFullScreen)) return;
    NSScreen *screen = w.screen ?: NSScreen.mainScreen;
    if (!screen) return;
    s.fitPending = NO;
    NSRect frame = screen.frame;
    if (s.decorated || s.requestedFullscreen) {
        NSRect visible = screen.visibleFrame;
        if (!NSIsEmptyRect(s.windowedFrame)) {
            frame = s.windowedFrame;
        } else {
            NSSize size = logicalSize(s);
            CGFloat fit = MIN(1, MIN(visible.size.width * 0.85 / size.width,
                                     visible.size.height * 0.85 / size.height));
            frame = [w frameRectForContentRect:NSMakeRect(0, 0, floor(size.width * fit), floor(size.height * fit))];
            frame.origin = NSMakePoint(NSMidX(visible) - frame.size.width / 2,
                                       NSMidY(visible) - frame.size.height / 2);
        }
        s.windowedFrame = frame;
    }
    [w setFrame:frame display:YES];
    configure(w);
    syncPresentation();
}

static void activateGameProcess(void) {
    ProcessSerialNumber process;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (GetProcessForPID(getpid(), &process) == noErr)
        SetFrontProcessWithOptions(&process, kSetFrontProcessFrontWindowOnly);
#pragma clang diagnostic pop
}

// Single-icon launches inject game-client.dylib, which keeps every Wine process an
// accessory app so only the launcher shows in the Dock. An accessory app never owns
// the menu bar and cannot hide it, so the app that was in front keeps its menu bar
// over the game. Make the game process a regular app. game-client overrides
// -setActivationPolicy: to turn Regular back into Accessory, so transform directly.
static void promoteGameProcess(void) {
    if (NSApp.activationPolicy == NSApplicationActivationPolicyRegular) return;
    ProcessSerialNumber process;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = GetProcessForPID(getpid(), &process);
    if (status == noErr) status = TransformProcessType(&process, kProcessTransformToForegroundApplication);
#pragma clang diagnostic pop
    fprintf(stderr, "[native-space] made game process a regular app: status %d\n", (int)status);
    NSString *icon = [NSBundle.mainBundle pathForResource:@"game" ofType:@"icns"];
    NSImage *image = icon ? [[NSImage alloc] initWithContentsOfFile:icon] : nil;
    if (image) NSApp.applicationIconImage = image;
    // The process may already be in front as an accessory; front it again so it
    // also takes the menu bar.
    activateGameProcess();
}

static void requestStartupFocus(NSWindow *w, NPGameWindowState *s) {
    if (s.startupFocused || s.activationQueued || s.activationAttempts >= 3) return;
    ++s.activationAttempts;
    [w makeKeyAndOrderFront:nil];
    if (s.activationAttempts == 1) {
        [[NSDistributedNotificationCenter defaultCenter]
            postNotificationName:@"org.notproton.GameWindowReady" object:nil
            userInfo:@{@"pid": @(getpid())} deliverImmediately:YES];
        [NSApp activate];
    }
    // [NSApp activate] only succeeds when the app in front yields, which Steam does
    // only while it is active. Target this process directly once its window exists.
    if (!NSApp.active) activateGameProcess();
    s.activationQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        s.activationQueued = NO;
        if (managedWindow == w) scheduleEntry(w);
    });
}

// Wine starts each Windows process as its own macOS app outside Launch Services, so
// nothing activates it, and macOS ignores a background app activating itself. A game's
// splash, driver-warning dialog or main window then opens behind the app in front,
// which also keeps that app's menu bar. Bring the process forward once per new window.
static void frontNewWindow(NSWindow *w) {
    if (!w.visible || objc_getAssociatedObject(w, &frontedKey) || w.miniaturized ||
        w.alphaValue == 0 || !eligible(w)) return;
    objc_setAssociatedObject(w, &frontedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (NSApp.active || overviewActive()) return;
    fprintf(stderr, "[native-space] bringing new window %s forward\n", w.title.UTF8String);
    activateGameProcess();
}

static void tryEntry(NSWindow *w) {
    NPGameWindowState *s = state(w);
    if (!s.pendingEntry || s.transitioning || s.closed || !w.visible || w.miniaturized ||
        NSApp.modalWindow || overviewActive()) return;
    BOOL fullscreen = (w.styleMask & NSWindowStyleMaskFullScreen) != 0;
    if (!fullscreen && !s.requestedFullscreen) {
        configure(w);
        fitWindow(w);
        report(w, NO, NO, YES);
    }
    if (!NSApp.active) {
        requestStartupFocus(w, s);
        return;
    }
    if (!w.keyWindow) {
        [w makeKeyAndOrderFront:nil];
        if (!w.keyWindow) {
            requestStartupFocus(w, s);
            return;
        }
    }
    s.startupFocused = YES;
    if (!w.onActiveSpace || !(w.occlusionState & NSWindowOcclusionStateVisible)) return;
    s.pendingEntry = NO;
    if (s.decorated && !fullscreen && s.requestedFullscreen && !w.zoomed)
        s.windowedFrame = w.frame;
    configure(w);
    if (fullscreen == s.requestedFullscreen) {
        fitWindow(w);
        report(w, fullscreen, NO, YES);
        return;
    }
    fprintf(stderr, "[native-space] switching to %s\n", s.requestedFullscreen ? "fullscreen" : "desktop");
    s.modeToggle = YES;
    nativeToggle(w, nil);
}

void np_game_space_display_mode(bool fullscreen) {
    atomic_store(&exclusiveMode, fullscreen);
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
        NSWindow *w = managedWindow;
        NPGameWindowState *s = state(w);
        if (s && !fullscreenFromWindowStyle && s.requestedFullscreen != wantsFullscreen(s)) {
            s.requestedFullscreen = wantsFullscreen(s);
            s.fitPending = YES;
            s.pendingEntry = YES;
            scheduleEntry(w);
        }
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

static void scheduleEntry(NSWindow *w) {
    NPGameWindowState *s = state(w);
    if (!s.pendingEntry || s.entryQueued) return;
    s.entryQueued = YES;
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
        s.entryQueued = NO;
        tryEntry(w);
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

// A game started behind Steam never becomes key until the player clicks it, so a visible window
// that already has the requested game size counts as the game window too.
static BOOL gameSized(NSWindow *w) {
    NSSize size = [w contentRectForFrameRect:w.frame].size;
    for (int scale = 1; scale <= 2; scale++)
        if (fabs(size.width - pixels.width / scale) < 1 && fabs(size.height - pixels.height / scale) < 1) return YES;
    return NO;
}

static void (*originalDraw)(id, SEL);
static void drawn(NSWindow *w, SEL cmd) {
    originalDraw(w, cmd);
    frontNewWindow(w);
    if (w.visible && (w.keyWindow || !managedWindow)) {
        attach(w);
        scheduleEntry(w);
    }
}

static BOOL (*originalPreventResize)(id, SEL);
static BOOL preventResize(NSWindow *w, SEL cmd) {
    return state(w) ? NO : originalPreventResize(w, cmd);
}

static NSInteger (*originalLevel)(id, SEL, BOOL);
static NSInteger level(NSWindow *w, SEL cmd, BOOL active) {
    return state(w) ? NSNormalWindowLevel : originalLevel(w, cmd, active);
}
static BOOL (*originalIsFullscreen)(id, SEL);
static BOOL isFullscreen(NSWindow *w, SEL cmd) {
    return state(w) ? NO : originalIsFullscreen(w, cmd);
}
static void (*originalUpdateFullscreen)(id, SEL);
static void updateFullscreen(NSWindow *w, SEL cmd) {
    if (!state(w)) originalUpdateFullscreen(w, cmd);
}
static void (*originalEnterFailed)(id, SEL, NSWindow *);
static void enterFailed(NSWindow *w, SEL cmd, NSWindow *window) {
    originalEnterFailed(w, cmd, window);
    NPGameWindowState *s = state(w);
    if (s) fprintf(stderr, "[native-space] AppKit rejected fullscreen entry\n");
    s.transitioning = NO;
    s.modeToggle = NO;
    configure(w);
}
static void (*originalExitFailed)(id, SEL, NSWindow *);
static void exitFailed(NSWindow *w, SEL cmd, NSWindow *window) {
    originalExitFailed(w, cmd, window);
    NPGameWindowState *s = state(w);
    if (s) fprintf(stderr, "[native-space] AppKit rejected fullscreen exit\n");
    s.transitioning = NO;
    s.modeToggle = NO;
    configure(w);
}

static NSRect (*originalFractionalFrame)(id, SEL);
static NSRect fractionalFrame(NSWindow *w, SEL cmd) {
    NPGameWindowState *s = state(w);
    if (!s || s.nativeGeometry) return originalFractionalFrame(w, cmd);
    return [wineClass frameRectForContentRect:s.reportedFrame styleMask:w.styleMask];
}
static void (*originalWillEnter)(id, SEL, NSNotification *);
static void willEnter(NSWindow *w, SEL cmd, NSNotification *notification) {
    NPGameWindowState *s = state(w);
    s.transitioning = YES;
    s.nativeGeometry = YES;
    originalWillEnter(w, cmd, notification);
    s.nativeGeometry = NO;
}

static void (*originalFrame)(id, SEL, NSRect);
static void wineFrame(NSWindow *w, SEL cmd, NSRect rect) {
    NPGameWindowState *s = state(w);
    if (!s) return originalFrame(w, cmd, rect);
    if (!NSIsEmptyRect(rect) && NSEqualSizes(rect.size, logicalSize(s))) {
        s.wineFrame = rect;
        s.hasWineFrame = YES;
        updateCursorMapping(w);
    }
    if (s.layout || s.transitioning || s.closed || NSIsEmptyRect(rect)) return;
    configure(w);
    NSSize desired = logicalSize(s);
    if (NSEqualSizes(rect.size, desired)) {
        s.lastRejected = NSZeroRect;
    } else if (!NSEqualRects(rect, s.lastRejected)) {
        s.lastRejected = rect;
        s.sentSize = NO;
        report(w, !!(w.styleMask & NSWindowStyleMaskFullScreen), NO, YES);
    }
}

static void (*originalFeatures)(id, SEL, const void *);
static void features(NSWindow *w, SEL cmd, const void *p) {
    NPGameWindowState *s = state(w);
    BOOL decorated = s.decorated;
    if (s && p) {
        unsigned int flags;
        memcpy(&flags, p, sizeof flags);
        s.decorated = (flags & 1u) != 0; // macdrv_window_features.title_bar
    }
    s.gameMutation = YES;
    originalFeatures(w, cmd, p);
    s.gameMutation = NO;
    if (s && s.decorated != decorated) {
        if (decorated && !s.transitioning && !(w.styleMask & NSWindowStyleMaskFullScreen) && !w.zoomed)
            s.windowedFrame = w.frame;
        s.requestedFullscreen = !s.decorated && wantsFullscreen(s);
        s.fitPending = YES;
        s.pendingEntry = YES;
        scheduleEntry(w);
    }
    configure(w);
}
static void (*originalState)(id, SEL, const void *);
static void driverState(NSWindow *w, SEL cmd, const void *p) {
    NPGameWindowState *s = state(w);
    s.gameMutation = YES;
    originalState(w, cmd, p);
    s.gameMutation = NO;
    configure(w);
}
static void (*originalBehavior)(id, SEL, NSWindowCollectionBehavior);
static void behavior(NSWindow *w, SEL cmd, NSWindowCollectionBehavior b) {
    if (!state(w)) originalBehavior(w, cmd, b);
    else configure(w);
}
static void (*originalStyle)(id, SEL, NSWindowStyleMask);
static void style(NSWindow *w, SEL cmd, NSWindowStyleMask mask) {
    NPGameWindowState *s = state(w);
    if (s.gameMutation && !s.layout) {
        // AppKit applies the chrome change after the current Space transition.
        mask = w.styleMask;
    }
    originalStyle(w, cmd, mask);
}
static void (*originalToggle)(id, SEL, id);
static void toggle(NSWindow *w, SEL cmd, id sender) {
    NPGameWindowState *s = state(w);
    if (!s) return originalToggle(w, cmd, sender);
    if (s.transitioning || s.closed) return;
    s.pendingEntry = NO;
    s.requestedFullscreen = !(w.styleMask & NSWindowStyleMaskFullScreen);
    nativeToggle(w, sender);
}
static NSSize (*originalFullSize)(id, SEL, NSWindow *, NSSize);
static NSSize fullSize(NSWindow *w, SEL cmd, NSWindow *window, NSSize proposed) {
    return state(w) ? proposed : originalFullSize(w, cmd, window, proposed);
}

static NSApplicationPresentationOptions (*originalPresentation)(id, SEL, NSWindow *, NSApplicationPresentationOptions);
static NSApplicationPresentationOptions presentation(NSWindow *w, SEL cmd, NSWindow *window,
                                                     NSApplicationPresentationOptions options) {
    if (!state(w)) return originalPresentation ? originalPresentation(w, cmd, window, options) : options;
    return (options & ~chromeMask) | hiddenChrome;
}

static BOOL mouseRects(NSWindow *w, id controller, CGRect *physical, CGRect *logical) {
    NPGameWindowState *s = state(w);
    if (!s || s.closed || !w.onActiveSpace) return NO;
    SEL flip = sel_registerName("flipRect:");
    if (![controller respondsToSelector:flip]) return NO;
    void (*flipRect)(id, SEL, NSRect *) = (void *)[controller methodForSelector:flip];
    NSRect content = [w contentRectForFrameRect:w.frame], reported = s.reportedFrame;
    if (NSIsEmptyRect(content) || NSIsEmptyRect(reported)) return NO;
    flipRect(controller, flip, &content);
    if (s.hasWineFrame) reported = s.wineFrame; // already top-down
    else flipRect(controller, flip, &reported);
    *physical = NSRectToCGRect(content);
    *logical = NSRectToCGRect(reported);
    return YES;
}

static __weak id inputController;

static void updateCursorMapping(NSWindow *w) {
    CGRect physical = CGRectZero, logical = CGRectZero;
    BOOL mapped = NSApp.active && w.keyWindow && mouseRects(w, inputController, &physical, &logical);
    CGAffineTransform toLogical = CGAffineTransformIdentity;
    if (mapped) {
        CGFloat x = logical.size.width / physical.size.width;
        CGFloat y = logical.size.height / physical.size.height;
        toLogical = CGAffineTransformMake(x, 0, 0, y, logical.origin.x - physical.origin.x * x,
                                          logical.origin.y - physical.origin.y * y);
    }
    os_unfair_lock_lock(&mouseLock);
    cursorMapped = mapped;
    cursorScale = mapped ? state(w).scale : 1;
    cursorLogical = logical;
    cursorToLogical = toLogical;
    cursorToPhysical = CGAffineTransformInvert(toLogical);
    os_unfair_lock_unlock(&mouseLock);
}

// Wine's AppKit event queue and cursor warp run on the main thread. The
// Windows cursor query can run on another thread and shares this snapshot.
void np_game_space_map_cursor(int32_t *x, int32_t *y) {
    os_unfair_lock_lock(&mouseLock);
    if (cursorMapped) {
        CGPoint point = CGPointApplyAffineTransform(CGPointMake(*x / cursorScale, *y / cursorScale), cursorToLogical);
        *x = floor(point.x * cursorScale);
        *y = floor(point.y * cursorScale);
    }
    os_unfair_lock_unlock(&mouseLock);
}
// Wine's event numbering differs between builds (CrossOver inserts entries), but every build
// keeps the names of its event enum in order in its string table, so read the numbers there.
static struct { int button, absolute, scroll; } eventTypes = { -1, -1, -1 };

static BOOL readEventTypes(const struct mach_header_64 *header) {
    // The names sit in __TEXT,__const on some builds and in __cstring on others.
    const char *end = NULL, *name = NULL;
    for (int i = 0; i < 2 && !name; i++) {
        unsigned long size;
        const char *pool = (const char *)getsectiondata(header, "__TEXT", i ? "__cstring" : "__const", &size);
        if (!pool) continue;
        end = pool + size;
        for (const char *p = pool; p && (name = memmem(p, end - p, "APP_ACTIVATED", 14)); p = name + 1) {
            if (name == pool || !name[-1]) break;
            name = NULL;
        }
    }
    if (!name) return NO;
    int relative = -1;
    for (int index = 0; name < end; index++, name += strlen(name) + 1) {
        for (const char *c = name; *c; c++)
            if ((*c < 'A' || *c > 'Z') && *c != '_') return eventTypes.button >= 0 && relative == eventTypes.button + 1 &&
                eventTypes.absolute == relative + 1 && eventTypes.scroll == eventTypes.absolute + 1;
        if (!strcmp(name, "MOUSE_BUTTON")) eventTypes.button = index;
        else if (!strcmp(name, "MOUSE_MOVED_RELATIVE")) relative = index;
        else if (!strcmp(name, "MOUSE_MOVED_ABSOLUTE")) eventTypes.absolute = index;
        else if (!strcmp(name, "MOUSE_SCROLL")) eventTypes.scroll = index;
    }
    return NO;
}

static BOOL fullscreenButtonDelivered;
static BOOL (*originalHandleEvent)(id, SEL, NSEvent *);
static BOOL handleEvent(id controller, SEL cmd, NSEvent *event) {
    // Wine queues the button first, then normally hands it to AppKit as well.
    // Once a fullscreen content click was delivered, avoid native drag handling.
    BOOL previous = fullscreenButtonDelivered;
    fullscreenButtonDelivered = NO;
    BOOL handled = originalHandleEvent(controller, cmd, event);
    BOOL delivered = fullscreenButtonDelivered;
    fullscreenButtonDelivered = previous;
    return handled || delivered;
}

static void (*originalPostEvent)(id, SEL, struct np_mouse_event *);
static void postEvent(id queue, SEL cmd, struct np_mouse_event *event) {
    int *x = NULL, *y = NULL;
    if (event->type == eventTypes.button) { x = &event->data.button.x; y = &event->data.button.y; }
    else if (event->type == eventTypes.absolute) { x = &event->data.move.x; y = &event->data.move.y; }
    else if (event->type == eventTypes.scroll) { x = &event->data.scroll.x; y = &event->data.scroll.y; }
    if (x && NSThread.isMainThread) {
        NSWindow *w = managedWindow;
        if (w && (__bridge NSWindow *)event->window == w) {
            np_game_space_map_cursor(x, y);
            if (event->type == eventTypes.button && (w.styleMask & NSWindowStyleMaskFullScreen))
                fullscreenButtonDelivered = YES;
        }
    }
    originalPostEvent(queue, cmd, event);
}

static BOOL (*originalSetCursor)(id, SEL, CGPoint);
static BOOL (*originalClipCursor)(id, SEL, CGRect);
static BOOL clippingUpdate;

static BOOL setCursor(id controller, SEL cmd, CGPoint point) {
    if (!clippingUpdate && cursorMapped && CGRectContainsPoint(cursorLogical, point))
        point = CGPointApplyAffineTransform(point, cursorToPhysical);
    return originalSetCursor(controller, cmd, point);
}

static BOOL clipCursor(id controller, SEL cmd, CGRect rect) {
    if (cursorMapped && !CGRectIsInfinite(rect))
        rect = CGRectApplyAffineTransform(rect, cursorToPhysical);
    clippingUpdate = YES;
    BOOL result = originalClipCursor(controller, cmd, rect);
    clippingUpdate = NO;
    return result;
}

static void installInput(void) {
    if (eventTypes.button < 0 || eventTypes.absolute < 0 || eventTypes.scroll < 0) return;
    Class controller = objc_getClass("WineApplicationController");
    Class queue = objc_getClass("WineEventQueue");
    SEL shared = sel_registerName("sharedController");
    SEL post = sel_registerName("postEvent:");
    SEL cursor = sel_registerName("setCursorPosition:");
    SEL clip = sel_registerName("startClippingCursor:");
    Method postMethod = class_getInstanceMethod(queue, post);
    Method cursorMethod = class_getInstanceMethod(controller, cursor);
    Method clipMethod = class_getInstanceMethod(controller, clip);
    Method sharedMethod = class_getClassMethod(controller, shared);
    Method handleMethod = class_getInstanceMethod(controller, sel_registerName("handleEvent:"));
    if (!postMethod || !cursorMethod || !clipMethod || !sharedMethod) return;
    id (*getController)(id, SEL) = (void *)method_getImplementation(sharedMethod);
    inputController = getController(controller, shared);
    originalPostEvent = (void *)method_setImplementation(postMethod, (IMP)postEvent);
    if (handleMethod) originalHandleEvent = (void *)method_setImplementation(handleMethod, (IMP)handleEvent);
    originalSetCursor = (void *)method_setImplementation(cursorMethod, (IMP)setCursor);
    originalClipCursor = (void *)method_setImplementation(clipMethod, (IMP)clipCursor);
}

static NSRect (*originalStandardFrame)(id, SEL, NSWindow *, NSRect);
static NSRect standardFrame(NSWindow *w, SEL cmd, NSWindow *window, NSRect proposed) {
    if (!state(w)) {
        return originalStandardFrame ? originalStandardFrame(w, cmd, window, proposed) : proposed;
    }
    NSRect content = [w contentRectForFrameRect:proposed];
    CGFloat fit = MIN(content.size.width / pixels.width, content.size.height / pixels.height);
    NSSize size = NSMakeSize(floor(pixels.width * fit), floor(pixels.height * fit));
    content.origin.x += floor((content.size.width - size.width) / 2);
    content.origin.y += content.size.height - size.height;
    content.size = size;
    return [w frameRectForContentRect:content];
}

static BOOL (*originalZoom)(id, SEL, NSWindow *, NSRect);
static BOOL zoom(NSWindow *w, SEL cmd, NSWindow *window, NSRect frame) {
    if (state(w)) return !state(w).transitioning;
    return originalZoom(w, cmd, window, frame);
}
static void (*originalRetina)(id, SEL, BOOL);
static void retina(NSWindow *w, SEL cmd, BOOL on) {
    originalRetina(w, cmd, on);
    NPGameWindowState *s = state(w);
    if (s) {
        s.scale = on ? 2 : 1;
        s.reportedFrame = NSMakeRect(NSMinX(s.reportedFrame), NSMinY(s.reportedFrame),
                                     pixels.width / s.scale, pixels.height / s.scale);
        s.sentSize = NO;
        configure(w);
        report(w, !!(w.styleMask & NSWindowStyleMaskFullScreen), NO, YES);
    }
}

static void observe(NSNotificationCenter *center, NSNotificationName name, void (^handler)(NSNotification *)) {
    [observers addObject:[center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:handler]];
}

static void install(void) {
    atomic_store(&installQueued, false);
    if (installed || installFailed || !NSApp || !(wineClass = objc_getClass("WineWindow"))) return;
    fprintf(stderr, "[native-space] pid %d installing WineWindow hooks\n", getpid());
    struct Hook { const char *name; IMP replacement; IMP *original; unsigned args; } hooks[] = {
        {"postWindowFrameChanged:fullscreen:resizing:skipSizeMove:", (IMP)postFrame, (IMP *)&originalPost, 6},
        {"setFrameFromWine:", (IMP)wineFrame, (IMP *)&originalFrame, 3},
        {"wine_fractionalFrame", (IMP)fractionalFrame, (IMP *)&originalFractionalFrame, 2},
        {"windowWillEnterFullScreen:", (IMP)willEnter, (IMP *)&originalWillEnter, 3},
        {"setWindowFeatures:", (IMP)features, (IMP *)&originalFeatures, 3},
        {"setMacDrvState:", (IMP)driverState, (IMP *)&originalState, 3},
        {"adjustFullScreenBehavior:", (IMP)behavior, (IMP *)&originalBehavior, 3},
        {"setStyleMask:", (IMP)style, (IMP *)&originalStyle, 3},
        {"toggleFullScreen:", (IMP)toggle, (IMP *)&originalToggle, 3},
        {"window:willUseFullScreenContentSize:", (IMP)fullSize, (IMP *)&originalFullSize, 4},
        {"windowShouldZoom:toFrame:", (IMP)zoom, (IMP *)&originalZoom, 4},
        {"setRetinaMode:", (IMP)retina, (IMP *)&originalRetina, 3},
        {"windowDidDrawContent", (IMP)drawn, (IMP *)&originalDraw, 2},
        {"preventResizing", (IMP)preventResize, (IMP *)&originalPreventResize, 2},
        {"minimumLevelForActive:", (IMP)level, (IMP *)&originalLevel, 3},
        {"updateFullscreen", (IMP)updateFullscreen, (IMP *)&originalUpdateFullscreen, 2},
        {"isFullscreen", (IMP)isFullscreen, (IMP *)&originalIsFullscreen, 2},
        {"windowDidFailToEnterFullScreen:", (IMP)enterFailed, (IMP *)&originalEnterFailed, 3},
        {"windowDidFailToExitFullScreen:", (IMP)exitFailed, (IMP *)&originalExitFailed, 3},
    };
    for (unsigned i = 0; i < sizeof hooks / sizeof *hooks; i++) {
        Method m = class_getInstanceMethod(wineClass, sel_registerName(hooks[i].name));
        if (!m || method_getNumberOfArguments(m) != hooks[i].args) {
            fprintf(stderr, "NotProton: native game Space unavailable: Wine method %s changed\n", hooks[i].name);
            installFailed = YES;
            return;
        }
    }
    installed = YES;
    for (unsigned i = 0; i < sizeof hooks / sizeof *hooks; i++) {
        SEL selector = sel_registerName(hooks[i].name);
        Method m = class_getInstanceMethod(wineClass, selector);
        *hooks[i].original = method_getImplementation(m);
        class_replaceMethod(wineClass, selector, hooks[i].replacement, method_getTypeEncoding(m));
    }
    SEL standard = @selector(windowWillUseStandardFrame:defaultFrame:);
    Method method = class_getInstanceMethod(wineClass, standard);
    if (method) {
        originalStandardFrame = (void *)method_getImplementation(method);
        class_replaceMethod(wineClass, standard, (IMP)standardFrame, method_getTypeEncoding(method));
    } else {
        Method signature = class_getInstanceMethod(NSClassFromString(@"NPGameWindowState"), standard);
        class_addMethod(wineClass, standard, (IMP)standardFrame, method_getTypeEncoding(signature));
    }
    SEL options = @selector(window:willUseFullScreenPresentationOptions:);
    Method optionsMethod = class_getInstanceMethod(wineClass, options);
    if (optionsMethod) originalPresentation = (void *)method_getImplementation(optionsMethod);
    else optionsMethod = class_getInstanceMethod(NPGameWindowState.class, options);
    class_replaceMethod(wineClass, options, (IMP)presentation, method_getTypeEncoding(optionsMethod));
    if (compatibleDriver) installInput();
    observers = [NSMutableArray new];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    observe(nc, NSWindowDidBecomeKeyNotification, ^(NSNotification *n) {
        NSWindow *w = n.object;
        hideSliver(w);
        fprintf(stderr, "[native-space] key window %s class=%s style=%lu size=%.0fx%.0f eligible=%d\n",
                w.title.UTF8String, object_getClassName(w), (unsigned long)w.styleMask,
                w.contentView.bounds.size.width, w.contentView.bounds.size.height, eligible(w));
        attach(w);
        scheduleEntry(w);
    });
    observe(nc, NSWindowDidResizeNotification, ^(NSNotification *n) {
        NSWindow *w = n.object;
        if (w.visible && !managedWindow) { attach(w); scheduleEntry(w); }
        configure(w);
        if (w == managedWindow) updateCursorMapping(w);
    });
    observe(nc, NSWindowDidMoveNotification, ^(NSNotification *n) {
        if (n.object == managedWindow) updateCursorMapping(managedWindow);
    });
    observe(nc, NSWindowDidChangeOcclusionStateNotification, ^(NSNotification *n) {
        NSWindow *w = n.object;
        frontNewWindow(w);
        if (w.visible && !managedWindow) attach(w);
        if (w == managedWindow) {
            syncPresentation();
            updateCursorMapping(w);
        }
        scheduleEntry(w);
    });
    observe(nc, NSWindowDidChangeBackingPropertiesNotification, ^(NSNotification *n) { configure(n.object); });
    observe(nc, NSWindowWillEnterFullScreenNotification, ^(NSNotification *n) {
        NPGameWindowState *s = state(n.object);
        s.transitioning = YES;
        if (!s.modeToggle) s.requestedFullscreen = YES;
        s.modeToggle = NO;
    });
    observe(nc, NSWindowWillExitFullScreenNotification, ^(NSNotification *n) {
        NPGameWindowState *s = state(n.object);
        s.transitioning = YES;
        if (!s.modeToggle) s.requestedFullscreen = NO;
        s.modeToggle = NO;
        s.fitPending = YES;
    });
    for (NSString *name in @[NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification])
        observe(nc, name, ^(NSNotification *n) {
            NSWindow *w = n.object;
            NPGameWindowState *s = state(w);
            if (!s) return;
            // Wine's fullscreen-exit delegate restores its pre-Space frame.
            // Apply the current game mode after all fullscreen observers finish.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
                s.transitioning = NO;
                syncPresentation();
                BOOL fullscreen = (w.styleMask & NSWindowStyleMaskFullScreen) != 0;
                fprintf(stderr, "[native-space] native Space %s\n", fullscreen ? "entered" : "exited");
                if (s.closed) return;
                configure(w);
                fitWindow(w);
                report(w, fullscreen, NO, YES);
                scheduleEntry(w);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    if (managedWindow == w) updateCursorMapping(w);
                });
            });
            CFRunLoopWakeUp(CFRunLoopGetMain());
        });
    observe(nc, NSWindowWillCloseNotification, ^(NSNotification *n) {
        NSWindow *w = n.object;
        if ([w respondsToSelector:NSSelectorFromString(@"isFakingClose")] && [[w valueForKey:@"isFakingClose"] boolValue]) {
            state(w).pendingEntry = !!(w.styleMask & NSWindowStyleMaskFullScreen);
        } else {
            state(w).closed = YES;
            if (managedWindow == w) {
                managedWindow = nil;
                syncPresentation();
                updateCursorMapping(nil);
            }
        }
    });
    for (NSString *name in @[NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification,
                              NSWindowDidResignKeyNotification, NSWindowDidBecomeKeyNotification])
        observe(nc, name, ^(NSNotification *n) {
            syncPresentation();
            updateCursorMapping(managedWindow);
            scheduleEntry(managedWindow);
        });
    observe(NSWorkspace.sharedWorkspace.notificationCenter, NSWorkspaceActiveSpaceDidChangeNotification,
            ^(NSNotification *n) {
                syncPresentation();
                updateCursorMapping(managedWindow);
                scheduleEntry(managedWindow);
            });
    observe(NSWorkspace.sharedWorkspace.notificationCenter, NSWorkspaceDidActivateApplicationNotification,
            ^(NSNotification *n) {
                NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
                NSWindow *w = managedWindow;
                NPGameWindowState *s = state(w);
                if (!s.startupFocused || s.closed || s.reclaimedLaunchFocus || !w.visible || w.miniaturized ||
                    NSApp.modalWindow ||
                    NSProcessInfo.processInfo.systemUptime - s.attachedAt > 45 || app.processIdentifier == getpid()) return;
                NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
                if (![bundle hasPrefix:@"com.notproton.launcher."] || ![app.bundleIdentifier isEqualToString:bundle] ||
                    overviewActive()) return;
                s.reclaimedLaunchFocus = YES;
                fprintf(stderr, "[native-space] returning launch focus from sibling pid %d\n", app.processIdentifier);
                activateGameProcess();
            });
    observe(NSDistributedNotificationCenter.defaultCenter, @"com.apple.expose.front.asleep",
            ^(NSNotification *n) { dispatch_async(dispatch_get_main_queue(), ^{ scheduleEntry(NSApp.keyWindow); }); });
    for (NSWindow *w in NSApp.windows) if (w.keyWindow) { attach(w); scheduleEntry(w); }
    // A game's Metal surface can appear after its window was last drawn or resized, with no
    // notification of its own. Re-check until a game window is found.
    [observers addObject:[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) {
        for (NSWindow *w in NSApp.windows) if (w.visible) { hideSliver(w); frontNewWindow(w); }
        // Leaving a native Space settles after its notifications, while the window
        // is not yet on the active Space, so a pointer mapping taken then is stale.
        if (managedWindow) { syncPresentation(); updateCursorMapping(managedWindow); return; }
        for (NSWindow *w in NSApp.windows)
            if (w.visible && eligible(w)) { attach(w); if (managedWindow) { scheduleEntry(w); break; } }
    }]];
}

// A native Wine startup can nest its AppKit event loop while the first
// main-run-loop block is still pending. Window creation is the reliable
// boundary once the Objective-C image and its classes are fully registered.
static id (*originalCreateWindow)(id, SEL, const void *, NSRect, void *, id);
static id createWindow(id cls, SEL cmd, const void *features, NSRect rect, void *hwnd, id queue) {
    install();
    if (compatibleDriver && !originalPostEvent) installInput();
    return originalCreateWindow(cls, cmd, features, rect, hwnd, queue);
}

static void hookWindowCreation(void) {
    Class cls = objc_getClass("WineWindow");
    if (!cls || originalCreateWindow) return;
    SEL selector = sel_registerName("createWindowWithFeatures:windowFrame:hwnd:queue:");
    Method method = class_getClassMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 6) return;
    originalCreateWindow = (void *)method_getImplementation(method);
    class_replaceMethod(object_getClass(cls), selector, (IMP)createWindow, method_getTypeEncoding(method));
}

static void displayDriverReady(void) {
    hookWindowCreation();
    if (!installed && !installFailed && !atomic_exchange(&installQueued, true)) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{ install(); });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

static void registerWineDriver(const struct np_user_driver *driver, unsigned version) {
    compatibleDriver = version == NP_WINE_DRIVER_VERSION;
    displayDriverReady();
    np_game_space_set_driver(driver, version);
}

static void imageAdded(const struct mach_header *header, intptr_t slide) {
    Dl_info info;
    if (!dladdr(header, &info) || !info.dli_fname) return;
    const char *name = strrchr(info.dli_fname, '/');
    if (strcmp(name ? name + 1 : info.dli_fname, "winemac.so")) return;

    if (!readEventTypes((const struct mach_header_64 *)header)) {
        eventTypes.button = eventTypes.absolute = eventTypes.scroll = -1;
        fprintf(stderr, "[native-space] pid %d Wine event table not found; pointer mapping off\n", getpid());
    }
    int count = np_rebind_import_with_original((const struct mach_header_64 *)header, slide,
                                               "___wine_set_user_driver", (void *)registerWineDriver,
                                               &np_game_space_original_registration);
    fprintf(stderr, "[native-space] pid %d Wine display registration bindings: %d\n", getpid(), count);
    displayDriverReady();
}

__attribute__((constructor)) static void start(void) {
    const char *value = getenv("NOTPROTON_NATIVE_SIZE");
    char executable[PATH_MAX], manifest[32];
    uint32_t capacity = sizeof(executable);
    // An explicit empty setting disables the feature. A copied per-game
    // launcher can recover the selection when Wine drops the host environment.
    if (!value && _NSGetExecutablePath(executable, &capacity) == 0 &&
        np_game_space_manifest(executable, manifest, sizeof(manifest))) value = manifest;
    unsigned width, height;
    if (!np_game_space_size(value, &width, &height)) return;
    pixels = NSMakeSize(width, height);
    np_game_space_set_display_size(width, height);
    const char *appID = getenv("STEAM_COMPAT_APP_ID");
    BOOL belowZero = appID && !strcmp(appID, "848450");
    BOOL source = appID && !strcmp(appID, "240");
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        belowZero |= [bundle isEqualToString:@"com.notproton.launcher.848450"];
        source |= [bundle isEqualToString:@"com.notproton.launcher.240"];
    }
    // Source also supports explicit borderless windowed launches.
    char **argv = *_NSGetArgv();
    for (int i = 1; source && i < *_NSGetArgc(); i++)
        if (!strcasecmp(argv[i], "-noborder")) source = NO;
    fullscreenFromWindowStyle = belowZero || source;
    fprintf(stderr, "[native-space] requested %ux%u in pid %d\n", width, height, getpid());
    _dyld_register_func_for_add_image(imageAdded);
}
