// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import ModemOS

/// HuskPatch: the user's own fake OS (ModemOS, src/app/ModemOS) as the whole interface. Its apps stay its own;
/// HuskPatch's Home, Library, Store and Settings sit in a "HuskPatch" folder in its app drawer and open as ModemOS
/// windows. Games still open in HuskPatch's own app windows, over everything.
enum ModemOSLook {
    static let key = "huskpatch.modemos"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Turning ModemOS on turns Android OS mode off: only one interface can stand in for HuskPatch's.
    @MainActor static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        if on, AndroidOS.isOn { AndroidOS.set(false) }
    }

    /// Hands ModemOS HuskPatch's screens and the way back.
    @MainActor static func registerHost() {
        let host = ModemOSHost.shared
        host.folderName = "HuskPatch"
        host.exitTitle = "Exit to HuskPatch"
        host.exit = {
            withAnimation(.easeInOut(duration: 0.35)) { ModemOSLook.set(false) }
        }
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
}

/// What ContentView shows when ModemOS is on.
struct ModemOSShellView: View {
    init() { ModemOSLook.registerHost() }

    var body: some View {
        ModemOSView()
            .ignoresSafeArea()
    }
}
