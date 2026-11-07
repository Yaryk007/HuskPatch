import SwiftUI
import UIKit

/// ModemOS has two complete looks. Every surface, control, icon and app reads the chosen one from here, so turning one on
/// changes the whole system rather than a few screens.
enum OSDesign: String, CaseIterable, Identifiable {
    /// Material 3 Expressive: tonal surfaces from the wallpaper's colour, big shapes, springy controls (ExpressiveUI).
    case expressive
    /// Liquid Glass: real glass on iOS 26 and later, over the wallpaper.
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expressive: return "Material 3 Expressive"
        case .liquidGlass: return "Liquid Glass"
        }
    }

    var detail: String {
        switch self {
        case .expressive: return "Tonal colours from your wallpaper, bold shapes and springy motion"
        case .liquidGlass: return "Clear glass that bends the light of what is behind it"
        }
    }

    var symbol: String {
        switch self {
        case .expressive: return "paintpalette.fill"
        case .liquidGlass: return "drop.fill"
        }
    }
}

/// HuskPatch's Info.plist keeps the old design (UIDesignRequiresCompatibility), so its own screens do not change. This
/// default overrides that for one process: UIKit and SwiftUI read it as the process starts and keep the answer, so the
/// switch works from the next launch. ModemOS reads the launch value once to know which glass it really has.
enum LiquidGlass {
    static let overrideKey = "com.apple.SwiftUI.IgnoreSolariumOptOut"

    /// Whether the system draws real Liquid Glass in this run. Touch it before the setting can change (ModemOSView.init).
    static let live: Bool = {
        guard #available(iOS 26.0, *) else { return false }
        let optedOut = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool ?? false
        return !optedOut || UserDefaults.standard.bool(forKey: overrideKey)
    }()

    static var supported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Asks for real glass from the next launch on.
    static func request(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: overrideKey)
    }

    /// Liquid Glass is chosen, the phone can draw it, and this run started without it.
    static var needsRestart: Bool {
        supported && !live && OSSettings.shared.design == .liquidGlass
    }
}

// MARK: - Colour

/// CIE LCh to sRGB, for tonal palettes: `l` is the tone (0 black to 100 white), which is what Material's tones are.
private func lchColor(_ l: Double, _ c: Double, _ h: Double) -> Color {
    let rad = h * .pi / 180
    let a = c * cos(rad), b = c * sin(rad)
    let fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
    func inv(_ t: Double) -> Double { t > 6.0 / 29 ? t * t * t : 3 * pow(6.0 / 29, 2) * (t - 4.0 / 29) }
    let x = 0.95047 * inv(fx), y = inv(fy), z = 1.08883 * inv(fz)
    func gamma(_ v: Double) -> Double {
        let u = min(1, max(0, v))
        return u <= 0.0031308 ? 12.92 * u : 1.055 * pow(u, 1 / 2.4) - 0.055
    }
    return Color(
        .sRGB,
        red: gamma(3.2406 * x - 1.5372 * y - 0.4986 * z),
        green: gamma(-0.9689 * x + 1.8758 * y + 0.0415 * z),
        blue: gamma(0.0557 * x - 0.2040 * y + 1.0570 * z),
        opacity: 1
    )
}

/// The hue of a colour in LCh, in degrees.
func labHue(_ color: Color) -> Double {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    func lin(_ v: CGFloat) -> Double {
        let u = Double(v)
        return u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4)
    }
    let R = lin(r), G = lin(g), B = lin(b)
    let x = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
    let y = 0.2126 * R + 0.7152 * G + 0.0722 * B
    let z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
    func f(_ t: Double) -> Double { t > pow(6.0 / 29, 3) ? cbrt(t) : t / (3 * pow(6.0 / 29, 2)) + 4.0 / 29 }
    let hue = atan2(200 * (f(y) - f(z)), 500 * (f(x) - f(y))) * 180 / .pi
    return hue < 0 ? hue + 360 : hue
}

/// Material's colour roles, made from one hue. Liquid Glass reads the same roles, with quieter colour.
struct OSPalette: Equatable {
    var primary, onPrimary, primaryContainer, onPrimaryContainer: Color
    var secondaryContainer, onSecondaryContainer, tertiaryContainer, onTertiaryContainer: Color
    var surface, surfaceLow, surfaceContainer, surfaceHigh, surfaceHighest: Color
    var onSurface, onSurfaceVariant, outline, outlineVariant: Color

    init(hue h: Double, dark: Bool, chroma: Double = 1) {
        let accent = 42 * chroma, soft = 18 * chroma, neutral = 5 * chroma, third = h + 60
        func t(_ light: Double, _ night: Double) -> Double { dark ? night : light }
        primary = lchColor(t(40, 80), accent, h)
        onPrimary = lchColor(t(100, 20), accent * 0.5, h)
        primaryContainer = lchColor(t(90, 30), accent * 0.8, h)
        onPrimaryContainer = lchColor(t(10, 90), accent * 0.6, h)
        secondaryContainer = lchColor(t(90, 30), soft, h)
        onSecondaryContainer = lchColor(t(10, 90), soft, h)
        tertiaryContainer = lchColor(t(90, 30), accent * 0.6, third)
        onTertiaryContainer = lchColor(t(10, 90), accent * 0.5, third)
        surface = lchColor(t(98, 6), neutral, h)
        surfaceLow = lchColor(t(96, 10), neutral, h)
        surfaceContainer = lchColor(t(94, 12), neutral, h)
        surfaceHigh = lchColor(t(92, 17), neutral, h)
        surfaceHighest = lchColor(t(90, 22), neutral, h)
        onSurface = lchColor(t(10, 92), neutral, h)
        onSurfaceVariant = lchColor(t(30, 80), neutral * 1.6, h)
        outline = lchColor(t(50, 60), neutral * 1.6, h)
        outlineVariant = lchColor(t(80, 30), neutral * 1.6, h)
    }

    /// The same roles for ExpressiveUI's components.
    var expressive: ExpressiveColors {
        ExpressiveColors(
            primary: primary, onPrimary: onPrimary, onPrimaryContainer: onPrimaryContainer,
            surfaceContainerHighest: surfaceHighest, outline: outline, primaryContainer: primaryContainer,
            surfaceContainer: surfaceContainer, onSurfaceVariant: onSurfaceVariant, onSurface: onSurface,
            surfaceContainerLow: surfaceLow, secondaryContainer: secondaryContainer,
            onSecondaryContainer: onSecondaryContainer, outlineVariant: outlineVariant,
            tertiaryContainer: tertiaryContainer, onTertiaryContainer: onTertiaryContainer
        )
    }

    /// An app's own colour as a themed icon: its hue, at the tones Android's themed icons use.
    static func iconColors(for color: Color, dark: Bool) -> (fill: Color, glyph: Color) {
        let h = labHue(color)
        return (lchColor(dark ? 28 : 88, 34, h), lchColor(dark ? 88 : 28, 48, h))
    }
}

extension OSSettings {
    /// The system's colours: the wallpaper's hue in the chosen theme and look.
    var palette: OSPalette {
        let key = PaletteKey(wallpaper: wallpaper, dark: theme == .dark, design: design)
        if let cached = Self.palettes[key] { return cached }
        let paper = WallpaperPreset.preset(wallpaper)
        let hue = labHue(paper.stops[paper.stops.count / 2])
        let made = OSPalette(hue: hue, dark: theme == .dark, chroma: design == .liquidGlass ? 0.7 : 1)
        Self.palettes[key] = made
        return made
    }

    fileprivate struct PaletteKey: Hashable {
        let wallpaper: Int
        let dark: Bool
        let design: OSDesign
    }

    fileprivate static var palettes: [PaletteKey: OSPalette] = [:]

    /// A title's typeface: Material's is rounder.
    func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: design == .expressive ? .rounded : .default)
    }

    /// The system's name and version, as About phone shows them.
    static let systemName = "ModemOS"
    static let systemVersion = "2.0"
    static let androidVersion = "16"
    static let buildNumber = "MOS2.260.11.07"
}

extension Color {
    /// The system's accent.
    static var osAccent: Color { OSSettings.shared.palette.primary }
    /// A page.
    static var osPage: Color { OSSettings.shared.palette.surface }
    /// A card on a page: tonal in Material, a light frost over the glass page otherwise.
    static var osCard: Color {
        let os = OSSettings.shared
        return os.design == .expressive ? os.palette.surfaceContainer : os.palette.onSurface.opacity(0.08)
    }
    /// A card on a card.
    static var osCardHigh: Color {
        let os = OSSettings.shared
        return os.design == .expressive ? os.palette.surfaceHighest : os.palette.onSurface.opacity(0.14)
    }
}

extension OSSettings {
    /// Changes when the whole look does: an app's views are rebuilt to pick it up.
    var lookID: String { "\(design.rawValue)-\(theme.rawValue)-\(wallpaper)" }
}

// MARK: - Surfaces

/// Behind an app. Material apps sit on a tonal page; with glass the wallpaper shows through, heavily blurred, so the app's
/// glass has something to bend.
struct OSAppBackground: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        switch os.design {
        case .expressive:
            os.palette.surface
        case .liquidGlass:
            ZStack {
                Wallpaper(preset: WallpaperPreset.preset(os.wallpaper))
                    .blur(radius: 36)
                    .scaleEffect(1.2)
                os.palette.surface.opacity(os.theme == .dark ? 0.62 : 0.5)
            }
            .clipped()
        }
    }
}

/// What every panel, sheet, card and bar is made of.
struct Glass<S: Shape>: View {
    let shape: S
    /// Multiplies the tint strength (1 = the user's setting).
    var tint: Double = 1

    @EnvironmentObject private var os: OSSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch os.design {
        case .expressive:
            shape.fill(tint > 1 ? os.palette.surfaceHigh : os.palette.surfaceContainer)
        case .liquidGlass:
            if LiquidGlass.live, #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                material
            }
        }
    }

    /// The closest thing before iOS 26, or until the restart that turns real glass on.
    private var material: some View {
        let dark = scheme == .dark
        let amount = (0.12 + os.glassTint * 0.5) * tint
        return shape
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

/// A panel placed at `rect` on the screen.
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
    /// Puts the system's surface behind the view.
    func glass<S: Shape>(_ shape: S, tint: Double = 1) -> some View {
        background(Glass(shape: shape, tint: tint))
    }
}
