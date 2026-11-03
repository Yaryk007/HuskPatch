import SwiftUI
import UIKit

/// An app the host (HuskPatch) puts into ModemOS: it sits in the host's folder in the app drawer and opens as a
/// ModemOS window like any other app.
public struct ModemOSHostApp: Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let color: Color
    public let content: () -> AnyView

    public init<V: View>(id: String, name: String, symbol: String, color: Color,
                         @ViewBuilder content: @escaping () -> V) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.content = { AnyView(content()) }
    }
}

/// What the host tells ModemOS: its apps, the folder they live in, and how to leave.
public final class ModemOSHost: ObservableObject {
    public static let shared = ModemOSHost()

    /// Up to nine apps (a folder holds three rows of three).
    @Published public var apps: [ModemOSHostApp] = []
    @Published public var folderName = "Apps"
    /// Shown in the Lab and the Settings app when set: goes back to the host's own interface.
    public var exitTitle = "Exit"
    public var exit: (() -> Void)?

    private init() {}

    var hasFolder: Bool { !apps.isEmpty }
}

/// ModemOS as a view: boot, setup and the home screen.
public struct ModemOSView: View {
    public init() {
        // The battery percentage in the status bar.
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    public var body: some View {
        RootView()
    }
}

/// "Exit to …" as a row the Lab and the Settings app share.
struct HostExitButton: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        if let exit = ModemOSHost.shared.exit {
            Button {
                Haptics.tap(.medium)
                exit()
            } label: {
                Label(os.t(ModemOSHost.shared.exitTitle), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
}

extension OSSettings {
    /// ModemOS keeps its settings apart from the host's.
    static let store = UserDefaults(suiteName: "modemos") ?? .standard
}
