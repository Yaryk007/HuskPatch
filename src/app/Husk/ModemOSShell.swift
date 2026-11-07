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

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

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
        host.folderName = "HuskPatch"
        host.exitTitle = "Exit to HuskPatch"
        host.exit = {
            withAnimation(.easeInOut(duration: 0.35)) { ModemOSLook.set(false) }
        }
        host.restart = { restart() }
        host.apps = [
            ModemOSHostApp(id: "home", name: "Games", symbol: "gamecontroller.fill",
                           color: Color(red: 0.12, green: 0.62, blue: 0.29)) { HomeView() },
            ModemOSHostApp(id: "library", name: "Library", symbol: "square.grid.2x2.fill",
                           color: Color(red: 0.25, green: 0.45, blue: 0.95)) { LibraryScreen() },
            ModemOSHostApp(id: "store", name: "Store", symbol: "bag.fill",
                           color: Color(red: 0.95, green: 0.55, blue: 0.15)) { StoreView() },
            ModemOSHostApp(id: "settings", name: "HuskPatch", symbol: "gearshape.2.fill",
                           color: Color(red: 0.45, green: 0.45, blue: 0.52)) { SettingsTab() },
        ]
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

    var body: some View {
        Group {
            if started {
                TLAttemptView(app: app)
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
                let name = TranslationLayerStore.shared.apps.first { $0.apks.first == loaded }?.label ?? "Another app"
                gate = .otherApp(name)
                return
            }
            if husk_unity_state() == Int32(HUSK_UNITY_ENDED) {
                gate = .ended
                return
            }
        }
        started = true
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
