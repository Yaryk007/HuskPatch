# HuskPatch

A fork of [Husk](https://github.com/Leviidev/Husk), an Android app launcher for
iOS. It fixes Android freezing at startup on iOS 26 TXM devices (A15 and newer,
for example the iPhone 16e).

Drop in an APK, tap it, and the Android app opens full-screen.

## What HuskPatch changes

Husk gets executable memory from StikDebug: the app executes a `brk`, and the
debugger answers it. While a debugger is attached, any `brk`, signal or fault
stops **the whole process** until the debugger replies. iOS suspends StikDebug
shortly after it hands the foreground back to Husk. If Husk then hits a stop
event, it hangs with no crash and no log line. Upstream did this in three
places:

1. **JIT claimed too late.** Once the runtime was downloaded, Husk only claimed
   JIT memory when Start was pressed. By then StikDebug was usually suspended.
   HuskPatch claims it on the first foreground pass after StikDebug attaches
   (`ContentView.evaluate`).
2. **Debugger never detached.** `husk_ios_jit_detach()` existed but nothing
   called it, so StikDebug's script stayed in its `c` loop for the whole
   session. HuskPatch detaches as soon as the region is held. The RX/RW pages
   stay valid after detach. To keep StikDebug attached for debugging, turn on
   Settings → JIT & sideload → *Keep debugger attached*.
3. **MAP_JIT probe on TXM devices.** The probe executes a MAP_JIT page. That
   cannot work on a TXM device, and under an attached debugger its fault is a
   stop rather than a signal. Upstream also ran the probe from the Settings
   view body. HuskPatch skips the probe on TXM devices (same rule as StikDebug:
   iOS 26 on iPhone14,2+ / iPad14,5+, and all of iOS 27). Settings only shows a
   cached result.

The QEMU allocator (`src/ios-jit/husk-ios-jit.c`) also no longer issues a
second `brk` from inside `qemu_init` after the first claim went unanswered.

The bundle ID is `com.huskpatch.app`, so HuskPatch installs alongside Husk.

### Using it on iOS 26

1. Install the IPA with your usual sideloading tool.
2. Open HuskPatch and tap **Enable JIT**. StikDebug opens, attaches, and runs
   the bundled JIT script.
3. Return to HuskPatch **right away**. It claims the JIT region and releases
   StikDebug within about a second.
4. Settings → JIT & sideload should show *Executable memory: granted* and
   *Debugger after setup: detached*. Then press Start.

## Building

Same as upstream; it needs a Mac with Xcode. Build QEMU and its dependencies
with `scripts/build_ios.sh`, then generate the app with XcodeGen from
`src/app/project.yml` and package it with `scripts/package_ipa.sh`. The change
in `src/ios-jit/` goes into the QEMU dylib, so CI must rebuild QEMU, not only
the app.

## Licence

GPL-2.0-or-later. Husk links QEMU, which is GPLv2, so the shipped binary is a
combined GPLv2 work and the full source is public. It cannot go on the App
Store, both because of that and because it needs `get-task-allow` plus a
debugger attaching at runtime. See [docs/01-licensing.md](docs/01-licensing.md).

## Notice

This was rebuilt via claude opus 5.5 so expect some issues, and also updates to original husk may be pushed and i dont focus to this as much.
