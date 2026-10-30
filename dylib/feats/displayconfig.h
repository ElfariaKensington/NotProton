// Per-game display configuration, shared by the native helper and WebUI service.
#ifndef NOTPROTON_DISPLAYCONFIG_H
#define NOTPROTON_DISPLAYCONFIG_H
#include <stdio.h>
#include <string.h>

#define NP_DISPLAY_CONFIG "notproton-display"
#define NP_DISPLAY_MIN_WIDTH 640
#define NP_DISPLAY_MIN_HEIGHT 480
#define NP_DISPLAY_MAX 16384

static int np_display_parse(const char *text, unsigned *width, unsigned *height) {
    unsigned w = 0, h = 0;
    const char *p = text;
    if (!p || !*p) return 0;
    while (*p >= '0' && *p <= '9') {
        w = w * 10 + (unsigned)(*p++ - '0');
        if (w > NP_DISPLAY_MAX) return 0;
    }
    if (*p++ != 'x') return 0;
    while (*p >= '0' && *p <= '9') {
        h = h * 10 + (unsigned)(*p++ - '0');
        if (h > NP_DISPLAY_MAX) return 0;
    }
    if (*p == '\n') p++;
    if (*p || w < NP_DISPLAY_MIN_WIDTH || h < NP_DISPLAY_MIN_HEIGHT) return 0;
    *width = w; *height = h;
    return 1;
}
#endif
