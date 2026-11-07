import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - Calculator

struct CalculatorApp: View {
    @EnvironmentObject private var os: OSSettings
    @State private var display = "0"
    @State private var stored: Double?
    @State private var pending: String?
    @State private var typing = false
    @State private var history = ""

    private let rows: [[String]] = [
        ["AC", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "⌫", "="],
    ]

    var body: some View {
        GeometryReader { geo in
            let size = (geo.size.width - 5 * 14) / 4
            VStack(spacing: 14) {
                Spacer()
                Text(history)
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                Text(display)
                    .font(.system(size: 76, weight: .light))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 14) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                Haptics.tap()
                                press(key)
                            } label: {
                                Text(key)
                                    .font(.system(size: size * 0.4, weight: .medium))
                                    .foregroundColor(foreground(key))
                                    .frame(width: size, height: size)
                                    .background(
                                        RoundedRectangle(cornerRadius: os.design == .expressive ? size * 0.34 : size / 2, style: .continuous)
                                            .fill(background(key))
                                    )
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func background(_ key: String) -> Color {
        let p = os.palette
        if key == "=" { return p.primary }
        if "÷×−+".contains(key) { return pending == key && !typing ? p.primary : p.primaryContainer }
        if ["AC", "±", "%"].contains(key) { return p.tertiaryContainer }
        return Color.osCard
    }

    private func foreground(_ key: String) -> Color {
        let p = os.palette
        if key == "=" { return p.onPrimary }
        if "÷×−+".contains(key) { return pending == key && !typing ? p.onPrimary : p.onPrimaryContainer }
        if ["AC", "±", "%"].contains(key) { return p.onTertiaryContainer }
        return p.onSurface
    }

    private var value: Double { Double(display) ?? 0 }

    private func show(_ number: Double) {
        if number.isNaN || number.isInfinite {
            display = os.t("Error")
            return
        }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        display = formatter.string(from: NSNumber(value: number)) ?? "0"
    }

    private func press(_ key: String) {
        switch key {
        case "0"..."9":
            if !typing || display == "0" { display = key } else if display.count < 15 { display += key }
            typing = true
        case ".":
            if !typing { display = "0."; typing = true } else if !display.contains(".") { display += "." }
        case "AC":
            display = "0"; stored = nil; pending = nil; typing = false; history = ""
        case "±":
            show(-value)
        case "%":
            show(value / 100)
        case "⌫":
            if typing && display.count > 1 { display.removeLast() } else { display = "0"; typing = false }
        case "=":
            guard let left = stored, let op = pending else { return }
            history = "\(format(left)) \(op) \(display) ="
            show(apply(op, left, value))
            stored = nil; pending = nil; typing = false
        default:
            if let left = stored, let op = pending, typing {
                show(apply(op, left, value))
            }
            stored = value
            pending = key
            typing = false
            history = "\(display) \(key)"
        }
    }

    private func format(_ number: Double) -> String {
        number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
    }

    private func apply(_ op: String, _ a: Double, _ b: Double) -> Double {
        switch op {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        case "÷": return a / b
        default: return b
        }
    }
}

// MARK: - Flashlight

/// The iPhone's torch.
enum Torch {
    private static var device: AVCaptureDevice? {
        AVCaptureDevice.default(for: .video)
    }

    static var available: Bool { device?.hasTorch ?? false }

    static var isOn: Bool { device?.torchMode == .on }

    static var level: Float { device?.torchLevel ?? 0 }

    static func set(on: Bool, level: Float = 1) {
        guard let device = device, device.hasTorch else {
            OSLogger.shared.log("Torch", "No torch on this device", level: .warn)
            return
        }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: max(0.05, min(1, level)))
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            OSLogger.shared.log("Torch", on ? "On (\(Int(level * 100))%)" : "Off")
        } catch {
            OSLogger.shared.log("Torch", error.localizedDescription, level: .error)
        }
    }

    static func toggle() {
        set(on: !isOn)
    }
}

struct FlashlightApp: View {
    @EnvironmentObject private var os: OSSettings
    @State private var on = Torch.isOn
    @State private var level: Double = 1

    var body: some View {
        VStack(spacing: 30) {
            AppTitle(title: "Flashlight")
            Spacer()
            Button {
                Haptics.tap(.medium)
                on.toggle()
                Torch.set(on: on, level: Float(level))
            } label: {
                ZStack {
                    Circle()
                        .fill(on ? Color.yellow : Color.osCard)
                        .frame(width: 180, height: 180)
                        .shadow(color: on ? Color.yellow.opacity(0.7) : .clear, radius: 40)
                    Image(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 70))
                        .foregroundColor(on ? .black : .primary)
                }
            }
            .buttonStyle(PressScaleStyle())

            if !Torch.available {
                Text(os.t("This device has no flashlight")).foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Text(os.t("Brightness") + " \(Int(level * 100))%").font(.system(size: 15, weight: .semibold))
                Slider(value: $level, in: 0.05...1) { editing in
                    if !editing && on { Torch.set(on: true, level: Float(level)) }
                }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .onAppear { on = Torch.isOn }
    }
}

// MARK: - Compass

struct CompassApp: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var location = LocationProvider.shared

    var body: some View {
        let heading = location.heading.map { $0.trueHeading >= 0 ? $0.trueHeading : $0.magneticHeading } ?? 0

        VStack(spacing: 24) {
            AppTitle(title: "Compass")
            Spacer()
            ZStack {
                ForEach(0..<72, id: \.self) { tick in
                    Capsule()
                        .fill(Color.primary.opacity(tick % 6 == 0 ? 0.9 : 0.35))
                        .frame(width: tick % 6 == 0 ? 3 : 1.5, height: tick % 6 == 0 ? 18 : 10)
                        .offset(y: -135)
                        .rotationEffect(.degrees(Double(tick) * 5))
                }
                ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { pair in
                    Text(os.t(pair.element))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(pair.offset == 0 ? .red : .primary)
                        .rotationEffect(.degrees(heading - Double(pair.offset) * 90))
                        .offset(y: -100)
                        .rotationEffect(.degrees(Double(pair.offset) * 90))
                }
            }
            .rotationEffect(.degrees(-heading))
            .animation(.interpolatingSpring(stiffness: 60, damping: 12), value: heading)
            .frame(width: 300, height: 300)
            .overlay(alignment: .top) {
                Capsule().fill(Color.red).frame(width: 4, height: 30).offset(y: 5)
            }

            Text("\(Int(heading))° \(direction(heading))")
                .font(.system(size: 48, weight: .light))
                .monospacedDigit()

            if let place = location.location {
                VStack(spacing: 4) {
                    Text(coordinate(place.coordinate))
                    Text(os.t("Altitude") + ": \(Int(place.altitude)) m")
                }
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            } else if !location.allowed {
                Button(os.t("Allow location")) {
                    PermissionsCenter.shared.request(.location)
                }
            }
            Spacer()
        }
        .onAppear { location.start(heading: true) }
        .onDisappear { location.stop(heading: true) }
    }

    private func direction(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return os.t(names[Int((degrees + 22.5) / 45) % 8])
    }

    private func coordinate(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.4f° %@, %.4f° %@", abs(c.latitude), c.latitude >= 0 ? "N" : "S", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
    }
}
