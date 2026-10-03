# HuskPatch

A fork of [Husk](https://github.com/Leviidev/Husk) (Android apps on iOS) that
fixes Android freezing at startup on iOS 26.

## What's different from Husk

| | Husk | HuskPatch |
|---|---|---|
| JIT memory claimed | When you press Start, often after iOS has suspended StikDebug, so the app freezes | As soon as StikDebug returns you to the app |
| StikDebug after setup | Stays attached all session; any later trap can freeze the app | Released once JIT memory is held (Settings toggle to keep it) |
| MAP_JIT test | Runs on every device, including from the Settings screen; can freeze TXM devices | Skipped on TXM devices (iOS 26 on A14 and newer, all of iOS 27) |
| Second JIT request inside QEMU | Asks StikDebug again after a failed first request; can freeze | Fails fast instead |
| Boot progress | Stuck at 58% for the whole second half of a cold boot (the image has no boot animation, so no milestones fire) | Two more milestones, a slow creep between them, and elapsed time instead of a wrong countdown |
| App ID / name | `com.husk.app` / Husk | `com.huskpatch.app` / HuskPatch; installs alongside Husk |
| Building | About 8 scripts run by hand on a Mac; the JIT patch didn't apply on a clean checkout | `scripts/ci_build.sh` runs the whole chain; GitHub Actions builds the IPA |

## Get the IPA

Download **HuskPatch-ipa.zip** from the newest release under
[Releases](https://github.com/Yaryk007/HuskPatch/releases), unzip it, and
sideload `HuskPatch.ipa` with your usual tool (it is unsigned; the tool signs
it). Builds of the latest code are under **Actions → Build IPA**.

Nothing in HuskPatch is tied to one iPhone model. It should work on any iPhone
on iOS 16.4 or later that StikDebug supports. JIT setup is confirmed on an
iPhone 16e (iOS 26.1) and an iPhone 15 Pro Max (iOS 26.0.1).

## Using it

1. Open HuskPatch and tap **Enable JIT**. StikDebug attaches.
2. Come straight back to HuskPatch.
3. Settings → JIT & sideload should show *Executable memory: granted* and
   *Debugger after setup: detached*.
4. Start Android.

### The first boot is slow

The pre-booted snapshot was saved with the CPU renderer, but the GPU renderer
is the default. With the GPU renderer, the first start boots Android from scratch: about
5–15 minutes under emulation, and the screen stays black most of that time.
Leave the app open until it finishes. Android then saves itself, so later
starts take seconds. For a fast first start, set Settings → Performance →
Renderer to **CPU** and leave sound and landscape off. HuskPatch then restores
the shipped snapshot instead, but draws more slowly.

## Licence

GPL-2.0-or-later, as upstream. See [docs/01-licensing.md](docs/01-licensing.md).

## Notice

This was rebuilt via claude opus 5.5 so expect some issues, and also updates to original husk may be pushed and i dont focus to this as much so this project may become outdated now.
