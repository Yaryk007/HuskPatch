import SwiftUI
import UIKit

/// Choices shared by setup, the Lab panel and the Settings app.

struct LanguagePicker: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(spacing: 8) {
            ForEach(OSLanguage.allCases) { language in
                OptionRow(selected: os.language == language) {
                    os.language = language
                } label: {
                    Text(language.flag).font(.system(size: 26))
                    Text(language.nativeName).font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }
}

struct ThemePicker: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ThemeMode.allCases) { mode in
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.35)) { os.theme = mode }
                } label: {
                    VStack(spacing: 10) {
                        ThemePreview(mode: mode)
                            .frame(height: 170)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(os.theme == mode ? Color.accentColor : Color.clear, lineWidth: 3)
                            )
                        Label(os.t(mode.title), systemImage: os.theme == mode ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(PressScaleStyle(pressedScale: 0.96))
            }
        }
    }
}

/// A tiny phone showing the wallpaper and a glass dock in the given theme.
private struct ThemePreview: View {
    let mode: ThemeMode
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper(preset: WallpaperPreset.preset(os.wallpaper))
            if mode == .dark { Color.black.opacity(0.18) }
            VStack(spacing: 6) {
                Capsule()
                    .fill(mode == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.6))
                    .frame(height: 10)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(HomeItem.dock[index].color)
                            .frame(width: 18, height: 18)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(mode == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.6))
                )
                .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct WallpaperGrid: View {
    var columns = 3
    var height: CGFloat = 150

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(WallpaperPreset.all) { paper in
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.3)) { os.wallpaper = paper.id }
                } label: {
                    Wallpaper(preset: paper)
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(os.wallpaper == paper.id ? Color.white : Color.clear, lineWidth: 3)
                        )
                        .overlay(alignment: .bottomLeading) {
                            Text(os.t(paper.name))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                                .padding(8)
                        }
                        .overlay(alignment: .topTrailing) {
                            if os.wallpaper == paper.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .shadow(radius: 3)
                                    .padding(6)
                            }
                        }
                }
                .buttonStyle(PressScaleStyle(pressedScale: 0.95))
            }
        }
    }
}

struct NavModePicker: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(spacing: 10) {
            ForEach(NavMode.allCases) { mode in
                OptionRow(selected: os.navMode == mode) {
                    os.navMode = mode
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(os.t(mode.title)).font(.system(size: 17, weight: .semibold))
                        illustration(mode)
                    }
                }
            }
        }
    }

    private func illustration(_ mode: NavMode) -> some View {
        HStack {
            if mode == .gestures {
                Spacer()
                Capsule().frame(width: 70, height: 5)
                Spacer()
            } else {
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in Capsule().frame(width: 2.5, height: 13) }
                }
                Spacer()
                RoundedRectangle(cornerRadius: 4).stroke(lineWidth: 2).frame(width: 14, height: 14)
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                Spacer()
            }
        }
        .foregroundColor(.primary.opacity(0.8))
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
    }
}

struct AnimStylePicker: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AnimStyle.allCases) { style in
                OptionRow(selected: os.animStyle == style) {
                    os.animStyle = style
                } label: {
                    Image(systemName: style.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(os.t(style.title)).font(.system(size: 16, weight: .semibold))
                        Text(os.t(style.detail)).font(.system(size: 13)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

/// A slider with a title and its value on the right.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(os.t(title)).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(format(value))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if let step = step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}

/// A selectable row with a check mark.
struct OptionRow<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.25)) { action() }
        } label: {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selected ? .accentColor : .secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(PressScaleStyle(pressedScale: 0.97))
    }
}

/// Facts about this iPhone, read live.
enum DeviceInfo {
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static var systemVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    static var memory: String {
        ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
    }

    static var cores: Int { ProcessInfo.processInfo.activeProcessorCount }

    static var storage: (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values?.volumeTotalCapacity ?? 0))
    }

    static var uptime: String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        return days > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(hours)h \(minutes)m"
    }

    static var battery: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let percent = level < 0 ? "--" : "\(Int((level * 100).rounded()))"
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "Charging"
        case .full: state = "Full"
        case .unplugged: state = "On battery"
        default: state = "Unknown"
        }
        return "\(percent)% · \(state)"
    }

    static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    static var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    static var screen: String {
        let bounds = UIScreen.main.nativeBounds
        return "\(Int(bounds.width))×\(Int(bounds.height)) @\(Int(UIScreen.main.scale))x, \(UIScreen.main.maximumFramesPerSecond) Hz"
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "ModemOS \(version)"
    }
}
