// SPDX-License-Identifier: GPL-2.0-or-later
import ObjectiveC
import SwiftUI
import UIKit

/// HuskPatch: Android's overscroll, in place of iOS's rubber band, in the Android 16 style and Android OS mode.
///
/// Pull a list past its top or bottom and, as on Android 12 and later, the content stretches from that edge and springs
/// back (a fling that hits the edge stretches it briefly too); or, as on Android 5 to 11, the content stays put and a
/// glow in the accent colour swells at the edge. Settings › Display & touch › Overscroll effect chooses; "iOS bounce"
/// keeps the rubber band.
///
/// Every scroll view gets it, SwiftUI's included, by way of one hook on UIScrollView.didMoveToWindow: the scroll view
/// stops bouncing, and its pan gesture's pull past the edge drives a transform of its content (or the glow's layer).
/// Scroll views with a pull-to-refresh control keep bouncing, which refreshing needs.
enum AndroidOverscroll {
    enum Effect: String, CaseIterable, Identifiable {
        case stretch, glow, bounce
        static let key = "huskpatch.overscroll"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .stretch: return "Stretch"
            case .glow: return "Glow"
            case .bounce: return "iOS bounce"
            }
        }
        var summary: String {
            switch self {
            case .stretch: return "Android 12 and later: the list stretches at its ends"
            case .glow: return "Android 5 to 11: a glow at the edge"
            case .bounce: return "The iPhone's rubber band"
            }
        }
    }

    /// The effect in use now: the setting's, when the Android 16 style (or Android OS mode) is on.
    static var effect: Effect {
        let d = UserDefaults.standard
        guard d.bool(forKey: Material3.key) || d.bool(forKey: AndroidOS.key) else { return .bounce }
        return Effect(rawValue: d.string(forKey: Effect.key) ?? "") ?? .stretch
    }

    private static var installed = false

    /// Hooks UIScrollView once, at launch.
    static func install() {
        guard !installed else { return }
        installed = true
        let cls: AnyClass = UIScrollView.self
        guard let original = class_getInstanceMethod(cls, #selector(UIView.didMoveToWindow)),
              let replacement = class_getInstanceMethod(cls, #selector(UIScrollView.huskOverscroll_didMoveToWindow)) else { return }
        method_exchangeImplementations(original, replacement)
    }

    fileprivate static var driverKey: UInt8 = 0

    fileprivate static func attach(_ view: UIScrollView) {
        guard view.window != nil, objc_getAssociatedObject(view, &driverKey) == nil else { return }
        // the wheels of pickers, text views (their own scrolling), and other apps' views stay as they are
        let name = NSStringFromClass(type(of: view))
        if view is UITextView || name.contains("Picker") || name.hasPrefix("_UIRemote") { return }
        let driver = OverscrollDriver(view)
        objc_setAssociatedObject(view, &driverKey, driver, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension UIScrollView {
    @objc fileprivate func huskOverscroll_didMoveToWindow() {
        huskOverscroll_didMoveToWindow()   // the original, swapped in
        if window != nil { AndroidOverscroll.attach(self) }
    }
}

/// One scroll view's overscroll: the pull past an edge (positive at the top or leading edge, negative at the bottom or
/// trailing one), turned into a stretch or a glow, and let go with a spring.
private final class OverscrollDriver: NSObject {
    private weak var view: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var originalBounces = true
    private var managing = false
    private var pull: CGFloat = 0
    private var horizontal = false
    private var lastTranslation: CGFloat = 0
    private var link: CADisplayLink?
    private var lastOffset: CGPoint = .zero
    private var lastTime: CFTimeInterval = 0
    private var velocity: CGFloat = 0
    private let glow = CAShapeLayer()

    init(_ view: UIScrollView) {
        self.view = view
        super.init()
        originalBounces = view.bounces
        lastOffset = view.contentOffset
        view.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
        offsetObservation = view.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.scrolled()
        }
        glow.zPosition = 1000
        glow.isHidden = true
        view.layer.addSublayer(glow)
        refreshMode()
    }

    deinit {
        offsetObservation?.invalidate()
        link?.invalidate()
    }

    /// Takes the scroll view over for the effect, or hands it back for iOS's bounce.
    private func refreshMode() {
        guard let view else { return }
        let want = AndroidOverscroll.effect != .bounce && view.refreshControl == nil
        if want != managing {
            managing = want
            view.bounces = want ? false : originalBounces
            if !want { pull = 0; apply() }
        } else if want, view.bounces {
            view.bounces = false        // SwiftUI may set it again on an update
        }
    }

    private var axisLength: CGFloat {
        guard let view else { return 1 }
        return max(1, horizontal ? view.bounds.width : view.bounds.height)
    }

    /// Where the content is: at the start edge, at the end edge (both when it does not fill the view).
    private func edges() -> (start: Bool, end: Bool) {
        guard let v = view else { return (false, false) }
        let inset = v.adjustedContentInset
        if horizontal {
            let minX = -inset.left, maxX = max(minX, v.contentSize.width + inset.right - v.bounds.width)
            return (v.contentOffset.x <= minX + 0.5, v.contentOffset.x >= maxX - 0.5)
        }
        let minY = -inset.top, maxY = max(minY, v.contentSize.height + inset.bottom - v.bounds.height)
        return (v.contentOffset.y <= minY + 0.5, v.contentOffset.y >= maxY - 0.5)
    }

    private func chooseAxis() {
        guard let v = view else { return }
        let inset = v.adjustedContentInset
        let scrollsX = v.contentSize.width + inset.left + inset.right > v.bounds.width + 1
        let scrollsY = v.contentSize.height + inset.top + inset.bottom > v.bounds.height + 1
        horizontal = scrollsX && !scrollsY && !v.alwaysBounceVertical
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        refreshMode()
        guard managing, let v = view else { return }
        let t = g.translation(in: v)
        let along = horizontal ? t.x : t.y
        switch g.state {
        case .began:
            chooseAxis()
            lastTranslation = horizontal ? t.x : t.y
            link?.invalidate(); link = nil
        case .changed:
            let delta = along - lastTranslation
            lastTranslation = along
            let e = edges()
            // Android's resistance: the further it is pulled, the less each point of finger travel moves it
            let resist = 0.5 * (1 - min(abs(pull) / axisLength, 0.9))
            if pull > 0 || (e.start && delta > 0) {
                pull = max(0, pull + delta * resist)
            } else if pull < 0 || (e.end && delta < 0) {
                pull = min(0, pull + delta * resist)
            }
            apply()
        default:
            release()
        }
    }

    /// A fling that reaches an edge: a short stretch, as Android's EdgeEffect absorbs the velocity.
    private func scrolled() {
        guard let v = view else { return }
        let now = CACurrentMediaTime()
        let off = horizontal ? v.contentOffset.x - lastOffset.x : v.contentOffset.y - lastOffset.y
        if lastTime > 0, now > lastTime { velocity = off / CGFloat(now - lastTime) }
        lastOffset = v.contentOffset
        lastTime = now
        if managing, pull != 0 { apply() }    // the glow's layer follows the scroll position
        guard managing, v.isDecelerating, link == nil, abs(velocity) > 400 else { return }
        let e = edges()
        if (e.start && velocity < 0) || (e.end && velocity > 0) {
            pull = min(axisLength * 0.12, abs(velocity) * 0.025) * (velocity < 0 ? 1 : -1)
            velocity = 0
            apply()
            release()
        }
    }

    /// Springs back to rest.
    private func release() {
        guard pull != 0, link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func step() {
        pull *= 0.80
        if abs(pull) < 0.5 { pull = 0; link?.invalidate(); link = nil }
        apply()
    }

    private func apply() {
        guard let v = view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let effect = AndroidOverscroll.effect
        guard pull != 0, managing else {
            v.layer.sublayerTransform = CATransform3DIdentity
            glow.isHidden = true
            return
        }
        let len = axisLength
        if effect == .stretch {
            glow.isHidden = true
            let s = 1 + min(abs(pull) / len, 1) * 0.22
            let c = len / 2
            // scaled about the edge it is pulled from (see the layer's anchor: the middle of what is visible)
            let shift = pull > 0 ? c * (s - 1) : c * (1 - s)
            v.layer.sublayerTransform = horizontal
                ? CATransform3DConcat(CATransform3DMakeScale(s, 1, 1), CATransform3DMakeTranslation(shift, 0, 0))
                : CATransform3DConcat(CATransform3DMakeScale(1, s, 1), CATransform3DMakeTranslation(0, shift, 0))
        } else {
            v.layer.sublayerTransform = CATransform3DIdentity
            drawGlow(in: v)
        }
    }

    /// The glow: a wide ellipse in the accent colour, deeper and brighter the further it is pulled.
    private func drawGlow(in v: UIScrollView) {
        let b = v.bounds
        let span = horizontal ? b.height : b.width
        let depth = min(abs(pull) * 0.6, span * 0.3)
        let atStart = pull > 0
        glow.isHidden = false
        glow.fillColor = Material3.primary.resolvedColor(with: v.traitCollection)
            .withAlphaComponent(0.12 + 0.25 * min(abs(pull) / 160, 1)).cgColor
        if horizontal {
            glow.frame = CGRect(x: atStart ? b.minX : b.maxX - depth, y: b.minY, width: depth, height: b.height)
            glow.path = UIBezierPath(ovalIn: CGRect(x: atStart ? -depth : 0, y: -b.height * 0.25, width: depth * 2, height: b.height * 1.5)).cgPath
        } else {
            glow.frame = CGRect(x: b.minX, y: atStart ? b.minY + v.adjustedContentInset.top : b.maxY - depth - v.adjustedContentInset.bottom,
                                width: b.width, height: depth)
            glow.path = UIBezierPath(ovalIn: CGRect(x: -b.width * 0.25, y: atStart ? -depth : 0, width: b.width * 1.5, height: depth * 2)).cgPath
        }
    }
}
