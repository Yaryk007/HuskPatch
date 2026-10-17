// SPDX-License-Identifier: GPL-2.0-or-later
import Network
import SwiftUI
import UIKit

/// HuskPatch: Android's status bar, drawn in the strip an app on the translation layer is kept out of in portrait.
///
/// The game screen hides iOS's own status bar, and Android apps expect one: the strip at the top was empty, painted in
/// the app's status bar colour (often grey). This draws Android's there instead, with the phone's real time, battery
/// and connection. Two looks: Android 16 (Material 3 Expressive) when the Android 16 style is on, and the classic one
/// (Android 5 to 8: everything on the right, a black bar) when it is off. iOS does not tell apps the cellular signal
/// strength, so the bars are drawn full whenever cellular is the connection.
struct AndroidStatusBar: View {
    let material: Bool
    /// Over a wallpaper (Android OS mode's home and lock screens): no bar of its own, icons in the wallpaper's ink.
    var transparent = false
    /// The lock screen: its own clock is the big one, so the bar's left side is empty, as Android's keyguard has it.
    var hidesClock = false
    @StateObject private var status = DeviceStatus()
    @Environment(\.colorScheme) private var scheme

    private var ink: Color {
        transparent ? Color(uiColor: Material3.onPrimaryContainer) : Color(uiColor: Material3.onSurface)
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.safeAreaInsets.top
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Group {
                    if material { expressive(context.date) } else { classic(context.date) }
                }
                .frame(height: max(height, 24))
                .frame(maxWidth: .infinity)
                .background(transparent ? Color.clear : material ? Color(uiColor: Material3.surface) : Color.black)
            }
            .ignoresSafeArea(edges: .top)
        }
        .environment(\.colorScheme, transparent ? scheme : .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Android 16

    /// The clock on the left, the connection and a horizontal battery with its level written in it on the right,
    /// in Google Sans's place the rounded face, with the bar's items kept clear of the notch at the sides.
    private func expressive(_ now: Date) -> some View {
        let fg = ink
        return HStack(spacing: 6) {
            Text(time(now))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(hidesClock ? 0 : 1)
            Spacer(minLength: 0)
            connection(fg, size: 13)
            ZStack(alignment: .leading) {
                Capsule().fill(fg.opacity(0.35))
                Capsule().fill(fg).frame(width: 30 * max(status.level, 0.08))
                Text(status.charging ? "⚡︎" : "\(Int((status.level * 100).rounded()))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.surface))
                    .frame(width: 30)
            }
            .frame(width: 30, height: 15)
            .clipShape(Capsule())
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 26)
        .padding(.top, 8)
    }

    // MARK: Classic

    /// Android 5 to 8: a black bar, white icons, and everything -- signal, Wi-Fi, an upright battery, the clock -- on the right.
    private func classic(_ now: Date) -> some View {
        HStack(spacing: 7) {
            Spacer(minLength: 0)
            connection(.white, size: 13)
            UprightBattery(level: status.level, charging: status.charging)
                .frame(width: 9, height: 15)
            Text(time(now))
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    // MARK: parts

    @ViewBuilder
    private func connection(_ color: Color, size: CGFloat) -> some View {
        if status.wifi {
            Image(systemName: "wifi").font(.system(size: size, weight: .bold))
        }
        if status.cellular {
            SignalTriangle().fill(color).frame(width: size, height: size)
        }
        if !status.wifi && !status.cellular {
            Image(systemName: "airplane").font(.system(size: size - 1, weight: .bold))
        }
    }

    private func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date).replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: "")
    }
}

/// Android's cellular signal: a right triangle, filled.
private struct SignalTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The classic battery: an upright cell with a nub on top, filled from the bottom, with a bolt while charging.
private struct UprightBattery: View {
    let level: Double
    let charging: Bool

    var body: some View {
        GeometryReader { g in
            let nub = g.size.height * 0.12
            VStack(spacing: 0) {
                Rectangle().frame(width: g.size.width * 0.45, height: nub)
                ZStack(alignment: .bottom) {
                    Rectangle().opacity(0.35)
                    Rectangle().frame(height: (g.size.height - nub) * max(level, 0.05))
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: g.size.width * 0.8, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }
}

/// The phone's battery and connection, kept current for the status bar.
@MainActor
final class DeviceStatus: ObservableObject {
    @Published var level: Double = 1
    @Published var charging = false
    @Published var wifi = false
    @Published var cellular = false
    private let monitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []

    init() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        readBattery()
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.readBattery() }
            })
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            let cellular = path.status == .satisfied && path.usesInterfaceType(.cellular)
            Task { @MainActor in self?.wifi = wifi; self?.cellular = cellular }
        }
        monitor.start(queue: DispatchQueue(label: "huskpatch.statusbar.path"))
    }

    deinit {
        monitor.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func readBattery() {
        let device = UIDevice.current
        // -1 when the level is unknown (the simulator): show a full battery rather than an empty one.
        level = device.batteryLevel < 0 ? 1 : Double(device.batteryLevel)
        charging = device.batteryState == .charging || device.batteryState == .full
    }
}
