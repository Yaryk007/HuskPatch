// SPDX-License-Identifier: GPL-2.0-or-later
import PhotosUI
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's look you can choose in Settings › Wallpaper & style -- where the colours come from (the
/// wallpaper, as Android 12+ does by default, or your accent), the colour style, your own photo as the wallpaper, and the
/// shape of app icons.
enum AndroidColors {
    static let wallpaperColorsKey = "huskpatch.androidOS.wallpaperColors"
    static let styleKey = "huskpatch.androidOS.colorStyle"
    private static let customSeedKey = "huskpatch.androidOS.customSeed"

    enum Style: String, CaseIterable, Identifiable {
        case tonalSpot, vibrant, monochrome
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tonalSpot: return "Tonal spot"
            case .vibrant: return "Vibrant"
            case .monochrome: return "Monochrome"
            }
        }
        var summary: String {
            switch self {
            case .tonalSpot: return "Android's default: soft colours, near-grey backgrounds"
            case .vibrant: return "Stronger colours everywhere"
            case .monochrome: return "Black, white and greys"
            }
        }
    }

    /// The colour style: in Android OS mode, Android's (tonal spot unless chosen); elsewhere, HuskPatch's vibrant one.
    static var style: Style {
        guard AndroidOS.isOn else { return .vibrant }
        return Style(rawValue: UserDefaults.standard.string(forKey: styleKey) ?? "") ?? .tonalSpot
    }

    static var useWallpaper: Bool {
        AndroidOS.isOn && (UserDefaults.standard.object(forKey: wallpaperColorsKey) as? Bool ?? true)
    }

    /// The seed the wallpaper gives, when wallpaper colours are on and the wallpaper has colours of its own: LineageOS's
    /// teal (hue 220), or what was taken from your photo. The orbit and Material shapes wallpapers are drawn in the
    /// palette, so they leave the accent in charge.
    static var wallpaperSeed: (h: Double, c: Double)? {
        guard useWallpaper else { return nil }
        switch AndroidOS.Wallpaper(rawValue: UserDefaults.standard.string(forKey: AndroidOS.wallpaperKey) ?? "") ?? .lineage22 {
        case .lineage22, .lineage20: return (220, 40)
        case .custom:
            if let v = UserDefaults.standard.array(forKey: customSeedKey) as? [Double], v.count == 2 { return (v[0], v[1]) }
            return nil
        case .lineage, .blobs: return nil
        }
    }

    /// Re-export Android apps' dynamic colours and redraw, after something the palette depends on changed.
    @MainActor static func changed() {
        Material3.exportDynamicColors()
        AppTheme.shared.objectWillChange.send()
        AndroidShellState.shared.objectWillChange.send()
    }

    // MARK: your own wallpaper

    static var customURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HuskPatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wallpaper.jpg")
    }

    private static var cachedImage: UIImage?
    static var customImage: UIImage? {
        if cachedImage == nil { cachedImage = UIImage(contentsOfFile: customURL.path) }
        return cachedImage
    }

    /// Keep the picture as the wallpaper and take its colours.
    @MainActor static func setCustom(_ image: UIImage) {
        // a phone-sized copy is plenty for a wallpaper
        let maxSide: CGFloat = 2400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? small.jpegData(compressionQuality: 0.88)?.write(to: customURL)
        cachedImage = small
        if let seed = seed(of: small) { UserDefaults.standard.set([seed.h, seed.c], forKey: customSeedKey) }
        else { UserDefaults.standard.removeObject(forKey: customSeedKey) }
        UserDefaults.standard.set(AndroidOS.Wallpaper.custom.rawValue, forKey: AndroidOS.wallpaperKey)
        changed()
    }

    /// The picture's main colour, as Android picks a seed from a wallpaper: the hue most of its colourful pixels share.
    static func seed(of image: UIImage) -> (h: Double, c: Double)? {
        let side = 40
        guard let cg = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var bins = [Double](repeating: 0, count: 36), hueX = [Double](repeating: 0, count: 36), hueY = [Double](repeating: 0, count: 36)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let c = UIColor(red: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255, blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            let lab = Lab(c)
            let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            guard chroma > 10, lab.l > 12, lab.l < 96 else { continue }
            let hue = atan2(lab.b, lab.a)
            var deg = hue * 180 / .pi
            if deg < 0 { deg += 360 }
            let bin = Int(deg / 10) % 36
            bins[bin] += chroma
            hueX[bin] += cos(hue) * chroma
            hueY[bin] += sin(hue) * chroma
        }
        // the strongest hue, with its neighbours
        guard let best = bins.indices.max(by: { bins[$0] < bins[$1] }), bins[best] > 0 else { return nil }
        var x = 0.0, y = 0.0
        for b in [best - 1, best, best + 1].map({ ($0 + 36) % 36 }) {
            x += hueX[b]; y += hueY[b]
        }
        var h = atan2(y, x) * 180 / .pi
        if h < 0 { h += 360 }
        // Android's tonal spot sets its own chroma; a seed this colourful lets every palette reach it
        return (h, 40)
    }
}

/// Your photo, filling the screen.
struct CustomWallpaper: View {
    var body: some View {
        GeometryReader { geo in
            if let image = AndroidColors.customImage {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                Lineage20Wallpaper()
            }
        }
        .ignoresSafeArea()
    }
}

/// iOS's photo picker, for a wallpaper.
struct WallpaperPhotoPicker: UIViewControllerRepresentable {
    let picked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: WallpaperPhotoPicker
        init(_ parent: WallpaperPhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in self.parent.picked(image) }
            }
        }
    }
}

// MARK: - icon shape

/// The shape of app icons, as Android's Wallpaper & style › App grid › Icon shape offers.
enum AndroidIconShape: String, CaseIterable, Identifiable {
    case circle, squircle, roundedSquare, teardrop, square
    static let key = "huskpatch.androidOS.iconShape"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .circle: return "Circle"
        case .squircle: return "Squircle"
        case .roundedSquare: return "Rounded square"
        case .teardrop: return "Teardrop"
        case .square: return "Square"
        }
    }

    static var current: AndroidIconShape {
        AndroidIconShape(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .circle
    }

    func shape(_ size: CGFloat) -> AnyShape {
        switch self {
        case .circle: return AnyShape(Circle())
        case .squircle: return AnyShape(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous))
        case .roundedSquare: return AnyShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        case .teardrop: return AnyShape(StackedCornersAsymmetric(radius: size / 2, sharp: size * 0.14))
        case .square: return AnyShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
        }
    }
}

/// A teardrop: round everywhere but its bottom-right corner.
struct StackedCornersAsymmetric: Shape {
    let radius: CGFloat
    let sharp: CGFloat
    func path(in r: CGRect) -> Path {
        let big = min(radius, r.width / 2, r.height / 2), small = min(sharp, big)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + big, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - big, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - big, y: r.minY + big), radius: big, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - small))
        p.addArc(center: CGPoint(x: r.maxX - small, y: r.maxY - small), radius: small, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + big, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + big, y: r.maxY - big), radius: big, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + big))
        p.addArc(center: CGPoint(x: r.minX + big, y: r.minY + big), radius: big, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The colour at the edge of a round icon picture, to fill the rest of a non-round icon shape with.
enum IconPlate {
    private static var cache: [String: Color] = [:]
    static func color(_ asset: String) -> Color {
        if let c = cache[asset] { return c }
        var result = Color.white
        if let cg = UIImage(named: asset)?.cgImage {
            var px = [UInt8](repeating: 0, count: 4)
            if let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                // a point just inside the circle's top edge
                let w = CGFloat(cg.width), h = CGFloat(cg.height)
                ctx.draw(cg, in: CGRect(x: -w / 2 + 0.5, y: -h + 0.5 + h * 0.06, width: w, height: h))
                result = Color(red: Double(px[0]) / 255, green: Double(px[1]) / 255, blue: Double(px[2]) / 255)
            }
        }
        cache[asset] = result
        return result
    }
}
