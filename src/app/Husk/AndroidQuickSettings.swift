// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's shared shade parts: the flashlight, button styles, dialogs and the notification card the
/// heads-up and lock screen use. The shade itself is AndroidShade in Android16Shade.swift (Android 13's in Android13.swift).

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

// MARK: - notification card (heads-up, lock screen)

/// A notification as Android 15 draws it on the lock screen and as a heads-up: a rounded card, the app's icon small in a
/// circle, "App · now" on the first line with an expand button on the right, the text under it, one line until expanded.
/// Swiped sideways, it is dismissed.
struct AndroidNotificationBubble: View {
    let note: ShellNotification
    /// On the lock screen: a darker, translucent card over the wallpaper.
    var overWallpaper = false
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var expanded = false
    @State private var dx: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(uiColor: Material3.onPrimary))
                .frame(width: 26, height: 26)
                .background(Color(uiColor: Material3.primary), in: Circle())
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(note.app).font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("· " + age(note.date)).font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                Text(note.title).font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .lineLimit(1)
                    .opacity(note.title.isEmpty ? 0 : 1)
                    .frame(height: note.title.isEmpty ? 0 : nil)
                Text(note.text).font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    .lineLimit(expanded ? nil : 1)
            }
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: 28, height: 28)
                    .background(Color(uiColor: Material3.surfaceContainerHighest), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .accessibilityLabel(expanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: overWallpaper ? Material3.surfaceContainer : Material3.surfaceContainerHigh).opacity(overWallpaper ? 0.92 : 1),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .offset(x: dx)
        .opacity(1 - Double(min(abs(dx) / 260, 1)))
        .gesture(DragGesture(minimumDistance: 14).onChanged { dx = $0.translation.width }.onEnded { v in
            if abs(v.translation.width) > 120 {
                withAnimation(.snappy) {
                    shell.notifications.removeAll { $0.id == note.id }
                    if shell.headsUp?.id == note.id { shell.headsUp = nil }
                }
            } else { withAnimation(.spring) { dx = 0 } }
        })
    }

    private func age(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A heads-up: the newest notification over the top of the screen for a few seconds. Swiped up, it goes; tapped, the shade.
struct AndroidHeadsUp: View {
    let note: ShellNotification
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        Group {
            if Android13.isOn {
                A13NotificationStack(notes: [note], expandable: true).environment(\.colorScheme, .dark)
            } else {
                AndroidNotificationBubble(note: note)
            }
        }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .onTapGesture { withAnimation(.snappy) { shell.headsUp = nil }; shell.openShade() }
            .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { v in
                if v.translation.height < -20 { withAnimation(.snappy) { shell.headsUp = nil } }
            })
    }
}
