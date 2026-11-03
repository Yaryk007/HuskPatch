/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * codesign-test: Test harness for Husk on-device Mach-O codesigner.
 *
 * Usage:
 *   tools/codesign-test <dylib> <p12> <password>  -- Signs dylib with developer certificate
 *   tools/codesign-test --adhoc <dylib>           -- Signs dylib with ad-hoc signature
 *   tools/codesign-test --info <p12> <password>   -- Prints Team ID and expiration date
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <time.h>

#include "husk-tl-codesign.h"

void tl_log_line(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

static uint8_t *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return NULL; }
    uint8_t *b = (uint8_t *)malloc((size_t)sz ? (size_t)sz : 1);
    if (!b || fread(b, 1, (size_t)sz, f) != (size_t)sz) {
        fclose(f);
        free(b);
        return NULL;
    }
    fclose(f);
    *out_len = (size_t)sz;
    return b;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
            "Usage:\n"
            "  %s <dylib> <p12> <password>   -- Sign dylib with .p12 certificate\n"
            "  %s --adhoc <dylib>            -- Sign dylib with ad-hoc signature\n"
            "  %s --info <p12> <password>    -- Inspect .p12 Team ID and expiry\n",
            argv[0], argv[0], argv[0]);
        return 2;
    }

    if (strcmp(argv[1], "--info") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Usage: %s --info <p12> <password>\n", argv[0]);
            return 2;
        }
        size_t p12_len = 0;
        uint8_t *p12_data = read_file(argv[2], &p12_len);
        if (!p12_data) {
            fprintf(stderr, "Cannot read .p12 file: %s\n", argv[2]);
            return 1;
        }

        char team_id[64] = {0};
        double not_after_epoch = 0;
        char err[512] = {0};

        bool ok = husk_p12_info(p12_data, p12_len, argv[3], team_id, sizeof(team_id), &not_after_epoch, err, sizeof(err));
        free(p12_data);

        if (!ok) {
            fprintf(stderr, "husk_p12_info failed: %s\n", err);
            return 1;
        }

        time_t exp_t = (time_t)not_after_epoch;
        struct tm tm_val;
        gmtime_r(&exp_t, &tm_val);
        char exp_str[64];
        strftime(exp_str, sizeof(exp_str), "%Y-%m-%d %H:%M:%S UTC", &tm_val);

        printf("PKCS#12 Certificate Information:\n");
        printf("  Team ID:    %s\n", team_id[0] ? team_id : "(none / individual)");
        printf("  Expires:    %s (epoch %.0f)\n", exp_str, not_after_epoch);
        return 0;
    }

    if (strcmp(argv[1], "--adhoc") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Usage: %s --adhoc <dylib>\n", argv[0]);
            return 2;
        }
        const char *dylib_path = argv[2];
        char err[512] = {0};
        bool ok = husk_codesign_dylib(dylib_path, NULL, 0, NULL, NULL, err, sizeof(err));
        if (!ok) {
            fprintf(stderr, "husk_codesign_dylib (ad-hoc) failed: %s\n", err);
            return 1;
        }
        printf("Successfully ad-hoc signed %s\n", dylib_path);
        return 0;
    }

    if (argc < 4) {
        fprintf(stderr, "Usage: %s <dylib> <p12> <password>\n", argv[0]);
        return 2;
    }

    const char *dylib_path = argv[1];
    const char *p12_path = argv[2];
    const char *password = argv[3];

    size_t p12_len = 0;
    uint8_t *p12_data = read_file(p12_path, &p12_len);
    if (!p12_data) {
        fprintf(stderr, "Cannot read .p12 file: %s\n", p12_path);
        return 1;
    }

    char err[512] = {0};
    bool ok = husk_codesign_dylib(dylib_path, p12_data, p12_len, password, getenv("TL_SIGN_IDENT"), err, sizeof(err));
    free(p12_data);

    if (!ok) {
        fprintf(stderr, "husk_codesign_dylib failed: %s\n", err);
        return 1;
    }

    printf("Successfully signed %s with %s\n", dylib_path, p12_path);
    return 0;
}
