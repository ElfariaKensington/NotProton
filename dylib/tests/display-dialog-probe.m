#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
static unsigned ticks;
__attribute__((constructor)) static void setup(void) {
 dispatch_async(dispatch_get_main_queue(),^{
  NSTimer *timer=[NSTimer timerWithTimeInterval:.2 repeats:YES block:^(NSTimer *t){
   if(++ticks>100){[t invalidate];return;}
   for(NSWindow *w in NSApp.windows){
    if(![w.title containsString:@"NotProton driver warning"])continue;
    NSString *log=[NSString stringWithContentsOfFile:@(getenv("NP_INPUT_LOG")) encoding:NSUTF8StringEncoding error:nil];
    NSRange line=[log rangeOfString:@"buttonLocal="];if(line.location==NSNotFound)return;
    double x,y;if(sscanf([log substringFromIndex:line.location].UTF8String,"buttonLocal=%lf,%lf",&x,&y)!=2)return;
    NSPoint local=NSMakePoint(x,y);if(!w.contentView.isFlipped)local.y=w.contentView.bounds.size.height-y;
    NSPoint inWindow=[w.contentView convertPoint:local toView:nil],cocoa=[w convertPointToScreen:inWindow];
    CGFloat height=NSScreen.screens.firstObject.frame.size.height;
    CGPoint physical=CGPointMake(cocoa.x,height-cocoa.y);
    id controller=((id(*)(id,SEL))objc_msgSend)(NSClassFromString(@"WineApplicationController"),NSSelectorFromString(@"sharedController"));
    fprintf(stderr,"PROBE frame=%s content=%s bounds=%s point=%s physical=%s ctrl=%p active=%d key=%d\n",NSStringFromRect(w.frame).UTF8String,NSStringFromRect(w.contentView.frame).UTF8String,NSStringFromRect(w.contentView.bounds).UTF8String,NSStringFromPoint(local).UTF8String,NSStringFromPoint(NSPointFromCGPoint(physical)).UTF8String,controller,NSApp.active,w.keyWindow);
    for(NSString *name in @[@"flippedMouseLocation:",@"handleMouseButton:"]){Dl_info di={0};IMP imp=class_getMethodImplementation([controller class],NSSelectorFromString(name));dladdr(imp,&di);fprintf(stderr,"PROBE %s=%s\n",name.UTF8String,di.dli_fname);}
    // Reproduce a game keeping mouse capture on its splash while a modal dialog opens.
    NSWindow *stale=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,50,50) styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    Ivar capture=class_getInstanceVariable([controller class],"mouseCaptureWindow");
    id previous=object_getIvar(controller,capture);
    object_setIvar(controller,capture,stale);
    for(NSNumber *type in @[@(NSEventTypeMouseMoved),@(NSEventTypeLeftMouseDown),@(NSEventTypeLeftMouseUp)]){
     NSEvent *e=[NSEvent mouseEventWithType:type.unsignedIntegerValue location:inWindow modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
     CGEventSetLocation(e.CGEvent,physical);
     SEL sel=NSSelectorFromString(type.unsignedIntegerValue==NSEventTypeMouseMoved?@"handleMouseMove:":@"handleMouseButton:");
     ((void(*)(id,SEL,id))objc_msgSend)(controller,sel,e);
    }
    fprintf(stderr,"nativeDialogInput=capture%s\n",object_getIvar(controller,capture)==stale?"Restored":"FAILED");
    object_setIvar(controller,capture,previous);
    [t invalidate];return;
   }
  }];[NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
 });
}
