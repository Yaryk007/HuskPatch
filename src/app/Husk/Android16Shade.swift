// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Android 16's notification shade and Quick Settings, as LineageOS 23.2 draws them.
///
/// Pulled once: the time and date with the status icons, four large tiles (Internet, Bluetooth, Modes, Cast), and the
/// notifications -- alerting ones first, then a Silent section -- over a footer of history, Clear all and notification
/// settings. Pulled again: the large clock, Material 3 Expressive's brightness slider, the four large tiles with their
/// state, Android 16's round icon tiles four to a row, the edit pencil, and settings and power at the bottom. Tapping
/// Internet or Cast opens their dialogs. It follows the finger while it is being pulled (AndroidShellState.shadePeek).
struct AndroidShade: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var torch = TorchSwitch.shared
    @StateObject private var status = DeviceStatus()
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system.rawValue
    @State private var drag: CGFloat = 0
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var dialog: Dialog?
    @State private var silentHidden = false
    @State private var toast: String?

    enum Dialog: Identifiable { case internet, cast; var id: Int { self == .internet ? 0 : 1 } }

    private var dark: Bool {
        switch Theme.Appearance(rawValue: appearance) ?? .system {
        case .dark: return true
        case .light: return false
        case .system: return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }

    /// How far the shade is out: 1 when open, less while it is being pulled or pushed away.
    private var reveal: Double {
        if !shell.shade { return Double(shell.shadePeek) }
        return 1 - Double(min(1, max(0, -drag) / 420))
    }

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            ZStack(alignment: .top) {
                // the blurred, dimmed screen behind the shade
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color(uiColor: Material3.tone(.neutral, dark ? 6 : 94)).opacity(0.72)
                }
                .ignoresSafeArea()
                .opacity(reveal)
                .onTapGesture { shell.closeShade() }

                Group {
                    if shell.shadeExpanded {
                        expanded(land: land)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -24)), removal: .opacity))
                    } else {
                        collapsed(land: land)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: land ? 760 : .infinity)
                .offset(y: shell.shade ? min(0, drag) : -(1 - CGFloat(reveal)) * 260)
                .opacity(min(1, reveal * 1.4))

                if let dialog {
                    ShadeDialogView(dialog: dialog, status: status) { withAnimation(AndroidMotion.fade) { self.dialog = nil } }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .zIndex(2)
                }
                if let toast {
                    VStack {
                        Spacer()
                        Text(toast).font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.inverseOnSurface))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Color(uiColor: Material3.inverseSurface), in: Capsule())
                            .padding(.bottom, 40)
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .gesture(DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.height }
                .onEnded { v in
                    let dy = v.translation.height, fling = v.predictedEndTranslation.height
                    withAnimation(AndroidMotion.spatial) {
                        drag = 0
                        if dy < -60 || fling < -260 {
                            if shell.shadeExpanded { shell.shadeExpanded = false } else { shell.closeShade() }
                        } else if dy > 50 || fling > 260 {
                            shell.shadeExpanded = true
                        }
                    }
                })
        }
        .animation(AndroidMotion.spatial, value: shell.shadeExpanded)
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            brightness = Double(UIScreen.main.brightness)
        }
    }

    // MARK: tiles

    private var bigTiles: [AndroidQSTile] {
        [
            AndroidQSTile(icon: status.wifi ? "wifi" : status.cellular ? "cellularbars" : "network.slash", title: "Internet",
                          subtitle: status.wifi ? "Wi-Fi" : status.cellular ? "Mobile data" : "Not connected",
                          on: status.wifi || status.cellular, detail: true) { withAnimation(AndroidMotion.fade) { dialog = .internet } },
            AndroidQSTile(icon: "personalhotspot.slash", title: "Bluetooth", subtitle: "Off", detail: true) { openIOSSettings() },
            AndroidQSTile(icon: shell.doNotDisturb ? "moon.fill" : "minus.circle", title: "Modes",
                          subtitle: shell.doNotDisturb ? "Do Not Disturb" : "Off", on: shell.doNotDisturb) { shell.doNotDisturb.toggle() },
            AndroidQSTile(icon: "rectangle.on.rectangle", title: "Cast", subtitle: "Not connected", detail: true) {
                withAnimation(AndroidMotion.fade) { dialog = .cast }
            },
        ]
    }

    private var smallTiles: [AndroidQSTile] {
        let offline = !status.wifi && !status.cellular
        let next = AndroidAlarms.load().filter(\.on).compactMap { AndroidAlarms.next($0) }.min()
        return [
            AndroidQSTile(icon: "airplane", title: "Airplane mode", subtitle: offline ? "On" : "Off", on: offline) { openIOSSettings() },
            AndroidQSTile(icon: "lock.rotation", title: "Auto-rotate", subtitle: "On", on: true) { openIOSSettings() },
            AndroidQSTile(icon: "battery.25", title: "Battery Saver",
                          subtitle: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off",
                          on: ProcessInfo.processInfo.isLowPowerModeEnabled) { openIOSSettings() },
            AndroidQSTile(icon: "alarm", title: "Alarm",
                          subtitle: next.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "No alarm set",
                          on: next != nil) { shell.closeShade(); shell.launch(.system(.clock)) },
            AndroidQSTile(icon: "flashlight.on.fill", title: "Flashlight", subtitle: torch.on ? "On" : "Off",
                          on: torch.on, unavailable: !torch.available) { torch.toggle() },
            AndroidQSTile(icon: "circle.lefthalf.filled", title: "Dark theme", subtitle: dark ? "On" : "Off", on: dark) {
                let next: Theme.Appearance = dark ? .light : .dark
                appearance = next.rawValue
                Theme.apply(next)
                Material3.exportDynamicColors()
            },
            AndroidQSTile(icon: "bolt.fill", title: "JIT", subtitle: Launcher.jitOn ? "On" : "Off", on: Launcher.jitOn) {
                if !Launcher.jitOn { JITCoordinator.shared.enable() }
            },
            AndroidQSTile(icon: navigation == .gestures ? "hand.draw" : "rectangle.split.3x1", title: "Navigation",
                          subtitle: navigation == .gestures ? "Gestures" : "3-button", on: navigation == .gestures) {
                navigation = navigation == .gestures ? .buttons : .gestures
            },
            AndroidQSTile(icon: "lock.fill", title: "Screen lock", subtitle: "Lock now") {
                shell.closeShade(); if AndroidLock.showsLockScreen { shell.locked = true }
            },
            AndroidQSTile(icon: "square.grid.2x2", title: "Recent apps", subtitle: "\(shell.recentApps.count) open") {
                shell.closeShade(); shell.toggleRecents()
            },
            AndroidQSTile(icon: "house", title: "Device controls", subtitle: "Unavailable", unavailable: true) {},
        ]
    }

    private func openIOSSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    private func show(_ text: String) {
        withAnimation(AndroidMotion.fade) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(AndroidMotion.fade) { if toast == text { toast = nil } }
        }
    }

    // MARK: pulled once

    private func collapsed(land: Bool) -> some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 10) {
                    Text(AndroidClockFace.time(ctx.date)).font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    Spacer()
                    ShadeStatusIcons(status: status)
                }
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .padding(.horizontal, 22)
                .frame(height: 40)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: land ? 4 : 2), spacing: 10) {
                ForEach(bigTiles) { A16BigTile(tile: $0, showsState: false) }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            notifications
                .padding(.top, 16)
        }
    }

    private var active: [Downloads.Job] {
        downloads.jobs.filter { !$0.complete || ($0.finished.map { Date().timeIntervalSince($0) < 3600 } ?? false) }
    }

    /// The notifications: the alerting ones grouped as one card, a Silent section for downloads, and the footer.
    private var notifications: some View {
        ScrollView {
            VStack(spacing: 14) {
                if shell.notifications.isEmpty && (active.isEmpty || silentHidden) {
                    Text("No notifications")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                }
                if !shell.notifications.isEmpty {
                    VStack(spacing: 2) {
                        let posted = Array(shell.notifications.prefix(6))
                        ForEach(Array(posted.enumerated()), id: \.element.id) { i, n in
                            A16NotificationRow(icon: n.icon, app: n.app, title: n.title, text: n.text, date: n.date, id: n.id)
                                .background(Color(uiColor: Material3.surfaceContainerHigh),
                                            in: StackedCorners(top: i == 0 ? 26 : 6, bottom: i == posted.count - 1 ? 26 : 6))
                        }
                    }
                }
                if !active.isEmpty && !silentHidden {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Silent").font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer()
                            Button { withAnimation(AndroidMotion.spatial) { silentHidden = true } } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear silent notifications")
                        }
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .padding(.horizontal, 12)
                        VStack(spacing: 2) {
                            let jobs = Array(active.prefix(4))
                            ForEach(Array(jobs.enumerated()), id: \.element.id) { i, job in
                                A16NotificationRow(icon: job.complete ? "checkmark" : job.failed ? "exclamationmark" : "arrow.down.to.line",
                                                   app: "Downloads", title: job.title,
                                                   text: job.complete ? "Download complete" : job.failed ? "Download failed" : job.paused ? "Paused"
                                                       : ByteCountFormatter.string(fromByteCount: job.received, countStyle: .file),
                                                   date: job.finished ?? Date(),
                                                   progress: job.complete || job.failed || job.total <= 0 ? nil : Double(job.received) / Double(job.total))
                                    .background(Color(uiColor: Material3.surfaceContainerHigh),
                                                in: StackedCorners(top: i == 0 ? 26 : 6, bottom: i == jobs.count - 1 ? 26 : 6))
                            }
                        }
                    }
                }
                // the footer: history, Clear all, notification settings
                HStack(spacing: 10) {
                    footerCircle("clock.arrow.circlepath", "Notification history") { show("No recent notifications") }
                    Button { withAnimation(AndroidMotion.spatial) { shell.dismissNotifications(); silentHidden = true } } label: {
                        Text("Clear all").font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                    }
                    .buttonStyle(AndroidSquashStyle())
                    footerCircle("bell.badge", "Notification settings") { shell.closeShade(); shell.launch(.settings) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .scrollBounceBehaviorBasedOnSizeCompat()
    }

    private func footerCircle(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .frame(width: 48, height: 48)
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: Circle())
        }
        .buttonStyle(AndroidSquashStyle())
        .accessibilityLabel(label)
    }

    // MARK: pulled again

    private func expanded(land: Bool) -> some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(AndroidClockFace.time(ctx.date))
                            .font(.system(size: land ? 30 : 44, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    Spacer()
                    ShadeStatusIcons(status: status).padding(.bottom, 2)
                }
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .padding(.horizontal, 22)
                .padding(.top, land ? 4 : 12)
                .padding(.bottom, land ? 12 : 30)
            }

            ScrollView {
                VStack(spacing: 10) {
                    BrightnessSlider(value: $brightness)
                        .padding(.bottom, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: land ? 4 : 2), spacing: 10) {
                        ForEach(bigTiles) { A16BigTile(tile: $0, showsState: true) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: land ? 8 : 4), spacing: 12) {
                        ForEach(smallTiles) { A16RoundTile(tile: $0) }
                    }
                    .padding(.top, 2)
                    HStack {
                        Spacer()
                        Button { show("Tiles can't be rearranged yet") } label: {
                            Image(systemName: "pencil").font(.system(size: 19, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .accessibilityLabel("Edit")
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollBounceBehaviorBasedOnSizeCompat()

            HStack(spacing: 14) {
                Spacer()
                Button { shell.closeShade(); shell.launch(.settings) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(AndroidSquashStyle())
                .accessibilityLabel("Settings")
                Button { shell.closeShade(); withAnimation(AndroidMotion.spatial) { shell.powerMenu = true } } label: {
                    Image(systemName: "power").font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                        .frame(width: 52, height: 52)
                        .background(Color(uiColor: Material3.tone(.primary, dark ? 80 : 85)), in: Circle())
                }
                .buttonStyle(AndroidSquashStyle())
                .accessibilityLabel("Power menu")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - parts

/// The time's neighbours in the shade's header: the connection and the battery with its level.
struct ShadeStatusIcons: View {
    @ObservedObject var status: DeviceStatus

    var body: some View {
        HStack(spacing: 6) {
            if status.wifi { Image(systemName: "wifi").font(.system(size: 14, weight: .bold)) }
            if status.cellular { Image(systemName: "cellularbars").font(.system(size: 14, weight: .bold)) }
            if !status.wifi && !status.cellular { Image(systemName: "airplane").font(.system(size: 13, weight: .bold)) }
            Android16Battery(level: status.level, charging: status.charging)
            Text("\(Int((status.level * 100).rounded()))%").font(.system(size: 15, weight: .medium, design: .rounded))
        }
    }
}

/// LineageOS 23's battery: a rounded bar filled to the level, green with a bolt beside it while charging.
struct Android16Battery: View {
    let level: Double
    let charging: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.35))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(charging ? Color(red: 0.2, green: 0.82, blue: 0.35) : .primary)
                    .frame(width: 25 * max(level, 0.08))
            }
            .frame(width: 25, height: 13)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 9, weight: .black))
            }
        }
        .accessibilityLabel("Battery \(Int(level * 100)) percent\(charging ? ", charging" : "")")
    }
}

/// One Quick Settings tile's content.
struct AndroidQSTile: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let subtitle: String
    var on = false
    var unavailable = false
    var detail = false
    let action: () -> Void
}

/// Android 16's large tile: a pill, the accent when on; the icon in its own circle at the start, the name (and its state
/// when Quick Settings is pulled all the way).
struct A16BigTile: View {
    let tile: AndroidQSTile
    var showsState = true

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(AndroidMotion.spatial) { tile.action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tile.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(tile.on ? Color.clear : Color(uiColor: Material3.surfaceContainerHighest), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.title).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
                    if showsState {
                        Text(tile.subtitle).font(.system(size: 13, design: .rounded)).lineLimit(1).opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(uiColor: tile.on ? Material3.onPrimaryContainer : Material3.onSurface))
            .opacity(tile.unavailable ? 0.4 : 1)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 64)
            .background(Color(uiColor: tile.on ? Material3.tone(.primary, 82) : Material3.surfaceContainerHigh), in: Capsule())
            .animation(AndroidMotion.spatial, value: tile.on)
        }
        .buttonStyle(AndroidSquashStyle())
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.subtitle)
    }
}

/// Android 16's icon tile: a circle with the tile's icon, the accent when on; it squares off a little while pressed.
struct A16RoundTile: View {
    let tile: AndroidQSTile

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(AndroidMotion.spatial) { tile.action() }
        } label: {
            Image(systemName: tile.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(uiColor: tile.on ? Material3.onPrimaryContainer : Material3.onSurface))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Color(uiColor: tile.on ? Material3.tone(.primary, 82) : Material3.surfaceContainerHigh),
                            in: RoundedRectangle(cornerRadius: tile.on ? 22 : 32, style: .continuous))
                .opacity(tile.unavailable ? 0.4 : 1)
                .animation(AndroidMotion.spatial, value: tile.on)
        }
        .buttonStyle(RoundTilePress())
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.subtitle)
    }
}

private struct RoundTilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Material 3 Expressive's slider, as the brightness slider is drawn on Android 16: a thick filled track with the sun in
/// it, a gap, a thin upright handle, then the rest of the track.
struct BrightnessSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h: CGFloat = 52
            let fill = max(h, (w - 10) * value)
            HStack(spacing: 4) {
                Capsule().fill(Color(uiColor: Material3.tone(.primary, 82)))
                    .frame(width: fill)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                            .padding(.trailing, 14)
                    }
                Capsule().fill(Color(uiColor: Material3.tone(.primary, 82))).frame(width: 4, height: h + 8)
                if w - fill - 8 > 6 {
                    Capsule().fill(Color(uiColor: Material3.surfaceContainerHigh))
                }
            }
            .frame(height: h)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                value = min(1, max(0, Double(v.location.x / max(w, 1))))
                UIScreen.main.brightness = CGFloat(value)
            })
        }
        .frame(height: 60)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { d in
            value = min(1, max(0, value + (d == .increment ? 0.1 : -0.1)))
            UIScreen.main.brightness = CGFloat(value)
        }
    }
}

/// A notification in the shade: the app's icon in a tonal circle, "App · 2 min", the title and the text, and the expand
/// button; swiped sideways, dismissed.
struct A16NotificationRow: View {
    let icon: String
    let app: String
    let title: String
    let text: String
    let date: Date
    var id: UUID?
    var progress: Double?
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var expanded = false
    @State private var dx: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                .frame(width: 40, height: 40)
                .background(Color(uiColor: Material3.tone(.primary, 82)), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(app + " · " + age).font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .lineLimit(expanded ? 2 : 1)
                Text(text).font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    .lineLimit(expanded ? nil : 1)
                if let progress {
                    ProgressView(value: progress).tint(Color(uiColor: Material3.primary)).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            Button { withAnimation(AndroidMotion.spatial) { expanded.toggle() } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: 32, height: 22)
                    .background(Color(uiColor: Material3.surfaceContainerHighest), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .accessibilityLabel(expanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .offset(x: dx)
        .opacity(1 - Double(min(abs(dx) / 260, 1)))
        .gesture(DragGesture(minimumDistance: 14).onChanged { v in if id != nil { dx = v.translation.width } }.onEnded { v in
            if let id, abs(v.translation.width) > 110 || abs(v.predictedEndTranslation.width) > 300 {
                withAnimation(AndroidMotion.spatial) {
                    shell.notifications.removeAll { $0.id == id }
                    if shell.headsUp?.id == id { shell.headsUp = nil }
                }
            } else { withAnimation(AndroidMotion.spatial) { dx = 0 } }
        })
    }

    private var age: String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60)) min" }
        if s < 86400 { return "\(Int(s / 3600)) h" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Quick Settings' dialogs: Internet (the connection in use, Wi-Fi's switch) and Cast (no devices nearby).
private struct ShadeDialogView: View {
    let dialog: AndroidShade.Dialog
    @ObservedObject var status: DeviceStatus
    let done: () -> Void
    @State private var searching = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: done)
            VStack(spacing: 16) {
                Text(dialog == .internet ? "Internet" : "Cast screen")
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    .multilineTextAlignment(.center)
                // the thin progress line Android shows while it scans
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(uiColor: Material3.surfaceContainerHighest))
                        if searching {
                            Capsule().fill(Color(uiColor: Material3.primary)).frame(width: g.size.width * 0.3)
                                .modifier(Sweep(width: g.size.width))
                        }
                    }
                }
                .frame(width: 200, height: 4)
                if dialog == .internet {
                    HStack(spacing: 14) {
                        Image(systemName: status.wifi ? "wifi" : status.cellular ? "cellularbars" : "network.slash")
                        Text(status.wifi ? "Wi-Fi" : status.cellular ? "Mobile data" : "Not connected")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(Color(uiColor: Material3.primaryContainer), in: Capsule())
                    HStack {
                        Text("Wi-Fi").font(.system(size: 16, design: .rounded))
                        Spacer()
                        Toggle("", isOn: Binding(get: { status.wifi }, set: { _ in
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }))
                        .labelsHidden()
                        .toggleStyle(Material3SwitchStyle())
                    }
                    .padding(.horizontal, 6)
                } else if !searching {
                    Text("No nearby devices were found. Make sure they're on the same network.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        .multilineTextAlignment(.center)
                }
                HStack {
                    Spacer()
                    Button("Done", action: done).buttonStyle(.expressive(.filled))
                }
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 24)
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(AndroidMotion.fade) { searching = false }
        }
    }

    private var subtitle: String {
        if dialog == .cast { return searching ? "Looking for devices…" : "No devices found" }
        return status.wifi ? "Wi-Fi connected" : "Wi-Fi off"
    }
}

/// A bar sliding along its track and back, for indeterminate progress.
private struct Sweep: ViewModifier {
    let width: CGFloat
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .offset(x: on ? width * 0.7 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true } }
    }
}
