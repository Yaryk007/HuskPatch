# Android translation

The aim is to replace QEMU: run Android's services and, later, its whole interface in Husk's own process. It is built a stage at a time, behind Developer options › **Android translation (currently at services stage)**, and is off by default. The QEMU machine is not touched.

## Stages

| Stage | What | Status |
| --- | --- | --- |
| **1 Services** | System services answer the real Binder protocol with the iPhone's own state | In progress |
| **2 Framework** | `framework.jar` in the build, so Android's own Java classes call those services | Not started |
| **3 system_server** | `services.jar` on Husk's Dalvik, replacing native services where that is practical | Not started |
| **4 Interface** | SurfaceFlinger, window management, then SystemUI and a launcher | Not started |

## Services

`src/translation-layer-next/husk-tl-services.c`. Each service has a switch of its own, takes its name in ServiceManager while it runs, and gives back any stand-in from `husk-tl-aosp.c` when stopped.

| Service | Interface | Written | Comes from |
| --- | --- | --- | --- |
| `batteryproperties` | `IBatteryPropertiesRegistrar` | `getProperty` (capacity, status), `scheduleUpdate` | `UIDevice` |
| `power` | `IPowerManager` | `isInteractive`, `isPowerSaveMode`, `isDeviceIdleMode`, wake locks | app state, Low Power Mode, idle timer |
| `thermalservice` | `IThermalService` | `getCurrentThermalStatus` | `ProcessInfo.thermalState` |
| `uimode` | `IUiModeManager` | mode type, night mode, locks | the iPhone's appearance |
| `country_detector` | `ICountryDetector` | `detectCountry`, listeners | the iPhone's region |

A call to a method not written yet is counted and shown beside the service with its code, as Binder's unknown transaction. That list is what to write next.

### Adding one

1. Add its `.aidl` to `FILES` in `tools/aidl-codes.py` and regenerate `husk-tl-aidl-codes.h`. Never type a code: 68 of the 94 checked differ between Android 13 and 16.
2. Write its call function and add it to `g_services`.
3. Test it in `tools/services-test.c` with the bytes `Parcel` writes, and run `tests/translation-layer/run_binder.sh`.

## Google Play services

`husk.GooglePackages` reports Play services as installed; `husk.GmsCore` is what apps then reach. This is always on, separate from the toggle. It is written from microG's Apache-2.0 protocol definitions, and Google's code must not be bundled (`docs/01-licensing.md`).

| Part | State |
| --- | --- |
| `isGooglePlayServicesAvailable`, signature check | Answers SUCCESS (checked with Google's own client code) |
| Broker handshake | Written; an API with no implementation gets `API_UNAVAILABLE` and is logged by number under `HuskGms` |
| Advertising ID | Written; zeros and limited, as a phone opted out of ad personalisation reports |
| Sign-in, Maps, Firebase push, Play Integrity | Not available: they need Google's servers or code. Integrity is not to be faked |

The `HuskGms` log says which API number to write next.

## Limits

- The codes are Android 16's, matching the LineageOS 23.2 guest.
- Apps do not call the system services yet: without `framework.jar` nothing on the Java side does. Stage 2 changes that.
- Listeners and callbacks are accepted but never called back.
