// SPDX-License-Identifier: GPL-2.0-or-later
import CryptoKit
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's screen lock, as LineageOS (AOSP's keyguard) has it.
///
/// Settings › Security & privacy › Device unlock chooses it: None, Swipe, Pattern, PIN or Password, and a fingerprint on
/// top of the last three. The lock screen shows the big clock and the date; swiping up opens the bouncer (the PIN pad, the
/// pattern grid or the password field) when there is a secret, and five wrong tries wait 30 seconds, as Android does.
///
/// It is a recreation, not security: the fingerprint is pretend (holding the sensor unlocks), and the secret is kept as a
/// salted hash in HuskPatch's preferences. HuskPatch itself and the iPhone stay protected by the iPhone's own passcode.
enum AndroidLock {
    enum Kind: String, CaseIterable, Identifiable {
        case none, swipe, pattern, pin, password
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "None"
            case .swipe: return "Swipe"
            case .pattern: return "Pattern"
            case .pin: return "PIN"
            case .password: return "Password"
            }
        }
        var summary: String {
            switch self {
            case .none: return "No lock screen"
            case .swipe: return "No security"
            case .pattern: return "Medium security"
            case .pin: return "Medium to high security"
            case .password: return "High security"
            }
        }
        var icon: String {
            switch self {
            case .none: return "lock.open"
            case .swipe: return "hand.draw"
            case .pattern: return "circle.grid.3x3"
            case .pin: return "circle.grid.3x3.fill"
            case .password: return "character.cursor.ibeam"
            }
        }
        var secure: Bool { self == .pattern || self == .pin || self == .password }
    }

    static let kindKey = "huskpatch.lock.kind"
    private static let secretKey = "huskpatch.lock.secret"
    private static let saltKey = "huskpatch.lock.salt"
    static let fingerprintKey = "huskpatch.lock.fingerprint"
    static let fingerprintsKey = "huskpatch.lock.fingerprints"

    static var kind: Kind { Kind(rawValue: UserDefaults.standard.string(forKey: kindKey) ?? "") ?? .swipe }

    /// Whether the lock screen shows at all.
    static var showsLockScreen: Bool { kind != .none }

    static var fingerprints: Int { UserDefaults.standard.integer(forKey: fingerprintsKey) }

    /// The lock screen's corner shortcuts (flashlight, Do Not Disturb). Off by default, as LineageOS 22 sets it up.
    static let shortcutsKey = "huskpatch.lock.shortcuts"

    /// Unlocked once since HuskPatch opened: until then the lock screen says "Unlock for all features and data", as Android
    /// does before the first unlock after a restart.
    @MainActor static var unlockedSinceLaunch = false

    /// Fingerprint unlock: on, with a finger enrolled and a secure lock under it, as Android requires.
    static var fingerprintOn: Bool {
        kind.secure && fingerprints > 0 && UserDefaults.standard.object(forKey: fingerprintKey) as? Bool ?? true
    }

    static func set(_ kind: Kind, secret: String? = nil) {
        let d = UserDefaults.standard
        d.set(kind.rawValue, forKey: kindKey)
        if kind.secure, let secret {
            let salt = UUID().uuidString
            d.set(salt, forKey: saltKey)
            d.set(hash(secret, salt), forKey: secretKey)
        } else {
            d.removeObject(forKey: secretKey)
            d.removeObject(forKey: saltKey)
            // no secure lock: Android removes the fingerprints with it
            if !kind.secure { d.set(0, forKey: fingerprintsKey) }
        }
    }

    static func check(_ secret: String) -> Bool {
        let d = UserDefaults.standard
        guard let salt = d.string(forKey: saltKey), let stored = d.string(forKey: secretKey) else { return true }
        return hash(secret, salt) == stored
    }

    private static func hash(_ secret: String, _ salt: String) -> String {
        SHA256.hash(data: Data((salt + ":" + secret).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Wrong tries: after five, the bouncer waits 30 seconds.
@MainActor
final class AndroidLockGuard: ObservableObject {
    static let shared = AndroidLockGuard()
    @Published private(set) var failures = 0
    @Published private(set) var lockedUntil: Date?

    func failed() {
        failures += 1
        if failures % 5 == 0 { lockedUntil = Date().addingTimeInterval(30) }
    }

    func succeeded() { failures = 0; lockedUntil = nil }

    func secondsLeft(_ now: Date) -> Int? {
        guard let until = lockedUntil, until > now else { return nil }
        return Int(until.timeIntervalSince(now).rounded(.up))
    }
}

// MARK: - lock screen

/// The keyguard, as LineageOS 22 (AOSP 15) draws it: with nothing waiting, the large clock in the middle with the date under
/// it; with notifications, the small clock and date at the top left and the notifications under them as cards. At the
/// bottom, the lock icon (or the fingerprint sensor) over "Unlock for all features and data" until the first unlock, then
/// "Swipe up to open"; the corner shortcuts when they are turned on. Swiping up opens the bouncer when there is a secret.
struct AndroidLockScreen: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var drag: CGFloat = 0
    @State private var bouncer = false
    @ObservedObject private var torch = TorchSwitch.shared
    @ObservedObject private var downloads = Downloads.shared
    @AppStorage(AndroidLock.shortcutsKey) private var shortcuts = false

    var body: some View {
        ZStack {
            AndroidWallpaper()
            Color.black.opacity(bouncer ? 0.55 : 0.28).ignoresSafeArea()
            AndroidStatusBar(material: true, transparent: true, hidesClock: true)
                .environment(\.colorScheme, .dark)

            if bouncer {
                AndroidBouncer(kind: AndroidLock.kind, onUnlock: unlock, onCancel: { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { bouncer = false } })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Group {
                    if Android13.isOn { Android13Keyguard(unlock: unlock) } else { keyguard }
                }
                    .offset(y: min(0, drag))
                    .opacity(1 - Double(min(abs(drag) / 500, 0.7)))
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .gesture(bouncer ? nil : DragGesture(minimumDistance: 10)
            .onChanged { drag = $0.translation.height }
            .onEnded { v in
                if v.translation.height < -110 || v.predictedEndTranslation.height < -280 {
                    if AndroidLock.kind.secure {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { bouncer = true; drag = 0 }
                    } else {
                        unlock()
                    }
                } else {
                    withAnimation(.spring) { drag = 0 }
                }
            })
        .statusBarHidden(true)
    }

    /// Notifications show as cards; what does not fit (and running downloads) as icons under them.
    private var cards: [ShellNotification] { Array(shell.notifications.prefix(3)) }
    private var overflow: [String] {
        shell.notifications.dropFirst(3).map(\.icon) + (downloads.jobs.contains { !$0.complete } ? ["arrow.down.circle"] : [])
    }

    private var keyguard: some View {
        let small = !cards.isEmpty || !overflow.isEmpty
        return VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let date = context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                if small {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AndroidClockFace.time(context.date))
                            .font(.system(size: 66, weight: .regular, design: .rounded))
                            .monospacedDigit()
                        Text(date).font(.system(size: 15, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 56)
                } else {
                    VStack(spacing: 4) {
                        Text(AndroidClockFace.time(context.date))
                            .font(.system(size: 118, weight: .regular, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(Color(uiColor: AndroidClockFace.ink))
                        Text(date).font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 150)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: small)

            if small {
                VStack(spacing: 6) {
                    ForEach(cards) { AndroidNotificationBubble(note: $0, overWallpaper: true) }
                    if !overflow.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(overflow.prefix(6).enumerated()), id: \.offset) { _, icon in
                                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .background(.white.opacity(0.18), in: Circle())
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 22)
                .transition(.opacity)
            }

            Spacer()
            ZStack(alignment: .bottom) {
                if shortcuts {
                    HStack {
                        shortcut(torch.on ? "flashlight.on.fill" : "flashlight.off.fill", on: torch.on) { torch.toggle() }
                        Spacer()
                        shortcut(shell.doNotDisturb ? "moon.fill" : "moon", on: shell.doNotDisturb) { shell.doNotDisturb.toggle() }
                    }
                    .padding(.horizontal, 30)
                }
                VStack(spacing: 12) {
                    if AndroidLock.fingerprintOn {
                        AndroidFingerprintSensor(onMatch: unlock)
                    } else {
                        Image(systemName: AndroidLock.kind.secure ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    Text(!AndroidLock.unlockedSinceLaunch && AndroidLock.kind.secure ? "Unlock for all features and data"
                         : AndroidLock.fingerprintOn ? "Touch the fingerprint sensor, or swipe up" : "Swipe up to open")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.bottom, shortcuts ? 64 : 40)
            }
            .padding(.bottom, 22)
        }
    }

    private func shortcut(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(on ? Color(uiColor: Material3.onPrimaryContainer) : .white)
                .frame(width: 60, height: 60)
                .background(on ? Color(uiColor: Material3.primaryContainer) : Color.white.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: on ? 20 : 30, style: .continuous))
        }
        .buttonStyle(AndroidSquashStyle())
    }

    private func unlock() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AndroidLockGuard.shared.succeeded()
        AndroidLock.unlockedSinceLaunch = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { shell.locked = false; drag = 0; bouncer = false }
    }
}

/// The under-display fingerprint sensor: a fingerprint in a circle. Holding it a moment "reads" the finger and unlocks.
struct AndroidFingerprintSensor: View {
    let onMatch: () -> Void
    @State private var pressing = false
    @State private var matched = false

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(pressing ? 0.28 : 0.12)).frame(width: 72, height: 72)
            if pressing {
                ExpressiveLoadingIndicator()
                    .frame(width: 72, height: 72)
                    .opacity(0.9)
            }
            Image(systemName: matched ? "checkmark" : "touchid")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(matched ? Color(uiColor: Material3.primaryContainer) : .white)
        }
        .scaleEffect(pressing ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressing)
        .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 40) {
            matched = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onMatch(); matched = false }
        } onPressingChanged: { p in
            pressing = p
            if p { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        .accessibilityLabel("Fingerprint sensor")
        .accessibilityAction { onMatch() }
    }
}

// MARK: - bouncer

/// The bouncer for the kind of lock in use: its title, what is entered, wrong-try messages and the 30-second wait.
struct AndroidBouncer: View {
    let kind: AndroidLock.Kind
    var title: String?
    let onUnlock: () -> Void
    var onCancel: (() -> Void)?
    /// Check against this instead of the stored secret (setting a lock up: "confirm your PIN").
    var expected: String?
    /// Instead of checking, hand back what was entered (setting a lock up: the first entry).
    var onEntered: ((String) -> Void)?

    @ObservedObject private var guardState = AndroidLockGuard.shared
    @State private var message: String?
    @State private var shake: CGFloat = 0
    @State private var resetToken = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = guardState.secondsLeft(context.date)
            VStack(spacing: 18) {
                Spacer(minLength: 40)
                Image(systemName: "lock.fill").font(.system(size: 22, weight: .semibold))
                Text(title ?? defaultTitle)
                    .font(.system(size: 26, weight: .regular, design: .rounded))
                Text(wait.map { "Try again in \($0) seconds" } ?? message ?? " ")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(message != nil || wait != nil ? Color(uiColor: Material3.error) : .clear)
                    .frame(height: 18)
                Group {
                    switch kind {
                    case .pin: AndroidPinPad(onEnter: submit)
                    case .pattern: AndroidPatternPad(onEnter: submit)
                    case .password: AndroidPasswordField(onEnter: submit)
                    default: EmptyView()
                    }
                }
                .id(resetToken)
                .offset(x: shake)
                .disabled(wait != nil)
                .opacity(wait != nil ? 0.4 : 1)
                if AndroidLock.fingerprintOn, onEntered == nil, expected == nil {
                    AndroidFingerprintSensor(onMatch: onUnlock).padding(.top, 6)
                }
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.expressive(.text))
                }
                Spacer(minLength: 20)
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
    }

    private var defaultTitle: String {
        switch kind {
        case .pin: return "Enter PIN"
        case .pattern: return "Draw your pattern"
        default: return "Enter password"
        }
    }

    private func submit(_ value: String) {
        if let onEntered {
            if kind == .pattern && value.split(separator: "-").count < 4 { wrong("Connect at least 4 dots"); return }
            if kind == .pin && value.count < 4 { wrong("PIN must be at least 4 digits"); return }
            if kind == .password && value.count < 4 { wrong("Must be at least 4 characters"); return }
            onEntered(value)
            resetToken += 1
            return
        }
        let ok = expected.map { $0 == value } ?? AndroidLock.check(value)
        if ok { onUnlock(); return }
        AndroidLockGuard.shared.failed()
        wrong(kind == .pin ? "Wrong PIN" : kind == .pattern ? "Wrong pattern" : "Wrong password")
    }

    private func wrong(_ text: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        message = text
        withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 14 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.spring(response: 0.3, dampingFraction: 0.3)) { shake = 0 } }
        resetToken += 1
    }
}

/// The PIN pad: the digits entered as dots, then round keys that turn into rounded squares while pressed (Material 3
/// Expressive's shape morph), with delete and enter on the last row.
struct AndroidPinPad: View {
    let onEnter: (String) -> Void
    @State private var digits = ""

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 12) {
                ForEach(Array(digits.enumerated()), id: \.offset) { _, _ in
                    Circle().fill(Color(uiColor: Material3.onSurface)).frame(width: 12, height: 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 24)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: digits)
            VStack(spacing: 14) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "↵"]], id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.self) { key in pinKey(key) }
                    }
                }
            }
        }
    }

    private func pinKey(_ key: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            switch key {
            case "⌫": if !digits.isEmpty { digits.removeLast() }
            case "↵": if !digits.isEmpty { onEnter(digits) }
            default: if digits.count < 16 { digits.append(key) }
            }
        } label: {
            Group {
                switch key {
                case "⌫": Image(systemName: "delete.left").font(.system(size: 24, weight: .regular))
                case "↵": Image(systemName: "arrow.forward").font(.system(size: 24, weight: .semibold))
                default: Text(key).font(.system(size: 34, weight: .regular, design: .rounded))
                }
            }
            .frame(width: 80, height: 80)
        }
        .buttonStyle(PinKeyStyle(accent: key == "↵"))
        .accessibilityLabel(key == "⌫" ? "Delete" : key == "↵" ? "Enter" : key)
    }

    private struct PinKeyStyle: ButtonStyle {
        let accent: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Color(uiColor: accent ? Material3.onPrimaryContainer : Material3.onSurface))
                .background(Color(uiColor: accent || configuration.isPressed ? Material3.primaryContainer : Material3.surfaceContainerHighest),
                            in: RoundedRectangle(cornerRadius: configuration.isPressed ? 22 : 40, style: .continuous))
                .animation(.spring(response: 0.22, dampingFraction: 0.62), value: configuration.isPressed)
        }
    }
}

/// The pattern: nine dots; a finger dragged through them draws the line, and lifting it enters the dots it passed, as
/// "0-4-8".
struct AndroidPatternPad: View {
    let onEnter: (String) -> Void
    var size: CGFloat = 270
    @State private var path: [Int] = []
    @State private var finger: CGPoint?

    private func center(_ i: Int) -> CGPoint {
        let step = size / 3
        return CGPoint(x: step * (CGFloat(i % 3) + 0.5), y: step * (CGFloat(i / 3) + 0.5))
    }

    var body: some View {
        ZStack {
            Path { p in
                guard let first = path.first else { return }
                p.move(to: center(first))
                for i in path.dropFirst() { p.addLine(to: center(i)) }
                if let finger { p.addLine(to: finger) }
            }
            .stroke(Color(uiColor: Material3.primary), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            ForEach(0..<9, id: \.self) { i in
                let on = path.contains(i)
                Circle()
                    .fill(Color(uiColor: on ? Material3.primary : Material3.onSurface))
                    .frame(width: on ? 24 : 12, height: on ? 24 : 12)
                    .position(center(i))
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: on)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                finger = v.location
                for i in 0..<9 where !path.contains(i) {
                    let c = center(i)
                    if hypot(c.x - v.location.x, c.y - v.location.y) < size / 9 {
                        // a dot passed over between two others joins too, as on Android
                        if let last = path.last {
                            let mid = (last + i) / 2
                            if (last + i) % 2 == 0, !path.contains(mid),
                               abs(last % 3 - i % 3) != 1, abs(last / 3 - i / 3) != 1 { path.append(mid) }
                        }
                        path.append(i)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .onEnded { _ in
                finger = nil
                let entered = path.map(String.init).joined(separator: "-")
                path = []
                if !entered.isEmpty { onEnter(entered) }
            })
        .accessibilityLabel("Pattern area")
    }
}

/// The password: a pill field on a surface container, entered with return.
struct AndroidPasswordField: View {
    let onEnter: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        SecureField("Password", text: $text)
            .font(.system(size: 18, design: .rounded))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focused)
            .onSubmit { if !text.isEmpty { onEnter(text); text = "" } }
            .padding(.horizontal, 22)
            .frame(height: 56)
            .background(Color(uiColor: Material3.surfaceContainerHighest), in: Capsule())
            .padding(.horizontal, 40)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } }
    }
}

// MARK: - Settings › Security & privacy

/// Settings › Security & privacy: Device unlock (screen lock, fingerprint), as Android 16 groups them.
struct AndroidSecurityPage: View {
    @AppStorage(AndroidLock.kindKey) private var kindRaw = AndroidLock.Kind.swipe.rawValue
    @AppStorage(AndroidLock.fingerprintsKey) private var fingerprints = 0
    @AppStorage(AndroidLock.shortcutsKey) private var shortcuts = false

    var body: some View {
        AndroidSettingsPage(title: "Security & privacy", onBack: AndroidSettingsRoute.pop) {
            HStack(spacing: 16) {
                Image(systemName: AndroidLock.kind.secure ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(uiColor: AndroidLock.kind.secure ? Material3.primary : Material3.error))
                VStack(alignment: .leading, spacing: 4) {
                    Text(AndroidLock.kind.secure ? "Device is protected" : "Set a screen lock")
                        .font(.system(size: 18, design: .rounded))
                    Text(AndroidLock.kind.secure ? "Screen lock is on" : "Swipe does not protect the device")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
                Spacer()
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(18)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.bottom, 8)
            AndroidSettingsGroup(header: "Device unlock") {
                NavigationLink(value: AndroidSettingsRoute.screenLock) {
                    AndroidSettingsRow(icon: "lock.fill", tint: .systemTeal, title: "Screen lock",
                                       summary: (AndroidLock.Kind(rawValue: kindRaw) ?? .swipe).title)
                }
                .buttonStyle(AndroidRippleStyle())
                NavigationLink(value: AndroidSettingsRoute.fingerprint) {
                    AndroidSettingsRow(icon: "touchid", tint: .systemPink, title: "Fingerprint Unlock",
                                       summary: fingerprints == 0 ? "Not set up" : "\(fingerprints) fingerprint\(fingerprints == 1 ? "" : "s") added")
                }
                .buttonStyle(AndroidRippleStyle())
            }
            AndroidSettingsGroup(header: "Lock screen") {
                AndroidSettingsRow(icon: "flashlight.on.fill", tint: .systemOrange, title: "Shortcuts",
                                   summary: "Flashlight and Do Not Disturb in the lock screen's corners") {
                    Toggle("", isOn: $shortcuts).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
            }
            Text("The lock is part of Android OS mode's look. It isn't real security: the iPhone's own passcode protects your data.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .padding(.horizontal, 8)
        }
    }
}

/// Settings › Security & privacy › Screen lock: confirm the current secret, choose a kind, enter the new secret twice.
struct AndroidScreenLockPage: View {
    private enum Step: Equatable { case verify, choose, enter(AndroidLock.Kind), confirm(AndroidLock.Kind, String) }
    @State private var step: Step = AndroidLock.kind.secure ? .verify : .choose
    @State private var current = AndroidLock.kind

    var body: some View {
        if step == .choose {
            AndroidSettingsPage(title: "Choose screen lock", onBack: back) {
                AndroidSettingsGroup {
                    ForEach(AndroidLock.Kind.allCases) { k in
                        Button { pick(k) } label: {
                            AndroidSettingsRow(icon: k.icon, title: k.title, summary: k == current ? "Current screen lock" : k.summary)
                        }
                        .buttonStyle(AndroidRippleStyle())
                    }
                }
            }
        } else {
            // the pads take drags (the pattern), so they are not in a scroll view
            VStack(spacing: 0) {
                HStack {
                    Button(action: back) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                            .frame(width: 40, height: 40)
                            .background(Color(uiColor: Material3.secondaryContainer), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
                bouncer
            }
            .background(Color(uiColor: Material3.surface).ignoresSafeArea())
        }
    }

    @ViewBuilder private var bouncer: some View {
            switch step {
            case .verify:
                AndroidBouncer(kind: AndroidLock.kind, title: "Confirm your \(AndroidLock.kind == .pattern ? "pattern" : AndroidLock.kind.title)",
                               onUnlock: { withAnimation { step = .choose } })
            case .choose:
                EmptyView()
            case .enter(let k):
                AndroidBouncer(kind: k, title: k == .pattern ? "Draw an unlock pattern" : "Set a \(k == .pin ? "PIN" : "password")",
                               onUnlock: {}, onEntered: { v in withAnimation { step = .confirm(k, v) } })
            case .confirm(let k, let v):
                AndroidBouncer(kind: k, title: k == .pattern ? "Draw pattern again to confirm" : "Re-enter your \(k == .pin ? "PIN" : "password")",
                               onUnlock: { save(k, v) }, expected: v)
            }
    }

    private func pick(_ k: AndroidLock.Kind) {
        if k.secure { withAnimation { step = .enter(k) } } else { save(k, nil) }
    }

    private func save(_ k: AndroidLock.Kind, _ secret: String?) {
        AndroidLock.set(k, secret: secret)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        current = k
        AndroidSettingsRoute.pop()
    }

    private func back() {
        switch step {
        case .enter, .confirm: withAnimation { step = .choose }
        default: AndroidSettingsRoute.pop()
        }
    }
}

/// Settings › Security & privacy › Fingerprint Unlock: the fingers added, adding one (touch the sensor until the ring is
/// full), and the switch for unlocking with it.
struct AndroidFingerprintPage: View {
    @AppStorage(AndroidLock.fingerprintsKey) private var fingerprints = 0
    @AppStorage(AndroidLock.fingerprintKey) private var useForUnlock = true
    @State private var enrolling = false
    @State private var progress = 0.0
    @State private var pressing = false

    var body: some View {
        AndroidSettingsPage(title: "Fingerprint Unlock", onBack: AndroidSettingsRoute.pop) {
            if !AndroidLock.kind.secure {
                AndroidSettingsGroup {
                    AndroidSettingsRow(icon: "lock.fill", tint: .systemTeal, title: "Set a screen lock first",
                                       summary: "Fingerprint Unlock needs a pattern, PIN or password as a backup")
                    NavigationLink(value: AndroidSettingsRoute.screenLock) {
                        AndroidSettingsRow(icon: "arrow.right", title: "Choose screen lock")
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            } else if enrolling {
                enrollment
            } else {
                AndroidSettingsGroup(header: "Fingerprints") {
                    ForEach(0..<fingerprints, id: \.self) { i in
                        AndroidSettingsRow(icon: "touchid", tint: .systemPink, title: "Fingerprint \(i + 1)") {
                            Button { fingerprints -= 1 } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        }
                    }
                    if fingerprints < 5 {
                        Button { withAnimation { progress = 0; enrolling = true } } label: {
                            AndroidSettingsRow(icon: "plus", title: "Add fingerprint")
                        }
                        .buttonStyle(AndroidRippleStyle())
                    }
                }
                if fingerprints > 0 {
                    AndroidSettingsGroup(header: "Use fingerprint for") {
                        AndroidSettingsRow(icon: "lock.open.fill", tint: .systemTeal, title: "Unlocking your phone") {
                            Toggle("", isOn: $useForUnlock).labelsHidden().toggleStyle(Material3SwitchStyle())
                        }
                    }
                }
            }
        }
    }

    /// "Touch the sensor": each touch fills the ring a sixth of the way, as Android's enrollment does with each lift.
    private var enrollment: some View {
        VStack(spacing: 24) {
            Text(progress >= 1 ? "Fingerprint added" : progress == 0 ? "Touch the sensor" : "Lift, then touch again")
                .font(.system(size: 26, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
            Text(progress >= 1 ? "When you see this icon, use your fingerprint to unlock" : "Put your finger on the sensor and lift after you feel a vibration")
                .font(.system(size: 15, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            ZStack {
                ExpressiveCircularProgressIndicator(progress: progress)
                    .frame(width: 180, height: 180)
                Image(systemName: progress >= 1 ? "checkmark" : "touchid")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color(uiColor: Material3.primary))
                    .scaleEffect(pressing ? 0.9 : 1)
            }
            .padding(.vertical, 20)
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 60) {
                guard progress < 1 else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { progress = min(1, progress + 1.0 / 6) }
                if progress >= 0.99 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            } onPressingChanged: { p in withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { pressing = p } }
            HStack {
                Button("Cancel") { withAnimation { enrolling = false } }.buttonStyle(.expressive(.text))
                Spacer()
                if progress >= 0.99 {
                    Button("Done") { fingerprints += 1; useForUnlock = true; withAnimation { enrolling = false } }
                        .buttonStyle(.expressive(.filled, size: .small))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}
