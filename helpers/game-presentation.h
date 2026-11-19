#include <dlfcn.h>
// App-local fullscreen presentation. Never change global preferences or Cmd-Tab.
static NSApplicationPresentationOptions npRequestedPresentation;
static BOOL npOwnsPresentation;
static __weak NSWindow *npPresentationWindow;
static int32_t (*npSystemUISet)(uint32_t, uint32_t);
static void (*npSystemUIGet)(uint32_t *, uint32_t *);
static BOOL npOwnsSystemUI;
static uint32_t npSavedSystemUIMode, npSavedSystemUIOptions;
static void (*npPresentationSet)(id, SEL, NSApplicationPresentationOptions);

static BOOL npPresentationRenderer(NSView *view) {
    if (!view || view.hidden || view.alphaValue <= 0) return NO;
    // Presentation belongs to the whole game window, not the cursor hit-test view.
    // HUD/native overlays over the center must not release fullscreen protection.
    if (metalAtPoint(view.layer, CGPointMake(CGRectGetMidX(view.layer.bounds), CGRectGetMidY(view.layer.bounds)))) return YES;
    SEL gl = NSSelectorFromString(@"hasGLDescendant");
    if ([view respondsToSelector:gl] && ((BOOL (*)(id, SEL))objc_msgSend)(view, gl)) return YES;
    for (NSView *child in view.subviews) if (npPresentationRenderer(child)) return YES;
    return NO;
}
static BOOL npPresentationFullscreen(NSWindow *window, NSWindow *modal, BOOL alreadyOwned) {
    if (!window || !window.isVisible || !window.isOnActiveSpace || window.isMiniaturized || modal ||
        window.attachedSheet || window.parentWindow ||
        (window.styleMask & NSWindowStyleMaskUtilityWindow) ||
        [NSStringFromClass(window.class) rangeOfString:@"Wine"].location == NSNotFound) return NO;
    BOOL native = (window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    // Native Space membership is authoritative, including GPU layer rebuilds.
    if (native) return YES;
    if (!alreadyOwned && !npPresentationRenderer(window.contentView)) return NO;
    SEL fullscreen = NSSelectorFromString(@"fullscreen");
    BOOL wineFullscreen = [window respondsToSelector:fullscreen] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(window, fullscreen);
    if ((window.styleMask & NSWindowStyleMaskTitled) && !wineFullscreen) return NO;
    NSScreen *screen = window.screen;
    if (!screen) return NO;
    NSRect content = [window convertRectToScreen:window.contentView.frame];
    NSEdgeInsets insets = screen.safeAreaInsets;
    NSRect safe = screen.frame;
    safe.origin.x += insets.left; safe.origin.y += insets.bottom;
    safe.size.width -= insets.left + insets.right;
    safe.size.height -= insets.top + insets.bottom;
    return NSContainsRect(NSInsetRect(content, -1, -1), safe);
}
static BOOL npPresentationTarget(NSWindow *window, BOOL active, NSWindow *modal) {
    return active && window.isKeyWindow && npPresentationFullscreen(window, modal, NO);
}
static NSWindow *npPresentationCandidate(NSWindow *key, NSWindow *previous, BOOL active, NSWindow *modal) {
    if (!active || modal) return nil;
    // A transient nil key window during a same-app handoff is not a mode change.
    if ((!key || key == previous) && previous && npPresentationFullscreen(previous, modal, YES)) return previous;
    return npPresentationTarget(key, active, modal) ? key : nil;
}
static BOOL npPresentationAuxiliaryKey(NSWindow *window) {
    if (!window) return YES;
    NSString *name = NSStringFromClass(window.class);
    return [name hasPrefix:@"NSToolbarFullScreen"] || [name hasPrefix:@"NSFullScreen"] ||
        [name hasPrefix:@"_NSFullScreen"];
}
static BOOL npShouldProtectPresentation(void) {
    NSWindow *key = NSApp.keyWindow;
    NSWindow *candidate = npPresentationCandidate(key, npPresentationWindow, NSApp.isActive, NSApp.modalWindow);
    if (!candidate && NSApp.isActive && !NSApp.modalWindow && npPresentationAuxiliaryKey(key)) {
        for (NSWindow *window in NSApp.orderedWindows) {
            if (npPresentationFullscreen(window, nil, NO)) { candidate = window; break; }
        }
    }
    npPresentationWindow = candidate;
    return candidate != nil;
}
static NSApplicationPresentationOptions npProtectedPresentation(NSApplicationPresentationOptions options) {
    options &= ~(NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar |
                 NSApplicationPresentationAutoHideToolbar);
    return options | NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
}
static BOOL npPresentationNeedsUpdate(NSApplicationPresentationOptions desired,
                                      NSApplicationPresentationOptions requested,
                                      NSApplicationPresentationOptions system, BOOL owned) {
    NSApplicationPresentationOptions mask = NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar |
        NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
    return !owned || requested != desired || (system & mask) != (desired & mask);
}
static void npEnsureSystemUI(NSApplicationPresentationOptions desired,
                             NSApplicationPresentationOptions effective, BOOL active) {
    NSApplicationPresentationOptions mask = NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar |
        NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
    if (!active || (effective & mask) == (desired & mask) || !npSystemUISet || !npSystemUIGet) return;
    if (!npOwnsSystemUI) {
        npSystemUIGet(&npSavedSystemUIMode, &npSavedSystemUIOptions);
        npOwnsSystemUI = YES;
    }
    // Space changes can leave the process-local HIToolbox UI mode at Normal
    // while AppKit still caches HideDock/HideMenuBar. Its identical setter then
    // does nothing. Reapply AllHidden directly, without changing global prefs.
    // Bits 0/1 are AutoShowMenuBar/AnimateMenuBar, neither is wanted during play.
    npSystemUISet(3, npSavedSystemUIOptions & ~3u);
}
static void npRestoreSystemUI(void) {
    if (!npOwnsSystemUI) return;
    npOwnsSystemUI = NO;
    if (npSystemUISet) npSystemUISet(npSavedSystemUIMode, npSavedSystemUIOptions);
}
static void npWriteProtectedPresentation(id application, NSApplicationPresentationOptions desired) {
    npPresentationSet(application, @selector(setPresentationOptions:), desired);
    npEnsureSystemUI(desired, [application currentSystemPresentationOptions], [application isActive]);
}
static void npLogPresentation(BOOL protect) {
    static NSString *last;
    NSWindow *key = NSApp.keyWindow;
    NSString *state = [NSString stringWithFormat:@"active=%d space=%d key=%ld keyClass=%@ keyStyle=0x%lx owner=%ld protect=%d requested=0x%lx system=0x%lx",
        NSApp.isActive, key.isOnActiveSpace, (long)key.windowNumber, key ? NSStringFromClass(key.class) : @"none", (unsigned long)key.styleMask,
        (long)npPresentationWindow.windowNumber, protect,
        (unsigned long)NSApp.presentationOptions, (unsigned long)NSApp.currentSystemPresentationOptions];
    if (![state isEqualToString:last]) {
        fprintf(stderr, "NotProton presentation v3: %s\n", state.UTF8String);
        last = state;
    }
}
static void npApplyPresentation(BOOL protect) {
    if (!npPresentationSet) return;
    if (protect) {
        NSApplicationPresentationOptions options = npProtectedPresentation(npRequestedPresentation);
        if (npPresentationNeedsUpdate(options, NSApp.presentationOptions, NSApp.currentSystemPresentationOptions, npOwnsPresentation))
            npWriteProtectedPresentation(NSApp, options);
        npOwnsPresentation = YES;
    } else if (npOwnsPresentation) {
        npOwnsPresentation = NO;
        npRestoreSystemUI();
        npPresentationSet(NSApp, @selector(setPresentationOptions:), npRequestedPresentation);
    } else if (!protect) npRestoreSystemUI();
}
static void npSetPresentation(id application, SEL selector, NSApplicationPresentationOptions options) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ npSetPresentation(application, selector, options); });
        return;
    }
    npRequestedPresentation = options;
    BOOL protect = npShouldProtectPresentation();
    npOwnsPresentation = protect;
    if (protect) npWriteProtectedPresentation(application, npProtectedPresentation(options));
    else { npRestoreSystemUI(); npPresentationSet(application, selector, options); }
    npLogPresentation(protect);
}
static void npRefreshPresentation(void) {
    BOOL protect = npShouldProtectPresentation();
    npApplyPresentation(protect);
    npLogPresentation(protect);
}
static BOOL npPresentationEventReleases(NSString *name, NSWindow *changed, NSWindow *owner) {
    if ([name isEqualToString:NSApplicationDidResignActiveNotification]) return YES;
    return owner && changed == owner &&
        ([name isEqualToString:NSWindowWillCloseNotification] || [name isEqualToString:NSWindowWillBeginSheetNotification]);
}
static void npWatchPresentation(void) {
    npSystemUISet = dlsym(RTLD_DEFAULT, "SetSystemUIMode");
    npSystemUIGet = dlsym(RTLD_DEFAULT, "GetSystemUIMode");
    npRequestedPresentation = NSApp.presentationOptions;
    Method method = class_getInstanceMethod(NSApplication.class, @selector(setPresentationOptions:));
    npPresentationSet = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)npSetPresentation);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification,
        NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification, NSWindowDidResizeNotification,
        NSWindowWillCloseNotification, NSWindowDidMiniaturizeNotification,
        NSWindowWillBeginSheetNotification, NSWindowDidEndSheetNotification,
        NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification])
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (npPresentationEventReleases(note.name, note.object, npPresentationWindow)) {
                npPresentationWindow = nil;
                npApplyPresentation(NO);
                npLogPresentation(NO);
            } else if ([note.name isEqualToString:NSWindowDidResignKeyNotification]) {
                // AppKit updates keyWindow as this notification is dispatched.
                dispatch_async(dispatch_get_main_queue(), ^{ npRefreshPresentation(); });
            } else npRefreshPresentation();
        }];
    [center addObserverForName:NSApplicationWillTerminateNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) { (void)note; npPresentationWindow = nil; npApplyPresentation(NO); }];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceActiveSpaceDidChangeNotification, NSWorkspaceDidActivateApplicationNotification])
        [workspace addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            npRefreshPresentation();
            // Let the paired AppKit activation/key-window notification settle.
            dispatch_async(dispatch_get_main_queue(), ^{ npRefreshPresentation(); });
        }];
    npRefreshPresentation();
}
