#include "display.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static unsigned width, height;
void *np_game_space_original_registration;
static uint32_t (*update_devices)(const struct np_device_manager *, void *);
static atomic_bool reported;
static int32_t (*get_cursor)(int32_t *);

static int32_t cursor(int32_t *point) {
    int32_t ret = get_cursor(point);
    if (ret) np_game_space_map_cursor(point, point + 1);
    return ret;
}

struct display_update {
    const struct np_device_manager *manager;
    void *param;
    bool primary;
};

static void add_gpu(const char *name, const void *pci, const void *uuid, void *param) {
    struct display_update *ctx = param;
    ctx->manager->add_gpu(name, pci, uuid, ctx->param);
}

static void add_source(const char *name, uint32_t flags, uint32_t dpi, void *param) {
    struct display_update *ctx = param;
    ctx->primary = (flags & (NP_WINE_PRIMARY | NP_WINE_ATTACHED)) == (NP_WINE_PRIMARY | NP_WINE_ATTACHED);
    ctx->manager->add_source(name, flags, dpi, ctx->param);
}

static void add_monitor(const struct np_monitor *monitor, void *param) {
    struct display_update *ctx = param;
    struct np_monitor copy = *monitor;
    if (ctx->primary) {
        copy.bounds.right = copy.bounds.left + (int32_t)width;
        copy.bounds.bottom = copy.bounds.top + (int32_t)height;
        copy.work = copy.bounds;
    }
    ctx->manager->add_monitor(&copy, ctx->param);
}

static void add_modes(const struct np_devmode *current, uint32_t count,
                      const struct np_devmode *modes, void *param) {
    struct display_update *ctx = param;
    if (!ctx->primary || current->size != sizeof(*current)) {
        ctx->manager->add_modes(current, count, modes, ctx->param);
        return;
    }
    struct np_devmode selected = *current;
    selected.width = width;
    selected.height = height;
    if (!selected.depth) selected.depth = 32;
    selected.fields |= 0x00080000u; // DM_BITSPERPEL
    selected.display_flags &= ~0x80000002u; // Wine unsupported flag and DM_INTERLACED
    selected.driver_extra = 0;
    // Wine treats a one-entry list as an emulated modeset and adds other sizes.
    // Expose the selected size at the three color depths Wine normally supplies.
    struct np_devmode fixed[] = {selected, selected, selected};
    fixed[0].depth = 32;
    fixed[1].depth = 16;
    fixed[2].depth = 8;
    ctx->manager->add_modes(&selected, 3, fixed, ctx->param);
    if (!atomic_exchange(&reported, true))
        fprintf(stderr, "[native-space] Wine primary mode %ux%u\n", width, height);
}

static uint32_t update(const struct np_device_manager *manager, void *param) {
    static const struct np_device_manager callbacks = {add_gpu, add_source, add_monitor, add_modes};
    struct display_update ctx = {manager, param, false};
    return update_devices(&callbacks, &ctx);
}

static int32_t change(struct np_devmode *modes, const uint16_t *primary,
                      void *window, uint32_t flags, void *param) {
    (void)window;
    (void)flags;
    (void)param;
    // Wine can restore a stale registry mode. Keep the primary on the selected
    // size in the mode array it commits to the guest display state.
    for (struct np_devmode *mode = modes; mode->size;
         mode = (void *)((char *)mode + mode->size + mode->driver_extra)) {
        if (mode->size != sizeof(*mode)) return -2; // DISP_CHANGE_BADMODE
        size_t i = 0;
        while (i < 32 && mode->device[i] == primary[i] && primary[i]) i++;
        if (i == 32 || mode->device[i] != primary[i]) continue;
        mode->width = width;
        mode->height = height;
    }
    return 0;
}

void np_game_space_set_driver(const struct np_user_driver *driver, unsigned version) {
    void (*register_driver)(const struct np_user_driver *, unsigned) = np_game_space_original_registration;
    if (version != NP_WINE_DRIVER_VERSION || !driver || !driver->update_devices || !driver->change_settings) {
        fprintf(stderr, "[native-space] Wine display ABI %u is unsupported\n", version);
        register_driver(driver, version);
        return;
    }
    update_devices = driver->update_devices;
    struct np_user_driver copy = *driver;
    if (driver->get_cursor) {
        get_cursor = driver->get_cursor;
        copy.get_cursor = cursor;
    }
    copy.update_devices = update;
    copy.change_settings = change;
    register_driver(&copy, version);
}

void np_game_space_set_display_size(unsigned w, unsigned h) {
    width = w;
    height = h;
}
