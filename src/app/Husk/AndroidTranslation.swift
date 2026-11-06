// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Android translation, the experiment that is meant to replace QEMU, one piece of Android at a time. Its first stage
/// is the services (husk-tl-services.c): Android's system services answering the real Binder protocol in this process, with what
/// is true of this iPhone. Off by default, and each service starts by itself. Nothing here touches the QEMU machine.
@MainActor enum AndroidTranslation {
    static let key = "huskpatch.dev.androidTranslation"
    private static let startedKey = "huskpatch.dev.androidTranslation.services"
    private static var observing = false

    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }
    private static var chosen: [String] { UserDefaults.standard.stringArray(forKey: startedKey) ?? [] }

    /// At launch: the services left on last time, when the option is on.
    static func startIfEnabled() { if enabled { setEnabled(true) } }

    static func setEnabled(_ on: Bool) {
        if on {
            observe()
            publishState()
            chosen.forEach { _ = husk_services_start($0) }
            HuskLog.log("android", "Android translation on: \(chosen.count) service(s)")
        } else {
            services().forEach { husk_services_stop($0.name) }
            HuskLog.log("android", "Android translation off")
        }
    }

    static func set(_ name: String, running: Bool) {
        var names = chosen.filter { $0 != name }
        if running { names.append(name) }
        UserDefaults.standard.set(names, forKey: startedKey)
        if running { _ = husk_services_start(name) } else { husk_services_stop(name) }
    }

    struct Service: Identifiable {
        let name, descriptor, summary: String
        let running: Bool
        let handled, unhandled: UInt64
        let lastUnhandled: UInt32
        var id: String { name }
    }

    static func services() -> [Service] {
        (0..<husk_services_count()).compactMap { i in
            var info = husk_service_info()
            guard husk_services_info(i, &info) else { return nil }
            return Service(name: String(cString: info.name), descriptor: String(cString: info.descriptor), summary: String(cString: info.summary),
                           running: info.running, handled: info.handled, unhandled: info.unhandled, lastUnhandled: info.last_unhandled)
        }
    }

    /// The call an app would make, through Binder.
    static func probe(_ name: String) -> String {
        var text = [CChar](repeating: 0, count: 200)
        let ok = husk_services_probe(name, &text, Int32(text.count))
        let answer = String(cString: text)
        return ok ? answer : (answer.isEmpty ? "No answer" : answer)
    }

    private static func observe() {
        guard !observing else { return }
        observing = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        husk_services_set_wakelock_host { held in
            DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = held > 0 }
        }
        let names: [Notification.Name] = [
            UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
            ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange,
            UIApplication.didBecomeActiveNotification, UIApplication.didEnterBackgroundNotification,
            NSLocale.currentLocaleDidChangeNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in publishState() }
            }
        }
    }

    static func publishState() {
        var state = husk_services_state()
        let level = UIDevice.current.batteryLevel
        state.battery_percent = level < 0 ? -1 : Int32((level * 100).rounded())
        switch UIDevice.current.batteryState {
        case .charging: state.battery_status = 2
        case .unplugged: state.battery_status = 3
        case .full: state.battery_status = 5
        default: state.battery_status = 1
        }
        switch ProcessInfo.processInfo.thermalState {
        case .fair: state.thermal_status = 1        // THERMAL_STATUS_LIGHT
        case .serious: state.thermal_status = 3     // THERMAL_STATUS_SEVERE
        case .critical: state.thermal_status = 4    // THERMAL_STATUS_CRITICAL
        default: state.thermal_status = 0
        }
        state.low_power = ProcessInfo.processInfo.isLowPowerModeEnabled
        state.screen_on = UIApplication.shared.applicationState != .background
        state.night_mode = UIScreen.main.traitCollection.userInterfaceStyle == .dark ? 2 : 1
        let country = Array((Locale.current.regionCode ?? "").uppercased().utf8.prefix(7))
        withUnsafeMutableBytes(of: &state.country) { bytes in
            for (i, c) in country.enumerated() { bytes[i] = c }
        }
        husk_services_set_state(&state)
    }
}

/// The services, in Developer options under the toggle.
struct AndroidTranslationServices: View {
    @State private var services = AndroidTranslation.services()
    @State private var answers: [String: String] = [:]
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each one answers Android 16's real Binder calls with this iPhone's own state. Android apps do not use them yet: "
               + "that needs Android's framework.jar, which is not in this build. Test makes the call an app would make.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(services) { service in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(get: { service.running }, set: { on in
                        AndroidTranslation.set(service.name, running: on)
                        answers[service.name] = nil
                        services = AndroidTranslation.services()
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name).font(.system(size: 16, design: .monospaced))
                            Text(service.summary).font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(Material3SwitchStyle())
                    if service.running {
                        HStack(spacing: 10) {
                            Button("Test") { answers[service.name] = AndroidTranslation.probe(service.name); services = AndroidTranslation.services() }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text("\(service.handled) answered" + (service.unhandled > 0 ? ", \(service.unhandled) not written (code \(service.lastUnhandled))" : ""))
                                .font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                        }
                        if let answer = answers[service.name] {
                            Text(answer).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .onReceive(tick) { _ in services = AndroidTranslation.services() }
    }
}
