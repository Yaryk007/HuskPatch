/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Android libraries as Mach-O dylibs, made ahead of time (Husk 3.2: running Android code with no JIT).
 *
 * The loader runs a library from memory it copies the image into and rewrites (svc, x18, tpidr_el0, ctr_el0, adr/adrp to data), which
 * needs executable memory iOS only grants to a debugged process. A dylib is code iOS runs once it is signed, so the loader's own
 * mapping and rewriting (tl_ld_aot_build) run ahead of time and the result is written as one:
 *
 *   __TEXT        the Mach-O header and the manifest (__husk_manifest), padded to 16 KiB; r-x
 *   __TEXT_EXEC   a run of the image's executable pages, at the vaddrs they have in the image, every code rewrite applied; r-x
 *                 (one segment per run: a 16 KiB page belongs to the image's code or its data, never both, in a 16 KiB-aligned library)
 *   __DATA        a run of the image's data pages, at those same vaddrs; rw. Relocated at run time, in place: a page the code reads
 *                 at its own address is the page the loader writes. The stubs' data page and the thread block follow the image.
 *   __DATA_n      a library built for 4 KiB pages: copies of its data pages, at the image's size plus the page's index; rw. The
 *                 pages that hold code keep their code at their own address (executable); every data access names the copy, and the
 *                 copies keep the image's numbering so an address that crosses a page boundary stays in them.
 *   __LINKEDIT    empty fixups, export trie and symbol table (dyld wants them); a code signature is added by whoever signs it
 *
 * Because every page keeps the address it has in the image (every page a mixed page's data access can reach), the code needs no
 * delta between a code view and a data view: the rewrites address data at its own address, exactly as they do in the JIT region. The
 * loader imports such a dylib from the folder given to tl_ld_set_aot_dir (see husk-tl-ld.h).
 */
#ifndef HUSK_TL_AOT_H
#define HUSK_TL_AOT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "husk-tl-ld.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Make `out_path` from the arm64 library `file` (named `name`, as the loader will ask for it), for iOS or for macOS. The file is
 * written beside out_path and renamed into place, so a reader never sees half of one. Unsigned. `info` (optional) receives the
 * counts of what was rewritten; its text is no longer valid. Returns false with a reason in err.
 */
bool tl_aot_make_dylib(const char *name, const uint8_t *file, size_t flen, const char *out_path, bool ios, tl_ld_aot_image *info,
                       char *err, size_t errlen);

/*
 * Get an app ready to run with no JIT: every arm64 library in its APKs (the .so files under lib/arm64-v8a; the first APK that has a library wins,
 * as the loader's search does) as a dylib in cache_dir, aot-v<version>-<hash>-<library>.dylib, signed with the developer certificate in p12
 * (husk-tl-codesign.h). A dylib already there is only signed again when cert_tag (any string naming the certificate) differs from
 * the one it was signed with, which is kept beside it in <dylib>.signer. progress (optional) is called before each library.
 * An entry of apks ending in .so is a library file itself (the Java runtime's own natives).
 * Returns how many libraries are ready, or -1 with a reason in err.
 */
typedef void (*tl_aot_progress_fn)(void *user, int index, int total, const char *library);
int husk_aot_prepare(const char *const *apks, int napks, const char *cache_dir, const uint8_t *p12, size_t p12_len,
                     const char *password, const char *cert_tag, const char *sign_ident, tl_aot_progress_fn progress, void *user,
                     char *err, size_t errlen);

#ifdef __cplusplus
}
#endif

#endif /* HUSK_TL_AOT_H */
