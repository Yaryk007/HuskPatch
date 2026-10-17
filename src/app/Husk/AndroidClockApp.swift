// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit
import UserNotifications

/// HuskPatch: Android OS mode's Clock, as AOSP's DeskClock lays it out: Alarms, Clock, Timer and Stopwatch along the bottom.
/// Alarms and a running timer are iOS notifications, so they go off with HuskPatch closed (as a notification, not a ringing
/// screen: iOS keeps alarms that ring to its own Clock app).
enum AndroidAlarms {
    struct Alarm: Codable, Identifiable, Hashable {
        var id = UUID()
        var hour: Int
        var minute: Int
        var label = ""
        var on = true
        /// Weekdays it repeats on, 1 (Sunday) to 7; empty: once.
        var days: Set<Int> = []
    }

    static let key = "huskpatch.clock.alarms"

    static func load() -> [Alarm] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Alarm].self, from: $0) } ?? []
    }

    static func save(_ alarms: [Alarm]) {
        if let d = try? JSONEncoder().encode(alarms) { UserDefaults.standard.set(d, forKey: key) }
        schedule(alarms)
    }

    /// Each alarm that is on, as a calendar notification (one per weekday when it repeats).
    static func schedule(_ alarms: [Alarm]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("huskpatch.alarm.") })
            center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                guard ok else { return }
                for a in alarms where a.on {
                    let content = UNMutableNotificationContent()
                    content.title = "Alarm"
                    content.body = (a.label.isEmpty ? "" : a.label + " · ") + String(format: "%02d:%02d", a.hour, a.minute)
                    content.sound = .defaultCritical
                    content.interruptionLevel = .timeSensitive
                    let days: [Int?] = a.days.isEmpty ? [nil] : a.days.sorted().map { $0 }
                    for d in days {
                        var c = DateComponents(hour: a.hour, minute: a.minute)
                        c.weekday = d
                        let trigger = UNCalendarNotificationTrigger(dateMatching: c, repeats: d != nil)
                        center.add(UNNotificationRequest(identifier: "huskpatch.alarm.\(a.id).\(d ?? 0)", content: content, trigger: trigger))
                    }
                }
            }
        }
    }

    static func next(_ a: Alarm, after now: Date = Date()) -> Date? {
        let cal = Calendar.current
        let days: [Int?] = a.days.isEmpty ? [nil] : a.days.map { $0 }
        return days.compactMap { d -> Date? in
            var c = DateComponents(hour: a.hour, minute: a.minute)
            c.weekday = d
            return cal.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
        }.min()
    }
}

struct AndroidClockApp: View {
    enum Tab: Hashable { case alarms, clock, timer, stopwatch }
    @State private var tab = Tab.clock

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .alarms: AlarmsPage()
                case .clock: WorldClockPage()
                case .timer: TimerPage()
                case .stopwatch: StopwatchPage()
                }
            }
            .frame(maxHeight: .infinity)
            SystemNavigationBar(selection: $tab, items: [(.alarms, "Alarm", "alarm"), (.clock, "Clock", "clock"),
                                                          (.timer, "Timer", "hourglass"), (.stopwatch, "Stopwatch", "stopwatch")])
        }
        .background(Color(uiColor: Material3.surface))
    }
}

// MARK: - Alarms

private struct AlarmsPage: View {
    @State private var alarms = AndroidAlarms.load()
    @State private var editing: AndroidAlarms.Alarm?
    @State private var newTime = Date()
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: "Alarm", large: true)
            if alarms.isEmpty {
                SystemEmptyState(icon: "alarm", text: "No alarms")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($alarms) { $a in AlarmCard(alarm: $a, onDelete: { delete(a) }, onChange: { AndroidAlarms.save(alarms) }) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 110)
                }
            }
        }
        .overlay(alignment: .bottom) {
            AndroidFAB(icon: "plus", large: true) { newTime = Date(); adding = true }.padding(.bottom, 16)
        }
        .overlay {
            if adding {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { adding = false }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select time").font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        DatePicker("", selection: $newTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                        HStack {
                            Spacer()
                            Button("Cancel") { adding = false }.buttonStyle(.expressive(.text))
                            Button("OK") {
                                let c = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                                alarms.append(.init(hour: c.hour ?? 7, minute: c.minute ?? 0))
                                alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
                                AndroidAlarms.save(alarms)
                                adding = false
                            }
                            .buttonStyle(.expressive(.text))
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 340)
                    .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 24)
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: adding)
    }

    private func delete(_ a: AndroidAlarms.Alarm) {
        withAnimation(.snappy) { alarms.removeAll { $0.id == a.id } }
        AndroidAlarms.save(alarms)
    }
}

private struct AlarmCard: View {
    @Binding var alarm: AndroidAlarms.Alarm
    let onDelete: () -> Void
    let onChange: () -> Void
    @State private var expanded = false

    private let letters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !alarm.label.isEmpty || expanded {
                TextField("Add label", text: $alarm.label, onCommit: onChange)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            HStack(alignment: .center) {
                Text(String(format: "%d:%02d", alarm.hour, alarm.minute))
                    .font(.system(size: 54, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(uiColor: alarm.on ? Material3.onSurface : Material3.onSurfaceVariant))
                Spacer()
                Toggle("", isOn: Binding(get: { alarm.on }, set: { alarm.on = $0; onChange() }))
                    .labelsHidden().toggleStyle(Material3SwitchStyle())
            }
            HStack {
                Text(summary).font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Spacer()
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 36, height: 36)
                        .background(Color(uiColor: Material3.surfaceContainerHighest), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(uiColor: Material3.onSurface))
            }
            if expanded {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { d in
                        let on = alarm.days.contains(d)
                        Button {
                            if on { alarm.days.remove(d) } else { alarm.days.insert(d) }
                            onChange()
                        } label: {
                            Text(letters[d - 1]).font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(uiColor: on ? Material3.onPrimary : Material3.onSurface))
                                .frame(width: 38, height: 38)
                                .background(Color(uiColor: on ? Material3.primary : Material3.surfaceContainerHighest), in: Circle())
                        }
                        .buttonStyle(AndroidSquashStyle())
                    }
                }
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash").font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Color(uiColor: alarm.on ? Material3.surfaceContainerHigh : Material3.surfaceContainer),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var summary: String {
        if alarm.days.isEmpty {
            guard let n = AndroidAlarms.next(alarm) else { return "Not scheduled" }
            return Calendar.current.isDateInToday(n) ? "Today" : "Tomorrow"
        }
        if alarm.days.count == 7 { return "Every day" }
        if alarm.days == [2, 3, 4, 5, 6] { return "Mon–Fri" }
        return alarm.days.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}

// MARK: - Clock

private struct WorldClockPage: View {
    @AppStorage("huskpatch.clock.cities") private var citiesRaw = ""
    @State private var picking = false
    @State private var search = ""

    private var cities: [String] { citiesRaw.split(separator: ",").map(String.init) }

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: "Clock", large: false)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                ScrollView {
                    VStack(spacing: 6) {
                        Text(ctx.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 76, weight: .regular, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                        Text(ctx.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                            .padding(.bottom, 24)
                        ForEach(cities, id: \.self) { id in
                            if let tz = TimeZone(identifier: id) { cityRow(tz, ctx.date) }
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 110)
                }
            }
        }
        .overlay(alignment: .bottom) {
            AndroidFAB(icon: "globe", large: true) { picking = true }.padding(.bottom, 16)
        }
        .sheet(isPresented: $picking) { cityPicker }
    }

    private func cityRow(_ tz: TimeZone, _ now: Date) -> some View {
        let f = DateFormatter()
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate("jmm")
        let diff = (tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(city(tz.identifier)).font(.system(size: 18, design: .rounded)).foregroundStyle(Color(uiColor: Material3.onSurface))
                Text(diff == 0 ? "Same time" : "\(diff > 0 ? "+" : "")\(diff) hr")
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            Spacer()
            Text(f.string(from: now)).font(.system(size: 34, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color(uiColor: Material3.onSurface))
        }
        .padding(18)
        .background(Color(uiColor: Material3.surfaceContainer), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            Button(role: .destructive) { citiesRaw = cities.filter { $0 != tz.identifier }.joined(separator: ",") } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private func city(_ id: String) -> String { id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id }

    private var cityPicker: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: "Select a city", onBack: { picking = false })
            TextField("Search", text: $search)
                .padding(.horizontal, 18).frame(height: 48)
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                .padding(.horizontal, 16).padding(.bottom, 8)
            List(TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { id in
                Button(city(id) + "  ·  " + id) {
                    if !cities.contains(id) { citiesRaw = (cities + [id]).joined(separator: ",") }
                    picking = false
                }
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .listRowBackground(Color(uiColor: Material3.surfaceContainerLow))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color(uiColor: Material3.surface))
    }
}

// MARK: - Timer

private struct TimerPage: View {
    @State private var entry = ""
    @State private var total: TimeInterval = 0
    @State private var ends: Date?
    @State private var pausedLeft: TimeInterval?

    private static let notification = "huskpatch.timer"

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: "Timer", large: false)
            if total == 0 { keypad } else { running }
        }
    }

    /// hh mm ss, filled from the right as digits are typed, as DeskClock does.
    private var typed: (Int, Int, Int) {
        let d = String(repeating: "0", count: max(0, 6 - entry.count)) + entry
        let a = Array(d)
        return (Int(String(a[0...1]))!, Int(String(a[2...3]))!, Int(String(a[4...5]))!)
    }

    private var keypad: some View {
        VStack(spacing: 18) {
            let t = typed
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                unit(t.0, "h"); unit(t.1, "m"); unit(t.2, "s")
            }
            .foregroundStyle(Color(uiColor: entry.isEmpty ? Material3.onSurfaceVariant : Material3.primary))
            .padding(.top, 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "⌫"], id: \.self) { k in
                    Button {
                        if k == "⌫" { if !entry.isEmpty { entry.removeLast() } }
                        else if entry.count < 6, !(entry.isEmpty && k.hasPrefix("0")) { entry = String((entry + k).prefix(6)) }
                    } label: {
                        Text(k).font(.system(size: 28, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                            .frame(width: 88, height: 72)
                            .background(Color(uiColor: k == "⌫" ? Material3.secondaryContainer : Material3.surfaceContainerHigh), in: Capsule())
                    }
                    .buttonStyle(AndroidSquashStyle())
                }
            }
            .padding(.horizontal, 28)
            Spacer()
            if !entry.isEmpty {
                AndroidFAB(icon: "play.fill", large: true) { start(seconds: TimeInterval(t.0 * 3600 + t.1 * 60 + t.2)) }
                    .padding(.bottom, 16)
            }
        }
    }

    private func unit(_ v: Int, _ u: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(String(format: "%02d", v)).font(.system(size: 56, design: .rounded)).monospacedDigit()
            Text(u).font(.system(size: 20, design: .rounded))
        }
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let left = max(0, pausedLeft ?? (ends?.timeIntervalSince(ctx.date) ?? 0))
            VStack(spacing: 28) {
                ZStack {
                    Circle().stroke(Color(uiColor: Material3.surfaceContainerHighest), lineWidth: 12)
                    Circle().trim(from: 0, to: total > 0 ? left / total : 0)
                        .stroke(Color(uiColor: left == 0 ? Material3.error : Material3.primary), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(format(left)).font(.system(size: 52, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                }
                .frame(width: 280, height: 280)
                .padding(.top, 24)
                HStack(spacing: 24) {
                    Button("Delete") { reset() }.buttonStyle(.expressive(.tonal))
                    AndroidFAB(icon: pausedLeft == nil && left > 0 ? "pause.fill" : "play.fill", large: true) {
                        if let p = pausedLeft { start(seconds: p, keepTotal: true) }
                        else if left == 0 { reset() }
                        else { pausedLeft = left; ends = nil; cancelNotification() }
                    }
                    Button("+1:00") {
                        if let p = pausedLeft { pausedLeft = p + 60 } else { ends = (ends ?? Date()).addingTimeInterval(60); notify() }
                        total += 60
                    }
                    .buttonStyle(.expressive(.tonal))
                }
                Spacer()
            }
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func start(seconds: TimeInterval, keepTotal: Bool = false) {
        guard seconds > 0 else { return }
        if !keepTotal { total = seconds }
        pausedLeft = nil
        ends = Date().addingTimeInterval(seconds)
        entry = ""
        notify()
    }

    private func notify() {
        guard let ends else { return }
        cancelNotification()
        let c = UNMutableNotificationContent()
        c.title = "Timer"
        c.body = "Time's up"
        c.sound = .defaultCritical
        c.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, ends.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            if ok { UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notification, content: c, trigger: trigger)) }
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notification])
    }

    private func reset() {
        cancelNotification()
        total = 0; ends = nil; pausedLeft = nil; entry = ""
    }
}

// MARK: - Stopwatch

private struct StopwatchPage: View {
    @State private var started: Date?
    @State private var banked: TimeInterval = 0
    @State private var laps: [TimeInterval] = []

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: "Stopwatch", large: false)
            TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                let elapsed = banked + (started.map { ctx.date.timeIntervalSince($0) } ?? 0)
                VStack(spacing: 24) {
                    ZStack {
                        Circle().stroke(Color(uiColor: Material3.surfaceContainerHighest), lineWidth: 10)
                        Circle().trim(from: 0, to: elapsed.truncatingRemainder(dividingBy: 60) / 60)
                            .stroke(Color(uiColor: Material3.primary), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(format(elapsed)).font(.system(size: 46, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                    }
                    .frame(width: 270, height: 270)
                    .padding(.top, 16)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(laps.enumerated().reversed()), id: \.offset) { i, lap in
                                HStack {
                                    Text("# \(i + 1)")
                                    Spacer()
                                    Text(format(lap - (i > 0 ? laps[i - 1] : 0)))
                                    Spacer()
                                    Text(format(lap))
                                }
                                .font(.system(size: 16, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                .padding(.horizontal, 32)
                            }
                        }
                    }
                    HStack(spacing: 24) {
                        Button(started == nil ? "Reset" : "Lap") {
                            if started == nil { banked = 0; laps = [] } else { laps.append(elapsed) }
                        }
                        .buttonStyle(.expressive(.tonal))
                        .disabled(started == nil && banked == 0)
                        AndroidFAB(icon: started == nil ? "play.fill" : "pause.fill", large: true) {
                            if let s = started { banked += Date().timeIntervalSince(s); started = nil } else { started = Date() }
                        }
                        Color.clear.frame(width: 80, height: 1)
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let cs = Int(t * 100)
        let m = cs / 6000, s = cs / 100 % 60, c = cs % 100
        return m >= 60 ? String(format: "%d:%02d:%02d.%02d", m / 60, m % 60, s, c) : String(format: "%02d:%02d.%02d", m, s, c)
    }
}
