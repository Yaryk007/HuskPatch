import SwiftUI
import Combine
import UIKit

private struct AppActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// true once the app window is fully open and in front (apps can start expensive work then).
    var appActive: Bool {
        get { self[AppActiveKey.self] }
        set { self[AppActiveKey.self] = newValue }
    }
}

/// The inside of an app window. The home screen ignores the real safe area, so the status bar and the
/// gesture bar / navigation buttons are passed in as `insets` and turned into the app's safe area here.
struct AppContentView: View {
    let item: HomeItem
    let insets: EdgeInsets
    let active: Bool

    @ObservedObject private var keyboard = KeyboardObserver.shared

    var body: some View {
        content
            .environment(\.appActive, active)
            .modemSafeArea(top: insets.top, bottom: max(insets.bottom, keyboard.height))
    }

    @ViewBuilder
    private var content: some View {
        switch item.app ?? .settings {
        case .dummy: DummyApp(item: item)
        case .host: HostAppView(id: item.hostID)
        case .phone: PhoneApp()
        case .messages: MessagesApp()
        case .browser: BrowserApp()
        case .camera: CameraApp()
        case .photos: PhotosApp()
        case .settings: SettingsApp()
        case .clock: ClockApp()
        case .maps: MapsApp()
        case .weather: WeatherApp()
        case .music: MusicApp()
        case .calendar: CalendarApp()
        case .contacts: ContactsApp()
        case .health: HealthApp()
        case .notes: NotesApp()
        case .files: FilesApp()
        case .calculator: CalculatorApp()
        case .compass: CompassApp()
        case .flashlight: FlashlightApp()
        case .recorder: RecorderApp()
        }
    }
}

/// The on-screen keyboard's height (the home screen ignores the keyboard, so apps make room themselves).
final class KeyboardObserver: ObservableObject {
    static let shared = KeyboardObserver()

    @Published private(set) var height: CGFloat = 0
    private var bag: Set<AnyCancellable> = []

    private init() {
        let center = NotificationCenter.default
        center.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: center.publisher(for: UIResponder.keyboardWillHideNotification))
            .sink { [weak self] note in
                guard let self = self else { return }
                if note.name == UIResponder.keyboardWillHideNotification {
                    self.height = 0
                    return
                }
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                self.height = max(0, UIScreen.main.bounds.height - frame.minY)
            }
            .store(in: &bag)
    }
}

/// The big bold title at the top of an app, One UI style.
struct AppTitle: View {
    let title: String
    var subtitle: String?

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(os.t(title))
                .font(.system(size: 34, weight: .bold))
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// Shown when an app needs a permission: asks for it, or sends you to the iOS settings if it was refused.
struct PermissionView: View {
    let symbol: String
    let title: String
    let message: String
    let denied: Bool
    let request: () -> Void

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(os.t(title))
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(os.t(message))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    request()
                }
            } label: {
                Text(os.t(denied ? "Open iOS Settings" : "Allow access"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A rounded One UI style card.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
    }
}

func openURL(_ string: String) {
    guard let url = URL(string: string) else { return }
    OSLogger.shared.log("System", "Open \(string)")
    UIApplication.shared.open(url)
}

extension View {
    /// The app's safe area: real safe-area padding on iOS 17, empty insets (which scroll views respect too) on iOS 16.
    @ViewBuilder
    func modemSafeArea(top: CGFloat, bottom: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            safeAreaPadding(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
        } else {
            safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: top) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: bottom) }
        }
    }
}

/// A host app's screen, looked up when its window opens.
struct HostAppView: View {
    let id: String?

    var body: some View {
        if let app = ModemOSHost.shared.apps.first(where: { $0.id == id }) {
            app.content()
        } else {
            DummyApp(item: HomeItem(0, .host))
        }
    }
}
