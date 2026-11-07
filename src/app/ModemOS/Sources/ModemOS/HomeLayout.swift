import SwiftUI

func * (size: CGSize, k: CGFloat) -> CGSize { CGSize(width: size.width * k, height: size.height * k) }

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
}

func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(
        x: lerp(a.minX, b.minX, t),
        y: lerp(a.minY, b.minY, t),
        width: lerp(a.width, b.width, t),
        height: lerp(a.height, b.height, t)
    )
}

/// Every position on the home screen, measured from the stable-release concept.
///
/// The concept is a 9:16 canvas. Horizontal positions are fractions of the screen width;
/// vertical ones are fractions of `ch`, the height that canvas would have at this width.
/// Things pinned to the bottom (drawer) are measured up from the bottom edge.
struct HomeLayout {
    let size: CGSize

    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    var ch: CGFloat { min(size.width * 16 / 9, size.height) }
    /// By the short side: in landscape the width would double everything.
    var u: CGFloat { min(size.width, size.height) / 390 }

    // MARK: Status bar (a floating capsule that grows into the control panel)

    var barX: CGFloat { w * 0.013 }
    var barWidth: CGFloat { w * 0.972 }
    var barTop: CGFloat { 0 }
    var barHeight: CGFloat { 44 * u }
    var barOpenHeight: CGFloat { ch * 0.6 + 50 * u }
    var statusSize: CGFloat { 14 * u }
    var statusCenterY: CGFloat { 22 * u }

    func barRect(shade s: CGFloat) -> CGRect {
        CGRect(x: barX, y: barTop, width: barWidth, height: lerp(barHeight, barOpenHeight, s))
    }

    func barRadius(shade s: CGFloat) -> CGFloat {
        lerp(barHeight / 2, w * 0.075, s)
    }

    // MARK: Control panel sliders (keep their spot relative to the bottom of the open panel)

    var sliderHeight: CGFloat { w * 0.184 }
    var sliderX: CGFloat { w * 0.004 }

    func sliderTop(_ index: Int) -> CGFloat {
        ch * (0.1105 + 0.1177 * CGFloat(index))
    }

    // MARK: Navigation bar (three-button mode only)

    /// true = three-button navigation, which takes a strip at the bottom of the screen.
    var buttons: Bool = false

    var navHeight: CGFloat { buttons ? 50 * u : 0 }

    // MARK: App drawer (a glass sheet that peeks up from the bottom; the peeking part is the dock)

    var sheetX: CGFloat { 10 * u }
    var sheetWidth: CGFloat { w - 20 * u }
    var sheetRadius: CGFloat { 38 * u }
    var sheetOpenTop: CGFloat { 46 * u }
    var sheetBottom: CGFloat { h - 18 * u - navHeight }
    var sheetHeight: CGFloat { sheetBottom - sheetOpenTop }
    /// How much of the sheet shows while it is closed: just enough for the dock icons.
    var dockPeek: CGFloat { 96 * u }
    var sheetClosedTop: CGFloat { sheetBottom - dockPeek }

    func sheetTop(drawer d: CGFloat) -> CGFloat {
        lerp(sheetClosedTop, sheetOpenTop, d)
    }

    // MARK: Icons

    var iconSize: CGFloat { 62 * u }
    var labelSize: CGFloat { 12 * u }

    func iconRadius(_ roundness: Double) -> CGFloat { iconSize * CGFloat(roundness) }

    // MARK: Dock (inside the peeking drawer)

    var dockIconSize: CGFloat { 62 * u }

    func dockIcon(_ index: Int, drawer d: CGFloat) -> CGRect {
        let cell = (sheetWidth - 24 * u) / 4
        return CGRect(
            x: sheetX + 12 * u + (CGFloat(index) + 0.5) * cell - dockIconSize / 2,
            y: sheetTop(drawer: d) + (dockPeek - dockIconSize) / 2,
            width: dockIconSize,
            height: dockIconSize
        )
    }

    /// Distance from the top of one home-screen row to the next.
    var homePitch: CGFloat { 103 * u }

    /// Four columns from the top of the grid down.
    func homeIcon(_ index: Int, rows: Int) -> CGRect {
        let cell = (w - 48 * u) / 4
        return CGRect(
            x: 24 * u + (CGFloat(index % 4) + 0.5) * cell - dockIconSize / 2,
            y: 300 * u + CGFloat(index / 4) * homePitch,
            width: dockIconSize,
            height: dockIconSize
        )
    }

    var widgetTop: CGFloat { barTop + barHeight + ch * 0.07 }

    /// The bottom strip under the dock where the gesture line sits.
    var gestureStrip: CGFloat { h - sheetBottom }

    // MARK: Apps

    /// Rounded corners of a full-screen app while it is moving (about the display's own corners).
    var displayRadius: CGFloat { w * 0.121 }

    // MARK: Folder

    var folderRect: CGRect { CGRect(x: 30 * u, y: 220 * u, width: w - 60 * u, height: 300 * u) }

    var folderTitle: CGPoint {
        CGPoint(x: w / 2, y: ch * 0.14)
    }

    /// One of the four little squares on a folder icon (they grow into the real icons when it opens).
    func miniRect(_ index: Int, in icon: CGRect) -> CGRect {
        let side = min(icon.width, icon.height)
        let mini = side * 0.32
        let gap = side * 0.08
        let margin = (side - (2 * mini + gap)) / 2
        let column = CGFloat(index % 2)
        let row = CGFloat(index / 2)
        return CGRect(
            x: icon.minX + margin + column * (mini + gap),
            y: icon.minY + margin + row * (mini + gap),
            width: mini,
            height: mini
        )
    }

    /// Where an app sits inside the open folder.
    func folderChild(_ index: Int) -> CGRect {
        let cell = (folderRect.width - 28 * u) / 3
        return CGRect(
            x: folderRect.minX + 14 * u + (CGFloat(index % 3) + 0.5) * cell - iconSize / 2,
            y: folderRect.minY + 55 * u + CGFloat(index / 3) * 99 * u,
            width: iconSize,
            height: iconSize
        )
    }
}
