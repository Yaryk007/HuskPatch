# Husk

The text bellow is not what huskpatch was used to be, it was a fork of husk to fix android startup issues like lag and freezes and crashes before a single frame was drawn. Leviidev put these new changes from this fork into official husk so now my job is done, husk is fixed, thank you guys for the support, i might still make updates but i will focus on my other projects more.

> **HuskPatch 2.6.0** is the latest official [Husk](https://github.com/Leviidev/Husk) code (2.0 plus build 119) with these additions:
>
> - **Android OS mode** (Settings › Appearance › Android OS): HuskPatch's interface replaced by LineageOS 23's (Android
>   16) -- a lock screen you swipe up, a home screen with your games and apps, an app drawer with the whole library, recents, and
>   Android's navigation: **3-button or gesture navigation** (Settings › System › Navigation mode; swipe up for home,
>   up and hold for recents, in from either edge for back). Games and apps open straight into the app, full screen.
>   Turns on the two options below with it.
>   - **Notification shade and Quick Settings**: pull down from the status bar (or anywhere on the home screen) for
>     the clock, notifications (your downloads) and tiles that work -- Internet, Flashlight, Dark theme, JIT,
>     Navigation mode, Battery Saver, Screen lock, Recent apps -- and a brightness slider; pull further for all of them.
>   - **LineageOS look**: its wallpaper (or Material shapes), Trebuchet's dock and page indicator, AOSP's lock screen
>     with the big two-line clock and flashlight / Do Not Disturb shortcuts, and Android's dialogs instead of iOS alerts.
>   - **Screen lock** (Settings › Security & privacy): None, Swipe, Pattern, PIN or Password, with AOSP's bouncer (PIN
>     pad, pattern grid, password field; five wrong tries wait 30 seconds) and a pretend **Fingerprint Unlock** you
>     enrol by touching the sensor. A look, not security: the iPhone's passcode still protects your data.
>   - **Testing** (Settings › Testing, also in HuskPatch's own Settings): every Material 3 Expressive component, the
>     palette, Android's dialogs, toasts, notifications, permission and file dialogs, the lock screen, the overscroll
>     effect, the translation layer's state, and **installing APKs** with Android's package installer.
>   - **Play Store app** laid out like Google Play: Games, Apps, Search and You tabs, chips for For you / Top charts /
>     Categories, carousels, and an app page with Install, screenshots and About.
>   - **Settings app** laid out like Android 16's: Network & internet, Connected devices, Apps (each app's permissions
>     and special app access), Display & touch, Wallpaper & style, System, About phone (tap Build number seven times).
> - **Android permissions** on the translation layer: when an app asks for a permission, Android's dialog appears. If
>   iOS guards the same thing (camera, microphone, location, photos, contacts, calendar, notifications, Bluetooth),
>   allowing it goes on to the iPhone's own prompt; if it is Android's alone (phone, SMS, display over other apps...),
>   only Android asks. Change them later in Settings › Apps.
> - **Files from the iPhone**: when an app on the translation layer opens a file (Android's file chooser,
>   `ACTION_GET_CONTENT` / `ACTION_OPEN_DOCUMENT`, the photo picker, Flutter's file_picker), the iPhone's Files picker
>   appears (the Photos picker for photos and videos, a folder picker for `ACTION_OPEN_DOCUMENT_TREE`). What you pick is
>   copied into the app's own storage (Download, Pictures or Movies on its sdcard) and handed to the app as a document,
>   with its name and size. The other way: a document the app creates is saved to Files, and a file it opens or shares
>   goes to Quick Look or the share sheet.
> - **Apps can close themselves**: finishing the last screen, `System.exit`, `killProcess` or moving to the back closes
>   the app (back to the launcher in Android OS mode) instead of leaving a black screen or quitting HuskPatch.
> - **Android's overscroll**: lists stretch at their ends as on Android 12+, or glow as on Android 5-11 (Settings ›
>   Display & touch › Overscroll effect), instead of iOS's rubber band.
> - **Android 16 Style**: Material 3 Expressive with [ExpressiveUI](https://github.com/edenkollcinaku/ExpressiveUI)'s
>   components (switches, buttons, menus, loading and progress indicators, carousel), and colours made the way Material
>   makes them: each role a tone (L*) of a palette from your accent, Android's navigation and search bars,
>   Material's back button, segmented buttons and switches, large rounded cards and pill buttons. No Liquid Glass.
> - **Material You in Apps**: apps on the translation layer get Android's dynamic colours, made from your accent.
> - **Resizable windows** (Multitasking): Android apps and Flutter apps lay out again at the window's new size; games
>   keep their shape as you resize or pinch, so there are no black bars and nothing is stretched. Maximise fills the
>   whole screen -- no rounded corners, no title bar (tap the handle at the top for it) -- and games start at
>   full-screen resolution, so a maximised game has no black borders.
> - **Android status bar** over apps in portrait, and **no grey borders** around apps.
> - HuskPatch's own icon and name; Husk's original icon is still there as **Automatic Legacy**, with the others.
>
> Upstream's PS4 games (libhuskps4) are not in these builds: the PS4 layer needs Leviidev's unpublished FEXCore fork.
>
> Builds: **Actions → Build IPA**, artifact **Husk-ipa**. Android's Java libraries in them come from the official 2.0
> release; Husk's Java framework is built from this repo. Untested builds: use
> [official releases](https://github.com/Leviidev/Husk/releases) for anything stable. The old HuskPatch 0.5.2 is on
> the [`huskpatch-0.5.2`](https://github.com/Yaryk007/HuskPatch/tree/huskpatch-0.5.2) branch.

<p align="center">
  <a href="https://trendshift.io/repositories/233057?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-233057" target="_blank" rel="noopener noreferrer">
    <img src="https://trendshift.io/api/badge/trendshift/repositories/233057/daily?language=Swift" alt="Leviidev/Husk | Trendshift" width="250" height="55"/>
  </a>
</p>

[![Husk Downloads](https://img.shields.io/github/downloads/leviidev/husk/total?style=for-the-badge&color=5865F2&labelColor=111111)](https://github.com/leviidev/husk/releases)

Android apps and games on your iPhone.

Add an APK, tap it, and it opens full-screen. Husk runs it in one of two ways,
shown as the two sides of its Library:

- **Translation Layer.** The game's own 64-bit Android code runs directly on
  the iPhone's processor, and Husk stands in for Android around it: the C
  library, the Java calls the game makes, OpenGL ES (through ANGLE), Vulkan
  (through MoltenVK), sound, touch and controllers. No Android boots, so a
  game starts in seconds, and its code is never emulated.
  See [docs/04-translation-layer.md](docs/04-translation-layer.md).
- **Emulation.** A full Android system (LineageOS) boots under QEMU inside
  Husk, for apps the translation layer cannot run yet and for using Android
  itself. iOS gives apps no hypervisor, so the processor is emulated, and
  this is much slower than the translation layer.
  See [docs/00-architecture.md](docs/00-architecture.md).

## Screenshots

### Games on the Translation Layer

<table>
  <tr>
    <td align="center"><img src="Screenshots/gta-san-andreas.jpeg" alt="GTA: San Andreas" width="100%"><br><sub><b>GTA: San Andreas</b></sub></td>
    <td align="center"><img src="Screenshots/minecraft-dungeons.jpeg" alt="Minecraft Dungeons" width="100%"><br><sub><b>Minecraft Dungeons</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Screenshots/beach-buggy-racing-2.jpeg" alt="Beach Buggy Racing 2" width="100%"><br><sub><b>Beach Buggy Racing 2</b></sub></td>
    <td align="center"><img src="Screenshots/geometry-dash.jpeg" alt="Geometry Dash" width="100%"><br><sub><b>Geometry Dash</b></sub></td>
  </tr>
</table>

### The app

<table>
  <tr>
    <td align="center" width="33%"><img src="Screenshots/library.png" alt="Library" width="100%"><br><sub><b>Library</b></sub></td>
    <td align="center" width="33%"><img src="Screenshots/game-settings.png" alt="Game Settings" width="100%"><br><sub><b>Game Settings</b></sub></td>
    <td align="center" width="33%"><img src="Screenshots/settings.png" alt="Settings" width="100%"><br><sub><b>Settings</b></sub></td>
  </tr>
</table>

## What the Translation Layer runs

Games made with an engine Husk has a driver for:

- Unity
- Unreal Engine 4 (through Vulkan)
- cocos2d-x
- Godot 3 and 4 (GLES2, GLES3 and the Compatibility renderer)
- SDL2 and SDL3, including LÖVE games
- GameActivity (Minecraft) and NativeActivity
- Rockstar's own engine (GTA: San Andreas)

Games see Google Play services as installed and signed out, so the ones that
check for it start normally; Play Games sign-in, cloud saves and purchases are
not available. Geometry Dash can load [Geode](https://geode-sdk.org) mods.

An APK needs 64-bit (`arm64-v8a`) native code. iPhones cannot run 32-bit ARM
code, so an APK that only has 32-bit libraries cannot run here. APKs and
split bundles (`.xapk`, `.apkm`, `.apks`, or a Play download's separate split
APKs and asset packs) can all be added. Apps written only
in Java, with no native engine, are not supported on the translation layer;
Emulation is the way to run those.

One game runs per launch of Husk. To switch, press **Close Husk to Play** on
the other game's page; when you open Husk again, that game starts by itself.

A game's saves can be backed up to a `.zip` from its page and restored later,
on the same iPhone or another. If a game crashes Husk, the next launch shows
what happened, with a report you can share.

## Installing

**SideStore, AltStore and other sideloaders:** add Husk's source, and the
sideloader installs Husk and offers each update as it comes out.

```
https://raw.githubusercontent.com/Leviidev/Husk/main/altsource.json
```

In SideStore or AltStore: Sources › + › paste the address above.

**Or by hand:** download `Husk.ipa` from
[Releases](https://github.com/leviidev/husk/releases) and install it with
SideStore, AltStore or TrollStore. It is one IPA for all of them: it carries
Husk's entitlements, which TrollStore keeps, and a sideloader re-signs it with
your own.

Husk needs iOS 16.0 or later.

## JIT

Both the translation layer and Emulation need JIT, which on iOS comes from a
debugger. Husk can get it in several ways, and walks you through each one
(Settings › JIT & Sideload):

- **Built-in StikJIT** (iOS 26 and later): Husk turns JIT on itself, with no
  second app. On iOS 27 it pairs with your iPhone from Settings, with no
  computer. See [docs/06-built-in-jit.md](docs/06-built-in-jit.md).
- **StikDebug**, installed alongside Husk.
- **TrollStore or a Dopamine jailbreak** ("Allow JIT in Apps"), on iOS
  versions before 26 only. From iOS 26 only a debugger can grant JIT.

## Building

Husk is built on a Mac with Xcode. The build scripts also call `meson`,
`ninja`, `pkg-config`, `python3`, `xcodegen`, `qemu-img` and a Rust
toolchain with the `aarch64-apple-ios` target.

```sh
./scripts/ci_build.sh
```

From a clean checkout this fetches and cross-compiles everything Husk links:

- QEMU and its dependencies
- ANGLE and virglrenderer
- MoltenVK
- the on-device pairing library

It then builds the app and writes the IPA to `build/Husk.ipa`. The first run
takes a couple of hours, and later runs reuse what is already built. After
that, `./scripts/package_ipa.sh` rebuilds just the app and writes
`~/Desktop/Husk.ipa`.

`tools/regress/run.sh` plays a set of games on the Mac through the
translation layer and checks each against a reference screenshot (see the
top of `tools/regress/cases.txt` for what it needs).

## Licence

GPL-2.0-or-later. Husk links QEMU, which is GPLv2, so the shipped binary is a
combined GPLv2 work and the full source is public. The translation layer is
Husk's own code, under the same licence. Husk cannot go on the App Store, both
because of that and because it needs `get-task-allow` plus a debugger
attaching at runtime. See [docs/01-licensing.md](docs/01-licensing.md).
