import SwiftUI

struct SettingsApp: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var controls = SystemControls.shared
    @ObservedObject private var permissions = PermissionsCenter.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .frame(width: 58, height: 58)
                            .background(Circle().fill(Color.accentColor))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(UIDevice.current.name).font(.system(size: 20, weight: .bold))
                            Text(DeviceInfo.appVersion + " · " + DeviceInfo.systemVersion)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section(os.t("Display")) {
                    Picker(selection: $os.theme) {
                        ForEach(ThemeMode.allCases) { Text(os.t($0.title)).tag($0) }
                    } label: {
                        row("circle.lefthalf.filled", .indigo, "Theme")
                    }
                    NavigationLink {
                        ScrollView {
                            WallpaperGrid(columns: 2, height: 260).padding(16)
                        }
                        .navigationTitle(os.t("Wallpaper"))
                    } label: {
                        row("photo.artframe", .teal, "Wallpaper", value: os.t(WallpaperPreset.preset(os.wallpaper).name))
                    }
                    VStack(alignment: .leading) {
                        row("sun.max.fill", .orange, "Brightness")
                        Slider(value: Binding(get: { Double(controls.brightness) }, set: { controls.setBrightness(CGFloat($0)) }))
                    }
                    Toggle(isOn: $os.showLabels) { row("textformat", .gray, "App labels") }
                }

                Section(os.t("Sounds")) {
                    VStack(alignment: .leading) {
                        row("speaker.wave.2.fill", .pink, "Volume")
                        Slider(value: Binding(get: { Double(controls.volume) }, set: { controls.setVolume(CGFloat($0)) }))
                    }
                    Toggle(isOn: $os.haptics) { row("iphone.radiowaves.left.and.right", .purple, "Vibration") }
                }

                Section(os.t("Navigation")) {
                    Picker(selection: $os.navMode) {
                        ForEach(NavMode.allCases) { Text(os.t($0.title)).tag($0) }
                    } label: {
                        row("hand.draw.fill", .blue, "Navigation type")
                    }
                    Picker(selection: $os.animStyle) {
                        ForEach(AnimStyle.allCases) { Text(os.t($0.title)).tag($0) }
                    } label: {
                        row("sparkles", .mint, "App animation")
                    }
                    Text(os.t("Swipe in from the left or right edge for the Lab panel with every animation setting."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Section(os.t("General")) {
                    Picker(selection: $os.language) {
                        ForEach(OSLanguage.allCases) { Text("\($0.flag) \($0.nativeName)").tag($0) }
                    } label: {
                        row("globe", .blue, "Language")
                    }
                    Toggle(isOn: $os.clock24h) { row("clock.fill", .gray, "24-hour time") }
                    Toggle(isOn: $os.showBattery) { row("battery.75", .green, "Battery percentage") }
                }

                Section(os.t("Privacy")) {
                    ForEach(PermissionsCenter.Kind.allCases) { kind in
                        let status = permissions.status(kind)
                        Button {
                            if status == .notAsked {
                                permissions.request(kind)
                            } else {
                                openURL(UIApplication.openSettingsURLString)
                            }
                        } label: {
                            row(kind.symbol, .blue, kind.title, value: os.t(statusText(status)))
                        }
                        .foregroundColor(.primary)
                    }
                }

                Section(os.t("Battery")) {
                    TimelineView(.periodic(from: .now, by: 10)) { _ in
                        VStack(spacing: 10) {
                            info("Level", DeviceInfo.battery)
                            info("Low Power Mode", os.t(DeviceInfo.lowPower ? "On" : "Off"))
                            info("Temperature", os.t(DeviceInfo.thermal))
                        }
                    }
                }

                Section(os.t("About phone")) {
                    let storage = DeviceInfo.storage
                    info("Model", DeviceInfo.modelIdentifier)
                    info("Software", DeviceInfo.systemVersion)
                    info("Processor", "\(DeviceInfo.cores) " + os.t("cores"))
                    info("Memory", DeviceInfo.memory)
                    info(
                        "Storage",
                        ByteCountFormatter.string(fromByteCount: storage.free, countStyle: .file) + " "
                            + os.t("free of") + " "
                            + ByteCountFormatter.string(fromByteCount: storage.total, countStyle: .file)
                    )
                    info("Screen", DeviceInfo.screen)
                    info("Uptime", DeviceInfo.uptime)
                }

                Section {
                    HostExitButton()
                    Button(os.t("Run setup again")) { os.setupDone = false }
                    Button(os.t("Reset all settings"), role: .destructive) { os.resetAll() }
                }
            }
            .navigationTitle(os.t("Settings"))
        }
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, value: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
            Text(os.t(title))
            if let value = value {
                Spacer()
                Text(value).foregroundColor(.secondary)
            }
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        HStack {
            Text(os.t(title))
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusText(_ status: PermissionsCenter.Status) -> String {
        switch status {
        case .allowed: return "Allowed"
        case .denied: return "Denied"
        case .notAsked: return "Not asked"
        }
    }
}
