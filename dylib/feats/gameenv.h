// Prefix-local environment text. Included by the service to keep this feature isolated.
#ifndef NOTPROTON_GAMEENV_H
#define NOTPROTON_GAMEENV_H

#define NP_GAME_ENV_MAX (64u * 1024u)
#define NP_GAME_ENV_FILE "notproton.env"

static int game_env_key(const char *s, size_t n) {
    if (!n || !((s[0] >= 'A' && s[0] <= 'Z') ||
                (s[0] >= 'a' && s[0] <= 'z') || s[0] == '_')) return 0;
    for (size_t i = 1; i < n; i++)
        if (!((s[i] >= 'A' && s[i] <= 'Z') || (s[i] >= 'a' && s[i] <= 'z') ||
              (s[i] >= '0' && s[i] <= '9') || s[i] == '_')) return 0;
    return 1;
}

// Reject the whole edit on a malformed line; never silently discard user input.
// Values are literal, with no quoting, expansion, or shell evaluation.
static int game_env_valid(const char *text) {
    if (strlen(text) > NP_GAME_ENV_MAX) return 0;
    for (const char *p = text; *p;) {
        const char *end = strchr(p, '\n');
        if (!end) end = p + strlen(p);
        const char *last = end;
        if (last > p && last[-1] == '\r') last--;
        while (p < last && (*p == ' ' || *p == '\t')) p++;
        if (p < last && *p != '#') {
            const char *eq = memchr(p, '=', (size_t)(last - p));
            if (!eq) return 0;
            const char *key_end = eq;
            while (key_end > p && (key_end[-1] == ' ' || key_end[-1] == '\t')) key_end--;
            if (!game_env_key(p, (size_t)(key_end - p))) return 0;
        }
        p = *end ? end + 1 : end;
    }
    return 1;
}

static int game_env_mkdir(const char *dir) {
    char path[PATH_MAX];
    if (dir[0] != '/' || strlen(dir) >= sizeof path) return 0;
    strcpy(path, dir);
    for (char *p = path + 1;; p++) {
        if (*p && *p != '/') continue;
        char c = *p;
        *p = '\0';
        struct stat st;
        if ((mkdir(path, 0700) != 0 && errno != EEXIST) ||
            stat(path, &st) != 0 || !S_ISDIR(st.st_mode)) return 0;
        *p = c;
        if (!c) return 1;
    }
}

static int game_env_filename(const char *dir, char *path, size_t cap) {
    if (!*dir) return 0;
    int n = snprintf(path, cap, "%s/" NP_GAME_ENV_FILE, dir);
    return n > 0 && (size_t)n < cap;
}

static int game_env_save(const char *dir, const char *text) {
    char path[PATH_MAX], temp[PATH_MAX];
    if (!game_env_valid(text) || !game_env_filename(dir, path, sizeof path)) return 0;
    if (!*text) return unlink(path) == 0 || errno == ENOENT;
    if (!game_env_mkdir(dir)) return 0;
    int n = snprintf(temp, sizeof temp, "%s/.notproton.env.XXXXXX", dir);
    if (n < 0 || (size_t)n >= sizeof temp) return 0;
    int fd = mkstemp(temp); // 0600, same directory, atomic replacement below.
    if (fd < 0) return 0;
    FILE *f = fdopen(fd, "wb");
    if (!f) { close(fd); unlink(temp); return 0; }
    size_t len = strlen(text);
    int ok = fwrite(text, 1, len, f) == len;
    if (fclose(f) != 0) ok = 0;
    if (ok && rename(temp, path) == 0) return 1;
    unlink(temp);
    return 0;
}

// NULL is a read error; a missing file is a successful empty configuration.
static char *game_env_read(const char *dir) {
    char path[PATH_MAX];
    if (!game_env_filename(dir, path, sizeof path)) return NULL;
    FILE *f = fopen(path, "rb");
    if (!f) return errno == ENOENT ? strdup("") : NULL;
    char *text = malloc(NP_GAME_ENV_MAX + 2u);
    if (!text) { fclose(f); return NULL; }
    size_t n = fread(text, 1, NP_GAME_ENV_MAX + 1u, f);
    int ok = !ferror(f) && n <= NP_GAME_ENV_MAX && !memchr(text, '\0', n);
    fclose(f);
    text[n] = '\0';
    if (ok) return text;
    free(text);
    return NULL;
}
#endif
