import SwiftUI

enum OSLanguage: String, CaseIterable, Identifiable {
    case english = "en", ukrainian = "uk", spanish = "es", german = "de", french = "fr"
    case italian = "it", portuguese = "pt", polish = "pl", japanese = "ja"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .ukrainian: return "Українська"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .polish: return "Polski"
        case .japanese: return "日本語"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .ukrainian: return "🇺🇦"
        case .spanish: return "🇪🇸"
        case .german: return "🇩🇪"
        case .french: return "🇫🇷"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇵🇹"
        case .polish: return "🇵🇱"
        case .japanese: return "🇯🇵"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case light, dark

    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var title: String { self == .dark ? "Dark" : "Light" }
}

enum NavMode: String, CaseIterable, Identifiable {
    case gestures, buttons

    var id: String { rawValue }
    var title: String { self == .gestures ? "Swipe gestures" : "Three buttons" }
}

/// The Recents screen layout.
enum RecentsLayout: String, CaseIterable, Identifiable {
    case carousel, grid

    var id: String { rawValue }
    var title: String { self == .carousel ? "Carousel" : "Grid" }
}

/// Where a Custom animation starts from.
enum AnimOrigin: String, CaseIterable, Identifiable {
    case icon, center, bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: return "Icon"
        case .center: return "Center"
        case .bottom: return "Bottom"
        }
    }
}

/// How apps open and close. Every style can be grabbed mid-flight, and its speed comes from `OSSettings.animSpeed`.
enum AnimStyle: String, CaseIterable, Identifiable {
    /// Home Up "Classic": the icon grows into the app, the home screen sinks back.
    case oneUI
    /// Home Up "Elegance": slow and see-through, with a long ghost trail and a strong colour wash.
    case elegance
    /// Home Up "Dynamic": fast, with a little overshoot and a short trail.
    case dynamic
    /// Home Up "Sweet": soft and squishy, with a bounce and an icon ripple when an app lands back home.
    case sweet
    /// The app zooms in from the middle of the screen.
    case zoom
    /// The app slides up from the bottom.
    case slide
    /// A quick crossfade.
    case fade
    /// Built in the Lab: origin, durations, size, fade, corners, spin, icon fade.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneUI: return "Classic"
        case .elegance: return "Elegance"
        case .dynamic: return "Dynamic"
        case .sweet: return "Sweet"
        case .zoom: return "Zoom"
        case .slide: return "Slide"
        case .fade: return "Fade"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .oneUI: return "Feel the classic sensibility"
        case .elegance: return "How about feeling as elegant as possible?"
        case .dynamic: return "If you want a faster and more dynamic feel"
        case .sweet: return "Soft bounce and an icon ripple"
        case .zoom: return "Zooms in from the centre"
        case .slide: return "Slides up from the bottom"
        case .fade: return "A quick crossfade"
        case .custom: return "Your own animation, built in the Lab"
        }
    }

    var symbol: String {
        switch self {
        case .oneUI: return "square.on.square"
        case .elegance: return "wind"
        case .dynamic: return "bolt.fill"
        case .sweet: return "sparkles"
        case .zoom: return "plus.magnifyingglass"
        case .slide: return "arrow.up.square"
        case .fade: return "circle.lefthalf.filled"
        case .custom: return "slider.horizontal.3"
        }
    }

    var openResponse: CGFloat {
        switch self {
        case .oneUI: return 0.5
        case .elegance: return 0.62
        case .dynamic: return 0.36
        case .sweet: return 0.62
        case .zoom: return 0.42
        case .slide: return 0.48
        case .fade: return 0.34
        case .custom: return CGFloat(OSSettings.shared.customOpen)
        }
    }

    var closeResponse: CGFloat {
        switch self {
        case .oneUI: return 0.46
        case .elegance: return 0.6
        case .dynamic: return 0.32
        case .sweet: return 0.56
        case .zoom: return 0.36
        case .slide: return 0.42
        case .fade: return 0.3
        case .custom: return CGFloat(OSSettings.shared.customClose)
        }
    }

    /// The style's own damping before the Bounce setting (1 = no bounce).
    var damping: CGFloat {
        switch self {
        case .sweet: return 0.62
        case .dynamic: return 0.78
        case .slide: return 0.9
        default: return 1
        }
    }
}

/// Everything the user can change (setup, the Lab panel and the Settings app), saved between launches.
final class OSSettings: ObservableObject {
    static let shared = OSSettings()

    private let defaults = OSSettings.store

    @Published var setupDone: Bool { didSet { save(setupDone, "setupDone") } }
    @Published var language: OSLanguage { didSet { save(language.rawValue, "language") } }
    @Published var theme: ThemeMode { didSet { save(theme.rawValue, "theme") } }
    @Published var wallpaper: Int { didSet { save(wallpaper, "wallpaper") } }
    @Published var navMode: NavMode { didSet { save(navMode.rawValue, "navMode") } }

    // Motion
    @Published var animStyle: AnimStyle { didSet { save(animStyle.rawValue, "animStyle") } }
    /// 0.25 = four times slower, 3 = three times faster.
    @Published var animSpeed: Double {
        didSet {
            Animator.durationScale = CGFloat(1 / animSpeed)
            save(animSpeed, "animSpeed")
        }
    }
    /// 0 = the style's own bounce, 1 = very bouncy (windows, drawer, panels and the ripple).
    @Published var bounce: Double { didSet { save(bounce, "bounce") } }
    /// How far the home screen sinks back while an app is open (0...0.25).
    @Published var homeZoom: Double { didSet { save(homeZoom, "homeZoom") } }
    /// How much the home screen blurs behind an app (0 = off).
    @Published var blurStrength: Double { didSet { save(blurStrength, "blurStrength") } }
    /// How much the home screen darkens behind an app.
    @Published var homeDim: Double { didSet { save(homeDim, "homeDim") } }
    /// Icons grow in place as an app opens, as far as it has opened. Off unless turned on in the Lab.
    @Published var rippleEnabled: Bool { didSet { save(rippleEnabled, "rippleEnabled") } }
    /// The wallpaper and icons lean and shift at different depths while things move over them.
    @Published var parallax: Bool { didSet { save(parallax, "parallax") } }
    /// The lock screen at each start.
    @Published var lockScreen: Bool { didSet { save(lockScreen, "lockScreen") } }

    // Custom animation (Lab > Motion)
    @Published var customOrigin: AnimOrigin { didSet { save(customOrigin.rawValue, "customOrigin") } }
    @Published var customOpen: Double { didSet { save(customOpen, "customOpen") } }
    @Published var customClose: Double { didSet { save(customClose, "customClose") } }
    /// Size the window starts at when it does not start from the icon.
    @Published var customStartScale: Double { didSet { save(customStartScale, "customStartScale") } }
    @Published var customFade: Bool { didSet { save(customFade, "customFade") } }
    /// Corner radius while the window moves.
    @Published var customRadius: Double { didSet { save(customRadius, "customRadius") } }
    /// Degrees the window turns while it opens.
    @Published var customSpin: Double { didSet { save(customSpin, "customSpin") } }
    /// How fast the icon fades into the app (higher = sooner).
    @Published var customIconFade: Double { didSet { save(customIconFade, "customIconFade") } }
    /// How see-through the window gets mid-flight (0 = solid, 1 = very see-through).
    @Published var customTranslucency: Double { didSet { save(customTranslucency, "customTranslucency") } }
    /// How strongly the window washes toward its icon's colour as it shrinks.
    @Published var customTint: Double { didSet { save(customTint, "customTint") } }
    /// Ghost copies trailing behind a moving window (0...4).
    @Published var customTrail: Double { didSet { save(customTrail, "customTrail") } }
    /// How much the window squashes and stretches with its speed.
    @Published var customSquash: Double { didSet { save(customSquash, "customSquash") } }

    // App switcher
    @Published var recentsLayout: RecentsLayout { didSet { save(recentsLayout.rawValue, "recentsLayout") } }
    @Published var holdForRecents: Bool { didSet { save(holdForRecents, "holdForRecents") } }

    // Look
    /// Icon corner radius as a fraction of the icon size.
    @Published var iconRoundness: Double { didSet { save(iconRoundness, "iconRoundness") } }
    @Published var showLabels: Bool { didSet { save(showLabels, "showLabels") } }
    /// How strong the glass tint is (0...1).
    @Published var glassTint: Double { didSet { save(glassTint, "glassTint") } }

    // Home screen
    @Published var homeApps: Bool { didSet { save(homeApps, "homeApps") } }
    @Published var clockWidget: Bool { didSet { save(clockWidget, "clockWidget") } }
    @Published var dummyFolder: Bool { didSet { save(dummyFolder, "dummyFolder") } }

    // System
    @Published var clock24h: Bool { didSet { save(clock24h, "clock24h") } }
    @Published var showBattery: Bool { didSet { save(showBattery, "showBattery") } }
    @Published var haptics: Bool { didSet { save(haptics, "haptics") } }
    @Published var showFPS: Bool { didSet { save(showFPS, "showFPS") } }
    /// The long boot: logs and Tux penguins force-installing Android. Off = just the Apple logo.
    /// The forced Android boot at each start. Off: straight to the home screen.
    @Published var forcedBoot: Bool { didSet { save(forcedBoot, "forcedBoot") } }
    /// Material 3 Expressive or Liquid Glass.
    @Published var design: OSDesign {
        didSet {
            save(design.rawValue, "design")
            LiquidGlass.request(design == .liquidGlass)
            OSLogger.shared.log("Settings", "Look: \(design.title)")
        }
    }

    private init() {
        let d = OSSettings.store
        func value<T>(_ key: String, _ fallback: T) -> T { d.object(forKey: key) as? T ?? fallback }

        setupDone = d.bool(forKey: "setupDone")
        language = OSLanguage(rawValue: d.string(forKey: "language") ?? "") ?? Self.systemLanguage
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .dark
        wallpaper = value("wallpaper", 20)
        navMode = NavMode(rawValue: d.string(forKey: "navMode") ?? "") ?? .gestures
        animStyle = AnimStyle(rawValue: d.string(forKey: "animStyle") ?? "") ?? .oneUI
        animSpeed = value("animSpeed", 1.0)
        bounce = value("bounce", 0.25)
        homeZoom = value("homeZoom", 0.06)
        blurStrength = value("blurStrength", 10.0)
        homeDim = value("homeDim", 0.12)
        rippleEnabled = value("rippleEnabled", false)
        parallax = value("parallax", true)
        lockScreen = value("lockScreen", true)
        customOrigin = AnimOrigin(rawValue: d.string(forKey: "customOrigin") ?? "") ?? .icon
        customOpen = value("customOpen", 0.5)
        customClose = value("customClose", 0.45)
        customStartScale = value("customStartScale", 0.5)
        customFade = value("customFade", false)
        customRadius = value("customRadius", 40.0)
        customSpin = value("customSpin", 0.0)
        customIconFade = value("customIconFade", 2.2)
        customTranslucency = value("customTranslucency", 0.35)
        customTint = value("customTint", 0.6)
        customTrail = value("customTrail", 2.0)
        customSquash = value("customSquash", 0.0)
        recentsLayout = RecentsLayout(rawValue: d.string(forKey: "recentsLayout") ?? "") ?? .carousel
        holdForRecents = value("holdForRecents", true)
        iconRoundness = value("iconRoundness", 0.5)
        showLabels = value("showLabels", true)
        glassTint = value("glassTint", 0.5)
        homeApps = value("homeApps", true)
        clockWidget = value("clockWidget", true)
        dummyFolder = value("dummyFolder", false)
        clock24h = value("clock24h", true)
        showBattery = value("showBattery", true)
        haptics = value("haptics", true)
        showFPS = d.bool(forKey: "showFPS")
        forcedBoot = value("forcedBoot", false)
        design = OSDesign(rawValue: value("design", OSDesign.expressive.rawValue)) ?? .expressive
        Animator.durationScale = CGFloat(1 / animSpeed)
    }

    private static var systemLanguage: OSLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return OSLanguage(rawValue: String(code)) ?? .english
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        OSLogger.shared.log("Settings", "\(key) = \(value)", level: .debug)
    }

    /// Translates an English UI string into the chosen language (falls back to English).
    func t(_ english: String) -> String {
        Localization.translate(english, to: language)
    }

    /// Puts the motion settings back to how they were on first launch.
    func resetMotion() {
        animStyle = .oneUI
        animSpeed = 1
        bounce = 0.25
        homeZoom = 0.06
        blurStrength = 10
        homeDim = 0.12
        rippleEnabled = false
        parallax = true
        customOrigin = .icon
        customOpen = 0.5
        customClose = 0.45
        customStartScale = 0.5
        customFade = false
        customRadius = 40
        customSpin = 0
        customIconFade = 2.2
        customTranslucency = 0.35
        customTint = 0.6
        customTrail = 2
        customSquash = 0
    }

    /// Puts everything except the setup flag back to how it was on first launch.
    func resetAll() {
        language = Self.systemLanguage
        theme = .dark
        wallpaper = 20
        navMode = .gestures
        resetMotion()
        recentsLayout = .carousel
        holdForRecents = true
        iconRoundness = 0.5
        showLabels = true
        glassTint = 0.5
        homeApps = true
        clockWidget = true
        dummyFolder = false
        clock24h = true
        showBattery = true
        haptics = true
        showFPS = false
        forcedBoot = false
        design = .expressive
        OSLogger.shared.log("Settings", "Reset to defaults", level: .warn)
    }

    // MARK: Motion values

    /// Window opening damping: the style's own, pulled down hard by the Bounce setting.
    func openDamping(_ style: AnimStyle) -> CGFloat {
        // The Bounce slider decides alone, so turning it down always takes the bounce out.
        max(0.28, 1 - CGFloat(bounce) * 0.72)
    }

    /// Closing bounces a little less, so a window only dips slightly below its icon before settling.
    func closeDamping(_ style: AnimStyle) -> CGFloat {
        min(1, max(0.5, openDamping(style) + 0.12))
    }

    /// How many smoothing stages lead the spring: bouncy motion needs fewer, or the overshoot is smoothed away.
    func easeStages(_ style: AnimStyle) -> Int {
        bounce > 0.5 ? 0 : 1
    }

    /// Damping for the drawer, control center and Lab panel.
    var uiDamping: CGFloat { max(0.5, 1 - CGFloat(bounce) * 0.5) }
    var uiStages: Int { bounce > 0.02 ? 1 : 2 }
}

/// Where a window is on its way from its icon (p = 0) to open (p = 1), for each animation style.
/// Shared by the real windows and the Lab preview, so the preview is exactly what you get.
enum WindowMotion {
    static func morphs(_ style: AnimStyle, _ os: OSSettings) -> Bool {
        switch style {
        case .oneUI, .elegance, .dynamic, .sweet: return true
        case .custom: return os.customOrigin == .icon
        default: return false
        }
    }

    /// The Home Up look of a style while it moves.
    struct Look {
        /// How see-through the window gets at mid-flight (0 = solid).
        var translucency: CGFloat = 0
        /// How strongly it washes toward its icon's colour as it shrinks.
        var tint: CGFloat = 0
        /// Ghost copies trailing behind it.
        var trail: Int = 0
        /// Squash and stretch with speed.
        var squash: CGFloat = 0
        /// A soft white glow mid-flight.
        var glow: CGFloat = 0
    }

    static func look(_ style: AnimStyle, _ os: OSSettings) -> Look {
        switch style {
        case .oneUI: return Look(translucency: 0.1, tint: 0.35, trail: 0, squash: 0, glow: 0.08)
        case .elegance: return Look(translucency: 0.45, tint: 0.7, trail: 3, squash: 0, glow: 0.3)
        case .dynamic: return Look(translucency: 0.35, tint: 0.6, trail: 2, squash: 0.05, glow: 0.18)
        case .sweet: return Look(translucency: 0.28, tint: 0.75, trail: 1, squash: 0.14, glow: 0.22)
        case .zoom, .slide, .fade: return Look()
        case .custom:
            return Look(
                translucency: CGFloat(os.customTranslucency),
                tint: CGFloat(os.customTint),
                trail: Int(os.customTrail.rounded()),
                squash: CGFloat(os.customSquash),
                glow: CGFloat(os.customTranslucency) * 0.5
            )
        }
    }

    /// Strongest in mid-flight, zero when the window is an icon or fully open.
    static func midFlight(_ p: CGFloat) -> CGFloat {
        let q = clamp01(p)
        return pow(sin(q * .pi), 0.8)
    }

    /// The icon-colour wash: strong while the window is small, gone once it is open.
    static func tint(_ look: Look, p: CGFloat) -> Double {
        Double(look.tint * pow(1 - clamp01(p), 0.8))
    }

    static func glow(_ look: Look, p: CGFloat) -> Double {
        Double(look.glow * midFlight(p))
    }

    /// Squash and stretch: a fast window gets taller and thinner (velocity in progress units per second).
    static func squash(_ look: Look, velocity: CGFloat) -> CGSize {
        guard look.squash > 0 else { return CGSize(width: 1, height: 1) }
        let v = max(-1, min(1, velocity / 5))
        let amount = look.squash * abs(v)
        return CGSize(width: 1 - amount * 0.6, height: 1 + amount)
    }

    /// Past the icon (a bouncy close dips below 0) the window keeps shrinking around the icon's centre.
    private static func grow(_ origin: CGRect, _ full: CGRect, _ p: CGFloat) -> CGRect {
        if p >= 0 { return lerp(origin, full, p) }
        return origin.scaledAroundCenter(max(0.4, 1 + p * 1.5))
    }

    static func rect(_ style: AnimStyle, _ os: OSSettings, origin: CGRect, full: CGRect, p: CGFloat) -> CGRect {
        switch style {
        case .oneUI, .elegance, .dynamic, .sweet:
            return grow(origin, full, p)
        case .zoom:
            return full.scaledAroundCenter(max(0.05, lerp(0.4, 1, p)))
        case .slide:
            return full.offsetBy(dx: 0, dy: (1 - p) * full.height)
        case .fade:
            return full.scaledAroundCenter(max(0.05, lerp(0.9, 1, p)))
        case .custom:
            let start = CGFloat(os.customStartScale)
            switch os.customOrigin {
            case .icon:
                return grow(origin, full, p)
            case .center:
                return full.scaledAroundCenter(max(0.05, lerp(start, 1, p)))
            case .bottom:
                return full.scaledAroundCenter(max(0.05, lerp(start, 1, p)))
                    .offsetBy(dx: 0, dy: (1 - p) * full.height * 0.6)
            }
        }
    }

    static func opacity(_ style: AnimStyle, _ os: OSSettings, p: CGFloat) -> Double {
        let fades = style == .zoom || style == .fade || (style == .custom && os.customFade)
        let base = fades ? clamp01(p * 1.6) : 1
        // Home Up: see-through in mid-flight, solid as an icon and as an open app.
        let see = look(style, os).translucency * midFlight(p)
        return Double(base * (1 - see))
    }

    /// How much of the icon still shows on the growing window.
    static func iconAlpha(_ style: AnimStyle, _ os: OSSettings, p: CGFloat) -> Double {
        guard morphs(style, os) else { return 0 }
        let speed: CGFloat
        switch style {
        case .custom: speed = CGFloat(os.customIconFade)
        // Home Up keeps the colour wash going instead, and only turns solid right at the icon.
        case .elegance, .dynamic, .sweet: speed = 4.5
        default: speed = 2.2
        }
        return Double(1 - clamp01(p * speed))
    }

    static func radius(_ style: AnimStyle, _ os: OSSettings, iconRadius: CGFloat, displayRadius: CGFloat, p: CGFloat) -> CGFloat {
        let start: CGFloat
        if morphs(style, os) {
            start = iconRadius
        } else if style == .custom {
            start = CGFloat(os.customRadius)
        } else {
            start = displayRadius
        }
        return max(0, lerp(start, displayRadius, clamp01(p)))
    }

    /// Degrees the window is turned (Custom spin).
    static func rotation(_ style: AnimStyle, _ os: OSSettings, p: CGFloat) -> Double {
        style == .custom ? os.customSpin * Double(1 - p) : 0
    }
}

extension CGRect {
    func scaledAroundCenter(_ s: CGFloat) -> CGRect {
        CGRect(x: midX - width * s / 2, y: midY - height * s / 2, width: width * s, height: height * s)
    }
}

/// Taptic Engine feedback (if vibration is on).
enum Haptics {
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard OSSettings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Navigation button pressed down: a short, crisp click.
    static func navDown() {
        guard OSSettings.shared.haptics else { return }
        rigid.impactOccurred(intensity: 0.8)
        soft.prepare()
    }

    /// Navigation button released: a soft, round thump, so the press feels like a real key.
    static func navUp() {
        guard OSSettings.shared.haptics else { return }
        soft.impactOccurred(intensity: 1)
        rigid.prepare()
    }

    static func prepare() {
        rigid.prepare()
        soft.prepare()
    }
}
