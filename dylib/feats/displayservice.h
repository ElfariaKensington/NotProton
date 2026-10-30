// Included after compatsvc's prefix resolver and protobuf helpers.
#ifndef NOTPROTON_DISPLAYSERVICE_H
#define NOTPROTON_DISPLAYSERVICE_H
#include "displayconfig.h"

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
