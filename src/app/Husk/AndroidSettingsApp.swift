// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// HuskPatch: the Settings app of Android OS mode, laid out as Android 16's: a large "Settings" title, a search pill, the
/// account card, then groups of rows with tinted icons -- Network & internet, Connected devices, Apps, Display & touch,
/// Wallpaper & style, System, About phone -- each opening a page of its own. HuskPatch's own settings (JIT, performance,
/// the library, the emulator) sit among them, as an Android phone's vendor settings do.
struct AndroidSettingsApp: View {
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        SwiftUI.NavigationStack(path: $shell.settingsPath) {
            AndroidSettingsHome()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AndroidSettingsRoute.self) { route in
                    route.destination
                }
        }
    }
}

/// Where a row in Settings goes.
enum AndroidSettingsRoute: Hashable {
    case network, connected, apps, appInfo(String), specialAccess(AndroidSpecialAccess), display, wallpaper, system, navigation,
         jit, performance, library, discover, emulator, input, savedMachine, about, legal,
         security, screenLock, fingerprint, testing, developer

    /// The pages HuskPatch already had are pushed with their own (Material-styled) navigation bar; the Android pages draw theirs.
    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .network: NetworkSettings().huskForm()
        case .connected: AndroidConnectedDevicesPage().toolbar(.hidden, for: .navigationBar)
        case .apps: AndroidAppsPage().toolbar(.hidden, for: .navigationBar)
        case .appInfo(let id):
            let app = TranslationLayerStore.shared.apps.first { $0.id == id }
            AndroidAppInfoPage(appID: id, label: app?.label ?? id, icon: app?.iconPath, onBack: AndroidSettingsRoute.pop)
                .toolbar(.hidden, for: .navigationBar)
        case .specialAccess(let s): AndroidSpecialAccessAppsPage(access: s).toolbar(.hidden, for: .navigationBar)
        case .display: AndroidDisplayPage().toolbar(.hidden, for: .navigationBar)
        case .wallpaper: AndroidWallpaperPage().toolbar(.hidden, for: .navigationBar)
        case .system: AndroidOSSystemPage().toolbar(.hidden, for: .navigationBar)
        case .navigation: AndroidNavigationModePage().toolbar(.hidden, for: .navigationBar)
        case .jit: JITSettings()
        case .performance: PerformanceSettings()
        case .library: LibrarySettings()
        case .discover: DiscoverView()
        case .emulator: AndroidEmulatorPage().toolbar(.hidden, for: .navigationBar)
        case .input: InputSettings()
        case .savedMachine: SavedMachineSettings()
        case .about: AndroidAboutPhonePage().toolbar(.hidden, for: .navigationBar)
        case .legal: AboutSettings()
        case .security: AndroidSecurityPage().toolbar(.hidden, for: .navigationBar)
        case .screenLock: AndroidScreenLockPage().toolbar(.hidden, for: .navigationBar)
        case .fingerprint: AndroidFingerprintPage().toolbar(.hidden, for: .navigationBar)
        case .testing: AndroidTestingPage(onBack: AndroidSettingsRoute.pop).toolbar(.hidden, for: .navigationBar)
        case .developer: AndroidDeveloperOptionsPage().toolbar(.hidden, for: .navigationBar)
        }
    }

    @MainActor static func pop() {
        let shell = AndroidShellState.shared
        if !shell.settingsPath.isEmpty { shell.settingsPath.removeLast() }
    }
}

/// A row that opens a page.
private struct SettingsLink: View {
    let route: AndroidSettingsRoute
    let icon: String
    let tint: UIColor
    let title: String
    var summary: String?

    var body: some View {
        NavigationLink(value: route) {
            AndroidSettingsRow(icon: icon, tint: tint, title: title, summary: summary)
        }
        .buttonStyle(AndroidRippleStyle())
    }
}

/// One entry of the home page, which search looks through too.
private struct SettingsEntry: Identifiable {
    let route: AndroidSettingsRoute
    let icon: String
    let tint: UIColor
    let title: String
    let summary: String
    var keywords = ""
    var id: String { title }
}

// MARK: - home

private struct AndroidSettingsHome: View {
    @State private var query = ""

    private static let groups: [[SettingsEntry]] = [
        [SettingsEntry(route: .network, icon: "wifi", tint: .systemBlue, title: "Network & internet", summary: "Internet, saved sessions", keywords: "wifi network proxy"),
         SettingsEntry(route: .connected, icon: "gamecontroller.fill", tint: .systemIndigo, title: "Connected devices", summary: "Controllers, Bluetooth", keywords: "bluetooth gamepad controller")],
        [SettingsEntry(route: .apps, icon: "square.grid.2x2.fill", tint: .systemTeal, title: "Apps", summary: "Permissions, default apps, special app access", keywords: "permission camera location overlay"),
         SettingsEntry(route: .discover, icon: "sparkle.magnifyingglass", tint: .systemMint, title: "Discover", summary: "Find apps in F-Droid and other repositories", keywords: "fdroid store")],
        [SettingsEntry(route: .display, icon: "sun.max.fill", tint: .systemOrange, title: "Display & touch", summary: "Dark theme, Android 16 style", keywords: "dark light theme"),
         SettingsEntry(route: .wallpaper, icon: "paintpalette.fill", tint: .systemPink, title: "Wallpaper & style", summary: "Colours, Material You", keywords: "accent colour color material you")],
        [SettingsEntry(route: .jit, icon: "bolt.fill", tint: .systemYellow, title: "JIT & Sideload", summary: "StikJIT is built in", keywords: "stikdebug jit sideload"),
         SettingsEntry(route: .performance, icon: "speedometer", tint: .systemRed, title: "Performance", summary: "Renderer, sound", keywords: "gpu renderer sound"),
         SettingsEntry(route: .library, icon: "books.vertical.fill", tint: .systemBlue, title: "Library", summary: "Your apps and their icons", keywords: "library icons"),
         SettingsEntry(route: .emulator, icon: "cpu", tint: .systemGreen, title: "Emulation", summary: "Input, saved machine", keywords: "qemu emulator snapshot input")],
        [SettingsEntry(route: .security, icon: "lock.shield.fill", tint: .systemTeal, title: "Security & privacy", summary: "Screen lock, Fingerprint Unlock", keywords: "lock pin pattern password fingerprint"),
         SettingsEntry(route: .testing, icon: "testtube.2", tint: .systemPurple, title: "Testing", summary: "Material 3 Expressive, translation layer, install APKs", keywords: "test debug apk install m3e expressive")],
        [SettingsEntry(route: .system, icon: "gearshape.fill", tint: .systemGray, title: "System", summary: "Navigation mode, multitasking, Android OS mode", keywords: "gestures buttons navigation windows"),
         SettingsEntry(route: .about, icon: "iphone", tint: .systemBlue, title: "About phone", summary: "HuskPatch \(Bundle.main.version)", keywords: "version build developer")],
    ]

    private var results: [SettingsEntry] {
        let q = query.lowercased()
        return Self.groups.flatMap { $0 }.filter {
            $0.title.lowercased().contains(q) || $0.summary.lowercased().contains(q) || $0.keywords.contains(q)
        } + (q.contains("nav") || q.contains("gest") || q.contains("button")
             ? [SettingsEntry(route: .navigation, icon: "hand.draw.fill", tint: .systemGray, title: "Navigation mode", summary: "Gestures or 3 buttons")] : [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .padding(.horizontal, 8)
                    .padding(.top, 36)
                    .padding(.bottom, 16)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium))
                    TextField("Search Settings", text: $query)
                        .font(.system(size: 16, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                }
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                .padding(.bottom, 20)

                if query.isEmpty {
                    account
                    ForEach(Self.groups.indices, id: \.self) { i in
                        AndroidSettingsGroup {
                            ForEach(Self.groups[i]) { e in SettingsLink(route: e.route, icon: e.icon, tint: e.tint, title: e.title, summary: e.summary) }
                        }
                    }
                } else {
                    AndroidSettingsGroup {
                        if results.isEmpty { AndroidSettingsRow(icon: "magnifyingglass", title: "No results") }
                        ForEach(results) { e in SettingsLink(route: e.route, icon: e.icon, tint: e.tint, title: e.title, summary: e.summary) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(uiColor: Material3.surface).ignoresSafeArea())
    }

    /// The account card at the top: HuskPatch, and what it is.
    private var account: some View {
        NavigationLink(value: AndroidSettingsRoute.about) {
            HStack(spacing: 16) {
                HuskMark(size: 48).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("HuskPatch").font(.system(size: 18, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                    Text("LineageOS 23 · translation layer and emulation").font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
                Spacer()
            }
            .padding(16)
            .background(Color(uiColor: Material3.primaryContainer).opacity(0.6), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(AndroidRippleStyle())
        .padding(.bottom, 16)
    }
}

// MARK: - Apps

private struct AndroidAppsPage: View {
    @ObservedObject private var store = TranslationLayerStore.shared

    var body: some View {
        AndroidSettingsPage(title: "Apps", onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup(header: "All apps") {
                if store.apps.isEmpty {
                    AndroidSettingsRow(icon: "square.grid.2x2", title: "No apps", summary: "Apps you add to the library appear here")
                }
                ForEach(store.apps.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }) { app in
                    NavigationLink(value: AndroidSettingsRoute.appInfo(app.id)) {
                        HStack(spacing: 16) {
                            AppIcon(path: app.iconPath, size: 40).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.label).font(.system(size: 17, design: .rounded)).lineLimit(1)
                                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                                Text(summary(app)).font(.system(size: 14, design: .rounded)).lineLimit(1)
                                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 64)
                        .background(Color(uiColor: Material3.surfaceContainer))
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            }
            AndroidSettingsGroup(header: "Special app access") {
                ForEach(AndroidSpecialAccess.allCases) { s in
                    NavigationLink(value: AndroidSettingsRoute.specialAccess(s)) {
                        AndroidSettingsRow(icon: s.icon, title: s.title)
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            }
        }
    }

    private func summary(_ app: TLApp) -> String {
        let allowed = AndroidPermissionGroup.allCases.filter { AndroidPermissions.granted(app.id, $0) }.map(\.title)
        return allowed.isEmpty ? "No permissions allowed" : allowed.joined(separator: ", ")
    }
}

/// Settings › Apps › Special app access › one kind: every app, with its switch.
private struct AndroidSpecialAccessAppsPage: View {
    let access: AndroidSpecialAccess
    @ObservedObject private var store = TranslationLayerStore.shared
    @State private var refresh = 0

    var body: some View {
        AndroidSettingsPage(title: access.title, onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup {
                if store.apps.isEmpty { AndroidSettingsRow(icon: access.icon, title: "No apps") }
                ForEach(store.apps) { app in
                    HStack(spacing: 16) {
                        AppIcon(path: app.iconPath, size: 40).clipShape(Circle())
                        Text(app.label).font(.system(size: 17, design: .rounded)).lineLimit(1)
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { AndroidPermissions.choice(app.id, access.rawValue).map { $0 == .granted } ?? access.byDefault },
                            set: { AndroidPermissions.set(app.id, access.rawValue, $0 ? .granted : .denied); refresh += 1 }))
                            .labelsHidden().toggleStyle(Material3SwitchStyle())
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                    .background(Color(uiColor: Material3.surfaceContainer))
                }
            }
            .id(refresh)
            Text(access.footer)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .padding(.horizontal, 8)
        }
    }
}

// MARK: - Connected devices

private struct AndroidConnectedDevicesPage: View {
    @ObservedObject private var pads = HuskGamepads.shared

    var body: some View {
        AndroidSettingsPage(title: "Connected devices", onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup(header: "Controllers") {
                if pads.names.isEmpty {
                    AndroidSettingsRow(icon: "gamecontroller", title: "No controllers connected",
                                       summary: "Pair one in the iPhone's Settings › Bluetooth; games see it as an Xbox-style controller")
                }
                ForEach(pads.names, id: \.self) { n in
                    AndroidSettingsRow(icon: "gamecontroller.fill", tint: .systemIndigo, title: n, summary: "Connected")
                }
            }
            AndroidSettingsGroup(header: "Input") {
                SettingsLink(route: .input, icon: "hand.tap.fill", tint: .systemIndigo, title: "Touch & keyboard", summary: "For Emulation")
            }
        }
    }
}

// MARK: - Display, wallpaper

private struct AndroidDisplayPage: View {
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system
    @AppStorage(Material3.key) private var material3 = false
    @AppStorage(Holiday.key) private var holiday = true
    @AppStorage(AndroidOverscroll.Effect.key) private var overscroll = AndroidOverscroll.Effect.stretch

    var body: some View {
        AndroidSettingsPage(title: "Display & touch", onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup(header: "Dark theme") {
                ForEach(Theme.Appearance.allCases) { a in
                    Button { appearance = a } label: {
                        AndroidSettingsRow(icon: a == .dark ? "moon.fill" : a == .light ? "sun.max.fill" : "circle.lefthalf.filled",
                                           title: a == .system ? "Automatic" : a.title,
                                           summary: a == .system ? "Follows the iPhone" : nil) {
                            AndroidRadio(on: appearance == a)
                        }
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            }
            AndroidSettingsGroup(header: "Overscroll effect") {
                ForEach(AndroidOverscroll.Effect.allCases) { e in
                    Button { overscroll = e } label: {
                        AndroidSettingsRow(icon: e == .stretch ? "arrow.up.and.down" : e == .glow ? "rays" : "arrow.up.arrow.down",
                                           title: e.title, summary: e.summary) {
                            AndroidRadio(on: overscroll == e)
                        }
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            }
            AndroidSettingsGroup(header: "Style") {
                AndroidSettingsRow(icon: "circle.hexagongrid.fill", title: "Android 16 style",
                                   summary: "Material 3 Expressive across HuskPatch") {
                    Toggle("", isOn: $material3).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
                AndroidSettingsRow(icon: "snowflake", title: "Holiday decorations") {
                    Toggle("", isOn: $holiday).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
            }
        }
    }
}

private struct AndroidWallpaperPage: View {
    @ObservedObject private var theme = AppTheme.shared
    @AppStorage(Material3.appsKey) private var materialApps = false
    @AppStorage(AndroidOS.wallpaperKey) private var wallpaper = AndroidOS.Wallpaper.lineage22
    @State private var custom: Color = AppTheme.shared.accentColor

    var body: some View {
        AndroidSettingsPage(title: "Wallpaper & style", onBack: AndroidSettingsRoute.pop) {
            // A preview of the home screen in the current colours, as Android's picker shows one.
            AndroidWallpaper()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .bottom) {
                    HStack(spacing: 14) {
                        ForEach(0..<4) { _ in Circle().fill(Color(uiColor: Material3.surfaceContainerHigh)).frame(width: 40, height: 40) }
                    }
                    .padding(.bottom, 18)
                }
                .padding(.bottom, 16)
            AndroidSettingsGroup(header: "Wallpaper") {
                ForEach(AndroidOS.Wallpaper.allCases) { w in
                    Button { wallpaper = w } label: {
                        AndroidSettingsRow(icon: w.icon, title: w.title) {
                            AndroidRadio(on: wallpaper == w)
                        }
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            }
            AndroidSettingsGroup(header: "Colours") {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(AppTheme.presets) { preset in
                            Button { theme.accentColor = preset.color; custom = preset.color } label: {
                                Circle().fill(preset.color).frame(width: 44, height: 44)
                                    .overlay {
                                        if preset.color.themeHex == theme.accentColor.themeHex {
                                            Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                        }
                    }
                    ColorPicker("Custom colour", selection: $custom, supportsOpacity: false)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .onChange(of: custom) { theme.accentColor = $0 }
                }
                .padding(16)
                .background(Color(uiColor: Material3.surfaceContainer))
                AndroidSettingsRow(icon: "paintbrush.pointed.fill", title: "Material You in apps",
                                   summary: "Apps get Android's dynamic colours from your accent, from the next app you open") {
                    Toggle("", isOn: $materialApps).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
            }
        }
        .onChange(of: theme.accentColor.themeHex) { _ in Material3.exportDynamicColors() }
        .onChange(of: materialApps) { _ in Material3.exportDynamicColors() }
    }
}

/// Material's radio button.
private struct AndroidRadio: View {
    let on: Bool
    var body: some View {
        Circle()
            .stroke(Color(uiColor: on ? Material3.primary : Material3.onSurfaceVariant), lineWidth: 2)
            .frame(width: 20, height: 20)
            .overlay(Circle().fill(Color(uiColor: Material3.primary)).frame(width: 10, height: 10).opacity(on ? 1 : 0))
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: on)
    }
}

// MARK: - System

private struct AndroidOSSystemPage: View {
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons
    @AppStorage(AppWindows.defaultKey) private var multitask = false
    @AppStorage(TranslationLayer.devInfoKey) private var devInfo = false
    @AppStorage(Android13.key) private var a13 = false
    @State private var leaving = false

    var body: some View {
        AndroidSettingsPage(title: "System", onBack: AndroidSettingsRoute.pop) {
            if devInfo {
                AndroidSettingsGroup {
                    SettingsLink(route: .developer, icon: "curlybraces", tint: .systemGreen, title: "Developer options",
                                 summary: a13 ? "Android 13 look on" : nil)
                }
            }
            AndroidSettingsGroup(header: "Gestures") {
                SettingsLink(route: .navigation, icon: "hand.draw.fill", tint: .systemGray, title: "Navigation mode", summary: navigation.title)
            }
            AndroidSettingsGroup(header: "Multitasking") {
                AndroidSettingsRow(icon: "macwindow.on.rectangle", tint: .systemPurple, title: "Open apps in windows",
                                   summary: "Move, resize and minimise apps; each app can override this") {
                    Toggle("", isOn: $multitask).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
            }
            AndroidSettingsGroup(header: "Android OS") {
                Button { leaving = true } label: {
                    AndroidSettingsRow(icon: "rectangle.portrait.and.arrow.right", tint: .systemRed, title: "Leave Android OS mode",
                                       summary: "Back to HuskPatch's own tabs")
                }
                .buttonStyle(AndroidRippleStyle())
            }
        }
        .confirmationDialog("Leave Android OS mode?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { AndroidOS.set(false) }
        } message: {
            Text("HuskPatch's tabs come back. Turn Android OS on again in Settings › Appearance.")
        }
    }
}

/// Settings › System › Navigation mode: Android's two choices, each with a picture of the bottom of the screen.
private struct AndroidNavigationModePage: View {
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons

    var body: some View {
        AndroidSettingsPage(title: "Navigation mode", onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup {
                ForEach(AndroidOS.Navigation.allCases) { mode in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { navigation = mode }
                    } label: {
                        HStack(alignment: .top, spacing: 16) {
                            AndroidRadio(on: navigation == mode).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(mode.title).font(.system(size: 17, design: .rounded))
                                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                                Text(mode.summary).font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                    .fixedSize(horizontal: false, vertical: true)
                                preview(mode)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .background(Color(uiColor: Material3.surfaceContainer))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            }
        }
    }

    /// The bottom of a phone, with the handle or the three buttons.
    private func preview(_ mode: AndroidOS.Navigation) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: Material3.surfaceContainerHighest))
            Group {
                if mode == .gestures {
                    Capsule().fill(Color(uiColor: Material3.onSurface)).frame(width: 64, height: 4).padding(.bottom, 10)
                } else {
                    HStack(spacing: 36) {
                        Image(systemName: "arrowtriangle.backward.fill").font(.system(size: 12))
                        Circle().frame(width: 12, height: 12)
                        RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1.8).frame(width: 11, height: 11)
                    }
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: 180, height: 56)
    }
}

// MARK: - Emulation, About phone

private struct AndroidEmulatorPage: View {
    var body: some View {
        AndroidSettingsPage(title: "Emulation", onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup {
                SettingsLink(route: .input, icon: "hand.tap.fill", tint: .systemIndigo, title: "Input", summary: "Screen, touch, keyboard")
                SettingsLink(route: .network, icon: "globe", tint: .systemGreen, title: "Network", summary: "Internet and saved sessions")
                SettingsLink(route: .savedMachine, icon: "externaldrive.fill", tint: .systemTeal, title: "Saved machine", summary: "Snapshots and automatic saving")
            }
        }
    }
}

private struct AndroidAboutPhonePage: View {
    @AppStorage(TranslationLayer.devInfoKey) private var devInfo = false
    @State private var taps = 0
    @State private var toast: String?

    private var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    var body: some View {
        AndroidSettingsPage(title: "About phone", onBack: AndroidSettingsRoute.pop) {
            VStack(spacing: 8) {
                HuskMark(size: 72).clipShape(Circle())
                Text("HuskPatch").font(.system(size: 26, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            AndroidSettingsGroup {
                AndroidSettingsRow(title: "Device name", summary: UIDevice.current.name)
                AndroidSettingsRow(title: "Model", summary: model)
                AndroidSettingsRow(title: "Android version", summary: Android13.isOn ? "13" : "16")
                AndroidSettingsRow(title: "LineageOS version",
                                   summary: (Android13.isOn ? "20.0" : "23.0") + "-\(Bundle.main.version)-HUSKPATCH")
                AndroidSettingsRow(title: "HuskPatch version", summary: Bundle.main.version)
                Button {
                    taps += 1
                    if devInfo { show("No need, you are already a developer.") }
                    else if taps >= 7 { devInfo = true; show("You are now a developer! Developer options are in System.") }
                    else if taps >= 3 { show("You are now \(7 - taps) step\(7 - taps == 1 ? "" : "s") away from being a developer.") }
                } label: {
                    AndroidSettingsRow(title: "Build number", summary: Bundle.main.commit)
                }
                .buttonStyle(AndroidRippleStyle())
            }
            AndroidSettingsGroup {
                SettingsLink(route: .legal, icon: "info.circle.fill", tint: .systemBlue, title: "Husk", summary: "Console, developer info, device checks")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.surface))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color(uiColor: Material3.onSurface), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
    }

    /// Android's toast: a short line at the bottom that goes by itself.
    private func show(_ text: String) {
        withAnimation { toast = text }
        let now = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if toast == now { withAnimation { toast = nil } } }
    }
}
