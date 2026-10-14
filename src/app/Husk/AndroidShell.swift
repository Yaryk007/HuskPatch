// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode -- Husk's interface replaced by a recreation of Android 16's.
///
/// Settings › Appearance › Android OS. Turning it on also turns on the Android 16 style and Material You in apps. What
/// it shows instead of the tabs:
///
/// - a lock screen, swiped up to unlock, at launch and whenever HuskPatch comes back to the front;
/// - a home screen with the games and apps Home shows, a dock (Play Store, Settings, Android) and a search pill;
/// - an app drawer, swiped up from the home screen, with everything in the Library;
/// - Settings and Play Store as apps: the same screens as the tabs, opened full screen like any other app;
/// - recents, and Android's three buttons -- back, home, recents -- along the bottom.
enum AndroidOS {
    static let key = "huskpatch.androidOS"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Turn the mode on or off. On also turns on what it is drawn with: the Android 16 style and Material You in apps.
    @MainActor static func set(_ on: Bool) {
        let d = UserDefaults.standard
        d.set(on, forKey: key)
        if on {
            d.set(true, forKey: Material3.key)
            d.set(true, forKey: Material3.appsKey)
            Material3.exportDynamicColors()
        }
        AndroidShellState.shared.locked = on
    }
}

/// Something that can be open in the shell: one of the two system apps, or an item from the library.
enum ShellApp: Hashable, Identifiable {
    case settings
    case playStore
    case item(LibraryItem)

    var id: String {
        switch self {
        case .settings: return "system:settings"
        case .playStore: return "system:playstore"
        case .item(let i): return i.id
        }
    }

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .playStore: return "Play Store"
        case .item(let i): return i.title
        }
    }
}

@MainActor
final class AndroidShellState: ObservableObject {
    static let shared = AndroidShellState()

    @Published var locked = AndroidOS.isOn
    @Published var open: ShellApp?
    @Published var drawer = false
    @Published var recents = false
    @Published private(set) var recentApps: [ShellApp] = []
    /// Why an app could not be opened, shown as an alert.
    @Published var notice: String?

    /// The game or app on the translation layer that is open now, if one is.
    var openGame: TLApp? {
        if case .item(.game(let g))? = open { return g }
        return nil
    }

    func launch(_ app: ShellApp) {
        if case .item(.game(let g)) = app, !canRun(g) { return }
        recentApps.removeAll { $0 == app }
        recentApps.insert(app, at: 0)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            drawer = false
            recents = false
            open = app
        }
    }

    /// Whether an app on the translation layer can be opened now: JIT is on, and no other app's engine is loaded.
    private func canRun(_ g: TLApp) -> Bool {
        if g.report?.webKind != nil { return true }
        guard Launcher.jitOn else {
            JITCoordinator.shared.enable()
            notice = "\(g.label) needs JIT. HuskPatch is turning it on: open the app again once JIT is on."
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
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { open = nil; drawer = false; recents = false }
    }

    /// Android's back: into the app first, when it has a back of its own (an Android app's activities, a Flutter or web
    /// app's pages); it closes itself when there is nothing left to go back to (appClosedItself). Otherwise home.
    func back() {
        if !recents, !drawer, let g = openGame {
            if g.report?.webKind != nil, let web = WebAppRuntime.runtime(for: g) { web.back(); return }
            switch g.screenEngine {
            case .java: husk_java_back(); return
            case .flutter: husk_flutter_back(); return
            default: break
            }
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            if recents { recents = false } else if drawer { drawer = false } else { open = nil }
        }
    }

    func toggleRecents() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { recents.toggle(); drawer = false }
    }

    func forget(_ app: ShellApp) {
        withAnimation(.snappy) {
            recentApps.removeAll { $0 == app }
            if open == app { open = nil }
        }
    }

    func clearRecents() {
        withAnimation(.snappy) { recentApps.removeAll(); open = nil; recents = false }
    }
}

// MARK: - the shell

struct AndroidShellView: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AndroidWallpaper()

            VStack(spacing: 0) {
                ZStack {
                    AndroidHomeScreen()
                        .opacity(shell.drawer || shell.open != nil ? 0 : 1)
                        .scaleEffect(shell.open != nil ? 0.94 : 1)

                    if shell.drawer {
                        AndroidAppDrawer()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                    }

                    if let app = shell.open {
                        AndroidAppContainer(app: app)
                            .id(app.id)
                            .transition(.scale(scale: 0.88).combined(with: .opacity))
                            .zIndex(2)
                    }

                    if shell.recents {
                        AndroidRecents()
                            .transition(.opacity)
                            .zIndex(3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                AndroidNavigationButtons(solid: shell.open != nil, overApp: shell.openGame != nil)
            }

            // Android's status bar over everything but the lock screen, which draws its own.
            if shell.openGame == nil {
                AndroidStatusBar(material: true, transparent: shell.open == nil)
            }

            if shell.locked {
                AndroidLockScreen()
                    .transition(.move(edge: .top))
                    .zIndex(10)
            }
        }
        .statusBarHidden(true)
        .alert("Can't open this app", isPresented: Binding(get: { shell.notice != nil }, set: { if !$0 { shell.notice = nil } })) {
            Button("OK", role: .cancel) { shell.notice = nil }
        } message: {
            Text(shell.notice ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: TLUnityUIView.appClosedItself)) { _ in
            if shell.openGame != nil { shell.home() }
        }
        .onChange(of: scenePhase) { phase in
            // A phone locks when it is put away: so does this, when HuskPatch goes to the background.
            if phase == .background { shell.locked = true }
        }
    }
}

// MARK: - wallpaper

/// The wallpaper: soft shapes in the palette's container colours, as Android 16's default wallpapers are.
struct AndroidWallpaper: View {
    var body: some View {
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

// MARK: - home screen

private struct AndroidHomeScreen: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var jit = JITCoordinator.shared

    /// What Home shows: the most recent first, then up to eight more.
    private var homeItems: [LibraryItem] {
        let all = Launcher.byRecent(Launcher.items(store: store, host: host))
        let lead = all.first { $0.lastUsed != nil } ?? all.first
        guard let lead else { return [] }
        return [lead] + all.filter { $0 != lead }.prefix(8)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            AtAGlance()
                .padding(.horizontal, 24)
                .padding(.top, 28)

            if !Launcher.jitOn {
                Button { jit.enable() } label: {
                    Label(jit.busy ? (jit.status ?? "Turning JIT on…") : "JIT is off — tap to turn on", systemImage: "bolt.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }

            Spacer(minLength: 12)

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(homeItems) { item in
                    AndroidAppIconButton(app: .item(item))
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 12)

            // The dock, then the search pill, as on a Pixel.
            HStack {
                AndroidAppIconButton(app: .playStore, showsLabel: false)
                AndroidAppIconButton(app: .item(.android), showsLabel: false)
                AndroidAppIconButton(app: .settings, showsLabel: false)
            }
            .padding(.horizontal, 28)

            Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { shell.drawer = true } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold))
                    Text("Search apps").font(.system(size: 16, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .padding(.horizontal, 20)
                .frame(height: 52)
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
        }
        .contentShape(Rectangle())
        // Swiping up anywhere on the home screen opens the drawer, as on Android.
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.height < -80 { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { shell.drawer = true } }
        })
    }
}

/// The date at the top of the home screen.
private struct AtAGlance: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 26, weight: .regular, design: .rounded))
                Text("HuskPatch")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .opacity(0.8)
            }
            .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - icons

/// An app on the home screen, in the drawer or in the dock: its icon in Android's circle, its name under it.
struct AndroidAppIconButton: View {
    let app: ShellApp
    var showsLabel = true
    var size: CGFloat = 58
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        Button { shell.launch(app) } label: {
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

/// Android's adaptive icon: the app's own picture in a circle; Settings and Play Store drawn in Material's colours.
struct AndroidAppIcon: View {
    let app: ShellApp
    let size: CGFloat

    var body: some View {
        Group {
            switch app {
            case .settings:
                Image(systemName: "gearshape.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                    .frame(width: size, height: size)
                    .background(Color(uiColor: Material3.primaryContainer).opacity(0.95))
            case .playStore:
                PlayTriangle()
                    .fill(AngularGradient(colors: [.green, .blue, .red, .yellow, .green], center: .center))
                    .frame(width: size * 0.48, height: size * 0.52)
                    .offset(x: size * 0.04)
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
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

/// The Play Store's triangle.
private struct PlayTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
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

    /// Everything in the Library, and the two system apps and Android, by name.
    private var apps: [ShellApp] {
        let items = Launcher.items(store: store, host: host).map(ShellApp.item) + [.item(.android), .settings, .playStore]
        return items
            .filter { matches(query, $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(uiColor: Material3.onSurfaceVariant).opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
            Material3SearchBar(text: $query, prompt: "Search apps")
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 20) {
                    ForEach(apps) { AndroidAppIconButton(app: $0, size: 54) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color(uiColor: Material3.surfaceContainer).opacity(0.97),
                    in: UnevenRoundedRectangleCompat(top: 28))
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if v.translation.height > 120 { shell.back() }
        })
    }
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
private struct AndroidAppContainer: View {
    let app: ShellApp

    var body: some View {
        switch app {
        case .item(.game(let g)):
            // Edge to edge: under the status bar and, in landscape, past the notch and the rounded corners, as an Android game
            // in immersive mode draws. Only the navigation buttons below keep their strip.
            TLAttemptView(app: g)
                .ignoresSafeArea(.container, edges: [.top, .horizontal])
        default:
            Group {
                switch app {
                case .settings: SettingsTab()
                case .playStore: StoreView()
                case .item(let item):
                    NavigationStack {
                        LibraryRouteView(route: item.route)
                            .libraryDestinations()
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea(.container, edges: [.top, .horizontal]))
        }
    }
}

// MARK: - recents

private struct AndroidRecents: View {
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { shell.back() }
            if shell.recentApps.isEmpty {
                Text("No recent items")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                VStack(spacing: 18) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(shell.recentApps) { app in RecentCard(app: app) }
                        }
                        .padding(.horizontal, 40)
                    }
                    Button("Clear all") { shell.clearRecents() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                }
            }
        }
    }
}

/// A card in recents: tap to open, swipe up to close.
private struct RecentCard: View {
    let app: ShellApp
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                AndroidAppIcon(app: app, size: 26)
                Text(app.title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: Material3.surfaceContainer))
                .overlay(AndroidAppIcon(app: app, size: 72))
                .frame(width: 210, height: 380)
        }
        .offset(y: drag)
        .opacity(1 - Double(min(abs(drag) / 300, 0.8)))
        .onTapGesture { shell.launch(app) }
        .gesture(DragGesture().onChanged { drag = min(0, $0.translation.height) }.onEnded { v in
            if v.translation.height < -140 { shell.forget(app) }
            withAnimation(.spring) { drag = 0 }
        })
    }
}

// MARK: - navigation buttons

/// Android's three buttons: back, home, recents.
private struct AndroidNavigationButtons: View {
    let solid: Bool
    /// Over an app running full screen: white on black, as Android draws them there.
    var overApp = false
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        HStack {
            button("Back") { shell.back() } label: {
                Image(systemName: "arrowtriangle.backward.fill").font(.system(size: 18, weight: .regular))
            }
            button("Home") { shell.home() } label: {
                Circle().frame(width: 18, height: 18)
            }
            button("Recents") { shell.toggleRecents() } label: {
                RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 2.4).frame(width: 16, height: 16)
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

// MARK: - lock screen

/// The lock screen: a big clock in Material 3 Expressive's style, the date, and a swipe up to unlock.
private struct AndroidLockScreen: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack {
            AndroidWallpaper()
            Color.black.opacity(0.25).ignoresSafeArea()
            AndroidStatusBar(material: true, transparent: true)
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 6) {
                        let parts = clock(context.date)
                        Text(parts.0)
                            .font(.system(size: 120, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text(parts.1)
                            .font(.system(size: 120, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .padding(.top, -50)
                        Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .padding(.top, 4)
                    }
                    .foregroundStyle(.white)
                }
                .padding(.top, 70)
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 18, weight: .semibold))
                    Text("Swipe up to unlock").font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.bottom, 36)
            }
        }
        .offset(y: min(0, drag))
        .opacity(1 - Double(min(abs(drag) / 600, 0.6)))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 10)
            .onChanged { drag = $0.translation.height }
            .onEnded { v in
                if v.translation.height < -120 || v.predictedEndTranslation.height < -300 {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { shell.locked = false; drag = 0 }
                } else {
                    withAnimation(.spring) { drag = 0 }
                }
            })
        .statusBarHidden(true)
    }

    /// Hours over minutes, as Android 16's large lock screen clock stacks them.
    private func clock(_ date: Date) -> (String, String) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let twelve = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("H") ?? false)
        var h = c.hour ?? 0
        if twelve { h = h % 12 == 0 ? 12 : h % 12 }
        return (String(format: "%02d", h), String(format: "%02d", c.minute ?? 0))
    }
}
