/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * HuskPatch: the broker between an app's file pickers and the host's (husk-tl-docs.h).
 *
 * A pick gets an id and waits in a small table until the host answers it with husk_docs_result, from any thread; whoever
 * asked hands the answer on to the thread it belongs to (the Java app's input queue, Flutter's platform thread).
 */
#include "husk-tl-docs.h"
#include "husk-tl-unity-app.h"

#include <pthread.h>
#include <string.h>

void tl_log_line(const char *fmt, ...);

static void (*g_pick)(int id, const char *mimes, int flags, const char *dest_dir);
static void (*g_export)(const char *path, int mode);

typedef struct { int id; tl_docs_done done; void *ctx; } pending;
static pending g_pending[16];
static int g_next = 1;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

void husk_docs_set_host(void (*pick)(int id, const char *mimes, int flags, const char *dest_dir),
                        void (*export_file)(const char *path, int mode))
{
    g_pick = pick;
    g_export = export_file;
}

void tl_docs_pick(const char *mimes, int flags, const char *dest_dir, tl_docs_done done, void *ctx)
{
    if (!g_pick || !dest_dir) { tl_log_line("docs: no file picker here"); if (done) done(ctx, NULL); return; }
    pthread_mutex_lock(&g_lock);
    int slot = -1, id = 0;
    for (int i = 0; i < 16; i++) if (!g_pending[i].id) { slot = i; break; }
    if (slot >= 0) {
        id = g_next++;
        if (g_next <= 0) g_next = 1;
        g_pending[slot] = (pending){ .id = id, .done = done, .ctx = ctx };
    }
    pthread_mutex_unlock(&g_lock);
    if (slot < 0) { tl_log_line("docs: too many pickers waiting"); if (done) done(ctx, NULL); return; }
    tl_log_line("docs: pick %d (%s, flags %#x) into %s", id, mimes && *mimes ? mimes : "*/*", flags, dest_dir);
    g_pick(id, mimes ? mimes : "", flags, dest_dir);
}

void husk_docs_result(int id, const char *paths)
{
    pending p = { 0 };
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < 16; i++) if (g_pending[i].id == id) { p = g_pending[i]; g_pending[i].id = 0; break; }
    pthread_mutex_unlock(&g_lock);
    if (!p.id) return;
    tl_log_line("docs: pick %d %s", id, paths && *paths ? "answered" : "cancelled");
    if (p.done) p.done(p.ctx, paths && *paths ? paths : NULL);
}

bool tl_docs_export(const char *path, int mode)
{
    if (!g_export || !path) return false;
    tl_log_line("docs: %s %s", mode == TL_DOCS_SAVE ? "save" : mode == TL_DOCS_VIEW ? "view" : "share", path);
    g_export(path, mode);
    return true;
}
