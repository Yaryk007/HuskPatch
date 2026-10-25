// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode -- Husk's interface replaced by a recreation of Android 16's.
///
/// Settings › Appearance › Android OS. Turning it on also turns on the Android 16 style and Material You in apps. What
/// it shows instead of the tabs:
///
/// - a lock screen, swiped up to unlock, at launch and whenever HuskPatch comes back to the front;
/// - a home screen as LineageOS 22 sets it up: the clock widget, the games and apps Home shows, and the dock of system apps
///   (Phone, Messaging, Contacts, Browser, Camera -- AndroidSystemApps.swift);
/// - an app drawer, swiped up from the home screen, with everything in the Library;
/// - Settings and Play Store as apps: the same screens as the tabs, opened full screen like any other app;
/// - recents, and Android's navigation along the bottom: the three buttons -- back, home, recents -- or gestures, as
///   Settings › System › Navigation mode chooses.
enum AndroidOS {
    static let key = "huskpatch.androidOS"

    /// How the system is navigated: Android's two choices, in Settings › System › Navigation mode.
    enum Navigation: String, CaseIterable, Identifiable {
        case gestures, buttons
        static let key = "huskpatch.androidOS.navigation"
        var id: String { rawValue }
        var title: String { self == .gestures ? "Gesture navigation" : "3-button navigation" }
        var summary: String {
            self == .gestures
                ? "To go Home, swipe up from the bottom of the screen. To switch apps, swipe up from the bottom, hold, then release. To go back, swipe from either the left or right edge."
                : "Go back, Home, and switch apps with buttons at the bottom of your screen."
        }
    }

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// The wallpaper: LineageOS 22's (a teal sweep across the dark), its earlier one (orbit rings in the palette's colours),
    /// or Material's soft shapes.
    enum Wallpaper: String, CaseIterable, Identifiable {
        case lineage22, lineage20, lineage, blobs, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .custom: return "Your photo"
            case .lineage22: return "LineageOS"
            case .lineage20: return "LineageOS 20"
            case .lineage: return "LineageOS orbit"
            case .blobs: return "Material shapes"
            }
        }
        var icon: String {
            switch self {
            case .custom: return "photo.on.rectangle"
            case .lineage22: return "rectangle.portrait.inset.filled"
            case .lineage20: return "photo"
            case .lineage: return "circle.circle"
            case .blobs: return "scribble.variable"
            }
        }
    }
    static let wallpaperKey = "huskpatch.androidOS.wallpaper"

    /// Turn the mode on or off. On also turns on what it is drawn with: the Android 16 style and Material You in apps.
    @MainActor static func set(_ on: Bool) {
        let d = UserDefaults.standard
        d.set(on, forKey: key)
        if on {
            d.set(true, forKey: Material3.key)
            d.set(true, forKey: Material3.appsKey)
            Material3.exportDynamicColors()
        }
        AndroidShellState.shared.locked = on && AndroidLock.showsLockScreen
    }
}

/// Something that can be open in the shell: Settings, the Play Store, one of the other system apps, or an item from the library.
enum ShellApp: Hashable, Identifiable {
    case settings
    case playStore
    case system(AndroidSystemApp)
    case item(LibraryItem)

    var id: String {
        switch self {
        case .settings: return "system:settings"
        case .playStore: return "system:playstore"
        case .system(let a): return "system:" + a.rawValue
        case .item(let i): return i.id
        }
    }

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .playStore: return "Play Store"
        case .system(let a): return a.title
        case .item(let i): return i.title
        }
    }
}

@MainActor
final class AndroidShellState: ObservableObject {
    static let shared = AndroidShellState()

    @Published var locked = AndroidOS.isOn && AndroidLock.showsLockScreen
    /// Do Not Disturb, from the lock screen's shortcut or Quick Settings.
    @Published var doNotDisturb = false
    /// Notifications posted in the shell (the Testing page's, an installed app's), newest first.
    @Published var notifications: [ShellNotification] = []

    /// A notification that has just come in, shown at the top for a few seconds (heads-up), unless Do Not Disturb is on.
    @Published var headsUp: ShellNotification?

    func post(_ n: ShellNotification) {
        withAnimation(.snappy) { notifications.insert(n, at: 0) }
        guard !doNotDisturb else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { headsUp = n }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if headsUp?.id == n.id { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { headsUp = nil } }
        }
    }

    func dismissNotifications() { withAnimation(.snappy) { notifications.removeAll() } }

    @Published var open: ShellApp?
    @Published var drawer = false
    @Published var recents = false
    @Published var recentApps: [ShellApp] = []
    /// Where Settings and the Play Store are, so Android's back goes back a page in them before it leaves them.
    @Published var settingsPath = NavigationPath()
    @Published var storePath = NavigationPath()
    /// Android's back inside the open system app (a page, a dialog), set by the app while it shows: true when it went back.
    private(set) var appBack: (() -> Bool)?
    private var appBackOwner: UUID?
    func setAppBack(_ owner: UUID, _ handler: @escaping () -> Bool) { appBackOwner = owner; appBack = handler }
    func clearAppBack(_ owner: UUID) { if appBackOwner == owner { appBack = nil; appBackOwner = nil } }
    /// Why an app could not be opened, shown as Android's dialog.
    @Published var notice: String?
    /// The notification shade, pulled down from the status bar; expanded: all of Quick Settings.
    @Published var shade = false
    @Published var shadeExpanded = false
    /// Android 13's power menu, and the screen it can turn off or restart.
    @Published var powerMenu = false
    @Published var blackout: Blackout?
    enum Blackout { case off, restarting }

    // Android 16 (Android16*.swift): pulled part-way, the shade and the drawer follow the finger (0...1)
    @Published var shadePeek: CGFloat = 0
    @Published var drawerPeek: CGFloat = 0
    /// Where the icon that opened the app is, so the app grows out of it and shrinks back into it.
    @Published var launchOrigin: CGPoint?
    /// "Phone is starting…", split screen and the app picking its other half, the notification prompt.
    @Published var starting = false
    @Published var split: SplitPair?
    @Published var splitPicking: ShellApp?
    @Published var notificationPrompt: AndroidSystemApp?
    /// Each app's picture as it was last left, for recents; and the apps started since HuskPatch opened (no splash again).
    var snapshots: [String: UIImage] = [:]
    var warmApps: Set<String> = []

    func powerOff() {
        withAnimation(.easeOut(duration: 0.25)) { blackout = .off; open = nil; drawer = false; recents = false }
    }

    func restart() {
        withAnimation(.easeOut(duration: 0.25)) { blackout = .restarting; open = nil; drawer = false; recents = false }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            AndroidLock.unlockedSinceLaunch = false
            withAnimation(.easeIn(duration: 0.4)) { blackout = nil; locked = AndroidLock.showsLockScreen }
        }
    }

    func wake() {
        withAnimation(.easeIn(duration: 0.25)) { blackout = nil; locked = AndroidLock.showsLockScreen }
    }

    func openShade(expanded: Bool = false) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(AndroidMotion.spatial) { shade = true; shadeExpanded = expanded }
    }

    func closeShade() {
        withAnimation(AndroidMotion.spatial) { shade = false; shadeExpanded = false; shadePeek = 0 }
    }

    /// The game or app on the translation layer that is open now, if one is.
    var openGame: TLApp? {
        if case .item(.game(let g))? = open { return g }
        return nil
    }

    func launch(_ app: ShellApp) {
        if case .item(.game(let g)) = app, !canRun(g) { return }
        TouchTracker.install()
        if open != app { captureSnapshot() }
        recentApps.removeAll { $0 == app }
        recentApps.insert(app, at: 0)
        withAnimation(AndroidMotion.launch) {
            drawer = false
            drawerPeek = 0
            recents = false
            split = nil
            open = app
        }
        if case .system(let a) = app { askNotificationsIfNeeded(a) }
    }

    /// Whether an app on the translation layer can be opened now: JIT is on, and no other app's engine is loaded.
    private func canRun(_ g: TLApp) -> Bool {
        if g.report?.webKind != nil { return true }
        guard Launcher.jitOn else {
            JITCoordinator.shared.enable()
            notice = "\(g.label) needs JIT. HuskPatch is turning it on: open the app again once JIT is on."
            return false
        }
        // An app that closed itself: its engine cannot be started again in this run, as an engine cannot be unloaded
        if let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), loaded == g.apks.first, husk_unity_state() == Int32(HUSK_UNITY_ENDED) {
            notice = "\(g.label) was closed. An Android app can't be started again once it has closed in the same session: "
                   + "close HuskPatch completely and open it again to run it."
            return false
        }
        if let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), loaded != g.apks.first {
            let other = Launcher.items(store: TranslationLayerStore.shared, host: AndroidHost.shared)
                .first { if case .game(let o) = $0 { return o.apks.first == loaded }; return false }?.title
                ?? (loaded as NSString).lastPathComponent
            notice = "HuskPatch can't run more than one Android app at a time. \(other) is already running, and an app "
                   + "can't be unloaded once it has started. Close HuskPatch completely and open it again to run \(g.label)."
            return false
        }
        return true
    }

    func home() {
        captureSnapshot()
        withAnimation(AndroidMotion.launch) {
            open = nil; split = nil; splitPicking = nil; drawer = false; drawerPeek = 0; recents = false; shade = false; shadeExpanded = false
        }
    }

    /// Android's back: into the app first, when it has a back of its own (an Android app's activities, a Flutter or web
    /// app's pages); it closes itself when there is nothing left to go back to (appClosedItself). Otherwise home.
    func back() {
        if shade { closeShade(); return }
        if !recents, !drawer, open == .settings, !settingsPath.isEmpty { settingsPath.removeLast(); return }
        if !recents, !drawer, open == .playStore, !storePath.isEmpty { storePath.removeLast(); return }
        if !recents, !drawer, case .system? = open, let appBack, appBack() { return }
        // split screen: back leaves the split, keeping the top app
        if !recents, !drawer, split != nil { withAnimation(AndroidMotion.spatial) { split = nil }; return }
        if recents, splitPicking != nil { withAnimation(AndroidMotion.spatial) { splitPicking = nil }; return }
        if !recents, !drawer, let g = openGame {
            if g.report?.webKind != nil, let web = WebAppRuntime.runtime(for: g) { web.back(); return }
            switch g.screenEngine {
            case .java: husk_java_back(); return
            case .flutter: husk_flutter_back(); return
            default: break
            }
        }
        if !recents, !drawer, open != nil { captureSnapshot() }
        withAnimation(AndroidMotion.spatial) {
            if recents { recents = false } else if drawer { drawer = false } else { open = nil }
        }
    }

    func toggleRecents() {
        if !recents { captureSnapshot() }
        withAnimation(AndroidMotion.spatial) { recents.toggle(); drawer = false; splitPicking = nil }
    }

    func forget(_ app: ShellApp) {
        snapshots[app.id] = nil
        withAnimation(AndroidMotion.spatial) {
            recentApps.removeAll { $0 == app }
            if open == app { open = nil; split = nil }
        }
    }

    func clearRecents() {
        snapshots.removeAll()
        withAnimation(AndroidMotion.spatial) { recentApps.removeAll(); open = nil; split = nil; recents = false }
    }
}

// MARK: - the shell

struct AndroidShellView: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var theme = AppTheme.shared
    @AppStorage(Android13.key) private var a13 = false
    @Environment(\.scenePhase) private var scenePhase

    /// Where the app being opened grows from: the icon tapped, or the middle of the screen.
    private var launchAnchor: UnitPoint {
        guard let o = shell.launchOrigin else { return .center }
        let b = UIScreen.main.bounds
        return UnitPoint(x: o.x / max(b.width, 1), y: o.y / max(b.height, 1))
    }

    /// How far the drawer is out: open, or following the finger.
    private var drawerReveal: CGFloat { shell.drawer ? 1 : shell.drawerPeek }

    var body: some View {
        ZStack {
            AndroidWallpaper()

            VStack(spacing: 0) {
                ZStack {
                    Group {
                        if a13 { Android13HomeScreen() } else { Android16HomeScreen() }
                    }
                        // Android 16's depth: the home screen sinks back and blurs as the drawer comes up or an app opens,
                        // and grows into place when the phone is unlocked
                        .opacity(shell.open != nil ? 0 : 1 - Double(drawerReveal) * (a13 ? 1 : 0.6))
                        .blur(radius: a13 ? 0 : drawerReveal * 14)
                        .scaleEffect(shell.locked ? 0.88 : shell.open != nil ? 0.92 : 1 - drawerReveal * 0.06)
                        .animation(AndroidMotion.spatial, value: shell.locked)

                    if shell.drawer || shell.drawerPeek > 0 {
                        AndroidAppDrawer()
                            .offset(y: shell.drawer ? 0 : (1 - shell.drawerPeek) * UIScreen.main.bounds.height * 0.6)
                            .opacity(shell.drawer ? 1 : Double(min(1, shell.drawerPeek * 2)))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                    }

                    if let pair = shell.split {
                        AndroidSplitView(pair: pair)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                            .zIndex(2)
                    } else if let app = shell.open {
                        AndroidAppContainer(app: app)
                            .id(app.id)
                            .transition(a13 ? .scale(scale: 0.88).combined(with: .opacity) : .androidLaunch(from: launchAnchor))
                            .zIndex(2)
                    }

                    if shell.recents {
                        Group {
                            if a13 { Android13Recents() } else { Android16Recents() }
                        }
                            .transition(.opacity)
                            .zIndex(3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if navigation == .gestures {
                    AndroidGestureBar(solid: shell.open != nil, overApp: shell.openGame != nil)
                } else {
                    AndroidNavigationButtons(solid: shell.open != nil, overApp: shell.openGame != nil)
                }
            }

            // Gesture navigation: back is a swipe in from either edge.
            if navigation == .gestures, !shell.locked {
                AndroidEdgeBack()
            }

            // Android's status bar over everything but the lock screen, which draws its own; pulled down, the shade.
            if shell.openGame == nil {
                AndroidStatusBar(material: true, transparent: shell.open == nil)
                AndroidShadePull()
            }

            if let n = shell.headsUp, !shell.shade, !shell.locked {
                VStack {
                    AndroidHeadsUp(note: n)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(4)
            }

            if shell.shade || shell.shadePeek > 0 {
                Group {
                    if a13 { Android13Shade() } else { AndroidShade() }
                }
                    .transition(a13 ? .move(edge: .top).combined(with: .opacity) : .opacity)
                    .zIndex(5)
            }

            if let app = shell.notificationPrompt, !shell.locked {
                NotificationPermissionDialog(app: app)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(7)
            }

            if let notice = shell.notice {
                AndroidAlertDialog(icon: "exclamationmark.triangle", title: "Can't open this app", message: notice) {
                    withAnimation(AndroidMotion.fade) { shell.notice = nil }
                }
                .zIndex(8)
            }

            if shell.starting && !shell.locked {
                PhoneStartingView()
                    .transition(.opacity)
                    .zIndex(9)
            }

            if shell.locked {
                AndroidLockScreen()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if shell.powerMenu {
                Android13PowerMenu().zIndex(11)
            }

            if let b = shell.blackout {
                Android13Blackout(restarting: b == .restarting)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .statusBarHidden(true)
        // iOS's own edge swipes (Notification Center from the top, home from the bottom) would take Android's shade and
        // drawer gestures: they need a second swipe while Android OS mode is showing
        .huskDefersSystemGestures(on: [.top, .bottom])
        .animation(AndroidMotion.fade, value: shell.notice)
        .animation(AndroidMotion.spatial, value: shell.split)
        .onReceive(NotificationCenter.default.publisher(for: TLUnityUIView.appClosedItself)) { _ in
            if shell.openGame != nil { shell.home() }
        }
        .onAppear { TouchTracker.install() }
        .onChange(of: scenePhase) { phase in
            // A phone locks when it is put away: so does this, when HuskPatch goes to the background.
            if phase == .background, AndroidLock.showsLockScreen { shell.locked = true }
        }
    }
}

// MARK: - wallpaper

/// The wallpaper: soft shapes in the palette's container colours, as Android 16's default wallpapers are.
struct AndroidWallpaper: View {
    @AppStorage(AndroidOS.wallpaperKey) private var style = AndroidOS.Wallpaper.lineage22

    var body: some View {
        switch style {
        case .lineage22: Lineage22Wallpaper()
        case .lineage20: Lineage20Wallpaper()
        case .custom: CustomWallpaper()
        case .lineage: LineageWallpaper()
        case .blobs: blobs
        }
    }

    private var blobs: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(uiColor: Material3.primaryContainer)
                Circle()
                    .fill(Color(uiColor: Material3.primary).opacity(0.55))
                    .frame(width: w * 1.3)
                    .offset(x: -w * 0.45, y: -h * 0.32)
                    .blur(radius: 30)
                Circle()
                    .fill(Color(uiColor: Material3.secondaryContainer))
                    .frame(width: w * 1.1)
                    .offset(x: w * 0.5, y: h * 0.38)
                    .blur(radius: 24)
                Capsule()
                    .fill(Color(uiColor: Material3.surfaceContainerHighest).opacity(0.6))
                    .frame(width: w * 0.9, height: w * 0.42)
                    .rotationEffect(.degrees(-28))
                    .offset(x: w * 0.25, y: -h * 0.05)
                    .blur(radius: 18)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

/// LineageOS's default wallpaper, after its logo: on a deep gradient of the palette's dark tones, the large ring and the
/// small orbiting circle, with a soft light behind them.
struct LineageWallpaper: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, r = max(w, h) * 0.42
            ZStack {
                LinearGradient(colors: [Color(uiColor: Material3.tone(.primary, 12)), Color(uiColor: Material3.tone(.tertiary, 22)),
                                        Color(uiColor: Material3.tone(.neutral, 8))],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(uiColor: Material3.tone(.primary, 45)).opacity(0.55), .clear],
                               center: UnitPoint(x: 0.7, y: 0.35), startRadius: 0, endRadius: r * 1.2)
                Circle()
                    .stroke(Color(uiColor: Material3.tone(.primary, 80)).opacity(0.35), lineWidth: r * 0.09)
                    .frame(width: r * 2, height: r * 2)
                    .offset(x: w * 0.18, y: -h * 0.12)
                Circle()
                    .stroke(Color(uiColor: Material3.tone(.tertiary, 70)).opacity(0.18), lineWidth: 2)
                    .frame(width: r * 2.7, height: r * 2.7)
                    .offset(x: w * 0.18, y: -h * 0.12)
                Circle()
                    .fill(Color(uiColor: Material3.tone(.tertiary, 85)).opacity(0.7))
                    .frame(width: r * 0.32, height: r * 0.32)
                    .offset(x: w * 0.18 - r * 1.05, y: -h * 0.12 + r * 0.85)
                    .blur(radius: 1)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

/// LineageOS's default wallpaper (22 and 23 keep 20's): the picture itself, a teal sweep across the dark.
struct Lineage22Wallpaper: View {
    var body: some View { Lineage20Wallpaper() }
}

// MARK: - home screen

/// The clock widget at the top of the home screen (DeskClock's digital clock): the time large and thin in the wallpaper's
/// light tone, the date under it. Tapping it opens Clock.
struct AndroidClockWidget: View {
    var large = true
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button { shell.launch(.system(.clock)) } label: {
                VStack(spacing: 2) {
                    Text(AndroidClockFace.time(context.date))
                        .font(.system(size: large ? 66 : 48, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(uiColor: AndroidClockFace.ink))
                    Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The clock's face, shared by the home screen's widget and the lock screen.
enum AndroidClockFace {
    /// The time without AM/PM, as Android's clocks show it: 5:27, or 17:27 with the 24-hour clock.
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("jmm")
        let s = f.string(from: date)
        return s.replacingOccurrences(of: f.amSymbol, with: "").replacingOccurrences(of: f.pmSymbol, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The clock's colour: the palette's light accent (#97DCEE, L* 85, on LineageOS's wallpaper).
    static var ink: UIColor { Material3.tone(.primary, 86) }
}

// MARK: - icons

/// An app on the home screen, in the drawer or in the dock: its icon in Android's circle, its name under it.
struct AndroidAppIconButton: View {
    let app: ShellApp
    var showsLabel = true
    var size: CGFloat = 58
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        Button {
            shell.launchOrigin = TouchTracker.last
            shell.launch(app)
        } label: {
            VStack(spacing: 6) {
                AndroidAppIcon(app: app, size: size)
                if showsLabel {
                    Text(app.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .lineLimit(1)
                        .frame(maxWidth: size + 18)
                }
            }
        }
        .buttonStyle(AndroidPressStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(app.title)
    }
}

/// Android's adaptive icon: the app's own picture in the icon shape chosen in Wallpaper & style (a circle unless changed);
/// LineageOS's own pictures for its apps, Google Play's for the Play Store.
struct AndroidAppIcon: View {
    let app: ShellApp
    let size: CGFloat
    @AppStorage(AndroidIconShape.key) private var shapeRaw = AndroidIconShape.circle.rawValue

    private var shape: AndroidIconShape { AndroidIconShape(rawValue: shapeRaw) ?? .circle }

    /// LineageOS's picture for one of its apps (a round picture: the rest of another shape is filled with its edge colour).
    private var asset: String? {
        switch app {
        case .settings: return "A13Icon-settings"
        case .system(let a): return Android13.iconAsset(a)
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let asset {
                ZStack {
                    if shape != .circle { IconPlate.color(asset) }
                    Image(asset).resizable().scaledToFit()
                        .scaleEffect(shape == .circle ? 1 : 1.04)
                }
            } else {
                switch app {
                case .settings:
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                        .frame(width: size, height: size)
                        .background(Color(uiColor: Material3.primaryContainer).opacity(0.95))
                case .system(let a):
                    AndroidSystemAppIcon(app: a, size: size)
                case .playStore:
                    GooglePlayLogo()
                        .frame(width: size * 0.56, height: size * 0.6)
                        .offset(x: size * 0.03)
                        .frame(width: size, height: size)
                        .background(Color.white)
                case .item(let item):
                    if item == .android {
                        Image(systemName: "apps.iphone")
                            .font(.system(size: size * 0.46, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: size, height: size)
                            .background(AndroidMark.green.gradient)
                    } else {
                        AppIcon(path: item.iconPath, size: size)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape.shape(size))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

/// Google Play's logo: the play triangle in its four colours -- green along the top, blue down the left, red along the
/// bottom, yellow at the point.
struct GooglePlayLogo: View {
    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let tl = CGPoint(x: 0, y: 0), bl = CGPoint(x: 0, y: h), tip = CGPoint(x: w, y: h / 2)
            let c = CGPoint(x: w * 0.42, y: h / 2)
            func tri(_ a: CGPoint, _ b: CGPoint, _ d: CGPoint, _ color: Color) {
                var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: d); p.closeSubpath()
                ctx.fill(p, with: .color(color))
            }
            tri(tl, bl, c, Color(red: 0.0, green: 0.62, blue: 1.0))            // blue
            tri(tl, tip, c, Color(red: 0.0, green: 0.84, blue: 0.47))          // green
            tri(bl, tip, c, Color(red: 1.0, green: 0.2, blue: 0.27))           // red
            // yellow: the point, from where the green and red meet the right of the centre
            var y = Path()
            y.move(to: CGPoint(x: w * 0.62, y: h * 0.31)); y.addLine(to: tip); y.addLine(to: CGPoint(x: w * 0.62, y: h * 0.69))
            y.addLine(to: CGPoint(x: w * 0.5, y: h / 2)); y.closeSubpath()
            ctx.fill(y, with: .color(Color(red: 1.0, green: 0.8, blue: 0.0)))
        }
        .clipShape(RoundedTriangle())
    }
}

/// The play triangle with softened corners.
private struct RoundedTriangle: Shape {
    func path(in r: CGRect) -> Path {
        let k: CGFloat = min(r.width, r.height) * 0.12
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + k))
        p.addQuadCurve(to: CGPoint(x: r.minX + k * 1.2, y: r.minY + k * 0.4), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - k, y: r.midY - k * 0.5))
        p.addQuadCurve(to: CGPoint(x: r.maxX - k, y: r.midY + k * 0.5), control: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + k * 1.2, y: r.maxY - k * 0.4))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - k), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Material 3 Expressive's press: a springy squash.
private struct AndroidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: - app drawer

private struct AndroidAppDrawer: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @State private var query = ""
    @State private var pull: CGFloat = 0
    @State private var menu: DrawerMenu?

    /// Everything in the Library, and the two system apps and Android, by name.
    private var apps: [ShellApp] {
        let items = Launcher.items(store: store, host: host).map(ShellApp.item) + [.item(.android), .settings, .playStore]
            + AndroidSystemApp.allCases.map(ShellApp.system)
        return items
            .filter { matches(query, $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @AppStorage(Android13.key) private var a13 = false

    var body: some View {
        if a13 {
            Android13Drawer(apps: apps, query: $query)
        } else {
            drawer16
        }
    }

    /// Android 16's drawer: a translucent sheet over the blurred home screen, its handle, the search field, five columns
    /// (seven in landscape), and a line when a search finds nothing. Pulled down, it follows the finger and goes.
    private var drawer16: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // the handle and the search field: pulled down, the drawer goes (the list scrolls on its own)
                    VStack(spacing: 0) {
                        Capsule().fill(Color(uiColor: Material3.onSurfaceVariant).opacity(0.5))
                            .frame(width: 36, height: 4)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        Material3SearchBar(text: $query, prompt: "Search apps")
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 10)
                        .onChanged { pull = max(0, $0.translation.height) }
                        .onEnded { v in
                            if v.translation.height > 100 || v.predictedEndTranslation.height > 360 { shell.back() }
                            withAnimation(AndroidMotion.spatial) { pull = 0 }
                        })
                    ScrollView {
                        if apps.isEmpty {
                            Text("No apps found for \u{201C}\(query)\u{201D}")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(24)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: land ? 7 : 5), spacing: 22) {
                            ForEach(apps) { app in
                                VStack(spacing: 6) {
                                    AndroidAppIcon(app: app, size: 52)
                                    Text(app.title)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                                        .lineLimit(1)
                                        .frame(maxWidth: 70)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    shell.launchOrigin = TouchTracker.last
                                    shell.launch(app)
                                }
                                .onLongPressGesture(minimumDuration: 0.4) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    let origin = geo.frame(in: .global).origin
                                    let at = TouchTracker.last.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) } ?? .zero
                                    withAnimation(AndroidMotion.bouncy) { menu = DrawerMenu(app: app, at: at) }
                                }
                                .accessibilityLabel(app.title)
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
                .background(Color(uiColor: Material3.surfaceContainer).opacity(0.86), in: UnevenRoundedRectangleCompat(top: 28))

                if let m = menu {
                    Color.black.opacity(0.001).onTapGesture { withAnimation(AndroidMotion.spatialFast) { menu = nil } }
                    let onHome = HomeLayout.shared.contains(m.app.id)
                    VStack(spacing: 0) {
                        drawerMenuRow(onHome ? "checkmark" : "plus.square.on.square", onHome ? "On Home screen" : "Add to Home screen") {
                            if !onHome { HomeLayout.shared.addToHome(m.app.id) }
                        }
                        drawerMenuRow("info.circle", "App info") {
                            if case .item(.game(let g)) = m.app { shell.settingsPath.append(AndroidSettingsRoute.appInfo(g.id)) }
                            else { shell.settingsPath.append(AndroidSettingsRoute.apps) }
                            shell.launch(.settings)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: 230)
                    .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .offset(x: min(max(m.at.x - 115, 12), geo.size.width - 242), y: max(20, m.at.y - 150))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .offset(y: pull)
        }
    }

    private func drawerMenuRow(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(AndroidMotion.spatialFast) { menu = nil }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 22)
                Text(title).font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 18)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(AndroidRippleStyle())
    }
}

/// An app held in the drawer, and where.
private struct DrawerMenu: Equatable {
    let app: ShellApp
    let at: CGPoint
}

/// A shape with only its top corners rounded (UnevenRoundedRectangle is iOS 17; HuskPatch runs on 16).
private struct UnevenRoundedRectangleCompat: Shape {
    let top: CGFloat
    func path(in r: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: r, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: top, height: top)).cgPath)
    }
}

// MARK: - an open app

/// An app, open. Settings and Play Store are the same screens as Husk's tabs, between the status bar and the buttons. A
/// game or app on the translation layer runs straight away, full screen over the status bar, with the buttons kept under
/// it: leaving it (back, home, or the app closing) returns to the launcher, and the app waits, paused, to be opened again.
/// Apps in Emulation open their page, since Android has to be started for them.
struct AndroidAppContainer: View {
    let app: ShellApp
    @State private var splash = false

    var body: some View {
        content
            .overlay {
                if splash { AndroidSplash(app: app).transition(.opacity) }
            }
            .onAppear {
                // Android 12+'s splash: shown while an app starts cold (not again until HuskPatch is opened anew)
                let shell = AndroidShellState.shared
                if case .item(.game) = app { return }
                guard !shell.warmApps.contains(app.id) else { return }
                shell.warmApps.insert(app.id)
                splash = true
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    withAnimation(.easeOut(duration: 0.25)) { splash = false }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch app {
        case .item(.game(let g)):
            // Edge to edge: under the status bar and, in landscape, past the notch and the rounded corners, as an Android game
            // in immersive mode draws. Only the navigation buttons below keep their strip.
            TLAttemptView(app: g)
                .ignoresSafeArea(.container, edges: [.top, .horizontal])
        default:
            Group {
                switch app {
                case .settings: AndroidSettingsApp()
                case .playStore: AndroidPlayStore()
                case .system(let a): a.content
                case .item(let item):
                    NavigationStack {
                        LibraryRouteView(route: item.route)
                            .libraryDestinations()
                    }
                }
            }
            .background(Color(uiColor: Material3.surface).ignoresSafeArea(.container, edges: [.top, .horizontal]))
        }
    }
}

// MARK: - recents

// MARK: - navigation buttons

/// Android's three buttons: back, home, recents.
private struct AndroidNavigationButtons: View {
    let solid: Bool
    /// Over an app running full screen: white on black, as Android draws them there.
    var overApp = false
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        HStack {
            // Android 13 fills all three (LineageOS 20's white triangle, circle and square); later versions outline recents
            button("Back") { shell.back() } label: {
                Image(systemName: Android13.isOn ? "arrowtriangle.left.fill" : "arrowtriangle.backward.fill")
                    .font(.system(size: Android13.isOn ? 20 : 18, weight: .regular))
            }
            button("Home") { shell.home() } label: {
                Circle().frame(width: Android13.isOn ? 20 : 18, height: Android13.isOn ? 20 : 18)
            }
            button("Recents") { shell.toggleRecents() } label: {
                if Android13.isOn {
                    RoundedRectangle(cornerRadius: 2.5).frame(width: 17, height: 17)
                } else {
                    RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 2.4).frame(width: 16, height: 16)
                }
            }
        }
        .foregroundStyle(overApp ? Color.white : solid ? Color(uiColor: Material3.onSurface) : Color(uiColor: Material3.onPrimaryContainer))
        .frame(height: 48)
        .padding(.horizontal, 36)
        .background((overApp ? Color.black : solid ? Color(uiColor: Material3.surfaceContainer) : Color.clear).ignoresSafeArea(edges: .bottom))
    }

    private func button<L: View>(_ name: String, _ action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            label().frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

// MARK: - gesture navigation

/// Gesture navigation's handle: a thin bar along the bottom. Swipe up from it to go home; swipe up and hold to see recent
/// apps. On the home screen, a swipe up opens the app drawer.
private struct AndroidGestureBar: View {
    let solid: Bool
    var overApp = false
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var lift: CGFloat = 0

    var body: some View {
        ZStack {
            Capsule()
                .fill(overApp ? Color.white.opacity(0.85) : solid ? Color(uiColor: Material3.onSurface) : Color(uiColor: Material3.onPrimaryContainer))
                .frame(width: 108, height: 4)
                .offset(y: max(-14, lift / 6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background((overApp ? Color.black : solid ? Color(uiColor: Material3.surfaceContainer) : Color.clear).ignoresSafeArea(edges: .bottom))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { lift = min(0, $0.translation.height) }
            .onEnded { v in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { lift = 0 }
                let dy = v.translation.height
                guard dy < -30 else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // held: the finger slowed down before letting go, far enough up
                let held = abs(v.predictedEndTranslation.height - dy) < 50 && dy < -110
                if held { shell.toggleRecents() }
                else if shell.open == nil && !shell.drawer && !shell.recents {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { shell.drawer = true }
                } else { shell.home() }
            })
        .accessibilityElement()
        .accessibilityLabel("Home")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { shell.home() }
    }
}

/// Gesture navigation's back: a swipe in from the left or right edge, with Android's arrow growing beside the finger.
private struct AndroidEdgeBack: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var pull: CGFloat = 0
    @State private var y: CGFloat = 0
    @State private var fromRight = false

    private let edge: CGFloat = 18
    private let trigger: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                strip(right: false, geo: geo)
                strip(right: true, geo: geo).offset(x: geo.size.width - edge)
                if pull > 4 {
                    let p = min(pull, 110)
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 32 + p * 0.2, height: 64)
                        .overlay(Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(pull > trigger ? 1.15 : 0.9))
                        .offset(x: fromRight ? geo.size.width - p * 0.5 - 16 : p * 0.5 - 32, y: y - 32)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func strip(right: Bool, geo: GeometryProxy) -> some View {
        Color.clear
            .frame(width: edge, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { v in
                    fromRight = right
                    y = v.startLocation.y
                    pull = max(0, right ? -v.translation.width : v.translation.width)
                }
                .onEnded { _ in
                    if pull > trigger {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        shell.back()
                    }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { pull = 0 }
                })
    }
}

// MARK: - shade pull

/// The status bar's strip, pulled down: the notification shade (pulled far: all of Quick Settings).
private struct AndroidShadePull: View {
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        GeometryReader { geo in
        VStack {
            // over the home screen a generous strip; over an app, just the status bar, so the app's own top bar works
            Color.clear
                .frame(height: shell.open == nil ? geo.safeAreaInsets.top + 44 : max(geo.safeAreaInsets.top, 24) + 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { v in if !Android13.isOn { shell.shadePeek = min(1, max(0, v.translation.height / 320)) } }
                    .onEnded { v in
                        let dy = v.translation.height
                        if dy > 28 || v.predictedEndTranslation.height > 160 {
                            shell.openShade(expanded: dy > 330)
                            shell.shadePeek = 0
                        } else {
                            withAnimation(AndroidMotion.spatial) { shell.shadePeek = 0 }
                        }
                    })
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(!shell.shade && !shell.locked)
    }
}

/// A notification in the shell: an icon, a title and its text.
struct ShellNotification: Identifiable, Equatable {
    var id = UUID()
    var icon: String
    var app: String
    var title: String
    var text: String
    var date = Date()
}
