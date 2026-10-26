// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Settings › Testing › System's developer toggles for Android OS mode, modelled on Android's own Developer
/// options -- the animation scale, Show taps, the refresh rate meter -- plus switches that take parts of the system UI
/// away (the status bar, the navigation bar, blur, the lock screen, heads-up notifications, the wallpaper) for a cleaner or
/// lighter phone.
enum AndroidDev {
    static let hideStatusBarKey = "huskpatch.dev.hideStatusBar"
    static let hideNavBarKey = "huskpatch.dev.hideNavBar"
    static let animationScaleKey = "huskpatch.dev.animationScale"
    static let showTouchesKey = "huskpatch.dev.showTouches"
    static let refreshRateKey = "huskpatch.dev.refreshRate"
    static let noBlurKey = "huskpatch.dev.noBlur"
    static let skipLockKey = "huskpatch.dev.skipLock"
    static let noHeadsUpKey = "huskpatch.dev.noHeadsUp"
    static let plainWallpaperKey = "huskpatch.dev.plainWallpaper"

    /// Android's animator duration scale choices; 0 is "Animation off".
    static let scales: [Double] = [0, 0.5, 1, 1.5, 2, 5, 10]

    static var animationScale: Double { UserDefaults.standard.object(forKey: animationScaleKey) as? Double ?? 1 }
    static func on(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    static func scaleTitle(_ s: Double) -> String {
        s == 0 ? "Animation off" : "Animation scale \(s.formatted(.number.precision(.fractionLength(0...1))))x"
    }

    /// Puts Show taps and the refresh rate meter on the window, or takes them off, to match the toggles.
    @MainActor static func applyOverlays() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        let showing = AndroidOS.isOn
        ShowTaps.set(showing && on(showTouchesKey), on: window)
        RefreshRateMeter.set(showing && on(refreshRateKey), on: window)
    }
}

extension View {
    /// A blur that Developer options can turn off (it is the most expensive thing the shell draws).
    func androidBlur(_ radius: CGFloat) -> some View {
        blur(radius: AndroidDev.on(AndroidDev.noBlurKey) ? 0 : radius)
    }
}

// MARK: - Show taps

/// Android's "Show taps": a pale dot under every finger, drawn in a view of its own over the whole window so it never
/// takes a touch. A gesture recogniser that never recognises sees every touch without delaying or cancelling any.
private final class ShowTaps: UIGestureRecognizer {
    private static weak var overlay: UIView?
    private var dots: [ObjectIdentifier: CALayer] = [:]

    static func set(_ on: Bool, on window: UIWindow) {
        let existing = window.gestureRecognizers?.first { $0 is ShowTaps }
        if !on {
            if let existing { window.removeGestureRecognizer(existing) }
            overlay?.removeFromSuperview()
            return
        }
        guard existing == nil else { return }
        let view = UIView(frame: window.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.layer.zPosition = 10_000
        window.addSubview(view)
        overlay = view
        let r = ShowTaps(target: nil, action: nil)
        r.cancelsTouchesInView = false
        r.delaysTouchesBegan = false
        r.delaysTouchesEnded = false
        window.addGestureRecognizer(r)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let overlay = Self.overlay else { return }
        overlay.superview?.bringSubviewToFront(overlay)
        for t in touches {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            dot.cornerRadius = 22
            dot.backgroundColor = UIColor(white: 1, alpha: 0.45).cgColor
            dot.borderColor = UIColor(white: 0.35, alpha: 0.55).cgColor
            dot.borderWidth = 1.5
            dot.position = t.location(in: overlay)
            overlay.layer.addSublayer(dot)
            dots[ObjectIdentifier(t)] = dot
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let overlay = Self.overlay else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in touches { dots[ObjectIdentifier(t)]?.position = t.location(in: overlay) }
        CATransaction.commit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for t in touches {
            guard let dot = dots.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setCompletionBlock { dot.removeFromSuperlayer() }
            dot.opacity = 0
            CATransaction.commit()
        }
        if dots.isEmpty { state = .failed }
    }
}

// MARK: - refresh rate

/// Android's "Show refresh rate": the frames drawn in the last second, in the top corner. Green at full rate, amber when
/// it drops, red when it is under half.
private final class RefreshRateMeter: NSObject {
    private static var current: RefreshRateMeter?
    private let label = UILabel()
    private var link: CADisplayLink?
    private var frames = 0
    private var since = CACurrentMediaTime()

    static func set(_ on: Bool, on window: UIWindow) {
        if !on { current?.stop(); current = nil; return }
        guard current == nil else { return }
        let m = RefreshRateMeter()
        m.start(on: window)
        current = m
    }

    private func start(on window: UIWindow) {
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        label.textColor = .systemGreen
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.isUserInteractionEnabled = false
        label.layer.zPosition = 10_001
        label.frame = CGRect(x: window.safeAreaInsets.left + 8, y: max(window.safeAreaInsets.top, 20) + 28, width: 46, height: 20)
        label.text = "--"
        window.addSubview(label)
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        frames += 1
        let now = CACurrentMediaTime()
        guard now - since >= 1 else { return }
        let fps = Int((Double(frames) / (now - since)).rounded())
        let full = UIScreen.main.maximumFramesPerSecond
        label.text = "\(fps)"
        label.textColor = fps >= full - 3 ? .systemGreen : fps >= full / 2 ? .systemOrange : .systemRed
        label.superview?.bringSubviewToFront(label)
        frames = 0
        since = now
    }

    private func stop() {
        link?.invalidate()
        label.removeFromSuperview()
    }
}

// MARK: - the card

/// Testing › System's "Developer options" card.
struct AndroidDeveloperOptions: View {
    @AppStorage(AndroidDev.hideStatusBarKey) private var hideStatusBar = false
    @AppStorage(AndroidDev.hideNavBarKey) private var hideNavBar = false
    @AppStorage(AndroidDev.animationScaleKey) private var scale = 1.0
    @AppStorage(AndroidDev.showTouchesKey) private var showTouches = false
    @AppStorage(AndroidDev.refreshRateKey) private var refreshRate = false
    @AppStorage(AndroidDev.noBlurKey) private var noBlur = false
    @AppStorage(AndroidDev.skipLockKey) private var skipLock = false
    @AppStorage(AndroidDev.noHeadsUpKey) private var noHeadsUp = false
    @AppStorage(AndroidDev.plainWallpaperKey) private var plainWallpaper = false
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("System UI")
            row("Hide status bar", "No clock or icons at the top; pull down from the top edge for the shade", $hideStatusBar)
            row(navigation == .gestures ? "Hide gesture bar" : "Hide navigation bar",
                navigation == .gestures ? "Apps get the whole screen; the swipes still work"
                                        : "Apps get the whole screen; switch to gesture navigation to keep back and home",
                $hideNavBar)
            row("Skip lock screen", "Open straight to the home screen, whatever the screen lock", $skipLock)
            row("No heads-up notifications", "Notifications only go to the shade", $noHeadsUp)

            section("Drawing")
            VStack(alignment: .leading, spacing: 8) {
                Text("Animator duration scale").font(.system(size: 16, design: .rounded))
                Picker("Animator duration scale", selection: $scale) {
                    ForEach(AndroidDev.scales, id: \.self) { s in Text(AndroidDev.scaleTitle(s)).tag(s) }
                }
                .pickerStyle(.menu)
                .tint(Color(uiColor: Material3.primary))
            }
            row("Disable blur", "Flat colours instead of blurred backgrounds: faster on older iPhones", $noBlur)
            row("Plain wallpaper", "A black wallpaper instead of the image", $plainWallpaper)

            section("Monitoring")
            row("Show taps", "A dot where you touch the screen", $showTouches)
            row("Show refresh rate", "The frames drawn each second, in the top corner", $refreshRate)
        }
        .onChange(of: showTouches) { _ in AndroidDev.applyOverlays() }
        .onChange(of: refreshRate) { _ in AndroidDev.applyOverlays() }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(uiColor: Material3.primary))
            .padding(.top, 4)
    }

    private func row(_ title: String, _ caption: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, design: .rounded))
                Text(caption).font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
        }
        .toggleStyle(Material3SwitchStyle())
    }
}
