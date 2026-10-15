/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * HuskPatch: files to and from the iPhone, for every engine. An app's "open a file" activity (ACTION_GET_CONTENT,
 * ACTION_OPEN_DOCUMENT, the photo picker, ACTION_OPEN_DOCUMENT_TREE; Flutter's file_picker) shows the iPhone's own picker,
 * and what the user picks is copied into the app's storage, where the app reads it as it would a document on a phone.
 * Going the other way, a document the app creates (ACTION_CREATE_DOCUMENT) is saved to Files, and a file it opens or shares
 * (ACTION_VIEW, ACTION_SEND) goes to the iPhone's viewer or share sheet. The host registers with husk_docs_set_host
 * (husk-tl-unity-app.h).
 */
#ifndef HUSK_TL_DOCS_H
#define HUSK_TL_DOCS_H

#include <stdbool.h>

/* Ask the host for files: `mimes` Android MIME types, one per line ("" or a wildcard: anything), copied into `dest_dir`.
 * `done` runs once, on some thread, with the copies' absolute paths one per line, or NULL when the user cancelled (or no
 * host is registered). */
enum { TL_DOCS_MULTIPLE = 1, TL_DOCS_FOLDER = 2, TL_DOCS_MEDIA = 4 };
typedef void (*tl_docs_done)(void *ctx, const char *paths);
void tl_docs_pick(const char *mimes, int flags, const char *dest_dir, tl_docs_done done, void *ctx);

/* Hand a file of the app's to the iPhone: TL_DOCS_SAVE asks where in Files to save it, TL_DOCS_VIEW opens it in the
 * iPhone's viewer, TL_DOCS_SHARE shows the share sheet. False when no host is registered. */
enum { TL_DOCS_SAVE = 0, TL_DOCS_VIEW = 1, TL_DOCS_SHARE = 2 };
bool tl_docs_export(const char *path, int mode);

#endif
