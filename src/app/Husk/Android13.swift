// SPDX-License-Identifier: GPL-2.0-or-later
import Photos
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's Android 13 look (LineageOS 20), a developer toggle (Settings › System › Developer options,
/// or Settings › Testing). Taken from LineageOS 20 itself, running in Waydroid at 1440x2560 and 560 dpi (411 dp wide, about
/// an iPhone's width in points), in portrait and landscape:
///
/// - its wallpaper and Monet colours from it (hue 220, nearly grey neutrals), its app icons;
/// - the lock screen (the thin clock in the light accent, notification cards, the charging line), the shade and Quick
///   Settings (four pill tiles over the notifications; pulled again, the big clock, the brightness slider, eight tiles to a
///   page and the settings and power buttons), the home screen (grid, dock), the app drawer, recents, the power menu, the
///   status bar and the filled navigation buttons;
/// - Settings as flat lists, as Android 13 draws them.
///
/// The controls themselves stay Material 3 Expressive (ExpressiveUI): switches, buttons, menus.
enum Android13 {
    static let key = "huskpatch.androidOS.a13"
    private static let previousAccentKey = "huskpatch.androidOS.a13.previousAccent"
    private static let previousWallpaperKey = "huskpatch.androidOS.a13.previousWallpaper"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// The seed Android 13 takes from LineageOS 20's wallpaper: its accent tone 90 is A7EEFF (L* 90, hue 220).
    static var seed: UIColor { Lab.color(l: 52, chroma: 38, hue: 220) }

    /// Turn the look on (the wallpaper and its colours with it) or off (what was there before comes back).
    @MainActor static func set(_ on: Bool) {
        let d = UserDefaults.standard
        guard on != isOn else { return }
        if on {
            d.set(AppTheme.shared.accentColor.themeHex, forKey: previousAccentKey)
            d.set(d.string(forKey: AndroidOS.wallpaperKey) ?? AndroidOS.Wallpaper.lineage22.rawValue, forKey: previousWallpaperKey)
            d.set(true, forKey: key)
            d.set(AndroidOS.Wallpaper.lineage20.rawValue, forKey: AndroidOS.wallpaperKey)
            AppTheme.shared.accentColor = Color(uiColor: seed)
        } else {
            d.set(false, forKey: key)
            if let w = d.string(forKey: previousWallpaperKey) { d.set(w, forKey: AndroidOS.wallpaperKey) }
            if let hex = d.string(forKey: previousAccentKey), let c = Color(themeHex: hex) { AppTheme.shared.accentColor = c }
        }
        Material3.exportDynamicColors()
        AndroidShellState.shared.objectWillChange.send()
    }

    /// Android 13's colours, by the tones its SystemUI uses (dark theme).
    static var accent: Color { Color(uiColor: Material3.tone(.primary, 90)) }        // active tile, slider, clock
    static var onAccent: Color { Color(uiColor: Material3.tone(.primary, 10)) }
    static var tile: Color { Color(uiColor: Material3.tone(.neutral, 20)) }          // 2E3132
    static var panel: Color { Color(uiColor: Material3.tone(.neutral, 10)) }         // 191C1D
    static var scrim: Color { Color(uiColor: Material3.tone(.neutral, 5)) }          // 0F1112
    static var field: Color { Color(uiColor: Material3.tone(.neutralVariant, 30)) }  // 3F484B
    static var text: Color { Color(uiColor: Material3.tone(.neutral, 95)) }
    static var textDim: Color { Color(uiColor: Material3.tone(.neutralVariant, 80)) }

    /// Roboto's place: the system face, not the rounded one HuskPatch's Android 16 look uses.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .default) }

    /// LineageOS 20's own icon for a system app, where it ships one.
    static func iconAsset(_ app: AndroidSystemApp) -> String? {
        switch app {
        case .browser: return "A13Icon-browser"
        case .calculator: return "A13Icon-calculator"
        case .camera: return "A13Icon-camera"
        case .clock: return "A13Icon-clock"
        case .contacts: return "A13Icon-contacts"
        case .files: return "A13Icon-files"
        case .phone, .messages: return nil
        }
    }
}

/// LineageOS 20's default wallpaper, the picture itself (framework-res's default_wallpaper).
struct Lineage20Wallpaper: View {
    var body: some View {
        GeometryReader { geo in
            Image("Lineage20Wallpaper")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

// MARK: - status bar pieces

/// The right side of Android 13's status bar and shade header: the connection and an upright battery, optionally its level.
struct A13StatusIcons: View {
    @ObservedObject var status: DeviceStatus
    var percent = false

    var body: some View {
        HStack(spacing: 7) {
            if status.wifi { Image(systemName: "wifi").font(.system(size: 14, weight: .bold)) }
            if status.cellular { Image(systemName: "cellularbars").font(.system(size: 14, weight: .bold)) }
            if !status.wifi && !status.cellular { Image(systemName: "airplane").font(.system(size: 13, weight: .bold)) }
            A13Battery(level: status.level, charging: status.charging).frame(width: 10, height: 17)
            if percent { Text("\(Int((status.level * 100).rounded()))%").font(Android13.font(15)) }
        }
    }
}

/// Android 13's battery: an upright cell with a rounded nub, filled from the bottom, a bolt cut out while charging.
struct A13Battery: View {
    let level: Double
    let charging: Bool

    var body: some View {
        GeometryReader { g in
            let nub = g.size.height * 0.12
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1).frame(width: g.size.width * 0.5, height: nub)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).opacity(0.35)
                    RoundedRectangle(cornerRadius: 2).frame(height: (g.size.height - nub) * max(level, 0.06))
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: g.size.width * 0.85, weight: .black))
                            .blendMode(.destinationOut)
                            .frame(maxHeight: .infinity)
                    }
                }
                .compositingGroup()
            }
        }
    }
}

// MARK: - Quick Settings tiles

/// A tile's content: what it shows and what tapping it does.
struct A13TileModel: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let subtitle: String
    var on = false
    var unavailable = false
    /// A tile that opens a page (Internet, Alarm, Device controls) has a chevron.
    var detail = false
    let action: () -> Void
}

/// Android 13's tile: a rounded rectangle (a pill when small) in the light accent when on, the dark tone when off, dimmer
/// when unavailable; the icon, then the name over the state.
struct A13Tile: View {
    let model: A13TileModel
    var compact = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { model.action() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: model.icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).font(Android13.font(compact ? 16 : 15, .medium)).lineLimit(1)
                    if !compact {
                        Text(model.subtitle).font(Android13.font(14)).lineLimit(1).opacity(model.on ? 0.85 : 0.7)
                    }
                }
                Spacer(minLength: 0)
                if model.detail {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).opacity(0.8)
                }
            }
            .foregroundStyle(model.on ? Android13.onAccent : Android13.text)
            .opacity(model.unavailable ? 0.45 : 1)
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .frame(height: compact ? 58 : 76)
            .background(model.on ? Android13.accent : model.unavailable ? Android13.panel : Android13.tile,
                        in: RoundedRectangle(cornerRadius: compact ? 29 : 28, style: .continuous))
        }
        .buttonStyle(AndroidSquashStyle())
        .accessibilityLabel(model.title)
        .accessibilityValue(model.subtitle)
    }
}

/// The tiles, in Android 13's default order: Internet, Bluetooth, Flashlight, Do Not Disturb, Alarm, Airplane mode, Dark
/// theme, Auto-rotate; then HuskPatch's own (JIT, Battery Saver, Navigation, Screen lock, Recent apps, Device controls).
@MainActor
struct A13Tiles {
    let status: DeviceStatus
    let torch: TorchSwitch
    let shell: AndroidShellState
    let dark: Bool
    let setDark: (Bool) -> Void
    let navigation: AndroidOS.Navigation
    let setNavigation: (AndroidOS.Navigation) -> Void

    var all: [A13TileModel] {
        let next = AndroidAlarms.load().filter(\.on).compactMap { AndroidAlarms.next($0) }.min()
        let settings = { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
        return [
            A13TileModel(icon: status.wifi ? "wifi" : status.cellular ? "cellularbars" : "wifi.slash", title: "Internet",
                         subtitle: status.wifi ? "Wi-Fi" : status.cellular ? "Mobile data" : "Not connected",
                         on: status.wifi || status.cellular, detail: true, action: settings),
            A13TileModel(icon: "wave.3.right", title: "Bluetooth", subtitle: "Off", action: settings),
            A13TileModel(icon: "flashlight.on.fill", title: "Flashlight",
                         subtitle: torch.available ? (torch.on ? "On" : "Off") : "Unavailable",
                         on: torch.on, unavailable: !torch.available) { torch.toggle() },
            A13TileModel(icon: "minus.circle", title: "Do Not Disturb", subtitle: shell.doNotDisturb ? "On" : "Off",
                         on: shell.doNotDisturb) { shell.doNotDisturb.toggle() },
            A13TileModel(icon: "alarm", title: "Alarm",
                         subtitle: next.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "No alarm set",
                         on: next != nil, detail: true) { shell.closeShade(); shell.launch(.system(.clock)) },
            A13TileModel(icon: "airplane", title: "Airplane mode", subtitle: !status.wifi && !status.cellular ? "On" : "Off",
                         on: !status.wifi && !status.cellular, action: settings),
            A13TileModel(icon: "circle.lefthalf.filled", title: "Dark theme", subtitle: dark ? "On" : "Off", on: dark) { setDark(!dark) },
            A13TileModel(icon: "arrow.triangle.2.circlepath", title: "Auto-rotate", subtitle: "On", on: true, action: settings),
            A13TileModel(icon: "bolt.fill", title: "JIT", subtitle: Launcher.jitOn ? "On" : JITCoordinator.shared.busy ? "Turning on…" : "Off",
                         on: Launcher.jitOn) { if !Launcher.jitOn { JITCoordinator.shared.enable() } },
            A13TileModel(icon: "battery.25", title: "Battery Saver", subtitle: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off",
                         on: ProcessInfo.processInfo.isLowPowerModeEnabled, action: settings),
            A13TileModel(icon: navigation == .gestures ? "hand.draw" : "rectangle.split.3x1", title: "Navigation",
                         subtitle: navigation == .gestures ? "Gestures" : "3-button", on: navigation == .gestures) {
                setNavigation(navigation == .gestures ? .buttons : .gestures)
            },
            A13TileModel(icon: "lock.fill", title: "Screen lock", subtitle: AndroidLock.showsLockScreen ? "Lock now" : "None") {
                shell.closeShade(); if AndroidLock.showsLockScreen { shell.locked = true }
            },
            A13TileModel(icon: "square.grid.2x2", title: "Recent apps", subtitle: "\(shell.recentApps.count) open") {
                shell.closeShade(); shell.toggleRecents()
            },
            A13TileModel(icon: "house", title: "Device controls", subtitle: "Unavailable", unavailable: true, detail: true) {},
        ]
    }
}

// MARK: - shade

/// Android 13's notification shade. Pulled once: the time and date, four small tiles (one row of four in landscape), and the
/// notifications on a panel rising from below, with Manage and Clear all. Pulled again: the large clock, the brightness
/// slider, pages of eight tiles with their dots and the build, and a bar with the settings and power buttons.
struct Android13Shade: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var torch = TorchSwitch.shared
    @StateObject private var status = DeviceStatus()
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system.rawValue
    @State private var drag: CGFloat = 0
    @State private var page = 0
    @State private var brightness = Double(UIScreen.main.brightness)

    private var dark: Bool {
        switch Theme.Appearance(rawValue: appearance) ?? .system {
        case .dark: return true
        case .light: return false
        case .system: return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }

    private var tiles: [A13TileModel] {
        A13Tiles(status: status, torch: torch, shell: shell, dark: dark, setDark: { on in
            let next: Theme.Appearance = on ? .dark : .light
            appearance = next.rawValue
            Theme.apply(next)
            Material3.exportDynamicColors()
        }, navigation: navigation, setNavigation: { navigation = $0 }).all
    }

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            ZStack(alignment: .top) {
                Android13.scrim.opacity(0.97 * reveal).ignoresSafeArea()
                    .onTapGesture { shell.closeShade() }
                Group {
                    if shell.shadeExpanded {
                        expanded(land: land, size: geo.size)
                    } else {
                        collapsed(land: land, size: geo.size)
                    }
                }
                .offset(y: min(0, drag))
            }
            .gesture(DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.height }
                .onEnded { v in
                    let dy = v.translation.height
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        drag = 0
                        if dy < -60 {
                            if shell.shadeExpanded { shell.shadeExpanded = false } else { shell.closeShade() }
                        } else if dy > 50 {
                            shell.shadeExpanded = true
                        }
                    }
                })
        }
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            brightness = Double(UIScreen.main.brightness)
        }
    }

    private var reveal: Double { 1 - Double(min(1, max(0, -drag) / 400)) }

    // MARK: pulled once

    private func collapsed(land: Bool, size: CGSize) -> some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 14) {
                    Text(AndroidClockFace.time(ctx.date)).font(Android13.font(16)).monospacedDigit()
                    Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(Android13.font(16))
                    Spacer()
                    A13StatusIcons(status: status, percent: true)
                }
                .foregroundStyle(Android13.text)
                .padding(.horizontal, 18)
                .frame(height: 44)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: land ? 4 : 2), spacing: 10) {
                ForEach(tiles.prefix(4)) { A13Tile(model: $0, compact: true) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            notifications(land: land)
                .frame(maxWidth: land ? 520 : .infinity)
                .padding(.top, land ? 18 : 24)
        }
    }

    private var active: [Downloads.Job] {
        downloads.jobs.filter { !$0.complete || ($0.finished.map { Date().timeIntervalSince($0) < 3600 } ?? false) }
    }

    /// The panel the notifications sit on: rounded at the top, down to the bottom of the screen.
    private func notifications(land: Bool) -> some View {
        VStack(spacing: 14) {
            if shell.notifications.isEmpty && active.isEmpty {
                Text("No notifications")
                    .font(Android13.font(16))
                    .foregroundStyle(Android13.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                A13NotificationStack(notes: Array(shell.notifications.prefix(5)), downloads: Array(active.prefix(3)), expandable: true)
                HStack {
                    Button("Manage") { shell.closeShade(); shell.launch(.settings) }
                    Spacer()
                    Button("Clear all") { shell.dismissNotifications(); shell.closeShade() }
                }
                .buttonStyle(A13PillButtonStyle())
                .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Android13.panel, in: StackedCorners(top: 32, bottom: 0))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: pulled again

    private func expanded(land: Bool, size: CGSize) -> some View {
        let perPage = 8
        let all = tiles
        let pages = Int(ceil(Double(all.count) / Double(perPage)))
        let columns = land ? 4 : 2
        let rows = perPage / columns
        let tileHeight: CGFloat = 76
        return VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !land {
                            Text(AndroidClockFace.time(ctx.date)).font(Android13.font(46)).monospacedDigit()
                        }
                        HStack(spacing: 14) {
                            if land { Text(AndroidClockFace.time(ctx.date)).font(Android13.font(16)).monospacedDigit() }
                            Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(Android13.font(16))
                        }
                    }
                    Spacer()
                    A13StatusIcons(status: status, percent: true)
                }
                .foregroundStyle(Android13.text)
                .padding(.horizontal, 18)
                .padding(.top, land ? 8 : 28)
                .padding(.bottom, 14)
            }

            brightnessSlider.padding(.horizontal, 16).padding(.bottom, 12)

            TabView(selection: $page) {
                ForEach(0..<pages, id: \.self) { p in
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 10) {
                        ForEach(all.dropFirst(p * perPage).prefix(perPage)) { A13Tile(model: $0) }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(p)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: CGFloat(rows) * tileHeight + CGFloat(rows - 1) * 10 + 2)

            HStack {
                Text("13 (TQ3A.230901.001)").font(Android13.font(15)).foregroundStyle(Android13.textDim)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { p in
                        Circle().fill(p == page ? Android13.accent : Android13.textDim.opacity(0.5)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                Button {} label: { Image(systemName: "pencil").font(.system(size: 18, weight: .medium)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Android13.text)
                    .accessibilityLabel("Edit")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Spacer()
                Button { shell.closeShade(); shell.launch(.settings) } label: {
                    Image(systemName: "gearshape").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Android13.text)
                        .frame(width: 40, height: 40).background(Android13.tile, in: Circle())
                }
                .buttonStyle(AndroidSquashStyle())
                .accessibilityLabel("Settings")
                Button { shell.closeShade(); withAnimation(.snappy) { shell.powerMenu = true } } label: {
                    Image(systemName: "power").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Android13.onAccent)
                        .frame(width: 40, height: 40).background(Android13.accent, in: Circle())
                }
                .buttonStyle(AndroidSquashStyle())
                .accessibilityLabel("Power menu")
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(StackedCorners(top: 28, bottom: 0).fill(Android13.panel).ignoresSafeArea(edges: .bottom))
        }
    }

    /// Android 13's brightness slider: a thick pill in the light accent, filled to the level, its sun at the fill's end.
    private var brightnessSlider: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Android13.tile)
                Capsule().fill(Android13.accent)
                    .frame(width: max(48, w * brightness))
                    .overlay(alignment: .trailing) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Android13.onAccent)
                            .padding(.trailing, 15)
                    }
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                brightness = min(1, max(0, Double(v.location.x / max(w, 1))))
                UIScreen.main.brightness = CGFloat(brightness)
            })
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(brightness * 100)) percent")
        .accessibilityAdjustableAction { d in
            brightness = min(1, max(0, brightness + (d == .increment ? 0.1 : -0.1)))
            UIScreen.main.brightness = CGFloat(brightness)
        }
    }
}

/// Android 13's pill buttons under the notifications: Manage, Clear all.
struct A13PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Android13.font(16, .medium))
            .foregroundStyle(Android13.text)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(Android13.tile, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - notifications

/// Notifications grouped as Android 13 stacks them: one card, its rows 3 points apart, only the outer corners rounded.
struct A13NotificationStack: View {
    let notes: [ShellNotification]
    var downloads: [Downloads.Job] = []
    /// In the shade: the app's name over the title, and a tap expands. On the lock screen: the title and one line.
    var expandable = false

    var body: some View {
        let count = notes.count + downloads.count
        VStack(spacing: 3) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { i, n in
                A13NotificationRow(icon: n.icon, app: n.app, title: n.title, text: n.text, date: n.date, expandable: expandable, id: n.id)
                    .background(Android13.tile, in: corners(i, count))
            }
            ForEach(Array(downloads.enumerated()), id: \.element.id) { j, job in
                A13NotificationRow(icon: job.complete ? "checkmark" : job.failed ? "exclamationmark" : "arrow.down.to.line",
                                   app: "Download Manager", title: job.title,
                                   text: job.complete ? "Download complete." : job.failed ? "Download failed." : job.paused ? "Paused"
                                       : ByteCountFormatter.string(fromByteCount: job.received, countStyle: .file)
                                         + (job.total > 0 ? " / " + ByteCountFormatter.string(fromByteCount: job.total, countStyle: .file) : ""),
                                   date: job.finished ?? Date(), expandable: expandable,
                                   progress: job.complete || job.failed || job.total <= 0 ? nil : Double(job.received) / Double(job.total))
                    .background(Android13.tile, in: corners(notes.count + j, count))
            }
        }
    }

    private func corners(_ i: Int, _ count: Int) -> StackedCorners {
        StackedCorners(top: i == 0 ? 28 : 4, bottom: i == count - 1 ? 28 : 4)
    }
}

struct A13NotificationRow: View {
    let icon: String
    let app: String
    let title: String
    let text: String
    let date: Date
    var expandable = false
    var id: UUID?
    var progress: Double?
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var expanded = false
    @State private var dx: CGFloat = 0

    var body: some View {
        HStack(alignment: expandable ? .top : .center, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Android13.onAccent)
                .frame(width: 30, height: 30)
                .background(Android13.accent, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                if expandable {
                    Text(app + " · " + age).font(Android13.font(13)).foregroundStyle(Android13.textDim)
                }
                Text(title).font(Android13.font(expandable ? 17 : 15, .medium)).foregroundStyle(Android13.text).lineLimit(1)
                Text(text).font(Android13.font(15)).foregroundStyle(Android13.textDim).lineLimit(expanded ? nil : 1)
                if let progress {
                    ProgressView(value: progress).tint(Android13.accent)
                }
            }
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .foregroundStyle(Android13.text)
                    .frame(width: 30, height: 30)
                    .background(Android13.panel, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, expandable ? 16 : 14)
        .offset(x: dx)
        .opacity(1 - Double(min(abs(dx) / 260, 1)))
        .gesture(DragGesture(minimumDistance: 14).onChanged { v in if id != nil { dx = v.translation.width } }.onEnded { v in
            if let id, abs(v.translation.width) > 120 {
                withAnimation(.snappy) {
                    shell.notifications.removeAll { $0.id == id }
                    if shell.headsUp?.id == id { shell.headsUp = nil }
                }
            } else { withAnimation(.spring) { dx = 0 } }
        })
    }

    private var age: String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - lock screen

/// Android 13's keyguard: the clock thin and large in the light accent at the top left (larger, alone, when nothing is
/// waiting), the date under it, the notifications as one stack with an icon shelf for the rest, and at the bottom the
/// battery while charging or "Swipe up to open". In landscape the notifications sit beside the clock.
struct Android13Keyguard: View {
    let unlock: () -> Void
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var downloads = Downloads.shared
    @StateObject private var status = DeviceStatus()

    private var cards: [ShellNotification] { Array(shell.notifications.prefix(3)) }
    private var shelf: [String] {
        shell.notifications.dropFirst(3).map(\.icon) + (downloads.jobs.contains { !$0.complete } ? ["arrow.down.to.line"] : [])
    }

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            let busy = !cards.isEmpty || !shelf.isEmpty
            ZStack(alignment: .topLeading) {
                if land {
                    HStack(alignment: .top, spacing: 24) {
                        clock(size: busy ? 96 : 120)
                        Spacer(minLength: 0)
                        if busy { stack.frame(width: min(420, geo.size.width * 0.5)).padding(.top, 140) }
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 24)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        clock(size: busy ? 104 : 150)
                            .padding(.horizontal, 28)
                            .padding(.top, busy ? 48 : 96)
                        if busy { stack.padding(.horizontal, 14).padding(.top, 24) }
                    }
                }
                VStack(spacing: 10) {
                    Spacer()
                    if AndroidLock.fingerprintOn {
                        AndroidFingerprintSensor(onMatch: unlock)
                    } else if AndroidLock.kind.secure {
                        Image(systemName: "lock.fill").font(.system(size: 18, weight: .semibold))
                    }
                    Text(bottomLine).font(Android13.font(16))
                }
                .foregroundStyle(Android13.text)
                .frame(maxWidth: .infinity)
                .padding(.bottom, land ? 18 : 44)
            }
        }
    }

    private var bottomLine: String {
        if status.charging { return "\(Int((status.level * 100).rounded()))% • Charging" }
        if !AndroidLock.unlockedSinceLaunch && AndroidLock.kind.secure { return "Unlock for all features and data" }
        return AndroidLock.fingerprintOn ? "Touch the fingerprint sensor, or swipe up" : "Swipe up to open"
    }

    private func clock(size: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 12) {
                Text(AndroidClockFace.time(ctx.date))
                    .font(.system(size: size, weight: .thin, design: .default))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Android13.accent)
                Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(Android13.font(17))
                    .foregroundStyle(Android13.text)
                    .padding(.leading, 4)
            }
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 10) {
            A13NotificationStack(notes: cards)
            if !shelf.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(shelf.prefix(6).enumerated()), id: \.offset) { _, icon in
                        Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Android13.text)
                            .frame(width: 48, height: 48)
                            .background(Android13.tile, in: Circle())
                    }
                }
            }
        }
    }
}

// MARK: - home screen

/// Android 13's home screen (Trebuchet on LineageOS 20): five columns of icons from the top, labels under them, and the
/// dock along the bottom without labels -- down the right side in landscape.
struct Android13HomeScreen: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var jit = JITCoordinator.shared

    private var items: [ShellApp] {
        let all = Launcher.byRecent(Launcher.items(store: store, host: host))
        return [.settings, .playStore, .system(.files), .system(.clock), .system(.calculator)] + all.prefix(15).map(ShellApp.item)
    }

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            Group {
                if land {
                    HStack(spacing: 0) {
                        grid(columns: 7, iconSize: 50)
                        VStack(spacing: 14) {
                            ForEach(AndroidSystemApp.dock.prefix(4)) { a in
                                AndroidAppIconButton(app: .system(a), showsLabel: false, size: 50)
                            }
                        }
                        .frame(width: 84)
                        .padding(.trailing, 8)
                    }
                } else {
                    VStack(spacing: 0) {
                        grid(columns: 5, iconSize: 54)
                        HStack {
                            ForEach(AndroidSystemApp.dock) { a in
                                AndroidAppIconButton(app: .system(a), showsLabel: false, size: 54)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.height < -80 { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { shell.drawer = true } }
                else if v.translation.height > 80 { shell.openShade() }
            })
        }
    }

    private func grid(columns: Int, iconSize: CGFloat) -> some View {
        VStack(spacing: 14) {
            if !Launcher.jitOn {
                Button { jit.enable() } label: {
                    Label(jit.busy ? (jit.status ?? "Turning JIT on…") : "JIT is off — tap to turn on", systemImage: "bolt.fill")
                        .font(Android13.font(14, .medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Android13.tile, in: Capsule())
                        .foregroundStyle(Android13.text)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 22) {
                ForEach(items.prefix(columns * 4)) { app in
                    AndroidAppIconButton(app: app, size: iconSize)
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
    }
}

// MARK: - app drawer

/// Android 13's app drawer: the whole screen in the dark surface, the search field at the top, five columns (seven in
/// landscape) of icons with their names.
struct Android13Drawer: View {
    let apps: [ShellApp]
    @Binding var query: String
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium))
                    TextField("Search apps", text: $query)
                        .font(Android13.font(20))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                }
                .foregroundStyle(Android13.text.opacity(0.85))
                .padding(.horizontal, 20)
                .frame(height: 50)
                .background(Android13.field, in: Capsule())
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 14)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: land ? 7 : 5), spacing: 26) {
                        ForEach(apps) { AndroidAppIconButton(app: $0, size: 50) }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(.top, geo.safeAreaInsets.top > 0 ? 0 : 24)
            .background(Android13.panel.ignoresSafeArea())
        }
        .environment(\.colorScheme, .dark)
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if v.translation.height > 120 { shell.back() }
        })
    }
}

// MARK: - recents

/// Android 13's recents: the wallpaper blurred and dimmed to grey, a row of app cards with each app's icon above it, and
/// Screenshot under the middle one; Clear all after the last.
struct Android13Recents: View {
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            let cardW = land ? geo.size.width * 0.34 : geo.size.width * 0.66
            let cardH = land ? geo.size.height * 0.62 : geo.size.height * 0.6
            ZStack {
                AndroidWallpaper().androidBlur(40).overlay(Color(white: 0.45).opacity(0.75)).ignoresSafeArea()
                    .onTapGesture { shell.back() }
                if shell.recentApps.isEmpty {
                    Text("No recent items").font(Android13.font(16)).foregroundStyle(Android13.text)
                } else {
                    VStack(spacing: 18) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .center, spacing: 22) {
                                ForEach(shell.recentApps) { app in A13RecentCard(app: app, width: cardW, height: cardH) }
                                Button("Clear all") { shell.clearRecents() }
                                    .buttonStyle(A13PillButtonStyle())
                                    .padding(.horizontal, 20)
                            }
                            .padding(.horizontal, (geo.size.width - cardW) / 2)
                        }
                        Button { A13Screenshot.take() } label: {
                            Label("Screenshot", systemImage: "viewfinder")
                                .font(Android13.font(16, .medium))
                                .foregroundStyle(Android13.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct A13RecentCard: View {
    let app: ShellApp
    let width: CGFloat
    let height: CGFloat
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 14) {
            AndroidAppIcon(app: app, size: 44)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Android13.panel)
                .overlay {
                    VStack(spacing: 12) {
                        AndroidAppIcon(app: app, size: 64)
                        Text(app.title).font(Android13.font(15)).foregroundStyle(Android13.textDim)
                    }
                }
                .frame(width: width, height: height)
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

// MARK: - power menu, screen off, restart

/// Android 13's power menu (from Quick Settings' power button): round buttons on a dark card -- Power off, Restart and
/// Screenshot. Power off blanks the screen until it is tapped (then the lock screen); Restart shows LineageOS's boot
/// animation; Screenshot saves the screen to Photos.
struct Android13PowerMenu: View {
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 18) {
                HStack(spacing: 22) {
                    item("power", "Power off") { close(); shell.powerOff() }
                    item("arrow.clockwise", "Restart") { close(); shell.restart() }
                }
                item("iphone.gen3.radiowaves.left.and.right", "Screenshot") {
                    close()
                    Task { try? await Task.sleep(nanoseconds: 400_000_000); A13Screenshot.take() }
                }
            }
            .padding(24)
            .background(Android13.panel, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .environment(\.colorScheme, .dark)
    }

    private func close() { withAnimation(.snappy) { shell.powerMenu = false } }

    private func item(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Android13.text)
                    .frame(width: 84, height: 84)
                    .background(Android13.tile, in: Circle())
                Text(title).font(Android13.font(14)).foregroundStyle(Android13.text)
            }
        }
        .buttonStyle(AndroidSquashStyle())
    }
}

/// The screen off (tap to wake) or restarting (LineageOS's boot animation, then the lock screen).
struct Android13Blackout: View {
    let restarting: Bool
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if restarting {
                // LineageOS's boot animation: the logo's ring with its small circle going round, in its blue-green
                ZStack {
                    Capsule().stroke(Color(red: 0.6, green: 0.9, blue: 0.75), lineWidth: 5).frame(width: 120, height: 34)
                    Circle().fill(Color(red: 0.6, green: 0.9, blue: 0.75)).frame(width: 14, height: 14)
                        .offset(x: spin ? 46 : -46)
                }
                .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { spin = true } }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !restarting { shell.wake() } }
    }
}

/// The power menu's and recents' Screenshot: the window as it is, saved to the photo library, with a notification.
@MainActor
enum A13Screenshot {
    static func take() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)
        else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                Task { @MainActor in
                    AndroidShellState.shared.post(ShellNotification(icon: "photo", app: "System UI",
                                                                     title: ok ? "Screenshot saved" : "Couldn't save screenshot",
                                                                     text: ok ? "Tap to view it in Photos" : "Allow HuskPatch to add photos"))
                }
            }
        }
    }
}

// MARK: - Settings › System › Developer options

/// Developer options, once Build number has been tapped seven times: the Android 13 look lives here.
struct AndroidDeveloperOptionsPage: View {
    @AppStorage(Android13.key) private var a13 = false

    var body: some View {
        AndroidSettingsPage(title: "Developer options", onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup(header: "Android OS look") {
                AndroidSettingsRow(icon: "13.circle", tint: .systemTeal, title: "Android 13 (LineageOS 20)",
                                   summary: "Lock screen, shade and Quick Settings, home, app drawer, recents, icons and wallpaper as Android 13 draws them. Off: LineageOS 22.") {
                    Toggle("", isOn: Binding(get: { a13 }, set: { Android13.set($0) })).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
            }
        }
    }
}
