import SwiftUI
import Combine
import UIKit

/// One app or folder window, from the moment it starts growing out of its icon
/// until it has shrunk back into it.
final class WindowSession: Identifiable {
    let id = UUID()
    /// The icon it opened from most recently (the same app has one in the dock, the drawer and on the home screen).
    fileprivate(set) var item: HomeItem
    /// Shrunk back into its icon but still running: hidden and untouchable, with everything it was doing kept.
    fileprivate(set) var parked = false
    /// Closed from Recents while on screen: it stops once it has shrunk away, rather than going to the background.
    fileprivate(set) var discard = false
    /// What it last looked like, for Recents.
    fileprivate(set) var snapshot: UIImage?
    /// The animation style it was opened with (changing the style never makes an open window jump).
    let style = OSSettings.shared.animStyle
    /// 0 = still an icon, 1 = fully open.
    let t = Animator(0)
    /// Where it is heading: 1 = opening / open, 0 = closing.
    var goal: CGFloat = 0
    /// The icon it grows out of (and shrinks back into), and where that icon's label sits.
    var origin: CGRect
    var labelCenter: CGPoint
    var labelSize: CGFloat
    /// An app that lives inside a folder: the folder stays open behind it.
    let parentID: Int?

    /// 1 = the window follows its normal path from icon to open; 0 = a finger is dragging it around.
    let k = Animator(1)
    /// While dragged: where the window's centre was when the finger touched it, and how far it has moved.
    var heldCenter: CGPoint = .zero
    var heldOffset: CGSize = .zero

    /// Where the window was drawn on recent frames (newest last), for the Home Up ghost trail.
    private(set) var trail: [CGRect] = []
    private var lastSample: CFTimeInterval = 0
    /// How fast the window's size is changing (progress units per second), for squash and stretch.
    private(set) var speed: CGFloat = 0
    private var lastP: CGFloat = 0

    /// Records where the window is this frame (called while drawing; at most once per 1/60 s).
    func sample(_ rect: CGRect, p: CGFloat) {
        let now = CACurrentMediaTime()
        let dt = now - lastSample
        guard dt >= 1.0 / 60 else { return }
        if dt < 0.2 {
            // Smooth it a little so squash does not flicker.
            speed = speed * 0.5 + (p - lastP) / CGFloat(dt) * 0.5
        } else {
            speed = 0
            trail.removeAll()
        }
        lastSample = now
        lastP = p
        trail.append(rect)
        if trail.count > 10 { trail.removeFirst(trail.count - 10) }
    }

    init(item: HomeItem, origin: CGRect, labelCenter: CGPoint, labelSize: CGFloat, parentID: Int?) {
        self.item = item
        self.origin = origin
        self.labelCenter = labelCenter
        self.labelSize = labelSize
        self.parentID = parentID
    }
}

/// Keeps track of every window, so a new one can start while another is still opening or closing.
///
/// - Tapping another app while one is opening sends the first one back to its icon and opens the second.
/// - A window that is closing never blocks anything: you can open the next app right away.
final class WindowManager: ObservableObject {
    /// How many apps stay running behind the one in front. An installed Android app never counts: its engine cannot be
    /// started twice in a run, so it is only ever closed by hand.
    static let maxParked = 6

    /// Every window, running ones included, oldest first so the newest is drawn on top. One list, so that SwiftUI keeps an
    /// app's views (and so its state) alive when it goes to the background.
    @Published private(set) var all: [WindowSession] = []
    /// The windows on screen: opening, open or closing.
    var sessions: [WindowSession] { all.filter { !$0.parked } }
    /// Recently opened apps, newest first (for the Recents screen).
    @Published private(set) var recents: [HomeItem] = []

    /// Called when a window has shrunk all the way back into its icon.
    var onLanded: ((WindowSession) -> Void)?
    /// The icon the last window landed in (the centre of the Sweet ripple).
    private(set) var lastLanded: CGRect = .zero

    private var forwards: [UUID: [AnyCancellable]] = [:]

    /// The window you are in right now (opening or open), if any.
    var front: WindowSession? {
        sessions.last { $0.goal == 1 }
    }

    /// The most open folder, used to blur everything behind it.
    var folderProgress: CGFloat {
        sessions.filter { $0.item.kind == .folder }.map { $0.t.value }.max() ?? 0
    }

    /// The most open app (folders do not count), used to shrink the control center to its text.
    var appProgress: CGFloat {
        sessions.filter { $0.item.kind == .app }.map { $0.t.value }.max() ?? 0
    }

    /// The most open window of any kind, used to dim and push back the home screen.
    var anyProgress: CGFloat {
        sessions.map { $0.t.value }.max() ?? 0
    }

    /// Whether an app is running, on screen or not.
    func isRunning(_ item: HomeItem) -> Bool {
        all.contains { $0.item.appKey == item.appKey }
    }

    /// What an app last looked like.
    func snapshot(of item: HomeItem) -> UIImage? {
        all.last { $0.item.appKey == item.appKey }?.snapshot
    }

    /// Remembers what the app in front looks like right now.
    func captureFront() {
        guard let session = front, session.item.kind == .app, session.t.value > 0.97 else { return }
        session.snapshot = ScreenGrab.capture()
    }

    func session(_ itemID: Int) -> WindowSession? {
        sessions.last { $0.item.id == itemID }
    }

    /// Whether an item currently has a window (opening, open or closing).
    func hasSession(_ itemID: Int) -> Bool {
        sessions.contains { $0.item.id == itemID }
    }

    /// How far an item is open (0 when it has no window).
    func progress(of itemID: Int) -> CGFloat {
        sessions.filter { $0.item.id == itemID }.map { $0.t.value }.max() ?? 0
    }

    func launch(
        _ item: HomeItem,
        from origin: CGRect,
        labelCenter: CGPoint,
        labelSize: CGFloat,
        parent: Int? = nil
    ) {
        if let current = front, current.item.appKey == item.appKey { return }

        OSLogger.shared.log("Window", "Open \(item.name) (\(OSSettings.shared.animStyle.title))")
        Haptics.tap(.soft)
        if item.kind == .app {
            recents.removeAll { $0.id == item.id }
            recents.insert(item, at: 0)
            if recents.count > 12 { recents.removeLast() }
        }

        // Whatever is still opening or open makes way for the new window - except the folder an app
        // is being opened from. (It keeps its momentum, so turning it around looks smooth.)
        for session in sessions where session.goal == 1 && session.item.id != parent {
            close(session, velocity: session.t.currentVelocity)
        }

        // The same app might still be on its way back to its icon, or running in the background: bring it back as it was.
        if let again = all.last(where: { $0.item.appKey == item.appKey }) {
            all.removeAll { $0.id == again.id }
            all.append(again)
            again.item = item
            again.parked = false
            again.discard = false
            again.origin = origin
            again.labelCenter = labelCenter
            again.labelSize = labelSize
            open(again, velocity: again.t.currentVelocity)
            return
        }

        let session = WindowSession(
            item: item,
            origin: origin,
            labelCenter: labelCenter,
            labelSize: labelSize,
            parentID: parent
        )
        forwards[session.id] = [
            session.t.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
            session.k.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
        ]
        all.append(session)
        open(session, velocity: 0)
    }

    func open(_ session: WindowSession, velocity: CGFloat) {
        let os = OSSettings.shared
        session.goal = 1
        session.t.animate(
            to: 1,
            response: session.item.kind == .folder ? max(0.5, session.style.openResponse) : session.style.openResponse,
            damping: os.openDamping(session.style),
            velocity: velocity,
            ease: true,
            stages: os.easeStages(session.style)
        )
        objectWillChange.send()
    }

    func close(_ session: WindowSession, velocity: CGFloat) {
        let os = OSSettings.shared
        if session.goal == 1 {
            OSLogger.shared.log("Window", "Close \(session.item.name)")
            if session.item.kind == .app && session.t.value > 0.97 { session.snapshot = ScreenGrab.capture() }
        }
        session.goal = 0
        session.t.animate(
            to: 0,
            response: session.style.closeResponse,
            damping: os.closeDamping(session.style),
            velocity: velocity,
            ease: true,
            stages: os.easeStages(session.style),
            landing: 0.012
        ) { [weak self, weak session] in
            guard let self = self, let session = session, session.goal == 0 else { return }
            if session.item.keepsRunning && !session.discard {
                session.parked = true
                OSLogger.shared.log("Window", "\(session.item.name) keeps running")
                self.trimParked()
            } else {
                self.remove(session)
            }
            self.lastLanded = session.origin
            self.onLanded?(session)
        }
        objectWillChange.send()
    }

    /// Carries on toward wherever the window was heading (used after a plain tap on the swipe bar).
    func resume(_ session: WindowSession) {
        if session.goal == 1 {
            open(session, velocity: 0)
        } else {
            close(session, velocity: 0)
        }
    }

    /// Sends every open window back to its icon (the Home button).
    func closeAll() {
        for session in sessions where session.goal == 1 {
            close(session, velocity: 0)
        }
    }

    /// Closes an app for good: it stops running and leaves Recents.
    func forget(_ item: HomeItem) {
        recents.removeAll { $0.appKey == item.appKey }
        for session in all where session.item.appKey == item.appKey { end(session) }
    }

    func forgetAll() {
        recents.removeAll()
        for session in all where session.item.kind == .app { end(session) }
    }

    /// Stops an app, whether it is in the background or on screen.
    private func end(_ session: WindowSession) {
        if session.parked {
            remove(session)
        } else {
            session.discard = true
            if session.goal == 1 { close(session, velocity: 0) }
        }
    }

    /// Past the limit, the app used longest ago stops running (it stays in Recents, and starts anew).
    private func trimParked() {
        let parked = all.filter { $0.parked && !$0.item.pinned }
        for session in parked.dropLast(Self.maxParked) {
            OSLogger.shared.log("Window", "\(session.item.name) stopped to free memory")
            remove(session)
        }
    }

    private func remove(_ session: WindowSession) {
        all.removeAll { $0.id == session.id }
        forwards[session.id] = nil
    }
}

/// A picture of the screen as it is now, at half size.
enum ScreenGrab {
    static func capture() -> UIImage? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let window else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.5
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}
