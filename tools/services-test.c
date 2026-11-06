/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Android translation's services, called as an AIDL proxy calls them: the bytes Parcel writes, the codes Android 16's stubs use. */
#include "husk-tl-aidl-codes.h"
#include "husk-tl-binder.h"
#include "husk-tl-servicemanager.h"
#include "husk-tl-services.h"

#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void tl_log_line(const char *fmt, ...) { (void)fmt; }

static uint8_t buf[512];
static size_t n;
static void i32(int32_t v) { memcpy(buf + n, &v, 4); n += 4; }
static void str16(const char *s)
{
    int32_t len = (int32_t)strlen(s);
    i32(len);
    size_t bytes = ((size_t)(len + 1) * 2 + 3) & ~(size_t)3;
    memset(buf + n, 0, bytes);
    for (int32_t i = 0; i < len; i++) buf[n + (size_t)i * 2] = (uint8_t)s[i];
    n += bytes;
}
static void token(const char *d) { n = 0; i32(0); i32(-1); i32(0x53595354); str16(d); }
static int32_t at(const husk_binder_reply *r, size_t o) { int32_t v; assert(o + 4 <= r->data_size); memcpy(&v, r->data + o, 4); return v; }

/* getService through handle 0, with a real interface token: what ServiceManager.getService sends. */
static uint32_t lookup(const char *name)
{
    token("android.os.IServiceManager");
    str16(name);
    husk_binder_reply r = {0};
    assert(husk_binder_transact(0, 1, 0, buf, n, NULL, 0, &r) == 0);
    /* no exception, then a flat_binder_object: BINDER_TYPE_HANDLE and the handle */
    uint32_t handle = 0;
    if (r.n_offsets == 1) memcpy(&handle, r.data + r.offsets[0] + 8, 4);
    husk_binder_reply_free(&r);
    assert(handle == husk_sm_get(name));
    return handle;
}

static husk_binder_reply send_call(const char *service, uint32_t code)
{
    husk_binder_reply r = {0};
    assert(husk_binder_transact(husk_sm_get(service), code, 0, buf, n, NULL, 0, &r) == 0);
    return r;
}

static int wake_held = -1;
static void wake_host(int held) { wake_held = held; }

int main(void)
{
    husk_services_state st = { 87, 2, 3, true, true, 2, "UA" };
    husk_services_set_state(&st);
    husk_services_set_wakelock_host(wake_host);

    /* stopped: nothing there */
    husk_sm_start();
    assert(!lookup("power"));
    char text[160];
    assert(!husk_services_probe("power", text, sizeof text));

    for (int i = 0; i < husk_services_count(); i++) {
        husk_service_info info;
        assert(husk_services_info(i, &info));
        assert(husk_services_start(info.name) && lookup(info.name));
    }

    /* battery: int getProperty(int, out BatteryProperty) */
    token("android.os.IBatteryPropertiesRegistrar"); i32(4);
    husk_binder_reply r = send_call("batteryproperties", AIDL_IBatteryPropertiesRegistrar_getProperty);
    assert(at(&r, 0) == 0 && at(&r, 4) == 0 && at(&r, 8) == 1);
    int64_t level; memcpy(&level, r.data + 12, 8); assert(level == 87);
    assert(at(&r, 20) == -1 && r.data_size == 24);
    husk_binder_reply_free(&r);
    token("android.os.IBatteryPropertiesRegistrar"); i32(1);    /* charge counter: iOS does not say */
    r = send_call("batteryproperties", AIDL_IBatteryPropertiesRegistrar_getProperty);
    assert(at(&r, 4) == -2);
    husk_binder_reply_free(&r);

    /* power */
    token("android.os.IPowerManager");
    r = send_call("power", AIDL_IPowerManager_isPowerSaveMode); assert(at(&r, 0) == 0 && at(&r, 4) == 1); husk_binder_reply_free(&r);
    token("android.os.IPowerManager");
    r = send_call("power", AIDL_IPowerManager_isInteractive); assert(at(&r, 4) == 1); husk_binder_reply_free(&r);
    /* two locks, one released twice: the screen is held until the last goes */
    for (uint64_t lock = 1; lock <= 2; lock++) {
        token("android.os.IPowerManager");
        i32(0x73622a85); i32(0); memcpy(buf + n, &lock, 8); n += 8; memset(buf + n, 0, 8); n += 8;
        r = send_call("power", AIDL_IPowerManager_acquireWakeLock); husk_binder_reply_free(&r);
    }
    assert(wake_held == 2);
    for (int k = 0; k < 2; k++) {
        uint64_t lock = 1;
        token("android.os.IPowerManager");
        i32(0x73622a85); i32(0); memcpy(buf + n, &lock, 8); n += 8; memset(buf + n, 0, 8); n += 8;
        r = send_call("power", AIDL_IPowerManager_releaseWakeLock); husk_binder_reply_free(&r);
    }
    assert(wake_held == 1);

    /* thermal, uimode */
    token("android.os.IThermalService");
    r = send_call("thermalservice", AIDL_IThermalService_getCurrentThermalStatus); assert(at(&r, 4) == 3); husk_binder_reply_free(&r);
    token("android.app.IUiModeManager");
    r = send_call("uimode", AIDL_IUiModeManager_getNightMode); assert(at(&r, 4) == 2); husk_binder_reply_free(&r);

    /* country: a typed Country */
    token("android.location.ICountryDetector");
    r = send_call("country_detector", AIDL_ICountryDetector_detectCountry);
    assert(at(&r, 4) == 1 && at(&r, 8) == 2 && r.data[12] == 'U' && r.data[14] == 'A');
    assert(at(&r, 20) == 3);
    husk_binder_reply_free(&r);

    /* the wrong interface is refused, as enforceInterface does */
    token("android.os.ISomethingElse");
    r = send_call("power", AIDL_IPowerManager_isInteractive); assert(r.data_size == 0); husk_binder_reply_free(&r);

    /* a method not written yet is counted, by its code */
    token("android.os.IThermalService");
    r = send_call("thermalservice", AIDL_IThermalService_getCurrentCoolingDevices); assert(r.data_size == 0); husk_binder_reply_free(&r);
    husk_service_info info;
    assert(husk_services_info(2, &info) && info.unhandled == 1 && info.last_unhandled == AIDL_IThermalService_getCurrentCoolingDevices);

    /* the words Settings shows come through Binder */
    assert(husk_services_probe("batteryproperties", text, sizeof text)); assert(!strcmp(text, "87%, BATTERY_STATUS 2"));
    assert(husk_services_probe("country_detector", text, sizeof text)); assert(!strcmp(text, "UA, COUNTRY_SOURCE_LOCALE"));
    assert(husk_services_probe("uimode", text, sizeof text)); assert(!strcmp(text, "UI_MODE_TYPE 1, MODE_NIGHT YES"));

    /* stopping one: gone from ServiceManager, its wake locks released, the others still up */
    husk_services_stop("power");
    assert(!husk_sm_get("power") && wake_held == 0 && husk_sm_get("uimode"));
    assert(husk_services_start("power") && lookup("power"));

    puts("services: real Android 16 transactions ok");
    return 0;
}
