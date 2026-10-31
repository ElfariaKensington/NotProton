// App-local fullscreen presentation: edges must stay usable by the game.
// No system preferences or application-switching restrictions are changed.
static NSApplicationPresentationOptions npRequestedPresentation;
static BOOL npOwnsPresentation;
static void (*npPresentationSet)(id, SEL, NSApplicationPresentationOptions);

static BOOL npPresentationTarget(NSWindow *window, BOOL active, NSWindow *modal) {
    if (!active || !window || !window.isVisible || !window.isKeyWindow || window.isMiniaturized ||
        modal || window.attachedSheet || window.parentWindow ||
        (window.styleMask & NSWindowStyleMaskUtilityWindow) ||
        [NSStringFromClass(window.class) rangeOfString:@"Wine"].location == NSNotFound) return NO;
    NSView *view = window.contentView;
    if (!renderedAtPoint(view, NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds)))) return NO;
    if (window.styleMask & NSWindowStyleMaskFullScreen) return YES;
    if (window.styleMask & NSWindowStyleMaskTitled) return NO;
    NSScreen *screen = window.screen;
    if (!screen) return NO;
    NSRect content = [window convertRectToScreen:view.frame];
    return NSContainsRect(NSInsetRect(content, -1, -1), screen.frame);
}
static BOOL npShouldProtectPresentation(void) {
    return npPresentationTarget(NSApp.keyWindow, NSApp.isActive, NSApp.modalWindow);
}
static NSApplicationPresentationOptions npProtectedPresentation(NSApplicationPresentationOptions options) {
    // autoHideToolbar requires autoHideMenuBar, so it cannot survive this policy.
    options &= ~(NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar |
                 NSApplicationPresentationAutoHideToolbar);
    return options | NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
}
static void npApplyPresentation(BOOL protect) {
    if (!npPresentationSet) return;
    if (protect) {
        NSApplicationPresentationOptions options = npProtectedPresentation(npRequestedPresentation);
        if (!npOwnsPresentation || NSApp.presentationOptions != options)
            npPresentationSet(NSApp, @selector(setPresentationOptions:), options);
        npOwnsPresentation = YES;
    } else if (npOwnsPresentation) {
        npOwnsPresentation = NO;
        npPresentationSet(NSApp, @selector(setPresentationOptions:), npRequestedPresentation);
    }
}
static void npSetPresentation(id application, SEL selector, NSApplicationPresentationOptions options) {
    if (!NSThread.isMainThread) { npPresentationSet(application, selector, options); return; }
    npRequestedPresentation = options;
    BOOL protect = npShouldProtectPresentation();
    npOwnsPresentation = protect;
    npPresentationSet(application, selector, protect ? npProtectedPresentation(options) : options);
}
static void npRefreshPresentation(void) { npApplyPresentation(npShouldProtectPresentation()); }
static void npWatchPresentation(void) {
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
            if ([note.name isEqualToString:NSApplicationDidResignActiveNotification] ||
                [note.name isEqualToString:NSWindowDidResignKeyNotification] ||
                [note.name isEqualToString:NSWindowWillCloseNotification] ||
                [note.name isEqualToString:NSWindowWillBeginSheetNotification]) npApplyPresentation(NO);
            else npRefreshPresentation();
        }];
    [center addObserverForName:NSApplicationWillTerminateNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) { (void)note; npApplyPresentation(NO); }];
    npRefreshPresentation();
}
