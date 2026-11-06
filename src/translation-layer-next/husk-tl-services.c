/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Android's system services, one by one (husk-tl-services.h). Unlike the stand-ins in husk-tl-aosp.c, which give every
 * method the same reply so that AOSP's classes construct, each method here is the real one: its own transaction code,
 * the interface checked as Parcel.enforceInterface does, its own reply layout. A method not written yet is counted and
 * answered as Binder answers an unknown transaction, so the next one to write is visible in Settings.
 */
#include "husk-tl-services.h"
#include "husk-tl-aidl-codes.h"
#include "husk-tl-binder.h"
#include "husk-tl-servicemanager.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

void tl_log_line(const char *fmt, ...);

#define PING_TRANSACTION 0x5f504e47u
#define DUMP_TRANSACTION 0x5f44554du
#define INTERFACE_TRANSACTION 0x5f4e5446u
#define PARCEL_HEADER 0x53595354 /* 'SYST', after the work source in every interface token */
#define NAME_NOT_FOUND (-2)      /* android::NAME_NOT_FOUND, healthd's answer for a property it does not have */

#define BATTERY_PROPERTY_CAPACITY 4
#define BATTERY_PROPERTY_STATUS 6
#define UI_MODE_TYPE_NORMAL 1
#define COUNTRY_SOURCE_LOCALE 3
#define MAX_WAKELOCKS 64

/* ---- parcels */

typedef struct { uint8_t *p; size_t n, cap; } out_parcel;

static void o_need(out_parcel *o, size_t extra)
{
    if (o->n + extra <= o->cap) return;
    size_t c = o->cap ? o->cap * 2 : 64;
    while (c < o->n + extra) c *= 2;
    uint8_t *q = realloc(o->p, c);
    if (!q) abort();
    o->p = q;
    o->cap = c;
}
static void o_i32(out_parcel *o, int32_t v) { o_need(o, 4); memcpy(o->p + o->n, &v, 4); o->n += 4; }
static void o_i64(out_parcel *o, int64_t v) { o_need(o, 8); memcpy(o->p + o->n, &v, 8); o->n += 8; }
static void o_str16(out_parcel *o, const char *s)
{
    int32_t len = (int32_t)strlen(s);
    o_i32(o, len);
    size_t bytes = ((size_t)(len + 1) * 2 + 3) & ~(size_t)3;
    o_need(o, bytes);
    memset(o->p + o->n, 0, bytes);
    for (int32_t i = 0; i < len; i++) { uint16_t c = (unsigned char)s[i]; memcpy(o->p + o->n + (size_t)i * 2, &c, 2); }
    o->n += bytes;
}
static void o_interface(out_parcel *o, const char *descriptor)
{
    o_i32(o, 0);             /* strict mode */
    o_i32(o, -1);            /* work source */
    o_i32(o, PARCEL_HEADER);
    o_str16(o, descriptor);
}

/* Parcel.enforceInterface. Returns where the arguments begin, 0 when the call is for another interface. */
static size_t enforce_interface(const uint8_t *d, size_t n, const char *descriptor)
{
    if (n < 16) return 0;
    int32_t header, len;
    memcpy(&header, d + 8, 4);
    if (header != PARCEL_HEADER) return 0;
    memcpy(&len, d + 12, 4);
    if (len != (int32_t)strlen(descriptor)) return 0;
    size_t bytes = ((size_t)(len + 1) * 2 + 3) & ~(size_t)3;
    if (16 + bytes > n) return 0;
    for (int32_t i = 0; i < len; i++) {
        uint16_t c;
        memcpy(&c, d + 16 + (size_t)i * 2, 2);
        if (c != (unsigned char)descriptor[i]) return 0;
    }
    return 16 + bytes;
}

/* ---- the services */

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static husk_services_state g_state = { -1, 1, 0, false, true, 1, "" };
static void (*g_wakelock_host)(int held);
static uint64_t g_wakelocks[MAX_WAKELOCKS];
static int g_nwakelocks;

typedef struct service service;
/* Writes the reply after the no-exception word. False: not a method written yet. */
typedef bool (*service_call)(uint32_t code, const uint8_t *data, size_t size, size_t args, const husk_services_state *state, out_parcel *reply);

struct service {
    const char *name, *descriptor, *summary;
    service_call call;
    uint32_t handle, previous;
    bool running;
    uint64_t handled, unhandled;
    uint32_t last_unhandled;
};

static bool battery_call(uint32_t code, const uint8_t *data, size_t size, size_t args, const husk_services_state *s, out_parcel *r)
{
    if (code == AIDL_IBatteryPropertiesRegistrar_scheduleUpdate) return true;
    if (code != AIDL_IBatteryPropertiesRegistrar_getProperty) return false;
    int32_t id = 0;
    if (args + 4 <= size) memcpy(&id, data + args, 4);
    int64_t value = INT64_MIN;
    int32_t status = NAME_NOT_FOUND;
    if (id == BATTERY_PROPERTY_CAPACITY && s->battery_percent >= 0) { value = s->battery_percent; status = 0; }
    if (id == BATTERY_PROPERTY_STATUS) { value = s->battery_status; status = 0; }
    o_i32(r, status);
    o_i32(r, 1);        /* the out BatteryProperty is there */
    o_i64(r, value);
    o_i32(r, -1);       /* its string, null */
    return true;
}

/* A wake lock is known by its IBinder token: a flat_binder_object, whose binder is 8 bytes in. */
static uint64_t wakelock_token(const uint8_t *data, size_t size, size_t args)
{
    uint64_t token = 0;
    if (args + 16 <= size) memcpy(&token, data + args + 8, 8);
    return token;
}

static int wakelock_change(uint64_t token, bool acquire)
{
    int at = -1;
    for (int i = 0; i < g_nwakelocks; i++) if (g_wakelocks[i] == token) at = i;
    if (acquire && at < 0 && g_nwakelocks < MAX_WAKELOCKS) g_wakelocks[g_nwakelocks++] = token;
    if (!acquire && at >= 0) g_wakelocks[at] = g_wakelocks[--g_nwakelocks];
    return g_nwakelocks;
}

static bool power_call(uint32_t code, const uint8_t *data, size_t size, size_t args, const husk_services_state *s, out_parcel *r)
{
    switch (code) {
    case AIDL_IPowerManager_isInteractive: o_i32(r, s->screen_on); return true;
    case AIDL_IPowerManager_isPowerSaveMode: o_i32(r, s->low_power); return true;
    case AIDL_IPowerManager_isDeviceIdleMode: o_i32(r, 0); return true;
    case AIDL_IPowerManager_acquireWakeLock:
    case AIDL_IPowerManager_releaseWakeLock: {
        pthread_mutex_lock(&g_lock);
        int held = wakelock_change(wakelock_token(data, size, args), code == AIDL_IPowerManager_acquireWakeLock);
        void (*host)(int) = g_wakelock_host;
        pthread_mutex_unlock(&g_lock);
        if (host) host(held);
        return true;
    }
    }
    return false;
}

static bool thermal_call(uint32_t code, const uint8_t *data, size_t size, size_t args, const husk_services_state *s, out_parcel *r)
{
    (void)data; (void)size; (void)args;
    if (code != AIDL_IThermalService_getCurrentThermalStatus) return false;
    o_i32(r, s->thermal_status);
    return true;
}

static bool uimode_call(uint32_t code, const uint8_t *data, size_t size, size_t args, const husk_services_state *s, out_parcel *r)
{
    (void)data; (void)size; (void)args;
    switch (code) {
    case AIDL_IUiModeManager_getCurrentModeType: o_i32(r, UI_MODE_TYPE_NORMAL); return true;
    case AIDL_IUiModeManager_getNightMode: o_i32(r, s->night_mode); return true;
    case AIDL_IUiModeManager_isNightModeLocked: o_i32(r, 1); return true;   /* it follows iOS */
    case AIDL_IUiModeManager_isUiModeLocked: o_i32(r, 0); return true;
    }
    return false;
}

static bool country_call(uint32_t code, const uint8_t *data, size_t size, size_t args, const husk_services_state *s, out_parcel *r)
{
    (void)data; (void)size; (void)args;
    if (code == AIDL_ICountryDetector_addCountryListener || code == AIDL_ICountryDetector_removeCountryListener) return true;
    if (code != AIDL_ICountryDetector_detectCountry) return false;
    if (!s->country[0]) { o_i32(r, 0); return true; }    /* null, as with nothing to go on */
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    o_i32(r, 1);
    o_str16(r, s->country);
    o_i32(r, COUNTRY_SOURCE_LOCALE);
    o_i64(r, (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000);
    return true;
}

static service g_services[] = {
    { "batteryproperties", "android.os.IBatteryPropertiesRegistrar", "Battery level and charging, from the iPhone", battery_call },
    { "power", "android.os.IPowerManager", "Screen state, Low Power Mode and wake locks", power_call },
    { "thermalservice", "android.os.IThermalService", "Thermal status, from iOS", thermal_call },
    { "uimode", "android.app.IUiModeManager", "Dark theme, following iOS", uimode_call },
    { "country_detector", "android.location.ICountryDetector", "Country, from the iPhone's region", country_call },
};
#define N_SERVICES ((int)(sizeof(g_services) / sizeof(g_services[0])))

static service *find(const char *name)
{
    for (int i = 0; name && i < N_SERVICES; i++) if (!strcmp(g_services[i].name, name)) return &g_services[i];
    return NULL;
}

static void on_transaction(uint32_t code, uint32_t flags, const uint8_t *data, size_t size,
                           const uint64_t *offsets, size_t n_offsets, husk_binder_reply *reply, void *cookie)
{
    (void)flags; (void)offsets; (void)n_offsets;
    service *svc = cookie;
    out_parcel r = {0};
    bool answered = false;
    pthread_mutex_lock(&g_lock);
    bool running = svc->running;
    husk_services_state state = g_state;
    pthread_mutex_unlock(&g_lock);
    if (!running) return;
    if (code == PING_TRANSACTION || code == DUMP_TRANSACTION) answered = true;
    else if (code == INTERFACE_TRANSACTION) { o_str16(&r, svc->descriptor); answered = true; }
    else {
        size_t args = enforce_interface(data, size, svc->descriptor);
        if (args) {
            o_i32(&r, 0);   /* no exception */
            answered = svc->call(code, data, size, args, &state, &r);
        } else tl_log_line("services: %s: code %u for another interface", svc->name, code);
    }
    pthread_mutex_lock(&g_lock);
    if (answered) svc->handled++;
    else { svc->unhandled++; svc->last_unhandled = code; }
    pthread_mutex_unlock(&g_lock);
    if (!answered) { free(r.p); return; }
    reply->data = r.p;
    reply->data_size = r.n;
}

/* ---- running them */

void husk_services_set_state(const husk_services_state *state)
{
    if (!state) return;
    pthread_mutex_lock(&g_lock);
    g_state = *state;
    pthread_mutex_unlock(&g_lock);
}

void husk_services_set_wakelock_host(void (*fn)(int held))
{
    pthread_mutex_lock(&g_lock);
    g_wakelock_host = fn;
    pthread_mutex_unlock(&g_lock);
}

int husk_services_count(void) { return N_SERVICES; }

bool husk_services_info(int index, husk_service_info *out)
{
    if (index < 0 || index >= N_SERVICES || !out) return false;
    service *s = &g_services[index];
    pthread_mutex_lock(&g_lock);
    *out = (husk_service_info){ s->name, s->descriptor, s->summary, s->running, s->handled, s->unhandled, s->last_unhandled };
    pthread_mutex_unlock(&g_lock);
    return true;
}

bool husk_services_running(const char *name)
{
    service *s = find(name);
    if (!s) return false;
    pthread_mutex_lock(&g_lock);
    bool running = s->running;
    pthread_mutex_unlock(&g_lock);
    return running;
}

bool husk_services_start(const char *name)
{
    service *s = find(name);
    if (!s) return false;
    husk_sm_start();
    pthread_mutex_lock(&g_lock);
    bool already = s->running;
    s->running = true;
    pthread_mutex_unlock(&g_lock);
    if (already) return true;
    if (!s->handle) s->handle = husk_binder_add_local(on_transaction, s);
    if (!s->handle) { husk_services_stop(name); return false; }
    s->previous = husk_sm_get(name);    /* the stand-in, when the AOSP path made one: it comes back on stop */
    husk_sm_add(name, s->handle);
    tl_log_line("services: %s started", name);
    return true;
}

void husk_services_stop(const char *name)
{
    service *s = find(name);
    if (!s) return;
    pthread_mutex_lock(&g_lock);
    bool was = s->running;
    s->running = false;
    if (s->call == power_call) g_nwakelocks = 0;
    void (*host)(int) = g_wakelock_host;
    pthread_mutex_unlock(&g_lock);
    if (!was) return;
    if (s->previous) husk_sm_add(name, s->previous); else husk_sm_remove(name);
    if (s->call == power_call && host) host(0);
    tl_log_line("services: %s stopped", name);
}

/* ---- a client */

static bool call(const service *s, uint32_t code, const int32_t *arg, husk_binder_reply *reply)
{
    uint32_t handle = husk_sm_get(s->name);
    if (!handle) return false;
    out_parcel q = {0};
    o_interface(&q, s->descriptor);
    if (arg) o_i32(&q, *arg);
    int rc = husk_binder_transact(handle, code, 0, q.p, q.n, NULL, 0, reply);
    free(q.p);
    if (rc != 0 || reply->data_size < 4) { husk_binder_reply_free(reply); return false; }
    int32_t exception;
    memcpy(&exception, reply->data, 4);
    if (exception == 0) return true;
    husk_binder_reply_free(reply);
    return false;
}

static int32_t word(const husk_binder_reply *r, size_t at)
{
    int32_t v = 0;
    if (at + 4 <= r->data_size) memcpy(&v, r->data + at, 4);
    return v;
}

static bool call_int(const service *s, uint32_t code, int32_t *out)
{
    husk_binder_reply r = {0};
    if (!call(s, code, NULL, &r)) return false;
    *out = word(&r, 4);
    husk_binder_reply_free(&r);
    return true;
}

static bool battery_property(const service *s, int32_t id, int64_t *out)
{
    husk_binder_reply r = {0};
    if (!call(s, AIDL_IBatteryPropertiesRegistrar_getProperty, &id, &r)) return false;
    bool ok = word(&r, 4) == 0 && word(&r, 8) == 1 && r.data_size >= 20;
    if (ok) memcpy(out, r.data + 12, 8);
    husk_binder_reply_free(&r);
    return ok;
}

bool husk_services_probe(const char *name, char *out, int cap)
{
    service *s = find(name);
    if (!s || !out || cap <= 0) return false;
    out[0] = 0;
    if (!husk_services_running(name)) { snprintf(out, (size_t)cap, "Not running"); return false; }
    int32_t a = 0, b = 0;
    int64_t level = 0, status = 0;
    if (s->call == battery_call) {
        if (!battery_property(s, BATTERY_PROPERTY_STATUS, &status)) return false;
        if (battery_property(s, BATTERY_PROPERTY_CAPACITY, &level)) snprintf(out, (size_t)cap, "%lld%%, BATTERY_STATUS %lld", (long long)level, (long long)status);
        else snprintf(out, (size_t)cap, "Level unknown, BATTERY_STATUS %lld", (long long)status);
        return true;
    }
    if (s->call == power_call) {
        if (!call_int(s, AIDL_IPowerManager_isInteractive, &a) || !call_int(s, AIDL_IPowerManager_isPowerSaveMode, &b)) return false;
        pthread_mutex_lock(&g_lock);
        int held = g_nwakelocks;
        pthread_mutex_unlock(&g_lock);
        snprintf(out, (size_t)cap, "isInteractive %s, isPowerSaveMode %s, %d wake lock(s)", a ? "true" : "false", b ? "true" : "false", held);
        return true;
    }
    if (s->call == thermal_call) {
        if (!call_int(s, AIDL_IThermalService_getCurrentThermalStatus, &a)) return false;
        snprintf(out, (size_t)cap, "THERMAL_STATUS %d", a);
        return true;
    }
    if (s->call == uimode_call) {
        if (!call_int(s, AIDL_IUiModeManager_getCurrentModeType, &a) || !call_int(s, AIDL_IUiModeManager_getNightMode, &b)) return false;
        snprintf(out, (size_t)cap, "UI_MODE_TYPE %d, MODE_NIGHT %s", a, b == 2 ? "YES" : "NO");
        return true;
    }
    if (s->call == country_call) {
        husk_binder_reply r = {0};
        if (!call(s, AIDL_ICountryDetector_detectCountry, NULL, &r)) return false;
        if (word(&r, 4) != 1) snprintf(out, (size_t)cap, "No country");
        else {
            int32_t len = word(&r, 8);
            char iso[8] = {0};
            for (int32_t i = 0; i < len && i < 7 && 12 + (size_t)i * 2 < r.data_size; i++) iso[i] = (char)r.data[12 + i * 2];
            snprintf(out, (size_t)cap, "%s, COUNTRY_SOURCE_LOCALE", iso);
        }
        husk_binder_reply_free(&r);
        return true;
    }
    return false;
}
