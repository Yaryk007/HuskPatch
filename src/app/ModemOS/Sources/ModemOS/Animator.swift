import SwiftUI
import UIKit

/// A small spring driver, used instead of `withAnimation` for everything that has to be
/// grabbed mid-flight (drawer, control panel, app windows, the setup card).
///
/// - `set(_:)` jumps to a value and cancels any running animation (use it while a finger is dragging).
/// - `animate(to:...)` springs to a target, starting from the *current* value and an optional velocity,
///   so handing over between a gesture and an animation never jumps.
/// - `ease: true` puts two extra springs in front of the value spring. The motion then starts very
///   gently, speeds up, and lands softly (a proper ease-in-out) instead of a spring's immediate kick.
final class Animator: NSObject, ObservableObject {
    /// Multiplies every animation's duration (set from the animation speed in the Lab panel).
    static var durationScale: CGFloat = 1

    @Published private(set) var value: CGFloat

    private var target: CGFloat
    private var velocity: CGFloat = 0
    /// Springs that chase the target; each one is chased by the next, and the last is chased by `value`.
    private var leads: [CGFloat] = []
    private var leadVelocities: [CGFloat] = []
    private var omega: CGFloat = 20
    private var zeta: CGFloat = 1
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var completion: (() -> Void)?
    private var landingBand: CGFloat?

    init(_ initial: CGFloat) {
        value = initial
        target = initial
        super.init()
    }

    deinit {
        link?.invalidate()
    }

    /// Current speed in value-units per second (0 while a finger is holding it).
    var currentVelocity: CGFloat { velocity }

    /// Cancels any running animation and keeps the current value.
    func stop() {
        link?.invalidate()
        link = nil
        completion = nil
        velocity = 0
        leads = []
        leadVelocities = []
        target = value
    }

    /// Jumps straight to a value (while dragging).
    func set(_ newValue: CGFloat) {
        stop()
        target = newValue
        value = newValue
    }

    /// Springs to `newTarget`.
    /// - response: roughly how long the spring takes (seconds). Smaller = snappier.
    /// - damping: 1 = smooth ease-out with no bounce, below 1 = slight overshoot.
    /// - velocity: starting speed in value-units per second (from the gesture).
    /// - ease: gentle start and soft landing instead of an immediate spring kick.
    func animate(
        to newTarget: CGFloat,
        response: CGFloat = 0.38,
        damping: CGFloat = 1,
        velocity initialVelocity: CGFloat = 0,
        ease: Bool = false,
        stages stageOverride: Int? = nil,
        landing: CGFloat? = nil,
        completion done: (() -> Void)? = nil
    ) {
        link?.invalidate()
        link = nil
        landingBand = landing
        completion = done
        target = newTarget
        velocity = initialVelocity

        // Fewer lead stages = less smoothing, so a bouncy (damping < 1) spring really overshoots.
        let stages = min(2, max(0, stageOverride ?? (ease ? 2 : 0)))
        leads = Array(repeating: value, count: stages)
        leadVelocities = Array(repeating: initialVelocity, count: stages)
        // Extra stages make the curve longer, so each spring is a little faster to keep the total time.
        let stretch: [CGFloat] = [1, 0.8, 0.66]
        omega = 2 * .pi / max(response * Self.durationScale * stretch[stages], 0.05)
        zeta = damping

        if abs(value - newTarget) < 0.0005 && abs(velocity) < 0.005 {
            value = newTarget
            velocity = 0
            leads = []
            leadVelocities = []
            let finished = completion
            completion = nil
            finished?()
            return
        }

        lastTime = CACurrentMediaTime()
        let newLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    @objc private func tick(_ frame: CADisplayLink) {
        let now = frame.timestamp
        var dt = now - lastTime
        lastTime = now
        if dt <= 0 { return }
        dt = min(dt, 1.0 / 20.0)

        // Integrate in small fixed steps so the springs stay stable at any frame rate.
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = CGFloat(dt) / CGFloat(steps)
        var x = value
        var v = velocity
        var l = leads
        var lv = leadVelocities

        for _ in 0..<steps {
            var input = target
            for k in 0..<l.count {
                let acceleration = -omega * omega * (l[k] - input) - 2 * omega * lv[k]
                lv[k] += acceleration * h
                l[k] += lv[k] * h
                input = l[k]
            }
            let acceleration = -omega * omega * (x - input) - 2 * zeta * omega * v
            v += acceleration * h
            x += v * h
        }

        var settled = abs(x - target) < 0.0005 && abs(v) < 0.01
        for k in 0..<l.count where abs(l[k] - target) > 0.0005 || abs(lv[k]) > 0.01 {
            settled = false
        }
        // A window arriving at its icon ends there, rather than waiting out the last of the spring.
        if let landingBand, abs(x - target) < landingBand { settled = true }

        if settled {
            velocity = 0
            leads = []
            leadVelocities = []
            value = target
            link?.invalidate()
            link = nil
            let finished = completion
            completion = nil
            finished?()
        } else {
            velocity = v
            leads = l
            leadVelocities = lv
            value = x
        }
    }
}
