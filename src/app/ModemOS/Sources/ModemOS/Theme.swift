import SwiftUI
import Foundation
import UIKit

enum Theme {
    /// Control panel sliders.
    static let yellow = Color(red: 247 / 255, green: 239 / 255, blue: 105 / 255)
    static let cyan = Color(red: 38 / 255, green: 244 / 255, blue: 224 / 255)

    /// Android logo colour, used at the end of the forced boot animation.
    static let androidGreen = Color(red: 61 / 255, green: 220 / 255, blue: 132 / 255)
}

/// Runs `work` on the main queue after `seconds`.
func after(_ seconds: Double, _ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
}

func clamp01(_ x: CGFloat) -> CGFloat {
    min(1, max(0, x))
}

func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255)
}

/// The key window's safe area (the home screen ignores the safe area, so apps ask for it here).
enum SafeArea {
    static var insets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}

// MARK: - Wallpapers

/// A wallpaper: a vertical gradient with a couple of soft glows on top.
struct WallpaperPreset: Identifiable {
    let id: Int
    let name: String
    let stops: [Color]
    let glows: [(color: Color, center: UnitPoint, radius: CGFloat)]

    static let all: [WallpaperPreset] = [
        WallpaperPreset(
            id: 0, name: "Ocean",
            stops: [rgb(55, 105, 235), rgb(44, 144, 226), rgb(37, 175, 222)],
            glows: [(rgb(120, 220, 255), .init(x: 0.85, y: 0.15), 0.6), (rgb(40, 60, 200), .init(x: 0.1, y: 0.9), 0.7)]
        ),
        WallpaperPreset(
            id: 1, name: "Sunset",
            stops: [rgb(58, 28, 113), rgb(215, 72, 110), rgb(255, 166, 94)],
            glows: [(rgb(255, 210, 120), .init(x: 0.2, y: 0.85), 0.6), (rgb(120, 40, 170), .init(x: 0.9, y: 0.1), 0.6)]
        ),
        WallpaperPreset(
            id: 2, name: "Aurora",
            stops: [rgb(8, 20, 40), rgb(12, 70, 80), rgb(20, 140, 110)],
            glows: [(rgb(80, 255, 180), .init(x: 0.3, y: 0.35), 0.55), (rgb(130, 80, 255), .init(x: 0.85, y: 0.2), 0.5)]
        ),
        WallpaperPreset(
            id: 3, name: "Blossom",
            stops: [rgb(255, 200, 215), rgb(236, 160, 200), rgb(180, 150, 230)],
            glows: [(rgb(255, 255, 255), .init(x: 0.2, y: 0.2), 0.5), (rgb(255, 120, 170), .init(x: 0.85, y: 0.8), 0.55)]
        ),
        WallpaperPreset(
            id: 4, name: "Forest",
            stops: [rgb(20, 50, 35), rgb(40, 100, 60), rgb(140, 170, 80)],
            glows: [(rgb(210, 240, 140), .init(x: 0.8, y: 0.25), 0.55), (rgb(10, 40, 30), .init(x: 0.1, y: 0.95), 0.6)]
        ),
        WallpaperPreset(
            id: 5, name: "Graphite",
            stops: [rgb(28, 28, 32), rgb(54, 56, 64), rgb(92, 96, 108)],
            glows: [(rgb(160, 170, 200), .init(x: 0.8, y: 0.2), 0.5), (rgb(10, 10, 12), .init(x: 0.2, y: 0.9), 0.6)]
        ),
        WallpaperPreset(
            id: 6, name: "Lava",
            stops: [rgb(30, 5, 5), rgb(140, 20, 20), rgb(255, 110, 30)],
            glows: [(rgb(255, 200, 60), .init(x: 0.5, y: 0.95), 0.6), (rgb(90, 0, 40), .init(x: 0.9, y: 0.1), 0.5)]
        ),
        WallpaperPreset(
            id: 7, name: "Mint",
            stops: [rgb(210, 250, 240), rgb(150, 225, 215), rgb(90, 190, 200)],
            glows: [(rgb(255, 255, 255), .init(x: 0.75, y: 0.2), 0.5), (rgb(60, 160, 190), .init(x: 0.15, y: 0.85), 0.55)]
        ),
    ]

    static func preset(_ index: Int) -> WallpaperPreset {
        all[min(max(index, 0), all.count - 1)]
    }
}

/// The chosen wallpaper, filling whatever frame it is given.
struct Wallpaper: View {
    @EnvironmentObject private var os: OSSettings
    /// Show a specific preset instead of the chosen one (thumbnails).
    var preset: WallpaperPreset?

    var body: some View {
        let paper = preset ?? WallpaperPreset.preset(os.wallpaper)
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: paper.stops, startPoint: .top, endPoint: .bottom)
                ForEach(0..<paper.glows.count, id: \.self) { index in
                    let glow = paper.glows[index]
                    RadialGradient(
                        colors: [glow.color.opacity(0.75), glow.color.opacity(0)],
                        center: glow.center,
                        startRadius: 0,
                        endRadius: size * glow.radius
                    )
                }
                // Dark mode dims the wallpaper a little, like One UI.
                if preset == nil && os.theme == .dark {
                    Color.black.opacity(0.18)
                }
            }
        }
    }
}

// MARK: - Glass

/// Tinted glass: the blurred background with a white (light theme) or black (dark theme) tint
/// and a thin highlight on the rim.
struct Glass<S: Shape>: View {
    let shape: S
    /// Multiplies the tint strength (1 = the user's setting).
    var tint: Double = 1

    @EnvironmentObject private var os: OSSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let amount = (0.12 + os.glassTint * 0.5) * tint
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(dark ? Color.black.opacity(amount) : Color.white.opacity(amount)))
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(dark ? 0.28 : 0.7), Color.white.opacity(dark ? 0.04 : 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
    }
}

/// A glass panel placed at `rect` on the screen.
struct GlassSurface<S: Shape>: View {
    let shape: S
    let rect: CGRect
    var opacity: Double = 1
    var tint: Double = 1

    var body: some View {
        Glass(shape: shape, tint: tint)
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .opacity(opacity)
            .position(x: rect.midX, y: rect.midY)
    }
}

extension View {
    /// Puts tinted glass behind the view.
    func glass<S: Shape>(_ shape: S, tint: Double = 1) -> some View {
        background(Glass(shape: shape, tint: tint))
    }
}

// MARK: - Buttons

/// Dims its label while the button is held down. Icons use this instead of scaling, because an icon
/// that turns into a window has to be exactly the size the window starts from.
struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Scales its label while the button is held down.
struct PressScaleStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Icons

/// An app icon: a soft gradient square with a white glyph.
struct AppIconView: View {
    let item: HomeItem
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [item.color.opacity(0.78), item.color], startPoint: .top, endPoint: .bottom))
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white))
            Image(systemName: item.symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
    }
}

/// The status-bar clock (e.g. 11:20).
struct ClockText: View {
    let size: CGFloat
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.string(for: context.date, h24: os.clock24h))
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
        }
    }

    static func string(for date: Date, h24: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = h24 ? "H:mm" : "h:mm"
        return formatter.string(from: date)
    }
}

/// Frames per second, for the Lab panel's FPS overlay.
final class FPSCounter: NSObject, ObservableObject {
    @Published var fps: Int = 0
    private var link: CADisplayLink?
    private var frames = 0
    private var start: CFTimeInterval = 0

    func run(_ on: Bool) {
        link?.invalidate()
        link = nil
        guard on else { return }
        frames = 0
        start = CACurrentMediaTime()
        let newLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    @objc private func tick(_ link: CADisplayLink) {
        frames += 1
        let elapsed = link.timestamp - start
        if elapsed >= 0.5 {
            fps = Int((Double(frames) / elapsed).rounded())
            frames = 0
            start = link.timestamp
        }
    }
}
