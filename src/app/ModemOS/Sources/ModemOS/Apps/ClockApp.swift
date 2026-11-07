import SwiftUI
import AudioToolbox

struct ClockApp: View {
    private enum Tab: String, CaseIterable {
        case clock = "Clock", world = "World", stopwatch = "Stopwatch", timer = "Timer"

        var symbol: String {
            switch self {
            case .clock: return "clock"
            case .world: return "globe"
            case .stopwatch: return "stopwatch"
            case .timer: return "timer"
            }
        }
    }

    @EnvironmentObject private var os: OSSettings
    @State private var tab: Tab = .clock

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .clock: ClockFace()
            case .world: WorldClock()
            case .stopwatch: Stopwatch()
            case .timer: CountdownTimer()
            }

            OSTabBar(selection: $tab, items: Tab.allCases.map { ($0, $0.rawValue, $0.symbol) })
        }
    }
}

private struct ClockFace: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            VStack(spacing: 24) {
                AppTitle(title: "Clock")
                Spacer()
                AnalogClock(date: date)
                    .frame(width: 260, height: 260)
                Text(timeString(date))
                    .font(OSSettings.shared.display(64, weight: .light))
                    .monospacedDigit()
                Text(dateString(date))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                Text(TimeZone.current.localizedName(for: .standard, locale: os.language.locale) ?? TimeZone.current.identifier)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = os.clock24h ? "HH:mm:ss" : "h:mm:ss a"
        return formatter.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = os.language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }
}

struct AnalogClock: View {
    let date: Date

    var body: some View {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(parts.second ?? 0)
        let minutes = Double(parts.minute ?? 0) + seconds / 60
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60

        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(Color.osCard)
                ForEach(0..<12, id: \.self) { tick in
                    Capsule()
                        .fill(Color.primary.opacity(tick % 3 == 0 ? 0.8 : 0.3))
                        .frame(width: tick % 3 == 0 ? 4 : 2, height: size * 0.06)
                        .offset(y: -size * 0.42)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                hand(width: 6, length: size * 0.25, angle: hours * 30, color: .primary)
                hand(width: 4, length: size * 0.36, angle: minutes * 6, color: .primary)
                hand(width: 2, length: size * 0.4, angle: seconds * 6, color: .orange)
                Circle().fill(Color.orange).frame(width: 10, height: 10)
            }
            .frame(width: size, height: size)
        }
    }

    private func hand(width: CGFloat, length: CGFloat, angle: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}

private struct WorldClock: View {
    @EnvironmentObject private var os: OSSettings
    private let zones = ["Europe/Kyiv", "Europe/London", "America/New_York", "America/Los_Angeles", "Asia/Tokyo", "Australia/Sydney", "Asia/Dubai"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 10) {
                    AppTitle(title: "World")
                    ForEach(zones, id: \.self) { id in
                        if let zone = TimeZone(identifier: id) {
                            Card {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id)
                                            .font(.system(size: 19, weight: .semibold))
                                        Text(offset(zone)).font(.system(size: 13)).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(time(context.date, zone))
                                        .font(.system(size: 34, weight: .light))
                                        .monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private func time(_ date: Date, _ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = os.clock24h ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    private func offset(_ zone: TimeZone) -> String {
        let difference = (zone.secondsFromGMT() - TimeZone.current.secondsFromGMT()) / 3600
        if difference == 0 { return os.t("Same time") }
        return String(format: "%+d h", difference)
    }
}

private struct Stopwatch: View {
    @EnvironmentObject private var os: OSSettings
    @State private var startedAt: Date?
    @State private var stored: TimeInterval = 0
    @State private var laps: [TimeInterval] = []

    var body: some View {
        VStack(spacing: 20) {
            AppTitle(title: "Stopwatch")
            TimelineView(.animation(paused: startedAt == nil)) { context in
                Text(Self.format(elapsed(context.date)))
                    .font(OSSettings.shared.display(64, weight: .light))
                    .monospacedDigit()
            }
            .padding(.top, 40)

            HStack(spacing: 40) {
                roundButton(startedAt == nil ? (stored > 0 ? "Reset" : "Lap") : "Lap", color: .gray) {
                    if startedAt != nil {
                        laps.insert(elapsed(Date()), at: 0)
                    } else {
                        stored = 0
                        laps = []
                    }
                }
                roundButton(startedAt == nil ? "Start" : "Stop", color: startedAt == nil ? .green : .red) {
                    if let start = startedAt {
                        stored += Date().timeIntervalSince(start)
                        startedAt = nil
                    } else {
                        startedAt = Date()
                    }
                }
            }

            List {
                ForEach(Array(laps.enumerated()), id: \.offset) { pair in
                    HStack {
                        Text(os.t("Lap") + " \(laps.count - pair.offset)")
                        Spacer()
                        Text(Self.format(pair.element)).monospacedDigit()
                    }
                    .osListRow()
                }
            }
            .osList()
        }
    }

    private func elapsed(_ now: Date) -> TimeInterval {
        stored + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    static func format(_ time: TimeInterval) -> String {
        let centis = Int((time * 100).rounded(.down))
        return String(format: "%02d:%02d.%02d", centis / 6000, (centis / 100) % 60, centis % 100)
    }

    private func roundButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(os.t(title))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 88, height: 88)
                .background(Circle().fill(color.opacity(0.18)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

private struct CountdownTimer: View {
    @EnvironmentObject private var os: OSSettings
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var endsAt: Date?
    @State private var finished = false

    var body: some View {
        VStack(spacing: 20) {
            AppTitle(title: "Timer")
            Spacer()
            if let end = endsAt {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let left = max(0, end.timeIntervalSince(context.date))
                    Text(String(format: "%02d:%02d", Int(left) / 60, Int(left) % 60))
                        .font(OSSettings.shared.display(76, weight: .light))
                        .monospacedDigit()
                        .onChange(of: left <= 0) { done in
                            if done { ring() }
                        }
                }
            } else {
                HStack {
                    Picker("", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Picker("", selection: $seconds) {
                        ForEach(0..<60, id: \.self) { Text("\($0) s").tag($0) }
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 180)
            }
            if finished {
                Text(os.t("Time's up!")).font(.system(size: 22, weight: .bold)).foregroundColor(.orange)
            }
            Spacer()
            Button {
                Haptics.tap()
                finished = false
                if endsAt == nil {
                    let total = minutes * 60 + seconds
                    guard total > 0 else { return }
                    endsAt = Date().addingTimeInterval(TimeInterval(total))
                    OSLogger.shared.log("Clock", "Timer started for \(total)s")
                } else {
                    endsAt = nil
                }
            } label: {
                Text(os.t(endsAt == nil ? "Start" : "Cancel"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 56)
                    .background(Capsule().fill(endsAt == nil ? Color.green : Color.red))
            }
            .buttonStyle(PressScaleStyle())
            .padding(.bottom, 20)
        }
    }

    private func ring() {
        endsAt = nil
        finished = true
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        OSLogger.shared.log("Clock", "Timer finished")
    }
}
