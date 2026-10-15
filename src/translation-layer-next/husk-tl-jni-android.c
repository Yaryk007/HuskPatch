/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * HuskPatch: more of Android's framework for engines whose Java is written in C (husk-tl-jni-hle.c).
 *
 * - Permissions: Activity.requestPermissions and Unity's UnityPermissions show Android's dialog (husk-tl-perm.c), and
 *   Unity's C# hears the answer through the callbacks it handed over.
 * - Closing: Activity.finish and finishAffinity, moveTaskToBack, System.exit and Process.killProcess end the app: it
 *   stops, and its screen closes back to wherever it was opened from, as Android ends the process.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "husk-tl-jni.h"
#include "husk-tl-perm.h"
#include "husk-tl-unity-app.h"

void tl_log_line(const char *fmt, ...);
jobj *tl_proxy_call(jobj *proxy, const char *iface, const char *name, const char *sig, jobj **args, int nargs);
void tl_loop_post_main_fn(void (*fn)(void *), void *arg);

static jvalue vz(int z) { jvalue v; v.j = 0; v.z = z != 0; return v; }

/* ------------------------------------------------------------- permissions */

/* The Strings of a String[] argument, as C strings (at most 32). */
static int strings_of(const jobj *arr, const char **out)
{
    int n = arr ? (int)arr->oarr.len : 0;
    if (n > 32) n = 32;
    for (int i = 0; i < n; i++) {
        const char *s = arr->oarr.v[i] ? tl_jni_string(arr->oarr.v[i]) : NULL;
        out[i] = s ? s : "";
    }
    return n;
}

/* A request whose answer only the user sees: the engine has no way to hear it (it checks again later, as games do). */
static void request_only(const jobj *arr)
{
    const char *perms[32];
    int n = strings_of(arr, perms);
    if (n) tl_perm_request(perms, n, NULL, NULL);
}

static void Activity_requestPermissions(tl_jcall *c) { request_only(c->args[0].l); }
static void Compat_requestPermissions(tl_jcall *c) { request_only(c->args[1].l); }   /* ActivityCompat.requestPermissions(activity, perms, code) */
static void Activity_shouldShowRationale(tl_jcall *c) { c->ret = vz(tl_perm_state(tl_jni_string(c->args[0].l)) == HUSK_PERM_DENIED); }
static void Compat_shouldShowRationale(tl_jcall *c) { c->ret = vz(tl_perm_state(tl_jni_string(c->args[1].l)) == HUSK_PERM_DENIED); }

/* Unity's UnityPermissions.requestUserPermissions(activity, perms, callbacks): the C# side's callbacks hear, on the main
 * looper, each permission granted, denied, or denied for good. */
typedef struct { jobj *callbacks; int n; char *perms[32]; uint32_t granted; } unity_req;

static void unity_answer(void *arg)
{
    unity_req *r = arg;
    for (int i = 0; i < r->n; i++) {
        const char *method = (r->granted & (1u << i)) ? "onPermissionGranted"
                           : tl_perm_state(r->perms[i]) == HUSK_PERM_DENIED_FOREVER ? "onPermissionDeniedAndDontAskAgain" : "onPermissionDenied";
        if (r->callbacks) {
            jobj *s = tl_jni_new_string(r->perms[i]);
            jobj *ret = tl_proxy_call(r->callbacks, "com/unity3d/player/IPermissionRequestCallbacks", method, "(Ljava/lang/String;)V", &s, 1);
            tl_jni_unref(ret);
            tl_jni_unref(s);
        }
        free(r->perms[i]);
    }
    tl_jni_unref(r->callbacks);
    free(r);
}

static void unity_done(void *ctx, int n, uint32_t granted)
{
    (void)n;
    unity_req *r = ctx;
    r->granted = granted;
    tl_loop_post_main_fn(unity_answer, r);
}

static void UP_requestUserPermissions(tl_jcall *c)
{
    const char *perms[32];
    int n = strings_of(c->args[1].l, perms);
    unity_req *r = calloc(1, sizeof(*r));
    if (!r) return;
    r->callbacks = c->args[2].l ? tl_jni_ref(c->args[2].l) : NULL;
    r->n = n;
    for (int i = 0; i < n; i++) r->perms[i] = strdup(perms[i]);
    tl_perm_request(perms, n, unity_done, r);
}

/* ------------------------------------------------------------------ closing */

static void end_finish(tl_jcall *c) { (void)c; tl_app_end("Activity.finish"); }
static void end_task(tl_jcall *c) { tl_app_end("moveTaskToBack"); c->ret = vz(1); }
static void end_exit(tl_jcall *c) { (void)c; tl_app_end("System.exit"); }
static void end_kill(tl_jcall *c) { (void)c; tl_app_end("Process.killProcess"); }

#define M(c, n, s, f) { c, n, s, f }
static const tl_jhle k_android[] = {
    M("android/app/Activity", "requestPermissions", "([Ljava/lang/String;I)V", Activity_requestPermissions),
    M("android/app/Activity", "shouldShowRequestPermissionRationale", "(Ljava/lang/String;)Z", Activity_shouldShowRationale),
    M("androidx/core/app/ActivityCompat", "requestPermissions", "(Landroid/app/Activity;[Ljava/lang/String;I)V", Compat_requestPermissions),
    M("androidx/core/app/ActivityCompat", "shouldShowRequestPermissionRationale", "(Landroid/app/Activity;Ljava/lang/String;)Z", Compat_shouldShowRationale),
    M("android/support/v4/app/ActivityCompat", "requestPermissions", "(Landroid/app/Activity;[Ljava/lang/String;I)V", Compat_requestPermissions),
    M("com/unity3d/player/UnityPermissions", "requestUserPermissions",
      "(Landroid/app/Activity;[Ljava/lang/String;Lcom/unity3d/player/IPermissionRequestCallbacks;)V", UP_requestUserPermissions),

    M("android/app/Activity", "finish", "()V", end_finish),
    M("android/app/Activity", "finishAffinity", "()V", end_finish),
    M("android/app/Activity", "finishAndRemoveTask", "()V", end_finish),
    M("android/app/Activity", "moveTaskToBack", "(Z)Z", end_task),
    M("java/lang/System", "exit", "(I)V", end_exit),
    M("java/lang/Runtime", "exit", "(I)V", end_exit),
    M("java/lang/Runtime", "halt", "(I)V", end_exit),
    M("android/os/Process", "killProcess", "(I)V", end_kill),
    { NULL, NULL, NULL, NULL }
};

static const struct { const char *name, *super; } k_classes[] = {
    { "com/unity3d/player/UnityPermissions", "java/lang/Object" },
    { "com/unity3d/player/IPermissionRequestCallbacks", "java/lang/Object" },
};

void tl_android_extras_install(void)
{
    for (size_t i = 0; i < sizeof(k_classes) / sizeof(k_classes[0]); i++) tl_jni_declare(k_classes[i].name, k_classes[i].super);
    tl_jni_register_hle(k_android);
}
