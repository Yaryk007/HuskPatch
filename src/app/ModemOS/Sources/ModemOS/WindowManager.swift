import SwiftUI
import Combine

/// One app or folder window, from the moment it starts growing out of its icon
/// until it has shrunk back into it.
final class WindowSession: Identifiable {
    let id = UUID()
    let item: HomeItem
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
    /// Oldest first, so the newest window is drawn on top.
    @Published private(set) var sessions: [WindowSession] = []
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
        if let current = front, current.item.id == item.id { return }

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

        // The same app might still be on its way back to its icon: just turn it around.
        if let again = sessions.last(where: { $0.item.id == item.id }) {
            sessions.removeAll { $0.id == again.id }
            sessions.append(again)
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
        sessions.append(session)
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
        }
        session.goal = 0
        session.t.animate(
            to: 0,
            response: session.style.closeResponse,
            damping: os.closeDamping(session.style),
            velocity: velocity,
            ease: true,
            stages: os.easeStages(session.style)
        ) { [weak self, weak session] in
            guard let self = self, let session = session, session.goal == 0 else { return }
            self.remove(session)
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

    func forget(_ item: HomeItem) {
        recents.removeAll { $0.id == item.id }
    }

    func forgetAll() {
        recents.removeAll()
    }

    private func remove(_ session: WindowSession) {
        sessions.removeAll { $0.id == session.id }
        forwards[session.id] = nil
    }
}
