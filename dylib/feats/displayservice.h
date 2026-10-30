// Included after compatsvc's prefix resolver and protobuf helpers.
#ifndef NOTPROTON_DISPLAYSERVICE_H
#define NOTPROTON_DISPLAYSERVICE_H
#include "displayconfig.h"
#include <CoreGraphics/CoreGraphics.h>

static int display_path(uint32_t appid, char *dir, char *path) {
    np_prefix_state_t st;
    if (!read_state(appid, &st)) return 0;
    int n = st.compatdata[0] ? snprintf(dir, PATH_MAX, "%s", st.compatdata)
        : snprintf(dir, PATH_MAX, "%s/Library/Application Support/Steam/steamapps/compatdata/%u",
                   np_home_dir(), appid);
    if (n < 0 || n >= PATH_MAX) return 0;
    n = snprintf(path, PATH_MAX, "%s/" NP_DISPLAY_CONFIG, dir);
    return n >= 0 && n < PATH_MAX;
}

static int get_display(uintptr_t request, uintptr_t response) {
    char dir[PATH_MAX], path[PATH_MAX], text[32] = "";
    uint32_t appid = request_appid(request);
    if (!display_path(appid, dir, path)) return RESULT_FAIL;
    FILE *f = fopen(path, "rb");
    if (f) {
        size_t n = fread(text, 1, sizeof text - 1, f);
        int ok = !ferror(f) && feof(f);
        fclose(f);
        text[n] = '\0';
        unsigned w, h;
        if (!ok || memchr(text, '\0', n) || !np_display_parse(text, &w, &h)) return RESULT_FAIL;
        snprintf(text, sizeof text, "%ux%u", w, h);
    } else if (errno != ENOENT) return RESULT_FAIL;
    return answer_json(response, appid, text);
}

// Include both HiDPI logical sizes and physical pixel sizes shown by macOS.
#define DISPLAY_MODE_MAX 256
typedef struct { unsigned width, height; } display_size_t;
static void display_add_size(display_size_t *sizes, size_t *count, size_t w, size_t h) {
    if (w < NP_DISPLAY_MIN_WIDTH || h < NP_DISPLAY_MIN_HEIGHT ||
        w > NP_DISPLAY_MAX || h > NP_DISPLAY_MAX) return;
    for (size_t i = 0; i < *count; i++)
        if (sizes[i].width == w && sizes[i].height == h) return;
    if (*count < DISPLAY_MODE_MAX) sizes[(*count)++] = (display_size_t){ (unsigned)w, (unsigned)h };
}
static int display_size_compare(const void *a, const void *b) {
    const display_size_t *x = a, *y = b;
    unsigned xa = x->width * x->height, ya = y->width * y->height;
    if (xa != ya) return xa > ya ? -1 : 1;
    return x->width > y->width ? -1 : x->width < y->width ? 1 : 0;
}
static int get_display_modes(uintptr_t request, uintptr_t response) {
    (void)request;
    CGDirectDisplayID display = CGMainDisplayID();
    display_size_t sizes[DISPLAY_MODE_MAX];
    size_t count = 0;
    unsigned current_w = 0, current_h = 0, native_w = 0, native_h = 0;
    CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
    if (current) {
        current_w = (unsigned)CGDisplayModeGetWidth(current);
        current_h = (unsigned)CGDisplayModeGetHeight(current);
        native_w = (unsigned)CGDisplayModeGetPixelWidth(current);
        native_h = (unsigned)CGDisplayModeGetPixelHeight(current);
        display_add_size(sizes, &count, current_w, current_h);
        display_add_size(sizes, &count, native_w, native_h);
        CGDisplayModeRelease(current);
    }
    const void *key = kCGDisplayShowDuplicateLowResolutionModes, *value = kCFBooleanTrue;
    CFDictionaryRef options = CFDictionaryCreate(NULL, &key, &value, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, options);
    if (options) CFRelease(options);
    if (modes) {
        for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
            CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            display_add_size(sizes, &count, CGDisplayModeGetWidth(mode), CGDisplayModeGetHeight(mode));
            display_add_size(sizes, &count, CGDisplayModeGetPixelWidth(mode), CGDisplayModeGetPixelHeight(mode));
        }
        CFRelease(modes);
    }
    qsort(sizes, count, sizeof sizes[0], display_size_compare);
    char json[DISPLAY_MODE_MAX * 32 + 128];
    int n = snprintf(json, sizeof json, "{\"current\":[%u,%u],\"pixels\":[%u,%u],\"modes\":[",
                     current_w, current_h, native_w, native_h);
    if (n < 0 || (size_t)n >= sizeof json) return RESULT_FAIL;
    size_t used = (size_t)n;
    for (size_t i = 0; i < count; i++) {
        n = snprintf(json + used, sizeof json - used, "%s[%u,%u]", i ? "," : "", sizes[i].width, sizes[i].height);
        if (n < 0 || (size_t)n >= sizeof json - used) return RESULT_FAIL;
        used += (size_t)n;
    }
    if (sizeof json - used < 3) return RESULT_FAIL;
    memcpy(json + used, "]}", 3);
    size_t cap = used + 2 + 8;
    uint8_t *body = malloc(cap);
    if (!body) return RESULT_FAIL;
    np_pb_t pb = { body, cap, 0, 1 };
    pb_string(&pb, RESP_DEFAULT, json);
    int ok = pb.ok && np_webui_parse_into(response, body, (uint32_t)pb.len);
    free(body);
    return ok ? RESULT_OK : RESULT_FAIL;
}

static int display_mkdir(const char *dir) {
    char path[PATH_MAX];
    if (dir[0] != '/' || strlen(dir) >= sizeof path) return 0;
    strcpy(path, dir);
    for (char *p = path + 1;; p++) {
        if (*p && *p != '/') continue;
        char c = *p; *p = '\0';
        struct stat st;
        if ((mkdir(path, 0700) != 0 && errno != EEXIST) ||
            stat(path, &st) != 0 || !S_ISDIR(st.st_mode)) return 0;
        *p = c;
        if (!c) return 1;
    }
}

static int set_display(uintptr_t request, uintptr_t response) {
    (void)response;
    uint32_t bits = *(const uint32_t *)(request + REQ_HAS_BITS_OFF);
    uint32_t appid = (bits & SPECIFY_HAS_APPID)
        ? *(const uint32_t *)(request + SPECIFY_APPID_OFF) : 0;
    const char *text = string_field(request + SPECIFY_TOOL_NAME_OFF);
    char dir[PATH_MAX], path[PATH_MAX], temp[PATH_MAX], canonical[32];
    unsigned width, height;
    if (*text && !np_display_parse(text, &width, &height)) return RESULT_FAIL;
    if (!display_path(appid, dir, path)) return RESULT_FAIL;
    if (!*text) return (unlink(path) == 0 || errno == ENOENT) ? RESULT_OK : RESULT_FAIL;
    if (!display_mkdir(dir)) return RESULT_FAIL;
    int n = snprintf(temp, sizeof temp, "%s/.notproton-display.XXXXXX", dir);
    if (n < 0 || (size_t)n >= sizeof temp) return RESULT_FAIL;
    int fd = mkstemp(temp);
    if (fd < 0) return RESULT_FAIL;
    snprintf(canonical, sizeof canonical, "%ux%u\n", width, height);
    FILE *f = fdopen(fd, "wb");
    if (!f) { close(fd); unlink(temp); return RESULT_FAIL; }
    int ok = fputs(canonical, f) >= 0;
    if (fclose(f) != 0) ok = 0;
    if (ok && rename(temp, path) == 0) return RESULT_OK;
    unlink(temp);
    return RESULT_FAIL;
}
#endif
