/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * HuskPatch: the broker between an app's permission requests and the host's dialogs (husk-tl-perm.h).
 *
 * A request gets an id and waits in a small table until the host answers it with husk_perm_result. The host may answer
 * from any thread, so whoever made the request hands its result on to the thread it belongs to (the Java app's input
 * queue, Unity's main looper).
 */
#include "husk-tl-perm.h"
#include "husk-tl-unity-app.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

void tl_log_line(const char *fmt, ...);

static int (*g_check)(const char *perm);
static void (*g_request)(int id, const char *perms);

typedef struct { int id, n; tl_perm_done done; void *ctx; } pending;
static pending g_pending[32];
static int g_next = 1;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

/* HuskPatch: the app closed itself (Activity.finish on its last screen, System.exit, Process.killProcess, moveTaskToBack).
 * The app host stops it where it is and its screen closes, as Android ends the process; until a host registers, nothing. */
void (*tl_app_end_hook)(const char *why);
void tl_app_end(const char *why)
{
    tl_log_line("app: the app closed itself (%s)", why ? why : "?");
    if (tl_app_end_hook) tl_app_end_hook(why);
}

void husk_perm_set_host(int (*check)(const char *perm), void (*request)(int id, const char *perms))
{
    g_check = check;
    g_request = request;
}

int tl_perm_state(const char *perm)
{
    if (!perm || !g_check) return HUSK_PERM_GRANTED;
    return g_check(perm);
}

bool tl_perm_granted(const char *perm) { return tl_perm_state(perm) == HUSK_PERM_GRANTED; }

bool tl_perm_granted_lenient(const char *perm)
{
    int s = tl_perm_state(perm);
    return s == HUSK_PERM_GRANTED || s == HUSK_PERM_UNSET;
}

void tl_perm_request(const char *const *perms, int n, tl_perm_done done, void *ctx)
{
    uint32_t all = n >= 32 ? 0xffffffffu : (1u << n) - 1;
    if (n <= 0) { if (done) done(ctx, 0, 0); return; }
    if (!g_request) { if (done) done(ctx, n, all); return; }

    size_t len = 1;
    for (int i = 0; i < n; i++) len += strlen(perms[i] ? perms[i] : "") + 1;
    char *joined = malloc(len), *p = joined;
    if (!joined) { if (done) done(ctx, n, 0); return; }
    for (int i = 0; i < n; i++) {
        const char *s = perms[i] ? perms[i] : "";
        size_t l = strlen(s);
        memcpy(p, s, l); p += l;
        if (i + 1 < n) *p++ = '\n';
    }
    *p = 0;

    pthread_mutex_lock(&g_lock);
    int slot = -1;
    for (int i = 0; i < 32; i++) if (!g_pending[i].id) { slot = i; break; }
    int id = 0;
    if (slot >= 0) {
        id = g_next++;
        if (g_next <= 0) g_next = 1;
        g_pending[slot] = (pending){ .id = id, .n = n, .done = done, .ctx = ctx };
    }
    pthread_mutex_unlock(&g_lock);

    if (slot < 0) {
        /* Android cancels a request made while another is still on screen: the app hears nothing was granted */
        tl_log_line("perm: too many requests waiting; refusing %s", joined);
        free(joined);
        if (done) done(ctx, n, 0);
        return;
    }
    tl_log_line("perm: request %d: %s", id, joined);
    g_request(id, joined);
    free(joined);
}

void husk_perm_result(int id, unsigned granted)
{
    pending p = { 0 };
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < 32; i++) if (g_pending[i].id == id) { p = g_pending[i]; g_pending[i].id = 0; break; }
    pthread_mutex_unlock(&g_lock);
    if (!p.id) return;
    tl_log_line("perm: request %d answered: %#x", id, granted);
    if (p.done) p.done(p.ctx, p.n, granted);
}
