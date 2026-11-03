import SwiftUI
import UIKit

/// The Lab: a Good Lock style panel you swipe in from either side edge.
/// Motion (animation style, speed, bounce...), Look (theme, wallpaper, icons, glass), System, and the live log.
struct LabPanel: View {
    let onClose: () -> Void
    let onRunSetup: () -> Void

    private enum Tab: String, CaseIterable {
        case motion = "Motion", look = "Look", system = "System", logs = "Logs"

        var symbol: String {
            switch self {
            case .motion: return "wand.and.stars"
            case .look: return "paintpalette.fill"
            case .system: return "cpu"
            case .logs: return "list.bullet.rectangle"
            }
        }
    }

    @EnvironmentObject private var os: OSSettings
    @State private var tab: Tab = .motion

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            Divider().opacity(0.4)
            switch tab {
            case .motion: MotionTab()
            case .look: LookTab()
            case .system: SystemTab(onRunSetup: onRunSetup)
            case .logs: LogsTab()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "flask.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("ModemOS Lab").font(.system(size: 22, weight: .bold))
                Text(os.t("Make it yours")).font(.system(size: 13)).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .semibold))
                        Text(os.t(item.rawValue)).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(tab == item ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tab == item ? Color.primary.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(PressScaleStyle(pressedScale: 0.94))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

/// A titled group of settings.
private struct LabSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(os.t(title).uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }
}

private struct LabToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(os.t(title), systemImage: symbol).font(.system(size: 15, weight: .semibold))
        }
    }
}

// MARK: - Motion (Home Up style: a live phone preview, presets, and a custom animation builder)

private struct MotionTab: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PhonePreview()
                    .frame(maxWidth: .infinity)

                LabSection(title: "Home gesture animation") {
                    // The four Home Up presets, as radio rows like Home Up's own list.
                    VStack(spacing: 0) {
                        ForEach([AnimStyle.oneUI, .elegance, .dynamic, .sweet]) { style in
                            homeUpRow(style)
                            if style != .sweet {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                    Text(os.t("More"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        ForEach([AnimStyle.zoom, .slide, .fade, .custom]) { style in
                            presetChip(style)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if os.animStyle == .custom {
                    customSection
                } else {
                    Button {
                        Haptics.tap()
                        copyToCustom()
                    } label: {
                        Label(os.t("Customise this animation"), systemImage: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                LabSection(title: "Feel") {
                    RainbowSpeedBar()
                    LabeledSlider(title: "Bounce", value: $os.bounce, range: 0...1) { "\(Int($0 * 100))%" }
                    HStack(spacing: 8) {
                        ForEach([("None", 0.0), ("Soft", 0.35), ("Bouncy", 0.7), ("Jelly", 1.0)], id: \.1) { preset in
                            chip(os.t(preset.0), selected: abs(os.bounce - preset.1) < 0.01) {
                                os.bounce = preset.1
                            }
                        }
                    }
                }

                LabSection(title: "Background") {
                    LabeledSlider(title: "Home screen zoom", value: $os.homeZoom, range: 0...0.25) { "\(Int($0 * 100))%" }
                    LabeledSlider(title: "Blur strength", value: $os.blurStrength, range: 0...30) {
                        $0 < 0.5 ? os.t("Off") : "\(Int($0))"
                    }
                    LabeledSlider(title: "Dim", value: $os.homeDim, range: 0...0.5) { "\(Int($0 * 200))%" }
                    LabToggle(title: "Icon ripple on close", symbol: "dot.radiowaves.left.and.right", isOn: $os.rippleEnabled)
                }

                LabSection(title: "App switcher") {
                    Picker("", selection: $os.recentsLayout) {
                        ForEach(RecentsLayout.allCases) { Text(os.t($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabToggle(title: "Hold the gesture line for Recents", symbol: "hand.tap.fill", isOn: $os.holdForRecents)
                }

                Button(role: .destructive) {
                    Haptics.tap()
                    os.resetMotion()
                } label: {
                    Label(os.t("Reset motion"), systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.leading, 4)
            }
            .padding(16)
        }
    }

    private var customSection: some View {
        LabSection(title: "Custom animation") {
            VStack(alignment: .leading, spacing: 6) {
                Text(os.t("Start from")).font(.system(size: 15, weight: .semibold))
                Picker("", selection: $os.customOrigin) {
                    ForEach(AnimOrigin.allCases) { Text(os.t($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            LabeledSlider(title: "Open duration", value: $os.customOpen, range: 0.15...1.5) { String(format: "%.2fs", $0) }
            LabeledSlider(title: "Close duration", value: $os.customClose, range: 0.15...1.5) { String(format: "%.2fs", $0) }
            if os.customOrigin == .icon {
                LabeledSlider(title: "Icon fade", value: $os.customIconFade, range: 1...6) { String(format: "%.1f", $0) }
            } else {
                LabeledSlider(title: "Start size", value: $os.customStartScale, range: 0.05...1) { "\(Int($0 * 100))%" }
                LabeledSlider(title: "Corner radius", value: $os.customRadius, range: 0...80) { "\(Int($0))" }
            }
            LabeledSlider(title: "Spin", value: $os.customSpin, range: -45...45) { "\(Int($0))°" }
            LabToggle(title: "Fade in", symbol: "circle.lefthalf.filled", isOn: $os.customFade)
            Divider()
            LabeledSlider(title: "Translucency", value: $os.customTranslucency, range: 0...0.8) { "\(Int($0 * 100))%" }
            LabeledSlider(title: "Colour wash", value: $os.customTint, range: 0...1) { "\(Int($0 * 100))%" }
            LabeledSlider(title: "Ghost trail", value: $os.customTrail, range: 0...4, step: 1) { "\(Int($0))" }
            LabeledSlider(title: "Squash", value: $os.customSquash, range: 0...0.3) { "\(Int($0 * 333))%" }
        }
    }

    /// A Home Up style radio row: the preset's name and its one-line description.
    private func homeUpRow(_ style: AnimStyle) -> some View {
        let selected = os.animStyle == style
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { os.animStyle = style }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().stroke(selected ? Color.accentColor : Color.secondary, lineWidth: 2)
                    if selected {
                        Circle().fill(Color.accentColor).padding(5)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(os.t(style.title))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(os.t(style.detail))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(pressedScale: 0.98))
    }

    /// Starts a Custom animation from the current preset, so it can be tweaked from there.
    private func copyToCustom() {
        let style = os.animStyle
        os.customOpen = Double(style.openResponse)
        os.customClose = Double(style.closeResponse)
        os.customFade = style == .zoom || style == .fade
        os.customSpin = 0
        switch style {
        case .zoom: os.customOrigin = .center; os.customStartScale = 0.4
        case .fade: os.customOrigin = .center; os.customStartScale = 0.9
        case .slide: os.customOrigin = .bottom; os.customStartScale = 1
        default: os.customOrigin = .icon
        }
        if style.damping < 1 && os.bounce < 0.3 { os.bounce = 0.3 }
        let look = WindowMotion.look(style, os)
        os.customTranslucency = Double(look.translucency)
        os.customTint = Double(look.tint)
        os.customTrail = Double(look.trail)
        os.customSquash = Double(look.squash)
        os.animStyle = .custom
    }

    private func presetChip(_ style: AnimStyle) -> some View {
        let selected = os.animStyle == style
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { os.animStyle = style }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: style.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.primary.opacity(0.08))
                    )
                    .foregroundColor(selected ? .white : .primary)
                Text(os.t(style.title))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .accentColor : .primary)
            }
            .frame(width: 64)
        }
        .buttonStyle(PressScaleStyle())
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(selected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Home Up's rainbow speed bar: twelve coloured steps from slow (red) to fast (violet).
/// Tap or drag along it; the chosen step stands taller.
private struct RainbowSpeedBar: View {
    @EnvironmentObject private var os: OSSettings

    private let speeds: [Double] = [0.25, 0.4, 0.5, 0.65, 0.8, 1, 1.2, 1.4, 1.7, 2, 2.5, 3]

    var body: some View {
        let selected = speeds.enumerated().min { abs($0.element - os.animSpeed) < abs($1.element - os.animSpeed) }?.offset ?? 5

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(os.t("Animation speed")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(String(format: "%.2gx", os.animSpeed))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                let step = geo.size.width / CGFloat(speeds.count)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<speeds.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hue: 0.78 * Double(index) / Double(speeds.count - 1), saturation: 0.75, brightness: 0.95))
                            .frame(height: index == selected ? 34 : 20)
                            .opacity(index <= selected ? 1 : 0.35)
                    }
                }
                .frame(height: 34, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let index = min(speeds.count - 1, max(0, Int(value.location.x / step)))
                            if abs(os.animSpeed - speeds[index]) > 0.001 {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { os.animSpeed = speeds[index] }
                            }
                        }
                )
            }
            .frame(height: 34)
            HStack {
                Text(os.t("Slow"))
                Spacer()
                Text(os.t("Fast"))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
        }
    }
}

/// A small phone with the real wallpaper, home icons and dock. Tap an icon and it opens with exactly the
/// animation, speed, bounce and background settings the real home screen uses; tap the app to close it.
private struct PhonePreview: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var t = Animator(0)
    @State private var item: HomeItem?
    @State private var origin: CGRect = .zero
    @State private var open = false

    private let width: CGFloat = 170
    private var height: CGFloat { width * 19.5 / 9 }

    var body: some View {
        let p = t.value
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let cover = item == nil ? 0 : clamp01(p)
        let icon = width * 0.15

        ZStack {
            ZStack {
                Wallpaper()
                ForEach(Array(HomeItem.home.enumerated()), id: \.element.id) { pair in
                    let rect = homeRect(pair.offset, icon)
                    previewIcon(pair.element, rect, icon)
                }
                Glass(shape: RoundedRectangle(cornerRadius: icon * 0.5, style: .continuous))
                    .frame(width: width - 14, height: icon + 14)
                    .position(x: width / 2, y: height - icon / 2 - 18)
                ForEach(Array(HomeItem.dock.enumerated()), id: \.element.id) { pair in
                    previewIcon(pair.element, dockRect(pair.offset, icon), icon)
                }
            }
            .scaleEffect(1 - CGFloat(os.homeZoom) * cover)
            .brightness(-os.homeDim * Double(cover))
            .blur(radius: CGFloat(os.blurStrength) * 0.4 * cover)

            if let item = item {
                let rect = WindowMotion.rect(os.animStyle, os, origin: origin, full: full, p: p)
                let radius = WindowMotion.radius(os.animStyle, os, iconRadius: icon * CGFloat(os.iconRoundness), displayRadius: width * 0.13, p: p)
                ZStack {
                    Color(uiColor: .systemBackground)
                    VStack(spacing: 8) {
                        Text(os.t(item.name)).font(.system(size: 15, weight: .bold))
                        ForEach(0..<5, id: \.self) { row in
                            Capsule().fill(item.color.opacity(0.25)).frame(width: width * CGFloat(0.4 + Double(row % 3) * 0.15), height: 8)
                        }
                    }
                    let look = WindowMotion.look(os.animStyle, os)
                    item.color.opacity(WindowMotion.tint(look, p: p))
                    Color.white.opacity(WindowMotion.glow(look, p: p))
                    Image(systemName: item.symbol)
                        .font(.system(size: icon * 0.44, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(look.tint > 0 ? Double(clamp01(1 - p * 2.2)) : 0)
                    ZStack {
                        LinearGradient(colors: [item.color.opacity(0.78), item.color], startPoint: .top, endPoint: .bottom)
                            .background(Color.white)
                        Image(systemName: item.symbol)
                            .font(.system(size: icon * 0.44, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .opacity(WindowMotion.iconAlpha(os.animStyle, os, p: p))
                }
                .frame(width: max(1, rect.width), height: max(1, rect.height))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .scaleEffect(
                    x: WindowMotion.squash(WindowMotion.look(os.animStyle, os), velocity: t.currentVelocity).width,
                    y: WindowMotion.squash(WindowMotion.look(os.animStyle, os), velocity: t.currentVelocity).height
                )
                .rotationEffect(.degrees(WindowMotion.rotation(os.animStyle, os, p: p)))
                .opacity(WindowMotion.opacity(os.animStyle, os, p: p))
                .position(x: rect.midX, y: rect.midY)
                .onTapGesture(perform: close)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                .stroke(Color.primary.opacity(0.35), lineWidth: 4)
        )
        .overlay(alignment: .bottom) {
            Text(os.t(item == nil ? "Tap an icon to preview" : "Tap the app to close it"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .offset(y: 22)
        }
        .padding(.bottom, 24)
    }

    private func homeRect(_ index: Int, _ icon: CGFloat) -> CGRect {
        let gap = (width - 4 * icon) / 5
        let column = CGFloat(index % 4)
        let row = CGFloat(index / 4)
        return CGRect(x: gap + column * (icon + gap), y: height - icon * 4.4 + row * icon * 1.5, width: icon, height: icon)
    }

    private func dockRect(_ index: Int, _ icon: CGFloat) -> CGRect {
        let gap = (width - 4 * icon) / 5
        return CGRect(x: gap + CGFloat(index) * (icon + gap), y: height - icon - 18, width: icon, height: icon)
    }

    private func previewIcon(_ entry: HomeItem, _ rect: CGRect, _ icon: CGFloat) -> some View {
        AppIconView(item: entry, size: icon, radius: icon * CGFloat(os.iconRoundness))
            .opacity(item?.id == entry.id && WindowMotion.morphs(os.animStyle, os) ? 0 : 1)
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture {
                guard item == nil || !open else { return }
                launch(entry, rect)
            }
    }

    private func launch(_ entry: HomeItem, _ rect: CGRect) {
        Haptics.tap(.soft)
        let style = os.animStyle
        item = entry
        origin = rect
        open = true
        t.set(0)
        t.animate(to: 1, response: style.openResponse, damping: os.openDamping(style), ease: true, stages: os.easeStages(style))
    }

    private func close() {
        guard open else { return }
        open = false
        let style = os.animStyle
        t.animate(to: 0, response: style.closeResponse, damping: os.closeDamping(style), ease: true, stages: os.easeStages(style)) {
            if !open { item = nil }
        }
    }
}

// MARK: - Look

private struct LookTab: View {
    @EnvironmentObject private var os: OSSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LabSection(title: "Theme") {
                    Picker("", selection: $os.theme) {
                        ForEach(ThemeMode.allCases) { Text(os.t($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledSlider(title: "Glass tint", value: $os.glassTint, range: 0...1) { "\(Int($0 * 100))%" }
                }

                LabSection(title: "Wallpaper") {
                    WallpaperGrid(columns: 4, height: 90)
                }

                LabSection(title: "Icons") {
                    LabeledSlider(title: "Corner roundness", value: $os.iconRoundness, range: 0.1...0.5) { "\(Int($0 * 200))%" }
                    HStack(spacing: 12) {
                        ForEach(HomeItem.dock) { item in
                            AppIconView(item: item, size: 48, radius: 48 * CGFloat(os.iconRoundness))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    LabToggle(title: "App labels", symbol: "textformat", isOn: $os.showLabels)
                }

                LabSection(title: "Home screen") {
                    LabToggle(title: "Apps on the home screen", symbol: "square.grid.2x2.fill", isOn: $os.homeApps)
                    LabToggle(title: "Clock widget", symbol: "clock.fill", isOn: $os.clockWidget)
                    LabToggle(title: "Dummy Apps folder", symbol: "questionmark.folder.fill", isOn: $os.dummyFolder)
                }

                LabSection(title: "Navigation") {
                    NavModePicker()
                }
            }
            .padding(16)
        }
    }
}

// MARK: - System

private struct SystemTab: View {
    let onRunSetup: () -> Void

    @EnvironmentObject private var os: OSSettings
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LabSection(title: "Status bar") {
                    LabToggle(title: "24-hour time", symbol: "clock", isOn: $os.clock24h)
                    LabToggle(title: "Battery percentage", symbol: "battery.75", isOn: $os.showBattery)
                    LabToggle(title: "FPS counter", symbol: "speedometer", isOn: $os.showFPS)
                }

                LabSection(title: "Feel") {
                    LabToggle(title: "Vibration", symbol: "iphone.radiowaves.left.and.right", isOn: $os.haptics)
                    LabToggle(title: "Forced Android boot", symbol: "terminal.fill", isOn: $os.forcedBoot)
                }

                LabSection(title: "Language") {
                    Picker("", selection: $os.language) {
                        ForEach(OSLanguage.allCases) { Text("\($0.flag) \($0.nativeName)").tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                LabSection(title: "Device") {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        VStack(spacing: 8) {
                            row("Model", DeviceInfo.modelIdentifier)
                            row("Software", DeviceInfo.systemVersion)
                            row("Processor", "\(DeviceInfo.cores) " + os.t("cores"))
                            row("Memory", DeviceInfo.memory)
                            row("Battery", DeviceInfo.battery)
                            row("Temperature", os.t(DeviceInfo.thermal))
                            row("Screen", DeviceInfo.screen)
                            row("Uptime", DeviceInfo.uptime)
                        }
                    }
                }

                LabSection(title: "Maintenance") {
                    HostExitButton()
                        .font(.system(size: 15, weight: .semibold))
                    Button {
                        onRunSetup()
                    } label: {
                        Label(os.t("Run setup again"), systemImage: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label(os.t("Reset all settings"), systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .confirmationDialog(os.t("Reset all settings?"), isPresented: $confirmReset) {
                        Button(os.t("Reset"), role: .destructive) { os.resetAll() }
                    }
                }
            }
            .padding(16)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(os.t(title)).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(value).font(.system(size: 14, design: .monospaced)).foregroundColor(.secondary)
        }
    }
}

// MARK: - Logs

private struct LogsTab: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var logger = OSLogger.shared
    @State private var levels: Set<OSLogger.Level> = Set(OSLogger.Level.allCases)
    @State private var follow = true
    @State private var copied = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(OSLogger.Level.allCases, id: \.self) { level in
                    Button {
                        if levels.contains(level) { levels.remove(level) } else { levels.insert(level) }
                    } label: {
                        Text(level.rawValue.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(levels.contains(level) ? .white : level.color)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(levels.contains(level) ? level.color : level.color.opacity(0.12)))
                    }
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = logger.text
                    copied = true
                    after(1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                Button {
                    logger.clear()
                } label: {
                    Image(systemName: "trash")
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(OSLogger.timeString(entry.date))
                                    .foregroundColor(.secondary)
                                Text(entry.level.letter)
                                    .foregroundColor(entry.level.color)
                                    .fontWeight(.bold)
                                Text("[\(entry.tag)] ").foregroundColor(.accentColor)
                                    + Text(entry.message).foregroundColor(.primary)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .onChange(of: logger.entries.count) { _ in
                    if follow, let last = filtered.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = filtered.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            HStack {
                Toggle(os.t("Follow new entries"), isOn: $follow).font(.system(size: 13, weight: .semibold))
                Text("\(logger.entries.count)").font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var filtered: [OSLogger.Entry] {
        logger.entries.filter { levels.contains($0.level) }
    }
}
