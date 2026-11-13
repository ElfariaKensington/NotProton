#include "../config.h"
#include "../display.h"

#include <assert.h>
#include <stdlib.h>
#include <unistd.h>

void np_game_space_map_cursor(int32_t *x, int32_t *y) {
    *x += 100;
    *y += 200;
}

static struct np_user_driver driver;
static unsigned registered_version;
static const struct np_user_driver *registered;
static struct np_devmode physical = {
    .size = sizeof(physical), .width = 1920, .height = 1080,
    .depth = 32, .frequency = 60, .display_flags = 0x80000000,
};
static struct np_monitor monitor = {{0, 0, 1920, 1080}, {0, 20, 1920, 1080}, NULL, 0, 0};

struct probe {
    unsigned sources, monitors, modes;
    unsigned state;
};

static void add_gpu(const char *name, const void *pci, const void *uuid, void *param) {
    (void)name;
    (void)pci;
    (void)uuid;
    assert(param);
}

static void add_source(const char *name, uint32_t flags, uint32_t dpi, void *param) {
    struct probe *probe = param;
    assert(name && dpi == 96);
    probe->sources++;
    probe->state = flags;
}

static void add_monitor(const struct np_monitor *info, void *param) {
    struct probe *probe = param;
    probe->monitors++;
    if (probe->state & NP_WINE_PRIMARY) {
        assert(info->bounds.right == 3841 && info->bounds.bottom == 2161);
        assert(info->work.top == 0 && info->work.bottom == 2161);
    } else assert(info == &monitor || !memcmp(info, &monitor, sizeof(*info)));
}

static void add_modes(const struct np_devmode *current, uint32_t count,
                      const struct np_devmode *modes, void *param) {
    struct probe *probe = param;
    probe->modes++;
    if (probe->state & NP_WINE_PRIMARY) {
        assert(current->width == 3841 && current->height == 2161 && current->frequency == 60);
        assert(!current->display_flags && count == 3);
        assert(modes[0].depth == 32 && modes[1].depth == 16 && modes[2].depth == 8);
        for (unsigned i = 0; i < count; i++)
            assert(modes[i].width == current->width && modes[i].height == current->height);
    } else assert(count == 1 && current == &physical && modes == &physical);
}

static uint32_t update(const struct np_device_manager *manager, void *param) {
    manager->add_gpu("GPU", NULL, NULL, param);
    manager->add_source("secondary", NP_WINE_ATTACHED, 96, param);
    manager->add_monitor(&monitor, param);
    manager->add_modes(&physical, 1, &physical, param);
    manager->add_source("primary", NP_WINE_PRIMARY | NP_WINE_ATTACHED, 96, param);
    manager->add_monitor(&monitor, param);
    manager->add_modes(&physical, 1, &physical, param);
    return 0;
}

static int32_t change(struct np_devmode *modes, const uint16_t *primary,
                      void *window, uint32_t flags, void *param) {
    (void)modes;
    (void)primary;
    (void)window;
    (void)flags;
    (void)param;
    assert(!"physical mode setter called");
    return -1;
}

static void registration(const struct np_user_driver *value, unsigned version) {
    registered = value;
    registered_version = version;
    driver = *value;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    unsigned w, h;
    assert(np_game_space_size("3841x2161", &w, &h));
    assert(w == 3841 && h == 2161);
    assert(np_game_space_size("320x200", &w, &h));
    assert(np_game_space_size("5120x2880", &w, &h));
    assert(!np_game_space_size("319x200", &w, &h));
    assert(!np_game_space_size("3840x2160junk", &w, &h));
    assert(!np_game_space_size("4294967296x2160", &w, &h));

    char executable[PATH_MAX], value[32];
    snprintf(executable, sizeof(executable), "%s/notproton/launchers/240/runner/wine", argv[1]);
    assert(np_game_space_manifest(executable, value, sizeof(value)));
    assert(!strcmp(value, "3841x2161"));
    assert(!np_game_space_manifest("/notproton/launchers/240x/wine", value, sizeof(value)));
    assert(!np_game_space_manifest(executable, value, 5));

    const struct np_user_driver original = {.change_settings = change, .update_devices = update};
    np_game_space_set_display_size(3841, 2161);
    np_game_space_original_registration = registration;
    np_game_space_set_driver(&original, 109);
    assert(registered == &original && registered_version == 109);
    np_game_space_set_driver(&original, 110);
    assert(registered_version == 110 && driver.change_settings != change && driver.update_devices != update);

    const struct np_device_manager manager = {add_gpu, add_source, add_monitor, add_modes};
    struct probe probe = {0};
    assert(driver.update_devices(&manager, &probe) == 0);
    assert(probe.sources == 2 && probe.monitors == 2 && probe.modes == 2);
    struct np_devmode modes[] = {physical, physical, {0}};
    modes[0].device[0] = '2';
    modes[1].device[0] = '1';
    const uint16_t primary[] = {'1', 0};
    assert(driver.change_settings(modes, primary, NULL, 0, NULL) == 0);
    assert(modes[0].width == 1920 && modes[0].height == 1080);
    assert(modes[1].width == 3841 && modes[1].height == 2161);
    puts("native game Space config and Wine display callbacks passed");
}
