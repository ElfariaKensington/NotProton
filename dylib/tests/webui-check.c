// Exercise the actual route registry, factories and dispatch instead of a mock.
#include "../feats/webui.c"
#include <stdio.h>

int np_log_level = -1;
FILE *np_log_file;
int np_log_first_hit(const void *anchor, unsigned long tag) { (void)anchor; (void)tag; return 1; }

static int failures, registered, sent;
static uintptr_t jobs[64], factories[64];
static char names[64][64];
static uintptr_t message_vtable[4];

static void check(int ok, const char *why) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", why); failures++; }
}
static uintptr_t new_message(void) { return (uintptr_t)message_vtable; }
static uintptr_t stock_factory(uintptr_t dispatcher, uintptr_t arg) {
    check(dispatcher == 123, "factory preserves dispatcher");
    check(arg < 64, "factory preserves job argument");
    return (uintptr_t)&jobs[arg];
}
static int register_route(uintptr_t registry, void *record) {
    check(registry == (uintptr_t)jobs, "route reaches the selected registry");
    uintptr_t *descriptor = (uintptr_t *)((uintptr_t *)record)[0];
    factories[registered++] = descriptor[DESC_FACTORY];
    return 1;
}
static int handler(uintptr_t request, uintptr_t response) {
    check(response == request + 100, "dispatch preserves request and response");
    return (int)request + 1;
}
static void send_response(uintptr_t job, uintptr_t ctx) {
    (void)job; (void)ctx; sent++;
}

int main(void) {
    static const char *const compatibility_routes[] = {
        "CompatManager.GetCompatTools#1", "CompatManager.SpecifyCompatTool#1",
        "NotProton.SetDefaults#1", "NotProton.SetToolDefaults#1", "NotProton.ApplyToolDefaults#1",
        "NotProton.GetGameEnvironment#1", "NotProton.SetGameEnvironment#1",
        "NotProton.PrefixState#1", "NotProton.RebuildPrefix#1",
        "NotProton.BackupAndRebuildPrefix#1", "NotProton.OpenPrefixLog#1",
        "NotProton.GetDisplay#1", "NotProton.SetDisplay#1",
    };
    const size_t required = sizeof compatibility_routes / sizeof compatibility_routes[0];
    g_registry = (uintptr_t)jobs;
    g_register_fn = (uintptr_t)register_route;
    g_stock_factory = (uintptr_t)stock_factory;
    g_send_response = (uintptr_t)send_response;
    // Message/vtable discovery is separate from the registration boundary under test.
    g_text_base = (uintptr_t)new_message & ~(uintptr_t)3;
    g_text_end = g_text_base + 4;
    message_vtable[3] = (uintptr_t)new_message;
    g_clone_words = 3;
    g_clone[2] = (uintptr_t)job_handler;
    for (size_t i = 0; i < required; i++) {
        if (!np_webui_register_route(compatibility_routes[i], (uintptr_t)message_vtable,
                                     (uintptr_t)message_vtable, handler)) {
            fprintf(stderr, "FAIL: actual registry rejected required route %s at index %zu\n",
                    compatibility_routes[i], i);
            return 1;
        }
    }
    // Every remaining slot needs a callable factory too, including the last one.
    while (g_route_count < MAX_ROUTES) {
        int i = g_route_count;
        snprintf(names[i], sizeof names[i], "NotProton.TestRoute%d#1", i);
        check(np_webui_register_route(names[i], (uintptr_t)message_vtable,
              (uintptr_t)message_vtable, handler), "remaining route slot registers");
    }
    check(!np_webui_register_route("NotProton.Overflow#1", (uintptr_t)message_vtable,
          (uintptr_t)message_vtable, handler), "capacity overflow fails safely");
    check(registered == MAX_ROUTES, "failed overflow does not reach the client registry");
    for (int i = 0; i < registered; i++) {
        uintptr_t job = ((np_job_factory_fn)factories[i])(123, (uintptr_t)i);
        check(*(uintptr_t *)job == (uintptr_t)&g_routes[i].vtable[2], "factory selects its own route vtable");
        struct { uint32_t result, padding; uintptr_t request, response; } ctx = { 0, 0, (uintptr_t)i, (uintptr_t)i + 100 };
        uintptr_t *vtable = (uintptr_t *)*(uintptr_t *)job;
        ((int64_t (*)(uintptr_t, uintptr_t))vtable[0])(job, (uintptr_t)&ctx);
        check(ctx.result == (uint32_t)i + 1, "job dispatch returns the correct handler result");
    }
    check(sent == registered, "every registered factory sends its response");
    if (failures) return 1;
    printf("==> webui: all %zu required routes register; %d factories dispatch; overflow stays safe\n", required, registered);
    return 0;
}
