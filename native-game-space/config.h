#ifndef NOTPROTON_NATIVE_GAME_SPACE_CONFIG_H
#define NOTPROTON_NATIVE_GAME_SPACE_CONFIG_H

#include <limits.h>
#include <stdio.h>
#include <string.h>

static int np_game_space_size(const char *value, unsigned *width, unsigned *height) {
    if (!value || !*value) return 0;
    const char *p = value;
    unsigned w = 0, h = 0;
    for (; *p >= '0' && *p <= '9'; p++) {
        w = w * 10 + (unsigned)(*p - '0');
        if (w > 16384) return 0;
    }
    if (p == value || *p++ != 'x') return 0;
    const char *start = p;
    for (; *p >= '0' && *p <= '9'; p++) {
        h = h * 10 + (unsigned)(*p - '0');
        if (h > 16384) return 0;
    }
    if (p == start || *p || w < 320 || h < 200) return 0;
    *width = w;
    *height = h;
    return 1;
}

static int np_game_space_manifest(const char *executable, char *value, size_t capacity) {
    const char *root = strstr(executable, "/notproton/launchers/");
    if (!root || !capacity) return 0;
    const char *id = root + strlen("/notproton/launchers/");
    const char *end = id;
    while (*end >= '0' && *end <= '9') end++;
    if (end == id || *end != '/') return 0;
    char path[PATH_MAX];
    int n = snprintf(path, sizeof path, "%.*s/.native-game-space", (int)(end - executable), executable);
    if (n < 0 || (size_t)n >= sizeof path) return 0;
    FILE *file = fopen(path, "r");
    if (!file) return 0;
    size_t length = fread(value, 1, capacity, file);
    int ok = !ferror(file) && length > 1 && length < capacity &&
             value[length - 1] == '\n' && !memchr(value, 0, length);
    fclose(file);
    if (ok) value[length - 1] = 0;
    return ok;
}

#endif
