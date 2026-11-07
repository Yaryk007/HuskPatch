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
    var barTop: CGFloat { ch * 0.02 }
    var barHeight: CGFloat { ch * 0.039 }
    var barOpenHeight: CGFloat { ch * 0.6 + 50 * u }
    var statusSize: CGFloat { w * 0.037 }
    var statusCenterY: CGFloat { ch * 0.039 }

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

    var sheetX: CGFloat { w * 0.045 }
    var sheetWidth: CGFloat { w * 0.91 }
    var sheetRadius: CGFloat { w * 0.085 }
    var sheetOpenTop: CGFloat { ch * 0.085 }
    var sheetBottom: CGFloat { h - ch * 0.029 - navHeight }
    var sheetHeight: CGFloat { sheetBottom - sheetOpenTop }
    /// How much of the sheet shows while it is closed: just enough for the dock icons.
    var dockPeek: CGFloat { dockIconSize + w * 0.1 }
    var sheetClosedTop: CGFloat { sheetBottom - dockPeek }

    func sheetTop(drawer d: CGFloat) -> CGFloat {
        lerp(sheetClosedTop, sheetOpenTop, d)
    }

    // MARK: Icons

    var iconSize: CGFloat { w * 0.19 }
    var labelSize: CGFloat { w * 0.032 }

    func iconRadius(_ roundness: Double) -> CGFloat { iconSize * CGFloat(roundness) }

    // MARK: Dock (inside the peeking drawer)

    var dockIconSize: CGFloat { w * 0.165 }

    func dockIcon(_ index: Int, drawer d: CGFloat) -> CGRect {
        let gap = (sheetWidth - 4 * dockIconSize) / 5
        return CGRect(
            x: sheetX + gap + CGFloat(index) * (dockIconSize + gap),
            y: sheetTop(drawer: d) + (dockPeek - dockIconSize) / 2 + 2 * u,
            width: dockIconSize,
            height: dockIconSize
        )
    }

    // MARK: Home screen (apps above the dock, and the clock widget)

    /// Distance from the top of one home-screen row to the next (icon + label + gap).
    var homePitch: CGFloat { dockIconSize + labelSize * 2.4 + ch * 0.022 }

    /// Four columns lined up with the dock; rows stack up from just above the dock.
    func homeIcon(_ index: Int, rows: Int) -> CGRect {
        let gap = (sheetWidth - 4 * dockIconSize) / 5
        let column = CGFloat(index % 4)
        let row = CGFloat(index / 4)
        let lastRowTop = sheetClosedTop - ch * 0.03 - labelSize * 2.4 - dockIconSize
        return CGRect(
            x: sheetX + gap + column * (dockIconSize + gap),
            y: lastRowTop - (CGFloat(rows - 1) - row) * homePitch,
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

    var folderRect: CGRect {
        CGRect(x: w * 0.08, y: ch * 0.175, width: w * 0.84, height: ch * 0.607)
    }

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
        let column = CGFloat(index % 3)
        let row = CGFloat(index / 3)
        let pad = w * 0.06
        let gap = (folderRect.width - 2 * pad - 3 * iconSize) / 2
        return CGRect(
            x: folderRect.minX + pad + column * (iconSize + gap),
            y: folderRect.minY + ch * 0.065 + row * ch * 0.165,
            width: iconSize,
            height: iconSize
        )
    }
}
