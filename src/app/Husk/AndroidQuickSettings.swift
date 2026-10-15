// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's notification shade and Quick Settings, pulled down from the status bar (or anywhere on the
/// home screen), as on a Pixel with Android 16.
///
/// Pulled once, it shows the first row of tiles and the notifications; pulled again (or dragged further), every tile and the
/// brightness slider. The tiles do what they say where the iPhone lets an app do it: the flashlight, the screen's brightness,
/// dark theme, JIT, the navigation mode, locking the screen. The notifications are HuskPatch's downloads.
struct AndroidShade: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var downloads = Downloads.shared
    @StateObject private var status = DeviceStatus()
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.45 * reveal)
                    .ignoresSafeArea()
                    .onTapGesture { shell.closeShade() }

                VStack(spacing: 12) {
                    header
                    AndroidQuickSettingsPanel(expanded: shell.shadeExpanded)
                    if !shell.shadeExpanded {
                        notifications
                    }
                    handle
                }
                .padding(.horizontal, 14)
                .padding(.top, geo.safeAreaInsets.top > 0 ? 4 : 18)
                .padding(.bottom, 10)
                .frame(maxWidth: 560)
                .background(Color(uiColor: Material3.surfaceContainer).opacity(0.98),
                            in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(.horizontal, 6)
                .offset(y: min(0, drag))
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
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var reveal: Double { 1 - Double(min(1, max(0, -drag) / 400)) }

    /// The clock and date on the left; the battery and the settings gear on the right, as Android 16's shade starts.
    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .firstTextBaseline) {
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: shell.shadeExpanded ? 44 : 32, weight: .regular, design: .rounded))
                    .monospacedDigit()
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Spacer()
                Label("\(Int((status.level * 100).rounded()))%", systemImage: status.charging ? "battery.100.bolt" : "battery.75")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
    }

    private var active: [Downloads.Job] {
        downloads.jobs.filter { !$0.complete || ($0.finished.map { Date().timeIntervalSince($0) < 3600 } ?? false) }
    }

    @ViewBuilder
    private var notifications: some View {
        if active.isEmpty && shell.notifications.isEmpty {
            Text("No notifications")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
        } else {
            VStack(spacing: 3) {
                let posted = Array(shell.notifications.prefix(4))
                ForEach(Array(posted.enumerated()), id: \.element.id) { i, n in
                    PostedNotificationCard(note: n, first: i == 0, last: i == posted.count - 1 && active.isEmpty)
                }
                ForEach(Array(active.prefix(4).enumerated()), id: \.element.id) { i, job in
                    AndroidNotificationCard(job: job, first: i == 0 && posted.isEmpty, last: i == min(active.count, 4) - 1)
                }
            }
            HStack {
                Spacer()
                Button("Manage") { shell.closeShade(); shell.launch(.settings) }
                Button("Clear all") { shell.dismissNotifications(); shell.closeShade() }
            }
            .buttonStyle(AndroidPillButtonStyle())
        }
    }

    private var handle: some View {
        Capsule().fill(Color(uiColor: Material3.onSurfaceVariant).opacity(0.5))
            .frame(width: 36, height: 4)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, minHeight: 18)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { shell.shadeExpanded.toggle() } }
    }
}

/// A notification posted in the shell, swiped away sideways as on Android.
private struct PostedNotificationCard: View {
    let note: ShellNotification
    let first: Bool
    let last: Bool
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var dx: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(uiColor: Material3.onPrimary))
                .frame(width: 36, height: 36)
                .background(Color(uiColor: Material3.primary), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(note.app) · \(note.date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Text(note.title).font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                Text(note.text).font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: Material3.surfaceContainerHighest),
                    in: RoundedRectangle(cornerRadius: first || last ? 24 : 6, style: .continuous))
        .offset(x: dx)
        .opacity(1 - Double(min(abs(dx) / 260, 1)))
        .gesture(DragGesture(minimumDistance: 14).onChanged { dx = $0.translation.width }.onEnded { v in
            if abs(v.translation.width) > 120 { withAnimation(.snappy) { shell.notifications.removeAll { $0.id == note.id } } }
            else { withAnimation(.spring) { dx = 0 } }
        })
    }
}

/// A notification: the app's icon in a circle, its name and text, a progress bar for a download that is running.
private struct AndroidNotificationCard: View {
    let job: Downloads.Job
    let first: Bool
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: job.complete ? "checkmark" : job.failed ? "exclamationmark" : "arrow.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(uiColor: Material3.onPrimary))
                .frame(width: 36, height: 36)
                .background(Color(uiColor: Material3.primary), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("HuskPatch · Downloads")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Text(job.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .lineLimit(1)
                if job.complete {
                    Text("Download complete").font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                } else if job.failed {
                    Text("Download failed").font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                } else {
                    ProgressView(value: job.total > 0 ? Double(job.received) / Double(job.total) : 0)
                        .tint(Color(uiColor: Material3.primary))
                    Text(job.paused ? "Paused" : ByteCountFormatter.string(fromByteCount: job.received, countStyle: .file)
                         + (job.total > 0 ? " / " + ByteCountFormatter.string(fromByteCount: job.total, countStyle: .file) : ""))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: Material3.surfaceContainerHighest),
                    in: RoundedRectangle(cornerRadius: first || last ? 24 : 6, style: .continuous))
    }
}

// MARK: - Quick Settings

/// The tiles: large ones, two to a row, as Android 13 and later draw them; the first two rows when the shade is pulled
/// once, all of them and the brightness slider when it is pulled all the way.
struct AndroidQuickSettingsPanel: View {
    let expanded: Bool
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @StateObject private var status = DeviceStatus()
    @ObservedObject private var torch = TorchSwitch.shared
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system.rawValue
    @Environment(\.colorScheme) private var scheme
    @State private var brightness = Double(UIScreen.main.brightness)

    private var dark: Bool {
        switch Theme.Appearance(rawValue: appearance) ?? .system {
        case .dark: return true
        case .light: return false
        case .system: return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if expanded { brightnessSlider }
            let tiles = allTiles
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(tiles.prefix(expanded ? tiles.count : 4).enumerated()), id: \.offset) { _, t in t }
            }
            if !expanded { brightnessSlider }
            if expanded {
                HStack(spacing: 22) {
                    Text("HuskPatch").font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    Spacer()
                    footerButton("pencil", "Edit") {}
                    footerButton("power", "Lock") { shell.closeShade(); if AndroidLock.showsLockScreen { shell.locked = true } }
                    footerButton("gearshape", "Settings") { shell.closeShade(); shell.launch(.settings) }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            brightness = Double(UIScreen.main.brightness)
        }
    }

    private var allTiles: [QuickSettingsTile] {
        [
            QuickSettingsTile(icon: status.wifi ? "wifi" : status.cellular ? "antenna.radiowaves.left.and.right" : "wifi.slash",
                        title: "Internet", subtitle: status.wifi ? "Wi-Fi" : status.cellular ? "Mobile data" : "Not connected",
                        on: status.wifi || status.cellular) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            },
            QuickSettingsTile(icon: "flashlight.on.fill", title: "Flashlight", subtitle: torch.available ? (torch.on ? "On" : "Off") : "Unavailable",
                        on: torch.on) { torch.toggle() },
            QuickSettingsTile(icon: "circle.lefthalf.filled", title: "Dark theme", subtitle: dark ? "On" : "Off", on: dark) {
                let next: Theme.Appearance = dark ? .light : .dark
                appearance = next.rawValue
                Theme.apply(next)
                Material3.exportDynamicColors()
            },
            QuickSettingsTile(icon: "bolt.fill", title: "JIT", subtitle: Launcher.jitOn ? "On" : jit.busy ? "Turning on…" : "Off",
                        on: Launcher.jitOn) { if !Launcher.jitOn { jit.enable() } },
            QuickSettingsTile(icon: navigation == .gestures ? "hand.draw" : "rectangle.split.3x1",
                        title: "Navigation", subtitle: navigation == .gestures ? "Gestures" : "3-button", on: navigation == .gestures) {
                navigation = navigation == .gestures ? .buttons : .gestures
            },
            QuickSettingsTile(icon: "battery.25", title: "Battery Saver",
                        subtitle: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off",
                        on: ProcessInfo.processInfo.isLowPowerModeEnabled) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            },
            QuickSettingsTile(icon: shell.doNotDisturb ? "moon.fill" : "moon", title: "Do Not Disturb",
                              subtitle: shell.doNotDisturb ? "On" : "Off", on: shell.doNotDisturb) { shell.doNotDisturb.toggle() },
            QuickSettingsTile(icon: "lock.fill", title: "Screen lock", subtitle: AndroidLock.showsLockScreen ? "Lock now" : "None", on: false) {
                shell.closeShade(); if AndroidLock.showsLockScreen { shell.locked = true }
            },
            QuickSettingsTile(icon: "square.grid.2x2", title: "Recent apps", subtitle: "\(shell.recentApps.count) open", on: false) {
                shell.closeShade(); shell.toggleRecents()
            },
        ]
    }

    /// Android's brightness slider: a thick track, filled in the accent colour, with the sun riding at its start.
    private var brightnessSlider: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(uiColor: Material3.surfaceContainerHighest))
                Capsule().fill(Color(uiColor: Material3.primaryContainer))
                    .frame(width: max(48, w * brightness))
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                    .padding(.leading, 15)
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

    private func footerButton(_ icon: String, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .frame(width: 40, height: 40)
                .background(Color(uiColor: Material3.surfaceContainerHighest), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

/// A Quick Settings tile: a rounded rectangle, filled in the accent colour when on, with its icon, name and state.
struct QuickSettingsTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text(subtitle).font(.system(size: 12, weight: .regular, design: .rounded)).lineLimit(1).opacity(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(uiColor: on ? Material3.onPrimary : Material3.onSurface))
            .padding(.horizontal, 16)
            .frame(height: 66)
            .background(Color(uiColor: on ? Material3.primary : Material3.surfaceContainerHighest),
                        in: RoundedRectangle(cornerRadius: on ? 22 : 33, style: .continuous))
        }
        .buttonStyle(AndroidSquashStyle())
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}

/// The flashlight, shared by the Quick Settings tile and the lock screen's shortcut.
@MainActor
final class TorchSwitch: ObservableObject {
    static let shared = TorchSwitch()
    @Published private(set) var on = false
    let available: Bool
    private let device = AVCaptureDevice.default(for: .video)

    init() {
        available = device?.hasTorch ?? false
        on = device?.torchMode == .on
    }

    /// Switches it, and says whether it is on now.
    @discardableResult func toggle() -> Bool {
        guard let device, available else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .off : .on
            device.unlockForConfiguration()
            on.toggle()
        } catch {
            HuskLog.log("ui", "flashlight: \(error.localizedDescription)")
        }
        return on
    }
}

// MARK: - styles and dialogs

/// Material 3 Expressive's press, for tiles and pills: a quick squash.
struct AndroidSquashStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A tonal pill button, as Android's shade and dialogs have.
struct AndroidPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color(uiColor: Material3.surfaceContainerHighest), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// Android's alert dialog: a rounded sheet in the middle of a dimmed screen, an icon, a headline, the text, and text buttons
/// on the right.
struct AndroidAlertDialog: View {
    let icon: String
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: dismiss)
            VStack(alignment: .center, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(uiColor: Material3.primary))
                Text(title)
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button("OK", action: dismiss)
                        .buttonStyle(.expressive(.text))
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 14)
            .frame(maxWidth: 340)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 40)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}
