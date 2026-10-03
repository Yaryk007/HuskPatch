# HuskPatch

A fork of [Husk](https://github.com/Leviidev/Husk) (Android apps on iOS) that
fixes Android freezing at startup on iOS 26.

## What's different from Husk

| | Husk | HuskPatch |
|---|---|---|
| JIT memory claimed | When you press Start, often after iOS has suspended StikDebug, so the app freezes | As soon as StikDebug returns you to the app |
| StikDebug after setup | Stays attached all session; any later trap can freeze the app | Released once JIT memory is held (Settings toggle to keep it) |
| MAP_JIT test | Runs on every device, including from the Settings screen; can freeze TXM devices | Skipped on TXM devices (iOS 26 on A15 and newer, all of iOS 27) |
| Second JIT request inside QEMU | Asks StikDebug again after a failed first request; can freeze | Fails fast instead |
| App ID / name | `com.husk.app` / Husk | `com.huskpatch.app` / HuskPatch; installs alongside Husk |
| Building | About 8 scripts run by hand on a Mac; the JIT patch didn't apply on a clean checkout | `scripts/ci_build.sh` runs the whole chain; GitHub Actions builds the IPA |

## Get the IPA

Open **Actions → Build IPA**, then download **HuskPatch-ipa** from the newest
green run. Each push to `main` rebuilds it, or click **Run workflow**. The IPA
is unsigned; your sideloading tool signs it.

## Using it

1. Open HuskPatch and tap **Enable JIT**. StikDebug attaches.
2. Come straight back to HuskPatch.
3. Settings → JIT & sideload should show *Executable memory: granted* and
   *Debugger after setup: detached*.
4. Start Android.

## Licence

GPL-2.0-or-later, as upstream. See [docs/01-licensing.md](docs/01-licensing.md).

## Notice

This was rebuilt via claude opus 5.5 so expect some issues, and also updates to original husk may be pushed and i dont focus to this as much.
