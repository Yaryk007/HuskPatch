// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: an optional Android 16 look, after Material 3 Expressive.
///
/// Off by default; Settings › Appearance › Android 16 Style turns it on. What it changes:
///
/// - Colour: a tonal palette derived from the accent colour, the way Android derives one from the
///   wallpaper. Pages sit on a faintly tinted surface, and cards on surface containers one step up.
/// - Shape: Material 3 Expressive's large, soft corners (28 pt cards) and pill-shaped buttons.
/// - Controls: Material's switch, a wide track whose thumb grows and shows a check when on.
/// - Type: the rounded system face, the nearest the phone has to Google Sans Flex.
///
/// Everything goes through `Theme`, the card and button styles and the root of the view tree, so a screen
/// that draws with those follows the setting without knowing about it.
enum Material3 {
    static let key = "huskpatch.material3"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    // MARK: tonal palette

    /// Material 3's roles are tones of a few palettes made from one seed colour: a tone is the colour's lightness L* (0 black,
    /// 100 white), so primary is "tone 40 of the primary palette" in light mode and tone 80 in dark, whatever the hue. The
    /// palettes keep the seed's hue and give each its own chroma, as Android's tonal-spot scheme does (primary 36,
    /// secondary 16, tertiary 24 turned 60 degrees, neutral 6, neutral variant 8; CAM16 chroma, about 1.3x in CIELAB).
    enum Palette { case primary, secondary, tertiary, neutral, neutralVariant, error }

    /// The seed in CIE L*C*h: (hue in degrees, chroma).
    private static var seedLCh: (h: Double, c: Double) {
        let lab = Lab(UIColor(AppTheme.shared.accentColor))
        return (atan2(lab.b, lab.a) * 180 / .pi, (lab.a * lab.a + lab.b * lab.b).squareRoot())
    }

    private static func hueAndChroma(_ p: Palette) -> (Double, Double) {
        let seed = seedLCh
        // a grey seed makes grey palettes, as Android's "monochrome" style does
        let k = min(1, seed.c / 18)
        switch p {
        case .primary: return (seed.h, max(min(seed.c, 62), 47) * k)
        case .secondary: return (seed.h, 21 * k)
        case .tertiary: return (seed.h + 60, 31 * k)
        case .neutral: return (seed.h, 8 * k)
        case .neutralVariant: return (seed.h, 11 * k)
        case .error: return (35, 70)
        }
    }

    /// Tone `tone` (L*, 0...100) of a palette, brought into sRGB by giving up chroma rather than tone.
    static func tone(_ p: Palette, _ tone: Double) -> UIColor {
        let (h, c) = hueAndChroma(p)
        return Lab.color(l: tone, chroma: c, hue: h)
    }

    /// One role: its tone in light and in dark mode.
    private static func role(_ p: Palette, _ light: Double, _ dark: Double) -> UIColor {
        UIColor { traits in tone(p, traits.userInterfaceStyle == .dark ? dark : light) }
    }

    static var primary: UIColor { role(.primary, 40, 80) }
    static var onPrimary: UIColor { role(.primary, 100, 20) }
    static var primaryContainer: UIColor { role(.primary, 90, 30) }
    static var onPrimaryContainer: UIColor { role(.primary, 10, 90) }
    static var secondary: UIColor { role(.secondary, 40, 80) }
    static var secondaryContainer: UIColor { role(.secondary, 90, 30) }
    static var onSecondaryContainer: UIColor { role(.secondary, 10, 90) }
    static var tertiary: UIColor { role(.tertiary, 40, 80) }
    static var tertiaryContainer: UIColor { role(.tertiary, 90, 30) }
    static var onTertiaryContainer: UIColor { role(.tertiary, 10, 90) }
    static var error: UIColor { role(.error, 40, 80) }
    static var errorContainer: UIColor { role(.error, 90, 30) }
    static var surface: UIColor { role(.neutral, 98, 6) }
    static var surfaceDim: UIColor { role(.neutral, 87, 6) }
    static var surfaceBright: UIColor { role(.neutral, 98, 24) }
    static var surfaceContainerLowest: UIColor { role(.neutral, 100, 4) }
    static var surfaceContainerLow: UIColor { role(.neutral, 96, 10) }
    static var surfaceContainer: UIColor { role(.neutral, 94, 12) }
    static var surfaceContainerHigh: UIColor { role(.neutral, 92, 17) }
    static var surfaceContainerHighest: UIColor { role(.neutral, 90, 22) }
    static var onSurface: UIColor { role(.neutral, 10, 90) }
    static var inverseSurface: UIColor { role(.neutral, 20, 90) }
    static var inverseOnSurface: UIColor { role(.neutral, 95, 20) }
    static var onSurfaceVariant: UIColor { role(.neutralVariant, 30, 80) }
    static var outline: UIColor { role(.neutralVariant, 50, 60) }
    static var outlineVariant: UIColor { role(.neutralVariant, 80, 30) }

    /// The palette as ExpressiveUI's components read it (its switch, buttons, menus, progress and loading indicators).
    static func expressive(_ scheme: ColorScheme) -> ExpressiveColors {
        let t = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        func c(_ u: UIColor) -> Color { Color(uiColor: u.resolvedColor(with: t)) }
        return ExpressiveColors(primary: c(primary), onPrimary: c(onPrimary), onPrimaryContainer: c(onPrimaryContainer),
                                surfaceContainerHighest: c(surfaceContainerHighest), outline: c(outline),
                                primaryContainer: c(primaryContainer), surfaceContainer: c(surfaceContainer),
                                onSurfaceVariant: c(onSurfaceVariant), onSurface: c(onSurface),
                                surfaceContainerLow: c(surfaceContainerLow), secondaryContainer: c(secondaryContainer),
                                onSecondaryContainer: c(onSecondaryContainer), outlineVariant: c(outlineVariant),
                                tertiaryContainer: c(tertiaryContainer), onTertiaryContainer: c(onTertiaryContainer))
    }

    // MARK: Material You for apps on the translation layer

    /// Whether apps on the translation layer get this palette as Android's dynamic colours (Material You).
    static let appsKey = "huskpatch.material3.apps"

    /// The 65 framework colours Android 12+ makes from the wallpaper, in android.R.color id order: system_neutral1,
    /// system_neutral2, system_accent1, system_accent2, system_accent3, each shade 0, 10, 50, 100 ... 900, 1000.
    /// A shade's lightness is Material's tone: shade 0 is white, 1000 black.
    static func dynamicColors() -> [UInt32] {
        let shades: [Double] = [0, 10, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
        let palettes: [Palette] = [.neutral, .neutralVariant, .primary, .secondary, .tertiary]
        var out: [UInt32] = []
        for p in palettes {
            for shade in shades {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                tone(p, 100 - shade / 10).getRed(&r, green: &g, blue: &b, alpha: &a)
                let byte = { (v: CGFloat) in UInt32((min(max(v, 0), 1) * 255).rounded()) }
                out.append(0xFF00_0000 | byte(r) << 16 | byte(g) << 8 | byte(b))
            }
        }
        return out
    }

    /// Hand the palette to the Java runtime (husk/DynamicColors.java reads HUSK_DYNAMIC_COLORS), or take it back.
    /// An app reads it once as it starts, and one app runs per launch of Husk, so a change applies from the next app.
    static func exportDynamicColors() {
        if UserDefaults.standard.bool(forKey: appsKey) {
            let value = dynamicColors().map { String(format: "%08X", $0) }.joined(separator: ",")
            setenv("HUSK_DYNAMIC_COLORS", value, 1)
        } else {
            unsetenv("HUSK_DYNAMIC_COLORS")
        }
    }

    // MARK: shape

    /// Material 3 Expressive's "extra large" corner, for cards and tiles.
    static let cardCorner: CGFloat = 28
    /// Its "large" corner, for rows and smaller containers.
    static let rowCorner: CGFloat = 20

    // MARK: bars

    /// The navigation bars at the top of each page are UIKit's, and read their appearance when they are built, so this
    /// runs at launch. (The tab bar is replaced outright: see Material3NavigationBar.)
    static func applyBars() {
        guard isOn else { return }
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = surface
        nav.shadowColor = .clear
        // Material's top app bar titles are regular weight, not bold: titleLarge (22) and headlineMedium (28) for the large one.
        nav.titleTextAttributes = [.foregroundColor: onSurface, .font: rounded(22, .regular)]
        nav.largeTitleTextAttributes = [.foregroundColor: onSurface, .font: rounded(32, .regular)]
        // Material 3 Expressive's back button: an arrow in a tonal circle, with no "Back" text beside it.
        let back = backButtonImage()
        nav.setBackIndicatorImage(back, transitionMaskImage: back.withRenderingMode(.alwaysTemplate))
        let hidden: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear, .font: UIFont.systemFont(ofSize: 0.1)]
        nav.backButtonAppearance.normal.titleTextAttributes = hidden
        nav.backButtonAppearance.highlighted.titleTextAttributes = hidden
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = primary

        // Segmented buttons: the chosen segment on secondary container, the rest on the surface, in the rounded face.
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = secondaryContainer
        seg.backgroundColor = surfaceContainer
        seg.setTitleTextAttributes([.foregroundColor: onSurfaceVariant, .font: rounded(14, .medium)], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: onSurface, .font: rounded(14, .semibold)], for: .selected)
        UISlider.appearance().minimumTrackTintColor = primary
    }

    private static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    /// The back button: a 40-point secondary-container circle with Material's arrow_back in it, in light and dark.
    private static func backButtonImage() -> UIImage {
        func draw(_ style: UIUserInterfaceStyle) -> UIImage {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let fill = secondaryContainer.resolvedColor(with: traits)
            let ink = onSurface.resolvedColor(with: traits)
            let size = CGSize(width: 48, height: 40)
            let arrow = UIImage(systemName: "arrow.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))?
                .withTintColor(ink, renderingMode: .alwaysOriginal)
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                fill.setFill()
                UIBezierPath(ovalIn: CGRect(x: 4, y: 0, width: 40, height: 40)).fill()
                if let arrow {
                    arrow.draw(in: CGRect(x: 4 + (40 - arrow.size.width) / 2, y: (40 - arrow.size.height) / 2,
                                          width: arrow.size.width, height: arrow.size.height))
                }
            }
        }
        let light = draw(.light), dark = draw(.dark)
        let asset = UIImageAsset()
        asset.register(light, with: UITraitCollection(userInterfaceStyle: .light))
        asset.register(dark, with: UITraitCollection(userInterfaceStyle: .dark))
        return asset.image(with: UITraitCollection.current).withRenderingMode(.alwaysOriginal)
    }
}

/// Material 3's switch, now ExpressiveUI's (built from the spec's SwitchTokens: the thumb grows to 28 while pressed, the
/// check is drawn in onPrimaryContainer, and it springs at Material's rates), in HuskPatch's palette.
struct Material3SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Material3Colors { ExpressiveSwitchStyle().makeBody(configuration: configuration) }
    }
}

/// HuskPatch's palette under `content`, for ExpressiveUI's components, in the scheme in effect.
struct Material3Colors<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var theme = AppTheme.shared
    @ViewBuilder let content: Content

    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        content.expressiveColors(Material3.expressive(scheme))
    }
}

/// Applied once at the root: the switch style and the rounded face, when the Android 16 style is on.
struct Material3Root: ViewModifier {
    @AppStorage(Material3.key) private var on = false

    func body(content: Content) -> some View {
        if on {
            if #available(iOS 16.1, *) {
                Material3Colors { content.toggleStyle(Material3SwitchStyle()).fontDesign(.rounded) }
            } else {
                Material3Colors { content.toggleStyle(Material3SwitchStyle()) }
            }
        } else {
            content
        }
    }
}

extension Theme {
    /// The shape of a filled button: a pill in the Android 16 style, Husk's rounded rectangle otherwise.
    static func buttonShape(_ corner: CGFloat = 15) -> AnyShape {
        Material3.isOn ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - navigation bar

/// Android's navigation bar, as Material 3 Expressive draws it: a surface-container band along the bottom,
/// each destination an outlined icon over its label, and the selected one filled, with a pill behind it that
/// springs open when it is chosen.
struct Material3NavigationBar: View {
    @Binding var selection: HuskTab

    private static let items: [(tab: HuskTab, title: String, icon: String)] = [
        (.home, "Home", "house"),
        (.library, "Library", "square.grid.2x2"),
        (.store, "Store", "cart"),
        (.settings, "Settings", "gearshape"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.items, id: \.tab) { item in
                destination(item.tab, item.title, item.icon)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: Material3.surfaceContainer).ignoresSafeArea(edges: .bottom))
    }

    private func destination(_ tab: HuskTab, _ title: String, _ icon: String) -> some View {
        let selected = selection == tab
        return Button {
            if selection != tab {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) { selection = tab }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Capsule()
                        .fill(Color(uiColor: Material3.secondaryContainer))
                        .frame(width: selected ? 64 : 24, height: 32)
                        .opacity(selected ? 1 : 0)
                    Image(systemName: selected ? icon + ".fill" : icon)
                        .font(.system(size: 20, weight: selected ? .semibold : .regular))
                        .foregroundStyle(Color(uiColor: selected ? Material3.onSurface : Material3.onSurfaceVariant))
                }
                .frame(height: 32)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: selected ? Material3.onSurface : Material3.onSurfaceVariant))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The tabs without UIKit's tab bar, for the Android 16 style: every tab stays built (each keeps where it was, as it
/// does in a TabView) and only the chosen one is shown, above Material3NavigationBar.
struct Material3Tabs<Home: View, Library: View, Store: View, Settings: View>: View {
    @Binding var selection: HuskTab
    let home: Home, library: Library, store: Store, settings: Settings

    var body: some View {
        ZStack {
            page(.home, home)
            page(.library, library)
            page(.store, store)
            page(.settings, settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Material3NavigationBar(selection: $selection)
        }
    }

    private func page<V: View>(_ tab: HuskTab, _ view: V) -> some View {
        view
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
    }
}

// MARK: - search bar

/// Material 3's search bar: a full-width, 56-point pill on a surface container, a magnifier at the start and a clear
/// button at the end, as the Play Store draws its own.
struct Material3SearchBar: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            TextField(prompt, text: $text)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A screen's search: Material's bar under the title in the Android 16 style, iOS's `.searchable` otherwise. On iOS 26
/// `.searchable` places its field beside the system tab bar, which the Android 16 style replaces -- so there it had
/// nowhere to appear.
struct HuskSearch: ViewModifier {
    @Binding var text: String
    let prompt: String
    @AppStorage(Material3.key) private var material = false

    func body(content: Content) -> some View {
        if material {
            content.safeAreaInset(edge: .top, spacing: 0) {
                Material3SearchBar(text: $text, prompt: prompt)
                    .background(Color(uiColor: Material3.surface))
            }
        } else {
            content.searchable(text: $text, prompt: prompt)
        }
    }
}

extension View {
    func huskSearchable(text: Binding<String>, prompt: String) -> some View {
        modifier(HuskSearch(text: text, prompt: prompt))
    }
}

// MARK: - CIELAB

/// CIE L*a*b* (D65) for the tonal palette: Material's tone is L*.
struct Lab {
    var l: Double, a: Double, b: Double

    init(l: Double, a: Double, b: Double) { self.l = l; self.a = a; self.b = b }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &bl, alpha: &al) {
            var w: CGFloat = 0
            color.getWhite(&w, alpha: &al); r = w; g = w; bl = w
        }
        func lin(_ v: CGFloat) -> Double { let v = Double(min(max(v, 0), 1)); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let R = lin(r), G = lin(g), B = lin(bl)
        let x = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B) / 0.95047
        let y = 0.2126729 * R + 0.7151522 * G + 0.0721750 * B
        let z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        l = 116 * f(y) - 16; a = 500 * (f(x) - f(y)); b = 200 * (f(y) - f(z))
    }

    /// sRGB, or nil when out of gamut.
    var rgb: (Double, Double, Double)? {
        let fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        func inv(_ t: Double) -> Double { let t3 = t * t * t; return t3 > 216.0 / 24389 ? t3 : (116 * t - 16) / (24389.0 / 27) }
        let x = inv(fx) * 0.95047, y = l > 8 ? fy * fy * fy : l / (24389.0 / 27), z = inv(fz) * 1.08883
        let R = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let G = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let B = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        let e = 0.0001
        guard (-e...1 + e).contains(R), (-e...1 + e).contains(G), (-e...1 + e).contains(B) else { return nil }
        func gam(_ v: Double) -> Double { let v = min(max(v, 0), 1); return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        return (gam(R), gam(G), gam(B))
    }

    /// L* `l` at `hue`, with as much of `chroma` as sRGB can show at that tone.
    static func color(l: Double, chroma: Double, hue: Double) -> UIColor {
        let rad = hue * .pi / 180
        var lo = 0.0, hi = chroma
        var best = Lab(l: l, a: 0, b: 0).rgb ?? (l / 100, l / 100, l / 100)
        if let full = Lab(l: l, a: cos(rad) * chroma, b: sin(rad) * chroma).rgb { best = full; lo = chroma }
        else {
            for _ in 0..<14 {
                let mid = (lo + hi) / 2
                if let c = Lab(l: l, a: cos(rad) * mid, b: sin(rad) * mid).rgb { best = c; lo = mid } else { hi = mid }
            }
        }
        return UIColor(red: best.0, green: best.1, blue: best.2, alpha: 1)
    }
}
