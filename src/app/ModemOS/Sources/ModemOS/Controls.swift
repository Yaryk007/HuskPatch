import SwiftUI
import UIKit
import MediaPlayer
import AVFoundation

/// Screen brightness and system volume, for the two sliders in the notification shade.
final class SystemControls: ObservableObject {
    static let shared = SystemControls()

    @Published var brightness: CGFloat
    @Published var volume: CGFloat

    /// Its hidden slider is the only public way to change the system volume.
    private let volumeView = MPVolumeView(frame: .zero)

    init() {
        brightness = UIScreen.main.brightness
        volume = CGFloat(AVAudioSession.sharedInstance().outputVolume)
    }

    func setBrightness(_ newValue: CGFloat) {
        brightness = newValue
        UIScreen.main.brightness = newValue
    }

    func setVolume(_ newValue: CGFloat) {
        volume = newValue
        attachVolumeViewIfNeeded()
        let slider = volumeView.subviews.compactMap { $0 as? UISlider }.first
        slider?.value = Float(newValue)
    }

    /// The volume view only drives the real volume once it lives in a window (off-screen is fine).
    private func attachVolumeViewIfNeeded() {
        guard volumeView.superview == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        volumeView.frame = CGRect(x: -2000, y: -2000, width: 10, height: 10)
        window?.addSubview(volumeView)
    }
}

/// A pill slider from the concept: a black track with a coloured pill on top that grows as the value goes up.
struct ControlSlider: View {
    let title: String
    let color: Color
    let screenWidth: CGFloat
    let height: CGFloat
    @Binding var value: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let trackWidth = screenWidth * 0.501
        let fillLeft = screenWidth * 0.066
        let fillMax = screenWidth * 0.435
        let fillWidth = lerp(height, fillMax, value)
        let font = Font.system(size: screenWidth * 0.045, weight: .bold)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(scheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.55))

            Capsule()
                .fill(color)
                .frame(width: fillWidth, height: height)
                .offset(x: fillLeft)

            // White label on the dark track, black label on the coloured fill.
            ZStack {
                Text(title)
                    .font(font)
                    .foregroundColor(.primary)
                    .frame(width: fillMax, height: height)

                Text(title)
                    .font(font)
                    .foregroundColor(.black)
                    .frame(width: fillMax, height: height)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: fillWidth, height: height)
                    }
            }
            .frame(width: fillMax, height: height)
            .offset(x: fillLeft)
        }
        .frame(width: trackWidth, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let x = drag.location.x - fillLeft - height
                    value = clamp01(x / (fillMax - height))
                }
        )
    }
}

/// Battery percentage for the status bar.
struct BatteryText: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            Text(Self.label())
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
        }
    }

    static func label() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "--%" }
        return "\(Int((level * 100).rounded()))%"
    }
}
