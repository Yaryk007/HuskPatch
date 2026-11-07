// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit
import ModemOS
import UserNotifications

/// HuskPatch: the user's own fake OS (ModemOS, src/app/ModemOS) as the whole interface. Its apps stay its own;
/// HuskPatch's Home, Library, Store and Settings sit in a "HuskPatch" folder in its app drawer. Installed Android apps get
/// their own icons in the drawer and open as ModemOS windows, so they run beside ModemOS's own apps.
enum ModemOSLook {
    static let key = "huskpatch.modemos"

    /// HuskPatch and ModemOS are one system now: it is the interface unless turned off in Android settings.
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Once: an install from before the merge moves onto ModemOS, whatever it was showing.
    @MainActor static func adoptMergedSystem() {
        let done = "huskpatch.modemos.merged"
        guard !UserDefaults.standard.bool(forKey: done) else { return }
        UserDefaults.standard.set(true, forKey: done)
        set(true)
    }

    /// Turning ModemOS on turns Android OS mode off: only one interface can stand in for HuskPatch's.
    @MainActor static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        if on, AndroidOS.isOn { AndroidOS.set(false) }
        // HuskPatch's own screens keep their look: real Liquid Glass is only asked for while ModemOS is the interface.
        ModemOSView.syncSystemGlass(modemOSOn: on)
    }

    /// Hands ModemOS HuskPatch's screens and the way back.
    @MainActor static func registerHost() {
        let host = ModemOSHost.shared
        host.folderName = "Android"
        host.restart = { restart() }
        host.frontChanged = { id in
            ModemOSHost.shared.frontID = id
            frontChanged(id)
        }
        host.apps = [
            ModemOSHostApp(id: "home", name: "Games", symbol: "gamecontroller.fill",
                           color: Color(red: 0.12, green: 0.62, blue: 0.29)) { HomeView() },
            ModemOSHostApp(id: "library", name: "Library", symbol: "square.grid.2x2.fill",
                           color: Color(red: 0.25, green: 0.45, blue: 0.95)) { LibraryScreen() },
            ModemOSHostApp(id: "store", name: "Play Store", symbol: "bag.fill",
                           color: Color(red: 0.95, green: 0.55, blue: 0.15)) { StoreView() },
            ModemOSHostApp(id: "settings", name: "Android settings", symbol: "gearshape.2.fill",
                           color: Color(red: 0.45, green: 0.45, blue: 0.52)) { SettingsTab() },
        ]
    }

    /// The OS stays upright; an Android app in front turns the screen the way it draws, and comes forward if it was paused.
    @MainActor private static func frontChanged(_ id: String?) {
        guard let id, id.hasPrefix("tl:"),
              let app = TranslationLayerStore.shared.apps.first(where: { "tl:" + $0.id == id }) else {
            HuskOrientation.set(HuskOrientation.standard)
            return
        }
        HuskOrientation.set(app.drawsPortrait(TLAppSettings.load(app.id)) ? .portrait : .landscape)
        // After the screen has turned and the window is up: a fixed-size surface must not draw while it is turning.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard ModemOSHost.shared.frontID == id, let apk = app.apks.first else { return }
            _ = husk_multiapp_switch(apk)
            revive(app)
        }
    }

    /// An app that closed itself comes back when it is opened again, without restarting HuskPatch.
    @MainActor static func revive(_ app: TLApp) {
        guard let apk = app.apks.first, husk_native_loaded_apk().map({ String(cString: $0) }) == apk,
              husk_unity_state() == Int32(HUSK_UNITY_ENDED) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = husk_native_reopen()
            DispatchQueue.main.async {
                if result == 1 { TLUnityScreen.forget(apk: apk) }
                ModemOSRevival.shared.finished(app.id, result: result)
            }
        }
    }

    /// The apps on the translation layer, as ModemOS apps.
    @MainActor static func syncInstalled(_ apps: [TLApp]) {
        ModemOSHost.shared.installed = apps.map { app in
            ModemOSHostApp(
                id: "tl:" + app.id, name: app.label, symbol: "app.fill",
                color: Color(red: 0.24, green: 0.72, blue: 0.45),
                icon: app.iconPath.flatMap { UIImage(contentsOfFile: $0) },
                // Its engine cannot be started twice in a run, so ModemOS never stops it to free memory.
                fullScreen: true, pinned: true
            ) {
                ModemOSAndroidApp(app: app)
            }
        }
    }

    /// Leaves, so the next launch reads what only a launch can (the system's Liquid Glass switch).
    @MainActor static func restart() {
        UIApplication.shared.perform(NSSelectorFromString("suspend"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(0) }
    }

    /// The app a restart was for (Android apps only swap with a fresh process): opened as this run's ModemOS comes up.
    @MainActor static func resumePendingLaunch() {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey: AndroidShellState.pendingLaunchKey) else { return }
        defaults.removeObject(forKey: AndroidShellState.pendingLaunchKey)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["huskpatch.relaunch"])
        Task { @MainActor in
            for _ in 0..<120 {
                if TranslationLayerStore.shared.apps.contains(where: { $0.id == id }) {
                    ModemOSHost.shared.openRequest = "tl:" + id
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

/// Developer options: more than one Android app in a run. Each engine keeps its state to itself, so two apps can only
/// share a run when they use different engines. Off by default: it has never run on a device, and can crash both apps.
enum HuskMultiApp {
    static let pausedKey = "huskpatch.dev.keepAppsPaused"
    static let liveKey = "huskpatch.dev.twoAppsLive"

    private static var mode: Int32 {
        let d = UserDefaults.standard
        return d.bool(forKey: liveKey) ? 2 : d.bool(forKey: pausedKey) ? 1 : 0
    }

    static var isOn: Bool { mode != 0 }

    static func apply() { husk_multiapp_set_mode(mode) }

    /// The ENGINE_ number husk-tl-unity-app.c uses for a screen engine.
    static func code(_ engine: TLNativeEngine) -> Int32 {
        switch engine {
        case .unity: return 0
        case .cocos: return 1
        case .minecraft: return 2
        case .sdl: return 3
        case .ue4, .nativeactivity: return 4
        case .gta: return 5
        case .godot: return 6
        case .flutter: return 7
        case .gamemaker: return 8
        case .java: return 9
        }
    }

    static func canStart(_ app: TLApp) -> Bool {
        isOn && husk_multiapp_has_room(code(app.screenEngine)) != 0
    }
}

/// Apps being brought back after closing themselves: a new run gets a new screen.
@MainActor final class ModemOSRevival: ObservableObject {
    static let shared = ModemOSRevival()
    @Published private(set) var runs: [String: Int] = [:]
    @Published private(set) var failed = Set<String>()

    func finished(_ id: String, result: Int32) {
        if result == 0 { failed.insert(id); return }
        failed.remove(id)
        if result == 1 { runs[id, default: 0] += 1 }
    }
}

/// What ContentView shows when ModemOS is on.
struct ModemOSShellView: View {
    @ObservedObject private var store = TranslationLayerStore.shared

    init() { ModemOSLook.registerHost() }

    var body: some View {
        ModemOSView()
            .ignoresSafeArea()
            .onAppear {
                ModemOSLook.syncInstalled(store.apps)
                ModemOSView.syncSystemGlass(modemOSOn: true)
                ModemOSLook.resumePendingLaunch()
            }
            .onChange(of: store.apps.map(\.id)) { _ in ModemOSLook.syncInstalled(store.apps) }
    }
}

/// An installed app in a ModemOS window. It runs while other apps are in front of it. The limit is the engine's: one can be
/// loaded per run and never unloaded, so a second Android app needs a fresh process, as it does in Android OS mode.
private struct ModemOSAndroidApp: View {
    let app: TLApp

    private enum Gate { case running, needsJIT, otherApp(String), ended }

    @State private var gate = Gate.needsJIT
    @State private var checked = false
    /// Once started it stays: the check must not take a running engine's view away.
    @State private var started = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @ObservedObject private var revival = ModemOSRevival.shared

    var body: some View {
        Group {
            if revival.failed.contains(app.id) {
                blockedEnded
            } else if started {
                TLAttemptView(app: app).id(revival.runs[app.id] ?? 0)
            } else if checked {
                blocked
            } else {
                Color.black
            }
        }
        .background(Color.black)
        .onAppear { check(ask: true) }
        .onReceive(tick) { _ in
            if !started, case .needsJIT = gate { check(ask: false) }
        }
    }

    private func check(ask: Bool) {
        guard !started else { return }
        checked = true
        if app.report?.webKind != nil { started = true; return }
        guard Launcher.jitOn else {
            gate = .needsJIT
            if ask { JITCoordinator.shared.enable() }
            return
        }
        if let loaded = husk_native_loaded_apk().map({ String(cString: $0) }) {
            if loaded != app.apks.first {
                // Developer options: it can start beside the one in front (TLUnityUIView makes the room).
                if HuskMultiApp.canStart(app) { started = true; return }
                let name = TranslationLayerStore.shared.apps.first { $0.apks.first == loaded }?.label ?? "Another app"
                gate = .otherApp(name)
                return
            }
            if husk_unity_state() == Int32(HUSK_UNITY_ENDED) { ModemOSLook.revive(app) }
        }
        started = true
    }

    private var blockedEnded: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("\(app.label) closed itself and can't start again in this run.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            restartButton
            Spacer()
        }
        .padding(32)
    }

    private var blocked: some View {
        VStack(spacing: 16) {
            Spacer()
            Group {
                if let path = app.iconPath, let icon = UIImage(contentsOfFile: path) {
                    Image(uiImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(app.label).font(.title2.bold()).foregroundStyle(.white)

            switch gate {
            case .needsJIT:
                Text("Waiting for JIT. \(app.label) starts as soon as it is on.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                ProgressView().tint(.white)
            case .otherApp(let name):
                Text("\(name) is running. Android's engine cannot be unloaded, so opening \(app.label) needs a fresh start, and \(name) closes.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                restartButton
            case .ended:
                Text("\(app.label) closed itself. Starting it again needs a fresh start.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                restartButton
            case .running:
                EmptyView()
            }
            Spacer()
        }
        .padding(32)
    }

    private var restartButton: some View {
        Button("Restart into \(app.label)") { AndroidShellState.shared.restartInto(app) }
            .buttonStyle(.borderedProminent)
    }
}
