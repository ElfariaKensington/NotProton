#define NP_CURSOR_TEST
#include "../../helpers/game-cursor.m"
#import <Metal/Metal.h>
#include <stdio.h>

@interface WineWindow : NSPanel
@property BOOL testVisible, testKey, testMinimized;
@property NSWindow *testSheet;
@end
@implementation WineWindow
- (BOOL)isVisible { return self.testVisible; }
- (BOOL)isKeyWindow { return self.testKey; }
- (BOOL)isMiniaturized { return self.testMinimized; }
- (NSWindow *)attachedSheet { return self.testSheet; }
@end
@interface GLView : NSView
@end
@implementation GLView
- (BOOL)hasGLDescendant { return YES; }
@end
@interface NPWineCursorState : NSObject {
@public BOOL clientWantsCursorHidden, cursorHidden;
@public unsigned hides, shows;
}
@end
@implementation NPWineCursorState
@end
static void wineCursorUpdate(id value, SEL selector, BOOL force) {
    (void)selector; (void)force;
    NPWineCursorState *state=value;
    if(state->clientWantsCursorHidden && !state->cursorHidden){state->cursorHidden=YES;state->hides++;}
    if(!state->clientWantsCursorHidden && state->cursorHidden){state->cursorHidden=NO;state->shows++;}
}
static int failures, checks;
static NSCursor *testCurrent;
static unsigned sets;
static id currentCursor(id self, SEL selector) { (void)self;(void)selector;return testCurrent; }
static void recordSet(id cursor, SEL selector) { (void)selector;testCurrent=cursor;sets++; }
static void check(BOOL condition, const char *message) {
    checks++; if (!condition) {fprintf(stderr,"FAIL: %s\n",message);failures++;}
}
static NSPoint screenPoint(NSWindow *window, NSView *view, NSPoint point) {
    return [window convertPointToScreen:[view convertPoint:point toView:nil]];
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1],"--classify")) {puts(gameProcess()?"game":"other");return 0;}
        [NSApplication sharedApplication];
        WineWindow *game=[[WineWindow alloc] initWithContentRect:NSMakeRect(100,100,800,600)
            styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        game.testVisible=YES;game.testKey=YES;
        NSView *render=[[NSView alloc] initWithFrame:NSMakeRect(50,50,600,400)];
        CAMetalLayer *layer=[CAMetalLayer layer];layer.device=MTLCreateSystemDefaultDevice();
        check(layer.device!=nil,"Metal fixture has a real device");
        render.wantsLayer=YES;render.layer=layer;[game.contentView addSubview:render];
        NSPoint inside=screenPoint(game,render,NSMakePoint(300,200));
        NSInteger top=game.windowNumber;
        check(cursorTarget(game,inside,top,YES,nil),"focused game renderer hides cursor");
        check(!cursorTarget(game,inside,top,NO,nil),"inactive game restores cursor");
        check(!cursorTarget(game,inside,top+1,YES,nil),"another app or popup covering game restores cursor");
        check(!cursorTarget(game,inside,top,YES,game),"native modal session restores cursor");
        game.testKey=NO;check(!cursorTarget(game,inside,top,YES,nil),"game losing key focus restores cursor");game.testKey=YES;
        game.testVisible=NO;check(!cursorTarget(game,inside,top,YES,nil),"closed or hidden game restores cursor");game.testVisible=YES;
        game.testMinimized=YES;check(!cursorTarget(game,inside,top,YES,nil),"minimized game restores cursor");game.testMinimized=NO;
        game.testSheet=game;check(!cursorTarget(game,inside,top,YES,nil),"attached sheet restores cursor");game.testSheet=nil;
        check(!cursorTarget(game,screenPoint(game,game.contentView,NSMakePoint(10,10)),top,YES,nil),"unrendered window region keeps cursor");
        check(!cursorTarget(game,screenPoint(game,game.contentView,NSMakePoint(20,615)),top,YES,nil),"titlebar keeps cursor");
        render.hidden=YES;check(!cursorTarget(game,inside,top,YES,nil),"hidden renderer keeps cursor");render.hidden=NO;
        NSButton *control=[[NSButton alloc] initWithFrame:NSMakeRect(100,100,100,50)];[render addSubview:control];
        check(!cursorTarget(game,screenPoint(game,control,NSMakePoint(20,20)),top,YES,nil),"native controls over renderer keep cursor");[control removeFromSuperview];
        game.styleMask=NSWindowStyleMaskTitled|NSWindowStyleMaskClosable;
        check(!cursorTarget(game,inside,top,YES,nil),"nonresizable graphics dialog keeps cursor");
        game.styleMask=NSWindowStyleMaskBorderless;
        check(cursorTarget(game,inside,top,YES,nil),"borderless game hides cursor");
        NSWindow *native=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,100,100) styleMask:0 backing:NSBackingStoreBuffered defer:NO];
        check(!cursorTarget(native,inside,native.windowNumber,YES,nil),"native app windows never qualify");
        WineWindow *dialog=[[WineWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        dialog.testVisible=YES;dialog.testKey=YES;
        check(!cursorTarget(dialog,screenPoint(dialog,dialog.contentView,NSMakePoint(50,50)),dialog.windowNumber,YES,nil),"GDI startup dialog keeps cursor");
        [game addChildWindow:dialog ordered:NSWindowAbove];
        check(!cursorTarget(dialog,inside,dialog.windowNumber,YES,nil),"child dialog keeps cursor");[game removeChildWindow:dialog];
        [render removeFromSuperview];GLView *gl=[[GLView alloc] initWithFrame:NSMakeRect(0,0,800,600)];[game.contentView addSubview:gl];
        check(cursorTarget(game,screenPoint(game,gl,NSMakePoint(100,100)),top,YES,nil),"OpenGL game hides cursor");
        [gl removeFromSuperview];
        check(!cursorTarget(game,inside,top,YES,nil),"bitmap splash keeps cursor");
        // Stub cursor output: never hide or move the user's real cursor in this test.
        Method current=class_getClassMethod(NSCursor.class,@selector(currentCursor));IMP old=method_getImplementation(current);
        method_setImplementation(current,(IMP)currentCursor);
        transparentCursor=makeTransparentCursor();
        NSBitmapImageRep *pixels=(NSBitmapImageRep *)transparentCursor.image.representations.firstObject;
        check(pixels.hasAlpha && pixels.bitmapData[3]==0,"cursor has a valid transparent bitmap");
        cursorSet=recordSet;testCurrent=NSCursor.crosshairCursor;
        applyCursor(YES);check(testCurrent==transparentCursor && showingTransparent,"entering game replaces cursor");
        unsigned before=sets;applyCursor(YES);check(sets==before,"repeated refresh does not accumulate hiding");
        applyCursor(NO);check(testCurrent==NSCursor.crosshairCursor && !showingTransparent,"leaving restores the requested cursor");
        before=sets;applyCursor(NO);check(sets==before,"repeated restore leaves other cursors alone");
        applyCursor(YES);testCurrent=NSCursor.IBeamCursor;applyCursor(NO);
        check(testCurrent==NSCursor.IBeamCursor,"focus change does not overwrite another owner's cursor");
        applyCursor(YES);testCurrent=NSCursor.arrowCursor;applyCursor(YES);
        check(testCurrent==transparentCursor,"late Wine cursor changes are suppressed");applyCursor(NO);
        NPWineCursorState *wine=[NPWineCursorState new];
        wine->clientWantsCursorHidden=YES;wine->cursorHidden=YES;
        wineWantsHidden=class_getInstanceVariable(NPWineCursorState.class,"clientWantsCursorHidden");
        wineUpdateCursor=wineCursorUpdate;
        updateWineCursorForTarget(wine,@selector(updateCursor:),NO,NO);
        check(!wine->cursorHidden && wine->shows==1 && wine->clientWantsCursorHidden,"dialog releases Wine hide while preserving game request");
        updateWineCursorForTarget(wine,@selector(updateCursor:),NO,NO);
        check(wine->shows==1,"dialog does not unhide repeatedly");
        updateWineCursorForTarget(wine,@selector(updateCursor:),NO,YES);
        check(wine->cursorHidden && wine->hides==1,"returning to game restores Wine hide request");
        updateWineCursorForTarget(wine,@selector(updateCursor:),NO,NO);
        check(!wine->cursorHidden && wine->shows==2,"focus loss or next dialog releases Wine hide again");
        method_setImplementation(current,old);
        printf("cursor: %d policy and ownership checks; %d failures\n",checks,failures);
        return failures?1:0;
    }
}
