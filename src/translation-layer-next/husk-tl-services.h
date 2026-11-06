/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_SERVICES_H
#define HUSK_TL_SERVICES_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Android translation, services stage: Android's system services, answering the real Binder protocol of Android 16 (the
 * codes come from AOSP's .aidl files, husk-tl-aidl-codes.h) with what is true of this iPhone. Each one starts and stops by
 * itself and takes over its name in ServiceManager. They run without framework.jar, so they do not depend on the AOSP boot path.
 * One at a time, these are what is meant to replace the guest's system_server.
 */

/* What the services report. The host keeps this current. */
typedef struct husk_services_state {
    int battery_percent;     /* -1 unknown */
    int battery_status;      /* BatteryManager.BATTERY_STATUS_*: 1 unknown, 2 charging, 3 discharging, 5 full */
    int thermal_status;      /* PowerManager.THERMAL_STATUS_*: 0 none ... 6 shutdown */
    bool low_power;
    bool screen_on;
    int night_mode;          /* UiModeManager.MODE_NIGHT_NO 1 / MODE_NIGHT_YES 2 */
    char country[8];         /* ISO 3166, upper case */
} husk_services_state;

typedef struct husk_service_info {
    const char *name;        /* its name in ServiceManager */
    const char *descriptor;  /* its AIDL interface */
    const char *summary;
    bool running;
    uint64_t handled;        /* transactions answered */
    uint64_t unhandled;      /* calls to methods not written yet */
    uint32_t last_unhandled; /* the code of the latest of those */
} husk_service_info;

void husk_services_set_state(const husk_services_state *state);
/* Told how many wake locks are held, so the host can keep the screen on while any is. */
void husk_services_set_wakelock_host(void (*fn)(int held));

int husk_services_count(void);
bool husk_services_info(int index, husk_service_info *out);
bool husk_services_running(const char *name);
bool husk_services_start(const char *name);
void husk_services_stop(const char *name);
/* A real client's call through Binder, as an app would make it, in words. False when the service is not answering. */
bool husk_services_probe(const char *name, char *out, int cap);

#ifdef __cplusplus
}
#endif

#endif
