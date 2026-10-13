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

    /// The seed's hue and saturation. Material keeps the seed's hue in every role and varies chroma and tone.
    private static var seed: (h: CGFloat, s: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(AppTheme.shared.accentColor).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s)
    }

    /// A colour of the seed's hue (turned by `hueShift`, in turns) at a given saturation and lightness (HSL, all 0...1).
    private static func tone(_ saturation: CGFloat, _ lightness: CGFloat, hueShift: CGFloat = 0) -> UIColor {
        let h = (seed.h + hueShift).truncatingRemainder(dividingBy: 1), s = saturation, l = lightness
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch hp {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default:   (r, g, b) = (c, 0, x)
        }
        let m = l - c / 2
        return UIColor(red: r + m, green: g + m, blue: b + m, alpha: 1)
    }

    /// One role: its lightness in light and in dark mode, at a saturation relative to the seed's.
    private static func role(sat: CGFloat, light: CGFloat, dark: CGFloat) -> UIColor {
        UIColor { traits in
            let s = min(max(seed.s, 0.35), 0.85) * sat
            return tone(s, traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    static var primary: UIColor { role(sat: 1, light: 0.40, dark: 0.80) }
    static var onPrimary: UIColor { role(sat: 1, light: 0.99, dark: 0.20) }
    static var primaryContainer: UIColor { role(sat: 0.8, light: 0.90, dark: 0.30) }
    static var onPrimaryContainer: UIColor { role(sat: 0.8, light: 0.10, dark: 0.90) }
    static var secondaryContainer: UIColor { role(sat: 0.3, light: 0.89, dark: 0.30) }
    static var surface: UIColor { role(sat: 0.10, light: 0.98, dark: 0.06) }
    static var surfaceContainerLow: UIColor { role(sat: 0.12, light: 0.96, dark: 0.10) }
    static var surfaceContainer: UIColor { role(sat: 0.14, light: 0.94, dark: 0.12) }
    static var surfaceContainerHigh: UIColor { role(sat: 0.14, light: 0.92, dark: 0.17) }
    static var surfaceContainerHighest: UIColor { role(sat: 0.14, light: 0.90, dark: 0.22) }
    static var onSurface: UIColor { role(sat: 0.08, light: 0.10, dark: 0.90) }
    static var onSurfaceVariant: UIColor { role(sat: 0.10, light: 0.30, dark: 0.80) }
    static var outline: UIColor { role(sat: 0.08, light: 0.50, dark: 0.60) }
    static var outlineVariant: UIColor { role(sat: 0.08, light: 0.80, dark: 0.30) }

    // MARK: Material You for apps on the translation layer

    /// Whether apps on the translation layer get this palette as Android's dynamic colours (Material You).
    static let appsKey = "huskpatch.material3.apps"

    /// The 65 framework colours Android 12+ makes from the wallpaper, in android.R.color id order: system_neutral1,
    /// system_neutral2, system_accent1, system_accent2, system_accent3, each shade 0, 10, 50, 100 ... 900, 1000.
    /// A shade's lightness is Material's tone: shade 0 is white, 1000 black.
    static func dynamicColors() -> [UInt32] {
        let shades: [CGFloat] = [0, 10, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
        let s = min(max(seed.s, 0.35), 0.85)
        // (saturation, hue shift) of each palette, as Material derives them from the seed
        let palettes: [(CGFloat, CGFloat)] = [(s * 0.08, 0), (s * 0.16, 0), (s, 0), (s * 0.33, 0), (s * 0.5, 1.0 / 6)]
        var out: [UInt32] = []
        for (sat, shift) in palettes {
            for shade in shades {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                tone(sat, 1 - shade / 1000, hueShift: shift).getRed(&r, green: &g, blue: &b, alpha: &a)
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

/// Material 3's switch: a 52 × 32 track, a thumb that grows from 16 to 24 points when on and carries a check mark,
/// and an outlined track when off.
struct Material3SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(Color(uiColor: configuration.isOn ? Material3.primary : Material3.surfaceContainerHighest))
                    .overlay(Capsule().stroke(Color(uiColor: Material3.outline), lineWidth: configuration.isOn ? 0 : 2))
                    .frame(width: 52, height: 32)
                Circle()
                    .fill(Color(uiColor: configuration.isOn ? Material3.onPrimary : Material3.outline))
                    .frame(width: configuration.isOn ? 24 : 16, height: configuration.isOn ? 24 : 16)
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                        }
                    }
                    .padding(.horizontal, configuration.isOn ? 4 : 8)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
    }
}

/// Applied once at the root: the switch style and the rounded face, when the Android 16 style is on.
struct Material3Root: ViewModifier {
    @AppStorage(Material3.key) private var on = false

    func body(content: Content) -> some View {
        if on {
            if #available(iOS 16.1, *) {
                content.toggleStyle(Material3SwitchStyle()).fontDesign(.rounded)
            } else {
                content.toggleStyle(Material3SwitchStyle())
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
        (.help, "FAQ", "questionmark.circle"),
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
struct Material3Tabs<Home: View, Library: View, Store: View, Help: View, Settings: View>: View {
    @Binding var selection: HuskTab
    let home: Home, library: Library, store: Store, help: Help, settings: Settings

    var body: some View {
        ZStack {
            page(.home, home)
            page(.library, library)
            page(.store, store)
            page(.help, help)
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
