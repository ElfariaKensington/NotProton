#ifndef NOTPROTON_NATIVE_GAME_SPACE_DISPLAY_H
#define NOTPROTON_NATIVE_GAME_SPACE_DISPLAY_H

#include <stddef.h>
#include <stdint.h>

// Wine 11.15 gdi_driver.h, driver ABI 110 (also used by CrossOver 27.0.0.41069).
// Only the display callbacks and fields used here are named.
enum { NP_WINE_DRIVER_VERSION = 110, NP_WINE_PRIMARY = 4, NP_WINE_ATTACHED = 1 };
struct np_devmode {
    uint16_t device[32], spec_version, driver_version, size, driver_extra;
    uint32_t fields;
    int32_t x, y;
    uint32_t orientation, fixed_output;
    uint16_t print_fields[5], form_name[32], log_pixels;
    uint32_t depth, width, height, display_flags, frequency, trailing[8];
};
struct np_rect { int32_t left, top, right, bottom; };
struct np_monitor {
    struct np_rect bounds, work;
    const void *edid;
    uint32_t edid_length, hdr;
};
struct np_device_manager {
    void (*add_gpu)(const char *, const void *, const void *, void *);
    void (*add_source)(const char *, uint32_t, uint32_t, void *);
    void (*add_monitor)(const struct np_monitor *, void *);
    void (*add_modes)(const struct np_devmode *, uint32_t, const struct np_devmode *, void *);
};
struct np_user_driver {
    void (*before_cursor[105])(void);
    int32_t (*get_cursor)(int32_t *);
    void (*before_display[10])(void);
    int32_t (*change_settings)(struct np_devmode *, const uint16_t *, void *, uint32_t, void *);
    uint32_t (*update_devices)(const struct np_device_manager *, void *);
    void (*after_display[34])(void);
};
_Static_assert(sizeof(struct np_devmode) == 220 && offsetof(struct np_devmode, width) == 172, "DEVMODEW layout");
_Static_assert(offsetof(struct np_user_driver, change_settings) == 0x3a0 &&
               sizeof(struct np_user_driver) == 0x4c0, "Wine driver layout");

void np_game_space_set_driver(const struct np_user_driver *driver, unsigned version);
void np_game_space_set_display_size(unsigned width, unsigned height);
extern void *np_game_space_original_registration;
void np_game_space_map_cursor(int32_t *x, int32_t *y);

#endif
