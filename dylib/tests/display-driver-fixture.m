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

// Mirror the Wine input boundary without posting events or moving the system cursor.
@interface NPInputEvent : NSObject
@property NSWindow *window;
@property CGEventRef CGEvent;
@property NSEventType type;
@end
@implementation NPInputEvent
@end
@interface WineApplicationController : NSObject
@property NSDictionary *result;
- (NSPoint)flippedMouseLocation:(NSPoint)point;
- (void)handleMouseButton:(NSEvent *)event;
- (void)handleMouseMove:(NSEvent *)event;
- (void)handleScrollWheel:(NSEvent *)event;
@end
@implementation WineApplicationController
- (NSPoint)flippedMouseLocation:(NSPoint)point {
    return NSMakePoint(point.x, NSMaxY(NSScreen.screens.firstObject.frame) - point.y);
}
- (void)handleMouseButton:(NSEvent *)event {
    CGPoint point = CGEventGetLocation(event.CGEvent);
    NSPoint cocoa = [self flippedMouseLocation:NSPointFromCGPoint(point)];
    NSRect content = [event.window contentRectForFrameRect:event.window.frame];
    self.result = @{@"hit": @(NSMouseInRect(cocoa, content, NO)), @"x": @(point.x), @"y": @(point.y),
                    @"cocoaX": @(cocoa.x), @"cocoaY": @(cocoa.y)};
}
- (void)handleMouseMove:(NSEvent *)event { [self handleMouseButton:event]; }
- (void)handleScrollWheel:(NSEvent *)event { [self handleMouseButton:event]; }
@end
NSDictionary *np_input_probe(NSWindow *window, CGPoint physical, CGFloat screenTop, CGPoint (*rawLocation)(CGEventRef)) {
    WineApplicationController *controller = [WineApplicationController new];
    CGEventRef cg = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, physical, kCGMouseButtonLeft);
    NPInputEvent *event = [NPInputEvent new];event.window = window;event.CGEvent = cg;event.type = NSEventTypeLeftMouseDown;
    [controller handleMouseButton:(NSEvent *)(id)event];
    NSMutableDictionary *result = [controller.result mutableCopy];
    NSPoint cursor = [controller flippedMouseLocation:NSMakePoint(physical.x, screenTop - physical.y)];
    result[@"pollMatches"] = @(fabs(cursor.x - [result[@"x"] doubleValue]) < .01 &&
                              fabs(cursor.y - [result[@"y"] doubleValue]) < .01);
    CGEventSetLocation(cg, NSPointToCGPoint(cursor));
    CGPoint roundTrip = rawLocation(cg);
    result[@"warpMatches"] = @(fabs(roundTrip.x - physical.x) < .01 && fabs(roundTrip.y - physical.y) < .01);
    event.type = NSEventTypeScrollWheel;
    [controller handleScrollWheel:(NSEvent *)(id)event];
    result[@"scrollMatches"] = @(([controller.result[@"hit"] boolValue] &&
         fabs([controller.result[@"x"] doubleValue] - cursor.x) < .01 &&
         fabs([controller.result[@"y"] doubleValue] - cursor.y) < .01));
    CFRelease(cg);
    return result;
}
