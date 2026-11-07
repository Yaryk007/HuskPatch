import SwiftUI
import UIKit

/// An app the host (HuskPatch) puts into ModemOS: it sits in the host's folder in the app drawer and opens as a
/// ModemOS window like any other app.
public struct ModemOSHostApp: Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let color: Color
    /// The app's own icon, when it has one.
    public let icon: UIImage?
    /// Draws edge to edge, under the status bar and the navigation (a game or an Android app).
    public let fullScreen: Bool
    /// Never stopped to free memory: it could not start again in this run.
    public let pinned: Bool
    public let content: () -> AnyView

    public init<V: View>(id: String, name: String, symbol: String, color: Color, icon: UIImage? = nil,
                         fullScreen: Bool = false, pinned: Bool = false,
                         @ViewBuilder content: @escaping () -> V) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.icon = icon
        self.fullScreen = fullScreen
        self.pinned = pinned
        self.content = { AnyView(content()) }
    }
}

/// What the host tells ModemOS: its apps, the folder they live in, and how to leave.
public final class ModemOSHost: ObservableObject {
    public static let shared = ModemOSHost()

    /// Up to nine apps (a folder holds three rows of three).
    @Published public var apps: [ModemOSHostApp] = []
    @Published public var folderName = "Apps"
    /// Installed apps: each gets its own icon in the app drawer (and the first ones on the home screen), however many there are.
    @Published public var installed: [ModemOSHostApp] = []
    /// Set to an app's id to open it, as tapping its icon would.
    @Published public var openRequest: String?
    /// The host app in front changed (its id; nil for the home screen or one of ModemOS's own apps).
    public var frontChanged: ((String?) -> Void)?
    /// The host app in front now.
    public var frontID: String?
    /// Shown in the Lab and the Settings app when set: goes back to the host's own interface.
    public var exitTitle = "Exit"
    public var exit: (() -> Void)?
    /// Starts the whole app again, for what only a new launch can change (real Liquid Glass).
    public var restart: (() -> Void)?

    private init() {}

    var hasFolder: Bool { !apps.isEmpty }

    func app(_ id: String?) -> ModemOSHostApp? {
        (apps + installed).first { $0.id == id }
    }
}

/// ModemOS as a view: boot, setup and the home screen.
public struct ModemOSView: View {
    public init() {
        // The battery percentage in the status bar.
        UIDevice.current.isBatteryMonitoringEnabled = true
        // Read before the look can be changed: this says what the system is drawing in this run.
        _ = LiquidGlass.live
    }

    public var body: some View {
        RootView()
    }

    /// Keeps the system's Liquid Glass switch in step with ModemOS: on only while ModemOS is the interface and its look is
    /// Liquid Glass, so HuskPatch's own screens never change. Applies from the next launch.
    public static func syncSystemGlass(modemOSOn: Bool) {
        LiquidGlass.request(modemOSOn && OSSettings.shared.design == .liquidGlass)
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
