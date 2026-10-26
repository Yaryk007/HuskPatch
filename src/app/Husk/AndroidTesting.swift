// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// HuskPatch: Settings › Testing. Three tabs:
///
/// - M3E: every Material 3 Expressive component HuskPatch draws with (ExpressiveUI's), in the current palette, and the
///   palette's roles;
/// - System: Android OS mode's parts on demand -- a dialog, a toast, a notification, the lock screen, the permission and
///   file dialogs, and the overscroll effect on a long list;
/// - Apps: the translation layer -- JIT, the engine loaded and its state, the apps in the library -- and installing an
///   APK with Android's package installer.
struct AndroidTestingPage: View {
    var onBack: (() -> Void)?

    enum Tab: Hashable { case m3e, system, apps }
    @State private var tab: Tab = .m3e

    var body: some View {
        AndroidSettingsPage(title: "Testing", onBack: onBack) {
            ExpressiveSegmentedButtons(selection: $tab, options: [
                .init(value: .m3e, label: "M3E", systemImage: "circle.hexagongrid"),
                .init(value: .system, label: "System", systemImage: "iphone.gen3"),
                .init(value: .apps, label: "Apps", systemImage: "square.grid.2x2"),
            ])
            .padding(.bottom, 16)
            switch tab {
            case .m3e: M3EGallery()
            case .system: SystemTests()
            case .apps: TranslationLayerTests()
            }
        }
        .modifier(Material3Root())
    }
}

/// A titled card of the Testing page.
private struct TestCard<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.primary))
            if let caption {
                Text(caption)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: Material3.surfaceContainer), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.bottom, 10)
    }
}

// MARK: - M3E

private struct M3EGallery: View {
    @State private var starred = false
    @State private var range = "week"
    @State private var modes: Set<String> = ["walk"]
    @State private var split = false
    @State private var menu = false
    @State private var switchOn = true
    @State private var progress = 0.4
    @State private var fab = false
    @State private var checked = true

    private struct Swatch: Identifiable { let id: String; let color: UIColor }

    var body: some View {
        VStack(spacing: 0) {
            TestCard(title: "Buttons", caption: "Filled, elevated, tonal, outlined and text; extra small to extra large") {
                FlowRow {
                    Button("Filled") {}.buttonStyle(.expressive(.filled))
                    Button("Elevated") {}.buttonStyle(.expressive(.elevated))
                    Button("Tonal") {}.buttonStyle(.expressive(.tonal))
                    Button("Outlined") {}.buttonStyle(.expressive(.outlined))
                    Button("Text") {}.buttonStyle(.expressive(.text))
                }
                FlowRow {
                    Button("XS") {}.buttonStyle(.expressive(.tonal, size: .extraSmall))
                    Button("Small") {}.buttonStyle(.expressive(.tonal, size: .small))
                    Button("Medium") {}.buttonStyle(.expressive(.tonal, size: .medium))
                }
                Button("Large") {}.buttonStyle(.expressive(.filled, size: .large))
                Button("Disabled") {}.buttonStyle(.expressive(.filled)).disabled(true)
            }
            TestCard(title: "Button groups") {
                ExpressiveButtonGroup(items: [
                    .init(label: "Reply", systemImage: "arrowshape.turn.up.left") {},
                    .init(label: "Forward") {},
                    .init(label: "Star", systemImage: "star", isOn: $starred),
                ])
                ExpressiveConnectedButtonGroup(selection: $range, options: [
                    .init(value: "day", label: "Day"), .init(value: "week", label: "Week"), .init(value: "month", label: "Month"),
                ])
            }
            TestCard(title: "Segmented buttons", caption: "Single and multiple choice") {
                ExpressiveSegmentedButtons(selection: $range, options: [
                    .init(value: "day", label: "Day"), .init(value: "week", label: "Week"), .init(value: "month", label: "Month"),
                ])
                ExpressiveSegmentedButtons(selection: $modes, options: [
                    .init(value: "walk", label: "Walk", systemImage: "figure.walk"),
                    .init(value: "ride", label: "Ride", systemImage: "bus"),
                    .init(value: "drive", label: "Drive", systemImage: "car"),
                ])
            }
            TestCard(title: "Split button and menu") {
                HStack(spacing: 12) {
                    ExpressiveSplitButton("Edit", systemImage: "pencil", isExpanded: $split) {}
                        .modifier(MenuCompat(isPresented: $split, groups: menuGroups))
                    Button("Menu") { menu = true }
                        .buttonStyle(.expressive(.tonal))
                        .modifier(MenuCompat(isPresented: $menu, groups: menuGroups))
                }
            }
            TestCard(title: "Switches") {
                Toggle("Switch", isOn: $switchOn).toggleStyle(.expressive)
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                Toggle("Disabled", isOn: .constant(true)).toggleStyle(.expressive).disabled(true)
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
            }
            TestCard(title: "Loading indicators", caption: "Indeterminate (the seven shapes morphing), contained, and by progress") {
                HStack(spacing: 24) {
                    ExpressiveLoadingIndicator().frame(width: 48, height: 48)
                    ExpressiveLoadingIndicator(contained: true).frame(width: 48, height: 48)
                    ExpressiveLoadingIndicator(progress: progress).frame(width: 48, height: 48)
                }
            }
            TestCard(title: "Progress indicators") {
                Slider(value: $progress, in: 0...1).tint(Color(uiColor: Material3.primary))
                ExpressiveLinearProgressIndicator(progress: progress)
                ExpressiveLinearWavyProgressIndicator(progress: progress)
                ExpressiveLinearProgressIndicator()
                ExpressiveLinearWavyProgressIndicator()
                HStack(spacing: 24) {
                    ExpressiveCircularProgressIndicator(progress: progress).frame(width: 48, height: 48)
                    ExpressiveCircularWavyProgressIndicator(progress: progress).frame(width: 48, height: 48)
                    ExpressiveCircularProgressIndicator().frame(width: 48, height: 48)
                    ExpressiveCircularWavyProgressIndicator().frame(width: 48, height: 48)
                }
            }
            TestCard(title: "Carousel", caption: "Multi-browse: items shrink as they leave") {
                ExpressiveCarousel(swatches, preferredItemWidth: 186, itemSpacing: 8) { s in
                    Color(uiColor: s.color).overlay(alignment: .bottomLeading) {
                        Text(s.id).font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white).padding(12)
                    }
                }
                .frame(height: 205)
            }
            TestCard(title: "FAB menu") {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: Material3.surfaceContainerHigh))
                        .frame(height: 300)
                    ExpressiveFABMenu(isOpen: $fab, items: [
                        .init(systemImage: "square.and.pencil", label: "Note") {},
                        .init(systemImage: "camera", label: "Photo") {},
                        .init(systemImage: "mic", label: "Voice") {},
                    ])
                    .padding(16)
                }
            }
            TestCard(title: "Palette", caption: "Material 3 roles from your accent colour, as tones of its palettes") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(roles, id: \.0) { name, color in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: color)).frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(uiColor: Material3.outlineVariant)))
                            Text(name).font(.system(size: 10, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        }
                    }
                }
            }
        }
    }

    private var menuGroups: [ExpressiveMenuGroup] {
        [ExpressiveMenuGroup("Edit", items: [
            .init("Cut", systemImage: "scissors", trailingText: "⌘X") {},
            .init("Copy", systemImage: "doc.on.doc") {},
            .init("Show hidden", systemImage: "eye", isOn: $checked),
        ]),
         ExpressiveMenuGroup(items: [.init("Settings", systemImage: "gearshape") {}])]
    }

    private var swatches: [Swatch] {
        [("Primary", Material3.tone(.primary, 50)), ("Tertiary", Material3.tone(.tertiary, 55)), ("Secondary", Material3.tone(.secondary, 45)),
         ("Primary 30", Material3.tone(.primary, 30)), ("Tertiary 35", Material3.tone(.tertiary, 35)), ("Neutral", Material3.tone(.neutral, 40))]
            .map { Swatch(id: $0.0, color: $0.1) }
    }

    private var roles: [(String, UIColor)] {
        [("primary", Material3.primary), ("onPrimary", Material3.onPrimary), ("primaryC", Material3.primaryContainer),
         ("onPrimaryC", Material3.onPrimaryContainer), ("secondary", Material3.secondary), ("secondaryC", Material3.secondaryContainer),
         ("tertiary", Material3.tertiary), ("tertiaryC", Material3.tertiaryContainer), ("error", Material3.error),
         ("errorC", Material3.errorContainer), ("surface", Material3.surface), ("container", Material3.surfaceContainer),
         ("highest", Material3.surfaceContainerHighest), ("onSurface", Material3.onSurface), ("outline", Material3.outline),
         ("outlineVar", Material3.outlineVariant)]
    }
}

/// ExpressiveUI's menu is a popover kept as one (iOS 16.4); before that, a sheet-free fallback: nothing opens.
private struct MenuCompat: ViewModifier {
    @Binding var isPresented: Bool
    let groups: [ExpressiveMenuGroup]
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.expressiveMenu(isPresented: $isPresented, groups: groups)
        } else {
            content
        }
    }
}

/// Views laid out in rows, wrapping to the next when one is full.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing; row = max(row, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

// MARK: - System

private struct SystemTests: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @AppStorage(AndroidOverscroll.Effect.key) private var overscroll = AndroidOverscroll.Effect.stretch
    @State private var dialog = false
    @State private var toast: String?
    @State private var picked: [URL] = []
    @State private var pickedNote: String?
    @State private var pattern: String?

    @AppStorage(Android13.key) private var a13 = false

    var body: some View {
        VStack(spacing: 0) {
            TestCard(title: "Android version", caption: "Developer toggle: Android OS mode's look") {
                Toggle("Android 13 (LineageOS 20)", isOn: Binding(get: { a13 }, set: { Android13.set($0) }))
                    .font(.system(size: 16, design: .rounded))
                    .toggleStyle(Material3SwitchStyle())
                Text(a13 ? "LineageOS 20: its wallpaper, icons, lock screen, shade, home, drawer and recents"
                         : "LineageOS 22 (Android 15/16)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            TestCard(title: "Developer options", caption: "Android OS mode, as Android's Developer options would change it") {
                AndroidDeveloperOptions()
            }
            TestCard(title: "Android firmware", caption: "Developer toggle: what the Android machine boots") {
                AndroidFirmwareSection()
            }
            TestCard(title: "Dialogs and notifications") {
                FlowRow {
                    Button("Dialog") { withAnimation(.snappy) { dialog = true } }.buttonStyle(.expressive(.tonal))
                    Button("Toast") { show("This is a toast") }.buttonStyle(.expressive(.tonal))
                    Button("Notification") {
                        shell.post(ShellNotification(icon: "testtube.2", app: "Testing", title: "Test notification",
                                                     text: "Pull down the status bar to see it in the shade."))
                        show("Notification posted")
                    }
                    .buttonStyle(.expressive(.tonal))
                    Button("Open shade") { shell.openShade(expanded: true) }.buttonStyle(.expressive(.outlined))
                }
            }
            TestCard(title: "Lock screen", caption: "Lock type: \(AndroidLock.kind.title)\(AndroidLock.fingerprintOn ? " + fingerprint" : "")") {
                FlowRow {
                    Button("Lock now") {
                        if AndroidLock.showsLockScreen { shell.locked = true } else { show("Screen lock is None: choose one in Security & privacy") }
                    }
                    .buttonStyle(.expressive(.filled))
                    NavigationLink(value: AndroidSettingsRoute.screenLock) { Text("Change screen lock") }
                        .buttonStyle(.expressive(.outlined))
                }
                Text("Pattern pad (draws, does not unlock)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                AndroidPatternPad(onEnter: { pattern = $0 }, size: 210)
                    .frame(maxWidth: .infinity)
                if let pattern { Text("Drawn: \(pattern)").font(.system(size: 13, design: .monospaced)) }
            }
            TestCard(title: "Permissions and files", caption: "Android's dialogs and the iPhone's pickers, as apps get them") {
                FlowRow {
                    Button("Camera permission") {
                        AndroidPermissionPrompter.shared.enqueue(id: -1, permissions: ["android.permission.CAMERA"])
                    }
                    .buttonStyle(.expressive(.tonal))
                    Button("Display over apps") {
                        AndroidPermissionPrompter.shared.enqueue(id: -2, permissions: ["android.permission.SYSTEM_ALERT_WINDOW"])
                    }
                    .buttonStyle(.expressive(.tonal))
                    Button("Pick a file") { pick(media: false) }.buttonStyle(.expressive(.tonal))
                    Button("Pick a photo") { pick(media: true) }.buttonStyle(.expressive(.tonal))
                }
                if let pickedNote {
                    Text(pickedNote).font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
                ForEach(picked, id: \.self) { u in
                    HStack {
                        Image(systemName: "doc").foregroundStyle(Color(uiColor: Material3.primary))
                        Text(u.lastPathComponent).font(.system(size: 14, design: .rounded)).lineLimit(1)
                        Spacer()
                        Button { AndroidDocumentPicker.shared.export(u, mode: 1) } label: { Image(systemName: "eye") }
                        Button { AndroidDocumentPicker.shared.export(u, mode: 2) } label: { Image(systemName: "square.and.arrow.up") }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                }
            }
            TestCard(title: "Overscroll", caption: "Scroll the list past its ends") {
                ExpressiveSegmentedButtons(selection: $overscroll, options: AndroidOverscroll.Effect.allCases.map {
                    .init(value: $0, label: LocalizedStringKey($0.title))
                })
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(1...30, id: \.self) { i in
                            Text("Item \(i)")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Color(uiColor: Material3.onSurface))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color(uiColor: Material3.surfaceContainerHighest),
                                            in: RoundedRectangle(cornerRadius: i == 1 || i == 30 ? 18 : 4, style: .continuous))
                        }
                    }
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...12, id: \.self) { i in
                            Circle().fill(Color(uiColor: Material3.tone(.tertiary, 40 + Double(i) * 3))).frame(width: 64, height: 64)
                        }
                    }
                }
            }
        }
        .overlay {
            if dialog {
                AndroidAlertDialog(icon: "testtube.2", title: "Test dialog",
                                   message: "This is Android's alert dialog, as HuskPatch draws it in Android OS mode.") {
                    withAnimation(.snappy) { dialog = false }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast { AndroidToast(text: toast) }
        }
    }

    private func pick(media: Bool) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HuskPatch-test-picks", isDirectory: true)
        AndroidDocumentPicker.shared.pickForTest(mimes: media ? "image/*\nvideo/*" : "*/*", flags: media ? 4 | 1 : 1, into: dir) { urls in
            picked = urls ?? []
            pickedNote = urls == nil ? "Cancelled" : "Copied \(urls!.count) into HuskPatch's temporary folder, as an app's storage gets them"
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if toast == text { withAnimation { toast = nil } } }
    }
}

/// Android's toast: a short line in a pill at the bottom.
struct AndroidToast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(Color(uiColor: Material3.inverseOnSurface))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Color(uiColor: Material3.inverseSurface), in: Capsule())
            .padding(.bottom, 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Apps

private struct TranslationLayerTests: View {
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var installer: AndroidPackageInstaller.Stage?

    private var engineState: String {
        switch husk_unity_state() {
        case Int32(HUSK_UNITY_IDLE): return "Idle"
        case Int32(HUSK_UNITY_STARTING): return "Starting"
        case Int32(HUSK_UNITY_RUNNING): return "Running"
        case Int32(HUSK_UNITY_FAILED): return "Failed"
        case Int32(HUSK_UNITY_ENDED): return "Ended (closed itself)"
        default: return "Unknown"
        }
    }

    private var loaded: String {
        guard let path = husk_native_loaded_apk().map({ String(cString: $0) }) else { return "None" }
        return store.apps.first { $0.apks.first == path }?.label ?? (path as NSString).lastPathComponent
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            VStack(spacing: 0) {
                TestCard(title: "Install an APK", caption: "An .apk, or a bundle (.apks, .xapk, .apkm), with Android's package installer") {
                    Button {
                        AndroidPackageInstaller.pickAndInstall { installer = $0 }
                    } label: {
                        Label("Choose APK", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.expressive(.filled, size: .medium))
                    if let busy = store.busy {
                        Text(busy).font(.system(size: 13, design: .rounded))
                        ExpressiveLinearWavyProgressIndicator()
                    }
                }
                TestCard(title: "Translation layer") {
                    row("JIT", Launcher.jitOn ? "On" : jit.busy ? "Turning on…" : "Off")
                    row("Engine", engineState)
                    row("App loaded", loaded)
                    row("Apps installed", "\(store.apps.count)")
                    row("Material You in apps", ProcessInfo.processInfo.environment["HUSK_DYNAMIC_COLORS"] != nil ? "On" : "Off")
                    if !Launcher.jitOn {
                        Button("Turn on JIT") { jit.enable() }.buttonStyle(.expressive(.tonal))
                    }
                }
                TestCard(title: "Apps", caption: "Open one in Android OS mode") {
                    if store.apps.isEmpty {
                        Text("No apps yet: install an APK above.").font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    }
                    ForEach(store.apps.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }) { app in
                        HStack(spacing: 12) {
                            AppIcon(path: app.iconPath, size: 40).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.label).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
                                Text(app.packageName ?? app.id).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                            }
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                            Spacer()
                            Button("Open") { shell.launch(.item(.game(app))) }
                                .buttonStyle(.expressive(.tonal, size: .extraSmall))
                                .disabled(!AndroidOS.isOn)
                        }
                    }
                }
                TestCard(title: "Log", caption: "The runtime's latest lines") {
                    Text(HuskLog.recentLines(14).joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .overlay {
            if let stage = installer {
                AndroidPackageInstaller(stage: stage) { installer = $0 }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color(uiColor: Material3.onSurface))
            Spacer()
            Text(v).foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
        }
        .font(.system(size: 15, design: .rounded))
    }
}

/// Android's package installer, as a dialog: "Do you want to install this app?", then installing, then "App installed"
/// with Open and Done.
struct AndroidPackageInstaller: View {
    enum Stage {
        case confirm([URL])
        case installing(String, before: Set<String>)
        case done(TLApp?)
        case failed(String)
    }

    let stage: Stage
    let set: (Stage?) -> Void
    @ObservedObject private var store = TranslationLayerStore.shared

    static var types: [UTType] {
        ["apk", "apks", "xapk", "apkm"].compactMap { UTType(filenameExtension: $0) } + [.zip]
    }

    static func pickAndInstall(_ set: @escaping (Stage?) -> Void) {
        HuskFilePicker.present(types: types, multiple: true) { urls in set(.confirm(urls)) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    icon
                    Text(title).font(.system(size: 20, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .lineLimit(2)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 32)
        }
        .onChange(of: store.busy) { busy in
            guard busy == nil, case .installing(_, let before) = stage else { return }
            if let error = store.lastError { set(.failed(error)); return }
            let new = store.apps.first { !before.contains($0.id) }
            set(.done(new))
        }
        .transition(.opacity)
    }

    @ViewBuilder private var icon: some View {
        if case .done(let app?) = stage {
            AppIcon(path: app.iconPath, size: 44).clipShape(Circle())
        } else {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                .frame(width: 44, height: 44)
                .background(Color(uiColor: Material3.primaryContainer), in: Circle())
        }
    }

    private var title: String {
        switch stage {
        case .confirm(let urls): return urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "\(urls.count) files"
        case .installing(let name, _): return name
        case .done(let app): return app?.label ?? "App"
        case .failed: return "Package installer"
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .confirm(let urls):
            Text("Do you want to install this app?")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            HStack {
                Spacer()
                Button("Cancel") { set(nil) }.buttonStyle(.expressive(.text))
                Button("Install") {
                    let before = Set(store.apps.map(\.id))
                    set(.installing(title, before: before))
                    store.add(urls)
                }
                .buttonStyle(.expressive(.filled))
            }
        case .installing:
            Text("Installing…").font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            ExpressiveLinearWavyProgressIndicator()
        case .done(let app):
            Text("App installed.").font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            HStack {
                Spacer()
                Button("Done") { set(nil) }.buttonStyle(.expressive(.text))
                if let app, AndroidOS.isOn {
                    Button("Open") { set(nil); AndroidShellState.shared.launch(.item(.game(app))) }
                        .buttonStyle(.expressive(.filled))
                }
            }
        case .failed(let error):
            Text("App not installed. \(error)").font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            HStack { Spacer(); Button("OK") { set(nil) }.buttonStyle(.expressive(.text)) }
        }
    }
}
