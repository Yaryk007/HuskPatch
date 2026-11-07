import SwiftUI

/// Settings, laid out as Android's: one list of categories, each opening its own page.
struct SettingsApp: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var host = ModemOSHost.shared
    @State private var search = ""

    private struct Entry: Identifiable {
        let id: String
        let symbol: String
        let color: Color
        let subtitle: String
        let page: AnyView
    }

    private var entries: [Entry] {
        [
            Entry(id: "Look & style", symbol: "paintpalette.fill", color: rgb(120, 110, 240),
                  subtitle: os.t(os.design.title), page: AnyView(LookPage())),
            Entry(id: "Display", symbol: "sun.max.fill", color: rgb(240, 170, 40),
                  subtitle: os.t("Brightness, dark theme"), page: AnyView(DisplayPage())),
            Entry(id: "Sound & vibration", symbol: "speaker.wave.2.fill", color: rgb(230, 90, 150),
                  subtitle: os.t("Volume, vibration"), page: AnyView(SoundPage())),
            Entry(id: "Apps", symbol: "square.grid.2x2.fill", color: rgb(60, 170, 110),
                  subtitle: "\(host.installed.count) " + os.t("installed"), page: AnyView(AppsPage())),
            Entry(id: "Gestures & navigation", symbol: "hand.draw.fill", color: rgb(50, 140, 240),
                  subtitle: os.t(os.navMode.title), page: AnyView(NavigationPage())),
            Entry(id: "Privacy", symbol: "lock.shield.fill", color: rgb(90, 120, 200),
                  subtitle: os.t("Permissions"), page: AnyView(PrivacyPage())),
            Entry(id: "Battery", symbol: "battery.100", color: rgb(70, 190, 120),
                  subtitle: DeviceInfo.battery, page: AnyView(BatteryPage())),
            Entry(id: "Storage", symbol: "internaldrive.fill", color: rgb(130, 120, 110),
                  subtitle: DeviceInfo.storageLine(os), page: AnyView(StoragePage())),
            Entry(id: "System", symbol: "gearshape.2.fill", color: rgb(120, 125, 140),
                  subtitle: os.t("Language, time, reset"), page: AnyView(SystemPage())),
            Entry(id: "About phone", symbol: "info.circle.fill", color: rgb(70, 150, 200),
                  subtitle: OSSettings.systemName + " " + OSSettings.systemVersion, page: AnyView(AboutPage())),
        ]
    }

    private var shown: [Entry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { os.t($0.id).localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            OSPushedPage {
                OSPage(title: "Settings") {
                    OSSearchField(prompt: "Search settings", text: $search)
                    OSGroup {
                        ForEach(shown) { entry in
                            OSLinkRow(symbol: entry.symbol, color: entry.color, title: entry.id, subtitle: entry.subtitle) {
                                entry.page
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A page under Settings, with the way back.
private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OSPage(title: title, onBack: { dismiss() }) { content }
    }
}

private struct LookPage: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        SettingsPage(title: "Look & style") {
            OSGroup(title: "Look") { DesignPicker().padding(.vertical, 4) }
            OSGroup(title: "Wallpaper") { WallpaperGrid(columns: 3, height: 170) }
            OSGroup(title: "Icons") {
                OSToggleRow(symbol: "textformat", color: .gray, title: "App labels", isOn: $os.showLabels)
                OSToggleRow(symbol: "square.grid.2x2.fill", color: .blue, title: "Apps on the home screen", isOn: $os.homeApps)
                OSToggleRow(symbol: "clock.fill", color: .orange, title: "Clock widget", isOn: $os.clockWidget)
            }
        }
    }
}

private struct DisplayPage: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var controls = SystemControls.shared

    var body: some View {
        SettingsPage(title: "Display") {
            OSGroup(title: "Brightness") {
                OSSlider(value: Binding(get: { Double(controls.brightness) }, set: { controls.setBrightness(CGFloat($0)) }), symbol: "sun.max.fill")
                    .padding(.vertical, 8)
            }
            OSGroup(title: "Theme") {
                OSSegmented(selection: $os.theme, options: ThemeMode.allCases.map { ($0, $0.title) })
            }
        }
    }
}

private struct SoundPage: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var controls = SystemControls.shared

    var body: some View {
        SettingsPage(title: "Sound & vibration") {
            OSGroup(title: "Volume") {
                OSSlider(value: Binding(get: { Double(controls.volume) }, set: { controls.setVolume(CGFloat($0)) }), symbol: "speaker.wave.2.fill")
                    .padding(.vertical, 8)
            }
            OSGroup {
                OSToggleRow(symbol: "iphone.radiowaves.left.and.right", color: .purple, title: "Vibration", isOn: $os.haptics)
            }
        }
    }
}

private struct AppsPage: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var host = ModemOSHost.shared

    var body: some View {
        SettingsPage(title: "Apps") {
            if host.installed.isEmpty {
                Text(os.t("No apps installed yet. Add them from the HuskPatch folder in the app drawer."))
                    .font(.system(size: 15))
                    .foregroundColor(os.palette.onSurfaceVariant)
                    .padding(.horizontal, 6)
            } else {
                OSGroup(title: "Installed") {
                    ForEach(HomeItem.installedApps) { item in
                        HStack(spacing: 14) {
                            AppIconView(item: item, size: 40, radius: 40 * CGFloat(os.iconRoundness))
                            Text(item.name)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(os.palette.onSurface)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minHeight: 64)
                        .modifier(OSRowSurface())
                    }
                }
            }
        }
    }
}

private struct NavigationPage: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        SettingsPage(title: "Gestures & navigation") {
            OSGroup(title: "Navigation type") {
                OSSegmented(selection: $os.navMode, options: NavMode.allCases.map { ($0, $0.title) })
            }
            OSGroup(title: "App animation") {
                AnimStylePicker()
            }
            Text(os.t("Swipe in from the left or right edge for the Lab panel with every animation setting."))
                .font(.system(size: 14))
                .foregroundColor(os.palette.onSurfaceVariant)
                .padding(.horizontal, 6)
        }
    }
}

private struct PrivacyPage: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var permissions = PermissionsCenter.shared

    var body: some View {
        SettingsPage(title: "Privacy") {
            OSGroup(title: "Permissions") {
                ForEach(PermissionsCenter.Kind.allCases) { kind in
                    let status = permissions.status(kind)
                    Button {
                        if status == .notAsked {
                            permissions.request(kind)
                        } else {
                            openURL(UIApplication.openSettingsURLString)
                        }
                    } label: {
                        OSValueRow(symbol: kind.symbol, color: .blue, title: kind.title, value: os.t(statusText(status)))
                    }
                    .buttonStyle(PressDimStyle())
                }
            }
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

private struct BatteryPage: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        SettingsPage(title: "Battery") {
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                OSGroup {
                    OSValueRow(symbol: "battery.100", color: .green, title: "Level", value: DeviceInfo.battery)
                    OSValueRow(symbol: "leaf.fill", color: .mint, title: "Low Power Mode", value: os.t(DeviceInfo.lowPower ? "On" : "Off"))
                    OSValueRow(symbol: "thermometer.medium", color: .orange, title: "Temperature", value: os.t(DeviceInfo.thermal))
                }
            }
            OSGroup {
                OSToggleRow(symbol: "percent", color: .green, title: "Battery percentage", isOn: $os.showBattery)
            }
        }
    }
}

private struct StoragePage: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        let storage = DeviceInfo.storage
        let used = storage.total > 0 ? Double(storage.total - storage.free) / Double(storage.total) : 0

        SettingsPage(title: "Storage") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(DeviceInfo.storageLine(os))
                        .font(os.display(22, weight: .semibold))
                        .foregroundColor(os.palette.onSurface)
                    ExpressiveLinearProgressIndicator(progress: used)
                }
            }
        }
    }
}

private struct SystemPage: View {
    @EnvironmentObject private var os: OSSettings
    @State private var confirmReset = false

    var body: some View {
        SettingsPage(title: "System") {
            OSGroup(title: "Language") {
                Menu {
                    Picker("", selection: $os.language) {
                        ForEach(OSLanguage.allCases) { Text("\($0.flag) \($0.nativeName)").tag($0) }
                    }
                } label: {
                    OSValueRow(symbol: "globe", color: .blue, title: "Language", value: os.language.nativeName)
                }
            }
            OSGroup(title: "Date & time") {
                OSToggleRow(symbol: "clock.fill", color: .gray, title: "24-hour time", isOn: $os.clock24h)
            }
            OSGroup(title: "Startup") {
                OSToggleRow(symbol: "terminal.fill", color: .green, title: "Boot sequence",
                            subtitle: os.t("Plays the forced Android boot at each start"), isOn: $os.forcedBoot)
            }
            OSGroup {
                if ModemOSHost.shared.app("settings") != nil {
                    Button(os.t("Android settings")) { ModemOSHost.shared.openRequest = "settings" }
                        .buttonStyle(OSButtonStyle(.plain))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .modifier(OSRowSurface(indented: false))
                }
                HostExitButton()
                    .buttonStyle(OSButtonStyle(.plain))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .modifier(OSRowSurface(indented: false))
                Button(os.t("Run setup again")) { os.setupDone = false }
                    .buttonStyle(OSButtonStyle(.plain))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .modifier(OSRowSurface(indented: false))
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Text(os.t("Reset all settings")).foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .modifier(OSRowSurface(indented: false))
                .confirmationDialog(os.t("Reset all settings?"), isPresented: $confirmReset) {
                    Button(os.t("Reset all settings"), role: .destructive) { os.resetAll() }
                }
            }
        }
    }
}

private struct AboutPage: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        SettingsPage(title: "About phone") {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text(UIDevice.current.name)
                        .font(os.display(26))
                        .foregroundColor(os.palette.onSurface)
                    Text(OSSettings.systemName + " " + OSSettings.systemVersion)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(os.palette.primary)
                }
            }
            OSGroup(title: "Software") {
                OSValueRow(title: "ModemOS version", value: OSSettings.systemVersion)
                OSValueRow(title: "Android version", value: OSSettings.androidVersion)
                OSValueRow(title: "Build number", value: OSSettings.buildNumber)
                OSValueRow(title: "Kernel version", value: DeviceInfo.kernel)
            }
            OSGroup(title: "Hardware") {
                OSValueRow(title: "Model", value: DeviceInfo.modelIdentifier)
                OSValueRow(title: "Processor", value: "\(DeviceInfo.cores) " + os.t("cores"))
                OSValueRow(title: "Memory", value: DeviceInfo.memory)
                OSValueRow(title: "Screen", value: DeviceInfo.screen)
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                OSGroup {
                    OSValueRow(title: "Uptime", value: DeviceInfo.uptime)
                }
            }
        }
    }
}
