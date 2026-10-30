// Built as winemac.so so caller-scoping is exercised through a separate Mach-O image.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include "../feats/displayconfig.h"

NSDictionary *np_display_probe(void) {
    CGDirectDisplayID display = CGMainDisplayID();
    CGRect bounds = CGDisplayBounds(display);
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, NULL);
    NSScreen *screen = NSScreen.screens.firstObject;
    unsigned width, height;
    BOOL enforced = np_display_parse(getenv("NOTPROTON_DISPLAY_RESOLUTION"), &width, &height);
    NSDictionary *result = @{
        @"width": @(bounds.size.width), @"height": @(bounds.size.height),
        @"modeWidth": @(CGDisplayModeGetWidth(mode)), @"modeHeight": @(CGDisplayModeGetHeight(mode)),
        @"pixelWidth": @(CGDisplayModeGetPixelWidth(mode)), @"pixelHeight": @(CGDisplayModeGetPixelHeight(mode)),
        @"screenWidth": @(screen.frame.size.width), @"screenHeight": @(screen.frame.size.height),
        @"scale": @(screen.backingScaleFactor), @"modes": @(CFArrayGetCount(modes)),
        @"setMode": @(enforced ? CGDisplaySetDisplayMode(display, mode, NULL) : kCGErrorSuccess)
    };
    CFRelease(modes); CGDisplayModeRelease(mode);
    return result;
}
