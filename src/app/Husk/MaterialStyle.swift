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

    /// A colour of the seed's hue at a given saturation and lightness (HSL, both 0...1).
    private static func tone(_ saturation: CGFloat, _ lightness: CGFloat) -> UIColor {
        let h = seed.h, s = saturation, l = lightness
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
        nav.titleTextAttributes = [.foregroundColor: onSurface]
        nav.largeTitleTextAttributes = [.foregroundColor: onSurface]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
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
