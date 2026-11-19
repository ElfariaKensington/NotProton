#ifndef NOTPROTON_NATIVE_GAME_SPACE_INPUT_H
#define NOTPROTON_NATIVE_GAME_SPACE_INPUT_H

// macdrv_event layout from Wine macdrv_cocoa.h; event type numbers differ per build.
struct np_mouse_event {
    int refs, deliver, type;
    void *window;
    union {
        struct { int button; bool pressed; int x, y; } button;
        struct { int x, y; } move;
        struct { int dx, dy, x, y; } scroll;
    } data;
};
_Static_assert(offsetof(struct np_mouse_event, data) == 24, "Wine event layout");

#endif
