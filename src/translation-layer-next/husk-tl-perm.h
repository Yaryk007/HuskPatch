/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * HuskPatch: Android's runtime permissions, for every engine. The Java framework (Activity.requestPermissions,
 * Context.checkSelfPermission) and the engines' Java-in-C (Unity's UnityPermissions, Godot, GameMaker) ask here; the host
 * shows Android's dialogs, and the iPhone's own for what iOS also guards (husk_perm_set_host in husk-tl-unity-app.h).
 */
#ifndef HUSK_TL_PERM_H
#define HUSK_TL_PERM_H

#include <stdbool.h>
#include <stdint.h>

/* HUSK_PERM_GRANTED ... HUSK_PERM_UNSET, as the host says; granted when no host is registered. */
int tl_perm_state(const char *perm);
/* Context.checkSelfPermission for the Java framework: granted only when the user granted it. */
bool tl_perm_granted(const char *perm);
/* The same for engines whose Java is written in C, where a request may have no way back to the game: a permission never asked
 * about stays granted, as it always was here, and only one the user turned down reads as denied. */
bool tl_perm_granted_lenient(const char *perm);

/* Ask for `n` permissions. `done` runs once, on some thread, with bit i set when perms[i] was granted (all of them when
 * no host is registered). */
typedef void (*tl_perm_done)(void *ctx, int n, uint32_t granted);
void tl_perm_request(const char *const *perms, int n, tl_perm_done done, void *ctx);

/* HuskPatch: the app closed itself; its screen closes (husk-tl-unity-app.c registers what that does). */
extern void (*tl_app_end_hook)(const char *why);
void tl_app_end(const char *why);

#endif
