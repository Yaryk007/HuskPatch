// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import Contacts
import CoreBluetooth
import CoreLocation
import EventKit
import Photos
import SwiftUI
import UIKit
import UserNotifications

/// HuskPatch: Android's runtime permissions for apps on the translation layer.
///
/// An app's request (Activity.requestPermissions, Unity's UnityPermissions...) reaches here through husk-tl-perm.c. Each
/// permission group it asks for gets Android 16's dialog. When iOS guards the same thing -- the camera, the microphone,
/// location, photos, contacts, calendars, notifications, Bluetooth -- allowing it on Android goes on to the iPhone's own
/// prompt, and the app is only granted it when both say yes. What only Android has (phone, SMS, body sensors...) is
/// asked on Android alone. Special app access (display over other apps, all files access...) gets its Settings page.
///
/// Choices are kept per app, and can be changed in the Settings app's Apps page.
enum AndroidPermissionGroup: String, CaseIterable, Identifiable {
    case camera, microphone, location, photos, music, storage, contacts, calendar, notifications, nearby, phone, callLog, sms,
         sensors, activity

    var id: String { rawValue }

    static func of(_ permission: String) -> AndroidPermissionGroup? {
        let name = permission.hasPrefix("android.permission.") ? String(permission.dropFirst(19)) : permission
        switch name {
        case "CAMERA": return .camera
        case "RECORD_AUDIO": return .microphone
        case "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "ACCESS_BACKGROUND_LOCATION": return .location
        case "READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO", "READ_MEDIA_VISUAL_USER_SELECTED", "ACCESS_MEDIA_LOCATION": return .photos
        case "READ_MEDIA_AUDIO": return .music
        case "READ_EXTERNAL_STORAGE", "WRITE_EXTERNAL_STORAGE": return .storage
        case "READ_CONTACTS", "WRITE_CONTACTS", "GET_ACCOUNTS": return .contacts
        case "READ_CALENDAR", "WRITE_CALENDAR": return .calendar
        case "POST_NOTIFICATIONS": return .notifications
        case "BLUETOOTH_SCAN", "BLUETOOTH_CONNECT", "BLUETOOTH_ADVERTISE", "NEARBY_WIFI_DEVICES", "UWB_RANGING": return .nearby
        case "READ_PHONE_STATE", "READ_PHONE_NUMBERS", "CALL_PHONE", "ANSWER_PHONE_CALLS", "ADD_VOICEMAIL", "USE_SIP",
             "ACCEPT_HANDOVER": return .phone
        case "READ_CALL_LOG", "WRITE_CALL_LOG", "PROCESS_OUTGOING_CALLS": return .callLog
        case "SEND_SMS", "RECEIVE_SMS", "READ_SMS", "RECEIVE_WAP_PUSH", "RECEIVE_MMS": return .sms
        case "BODY_SENSORS", "BODY_SENSORS_BACKGROUND": return .sensors
        case "ACTIVITY_RECOGNITION": return .activity
        default: return nil
        }
    }

    /// Settings › Apps › Permissions names it so.
    var title: String {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .location: return "Location"
        case .photos: return "Photos and videos"
        case .music: return "Music and audio"
        case .storage: return "Files and media"
        case .contacts: return "Contacts"
        case .calendar: return "Calendar"
        case .notifications: return "Notifications"
        case .nearby: return "Nearby devices"
        case .phone: return "Phone"
        case .callLog: return "Call logs"
        case .sms: return "SMS"
        case .sensors: return "Body sensors"
        case .activity: return "Physical activity"
        }
    }

    /// The end of the dialog's question: "Allow Subway Surfers to …?"
    var question: String {
        switch self {
        case .camera: return "take pictures and record video"
        case .microphone: return "record audio"
        case .location: return "access this device's location"
        case .photos: return "access photos and videos on this device"
        case .music: return "access music and audio on this device"
        case .storage: return "access photos, media, and files on your device"
        case .contacts: return "access your contacts"
        case .calendar: return "access your calendar"
        case .notifications: return "send you notifications"
        case .nearby: return "find, connect to, and determine the relative position of nearby devices"
        case .phone: return "make and manage phone calls"
        case .callLog: return "access your phone call logs"
        case .sms: return "send and view SMS messages"
        case .sensors: return "access sensor data about your vital signs"
        case .activity: return "access your physical activity"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .location: return "location.fill"
        case .photos: return "photo.fill"
        case .music: return "music.note"
        case .storage: return "folder.fill"
        case .contacts: return "person.crop.circle.fill"
        case .calendar: return "calendar"
        case .notifications: return "bell.fill"
        case .nearby: return "dot.radiowaves.left.and.right"
        case .phone: return "phone.fill"
        case .callLog: return "phone.arrow.up.right.fill"
        case .sms: return "message.fill"
        case .sensors: return "heart.fill"
        case .activity: return "figure.walk"
        }
    }

    /// Android offers "While using the app" and "Only this time" for these; the rest are Allow or Don't allow.
    var whileInUse: Bool { self == .camera || self == .microphone || self == .location }

    /// What the iPhone also asks about, or nil when the permission is Android's alone.
    var ios: IOSPermission? {
        switch self {
        case .camera: return .camera
        case .microphone: return .microphone
        case .location: return .location
        case .photos: return .photos
        case .contacts: return .contacts
        case .calendar: return .calendar
        case .notifications: return .notifications
        case .nearby: return .bluetooth
        default: return nil
        }
    }
}

/// Settings › Apps › Special app access: switches the app sends you to, rather than dialogs.
enum AndroidSpecialAccess: String, CaseIterable, Identifiable {
    case overlay = "android.permission.SYSTEM_ALERT_WINDOW"
    case writeSettings = "android.permission.WRITE_SETTINGS"
    case allFiles = "android.permission.MANAGE_EXTERNAL_STORAGE"
    case installApps = "android.permission.REQUEST_INSTALL_PACKAGES"
    case exactAlarms = "android.permission.SCHEDULE_EXACT_ALARM"
    case battery = "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"
    case usage = "android.permission.PACKAGE_USAGE_STATS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overlay: return "Display over other apps"
        case .writeSettings: return "Modify system settings"
        case .allFiles: return "All files access"
        case .installApps: return "Install unknown apps"
        case .exactAlarms: return "Alarms & reminders"
        case .battery: return "Unrestricted battery usage"
        case .usage: return "Usage access"
        }
    }

    var toggle: String {
        switch self {
        case .overlay: return "Allow display over other apps"
        case .writeSettings: return "Allow modifying system settings"
        case .allFiles: return "Allow access to manage all files"
        case .installApps: return "Allow from this source"
        case .exactAlarms: return "Allow setting alarms and reminders"
        case .battery: return "Allow unrestricted battery usage"
        case .usage: return "Permit usage access"
        }
    }

    var footer: String {
        switch self {
        case .overlay: return "Allow this app to display on top of other apps you're using. This app will be able to see where you tap or change what's displayed on the screen."
        case .writeSettings: return "This permission allows an app to modify system settings."
        case .allFiles: return "Allow this app to read, modify and delete all files on this device or any connected storage volumes. If granted, app may access files without your explicit knowledge."
        case .installApps: return "Your phone and personal data are more vulnerable to attack by unknown apps. By installing apps from this source, you agree that you are responsible for any damage to your phone or loss of data that may result from their use."
        case .exactAlarms: return "Allow this app to set alarms and schedule time-sensitive actions. This lets the app run in the background, which may use more battery."
        case .battery: return "Allow this app to run in the background without restrictions. It may use more battery."
        case .usage: return "Usage access allows an app to track what other apps you're using and how often, as well as your carrier, language settings, and other details."
        }
    }

    var icon: String {
        switch self {
        case .overlay: return "rectangle.on.rectangle"
        case .writeSettings: return "gearshape.2.fill"
        case .allFiles: return "folder.fill"
        case .installApps: return "square.and.arrow.down.fill"
        case .exactAlarms: return "alarm.fill"
        case .battery: return "battery.100.bolt"
        case .usage: return "chart.bar.fill"
        }
    }

    /// What a new phone answers before the user chooses: the framework's own defaults (husk.Permissions.special).
    var byDefault: Bool {
        switch self {
        case .allFiles, .exactAlarms: return true
        default: return false
        }
    }
}

/// The iPhone's side of a permission.
enum IOSPermission {
    case camera, microphone, location, photos, contacts, calendar, notifications, bluetooth

    enum Status { case notDetermined, granted, denied }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .location: return "Location"
        case .photos: return "Photos"
        case .contacts: return "Contacts"
        case .calendar: return "Calendars"
        case .notifications: return "Notifications"
        case .bluetooth: return "Bluetooth"
        }
    }

    /// Safe from any thread: the translation layer asks while the app runs.
    var status: Status {
        switch self {
        case .camera: return Self.av(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: return Self.av(AVCaptureDevice.authorizationStatus(for: .audio))
        case .location: return IOSPermissionCache.location.value
        case .photos:
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .notDetermined: return .notDetermined
            case .authorized, .limited: return .granted
            default: return .denied
            }
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .notDetermined: return .notDetermined
            case .denied, .restricted: return .denied
            default: return .granted
            }
        case .calendar:
            let s = EKEventStore.authorizationStatus(for: .event)
            // 3: authorized (iOS 16) / fullAccess (iOS 17); writeOnly (4) cannot read, which is what Android's calendar grants
            return s == .notDetermined ? .notDetermined : s.rawValue == 3 ? .granted : .denied
        case .notifications: return IOSPermissionCache.notifications.value
        case .bluetooth:
            switch CBManager.authorization {
            case .notDetermined: return .notDetermined
            case .allowedAlways: return .granted
            default: return .denied
            }
        }
    }

    private static func av(_ s: AVAuthorizationStatus) -> Status {
        switch s {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        default: return .denied
        }
    }

    /// The iPhone's prompt (once: after that iOS answers from Settings), and what it says now.
    @MainActor func request() async -> Bool {
        switch self {
        case .camera: return await AVCaptureDevice.requestAccess(for: .video)
        case .microphone: return await AVCaptureDevice.requestAccess(for: .audio)
        case .location: return await LocationAsker.shared.ask()
        case .photos:
            let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return s == .authorized || s == .limited
        case .contacts: return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        case .calendar:
            let store = EKEventStore()
            if #available(iOS 17.0, *) { return (try? await store.requestFullAccessToEvents()) ?? false }
            return (try? await store.requestAccess(to: .event)) ?? false
        case .notifications:
            let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await IOSPermissionCache.refresh()
            return ok
        case .bluetooth: return await BluetoothAsker.shared.ask()
        }
    }
}

/// What iOS only says asynchronously (notifications) or on the main thread (location), kept for answers from any thread.
enum IOSPermissionCache {
    final class Box {
        private let lock = NSLock()
        private var v: IOSPermission.Status = .notDetermined
        var value: IOSPermission.Status {
            get { lock.lock(); defer { lock.unlock() }; return v }
            set { lock.lock(); v = newValue; lock.unlock() }
        }
    }
    static let location = Box()
    static let notifications = Box()

    @MainActor static func refresh() async {
        location.value = LocationAsker.shared.status
        let n = await UNUserNotificationCenter.current().notificationSettings()
        switch n.authorizationStatus {
        case .notDetermined: notifications.value = .notDetermined
        case .denied: notifications.value = .denied
        default: notifications.value = .granted
        }
    }
}

@MainActor
private final class LocationAsker: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAsker()
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: IOSPermission.Status {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        default: return .denied
        }
    }

    func ask() async -> Bool {
        guard status == .notDetermined else { return status == .granted }
        return await withCheckedContinuation { c in
            waiting = c
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            IOSPermissionCache.location.value = self.status
            guard self.status != .notDetermined, let c = self.waiting else { return }
            self.waiting = nil
            c.resume(returning: self.status == .granted)
        }
    }
}

@MainActor
private final class BluetoothAsker: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothAsker()
    private var central: CBCentralManager?
    private var waiting: CheckedContinuation<Bool, Never>?

    func ask() async -> Bool {
        guard CBManager.authorization == .notDetermined else { return CBManager.authorization == .allowedAlways }
        return await withCheckedContinuation { c in
            waiting = c
            // making a central manager is what asks
            central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            guard CBManager.authorization != .notDetermined, let c = self.waiting else { return }
            self.waiting = nil
            c.resume(returning: CBManager.authorization == .allowedAlways)
        }
    }
}

// MARK: - what each app was allowed

enum AndroidPermissions {
    /// One app's choices: a group's or a special permission's key, and what was chosen.
    enum Choice: String { case granted, denied, forever }

    private static func key(_ appID: String) -> String { "huskpatch.perms." + appID }

    /// "Only this time": granted until HuskPatch next starts.
    private static let lock = NSLock()
    private static var oneTime: Set<String> = []

    static func choice(_ appID: String, _ what: String) -> Choice? {
        let d = UserDefaults.standard.dictionary(forKey: key(appID)) as? [String: String]
        return d?[what].flatMap(Choice.init(rawValue:))
    }

    static func set(_ appID: String, _ what: String, _ choice: Choice?) {
        var d = (UserDefaults.standard.dictionary(forKey: key(appID)) as? [String: String]) ?? [:]
        d[what] = choice?.rawValue
        UserDefaults.standard.set(d, forKey: key(appID))
        if choice != .granted { lock.lock(); oneTime.remove(appID + "|" + what); lock.unlock() }
    }

    static func grantOnce(_ appID: String, _ what: String) {
        lock.lock(); oneTime.insert(appID + "|" + what); lock.unlock()
    }

    static func isOneTime(_ appID: String, _ what: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return oneTime.contains(appID + "|" + what)
    }

    /// Forget everything an app was allowed (Settings › Apps › the app › Clear permissions).
    static func reset(_ appID: String) {
        UserDefaults.standard.removeObject(forKey: key(appID))
        lock.lock(); oneTime = oneTime.filter { !$0.hasPrefix(appID + "|") }; lock.unlock()
    }

    /// Whether a group reads as granted to an app now: allowed on Android (or for this run), and not refused by iOS.
    static func granted(_ appID: String, _ group: AndroidPermissionGroup) -> Bool {
        let android = choice(appID, group.rawValue) == .granted || isOneTime(appID, group.rawValue)
        guard android else { return false }
        return group.ios.map { $0.status == .granted } ?? true
    }

    /// The app that is running, by the folder its APKs are in (TranslationLayer/<id>/base.apk).
    static func runningAppID() -> String? {
        guard let apk = husk_native_loaded_apk().map({ String(cString: $0) }) else { return nil }
        return URL(fileURLWithPath: apk).deletingLastPathComponent().lastPathComponent
    }

    /// The permissions an app's manifest asks for.
    static func declared(_ app: TLApp) -> [String] {
        guard let apk = app.apks.first else { return [] }
        var buf = [CChar](repeating: 0, count: 64 * 1024)
        _ = husk_apk_permissions(apk, &buf, UInt(buf.count))
        return String(cString: buf).split(separator: "\n").map(String.init)
    }

    // MARK: answers for the translation layer (any thread)

    static func state(_ permission: String) -> Int32 {
        guard let app = runningAppID() else { return Int32(HUSK_PERM_GRANTED) }
        if let special = AndroidSpecialAccess(rawValue: permission) {
            switch choice(app, special.rawValue) {
            case .granted?: return Int32(HUSK_PERM_GRANTED)
            case .denied?, .forever?: return Int32(HUSK_PERM_DENIED)
            case nil: return Int32(HUSK_PERM_UNSET)
            }
        }
        // A normal permission (the internet, vibration...) is granted when the app is installed.
        guard let group = AndroidPermissionGroup.of(permission) else { return Int32(HUSK_PERM_GRANTED) }
        if isOneTime(app, group.rawValue) || choice(app, group.rawValue) == .granted {
            // turned off for HuskPatch in iOS Settings since: the app sees it denied
            if let ios = group.ios, ios.status == .denied { return Int32(HUSK_PERM_DENIED) }
            // "Approximate" location grants coarse location alone
            if permission.hasSuffix("ACCESS_FINE_LOCATION"), choice(app, "location.approximate") == .granted {
                return Int32(HUSK_PERM_DENIED)
            }
            return Int32(HUSK_PERM_GRANTED)
        }
        switch choice(app, group.rawValue) {
        case .forever?: return Int32(HUSK_PERM_DENIED_FOREVER)
        case .denied?: return Int32(HUSK_PERM_DENIED)
        default: return Int32(HUSK_PERM_UNSET)
        }
    }

    /// Registers HuskPatch as the translation layer's permission host. At launch.
    static func install() {
        husk_perm_set_host({ perm in
            guard let perm else { return Int32(HUSK_PERM_GRANTED) }
            return AndroidPermissions.state(String(cString: perm))
        }, { id, perms in
            let list = perms.map { String(cString: $0) }?.split(separator: "\n").map(String.init) ?? []
            Task { @MainActor in AndroidPermissionPrompter.shared.enqueue(id: id, permissions: list) }
        })
        Task { @MainActor in await IOSPermissionCache.refresh() }
    }
}

// MARK: - asking

/// Shows the dialogs, one request at a time, in a window of their own over whatever is on screen: the app full screen,
/// a window in multitasking, or Android OS mode.
@MainActor
final class AndroidPermissionPrompter: ObservableObject {
    static let shared = AndroidPermissionPrompter()

    enum Screen: Equatable {
        case dialog(AndroidPermissionGroup, location: Bool)
        case blocked(AndroidPermissionGroup)
        case special(AndroidSpecialAccess)
        case appInfo
    }

    /// A dialog's answer.
    enum Answer { case allow, whileInUse, once, deny, approximate }

    @Published private(set) var screen: Screen?
    @Published private(set) var appLabel = "This app"
    @Published private(set) var appID = ""
    @Published private(set) var appIcon: String?

    private var queue: [(id: Int32, permissions: [String])] = []
    private var busy = false
    private var answer: CheckedContinuation<Answer, Never>?
    private var window: UIWindow?
    private weak var previousKey: UIWindow?

    func enqueue(id: Int32, permissions: [String]) {
        queue.append((id, permissions))
        if !busy { Task { await drain() } }
    }

    /// The dialog's buttons call this.
    func answered(_ a: Answer) {
        let c = answer
        answer = nil
        c?.resume(returning: a)
    }

    private func drain() async {
        busy = true
        while !queue.isEmpty {
            let next = queue.removeFirst()
            let mask = await handle(next.permissions)
            husk_perm_result(next.id, mask)
        }
        hide()
        busy = false
    }

    private func ask(_ s: Screen) async -> Answer {
        show()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { screen = s }
        let a = await withCheckedContinuation { answer = $0 }
        withAnimation(.easeOut(duration: 0.15)) { screen = nil }
        try? await Task.sleep(nanoseconds: 160_000_000)
        return a
    }

    private func handle(_ permissions: [String]) async -> UInt32 {
        guard let app = AndroidPermissions.runningAppID() else { return permissions.isEmpty ? 0 : UInt32.max }
        appID = app
        let tl = TranslationLayerStore.shared.apps.first { $0.id == app }
        appLabel = tl?.label ?? "This app"
        appIcon = tl?.iconPath

        var granted = [Bool](repeating: false, count: permissions.count)

        // An app opening a Settings page: special app access, or its App info.
        if permissions.count == 1 {
            if permissions[0] == "husk.APP_INFO" { _ = await ask(.appInfo); return 0 }
            if let special = AndroidSpecialAccess(rawValue: permissions[0]) {
                _ = await ask(.special(special))
                return AndroidPermissions.choice(app, special.rawValue) == .granted ? 1 : 0
            }
        }

        var groups: [AndroidPermissionGroup] = []
        for (i, p) in permissions.enumerated() {
            if let special = AndroidSpecialAccess(rawValue: p) {
                // asked through requestPermissions, a special permission is not a dialog on Android: it is what Settings says
                granted[i] = AndroidPermissions.choice(app, special.rawValue) == .granted
            } else if let g = AndroidPermissionGroup.of(p) {
                if !groups.contains(g) { groups.append(g) }
            } else {
                granted[i] = true
            }
        }

        for g in groups {
            let wantsFine = permissions.contains { $0.hasSuffix("ACCESS_FINE_LOCATION") }
            var allowed = AndroidPermissions.granted(app, g)
            if !allowed && AndroidPermissions.choice(app, g.rawValue) != .forever {
                let a = await ask(.dialog(g, location: g == .location && wantsFine))
                switch a {
                case .deny:
                    let before = AndroidPermissions.choice(app, g.rawValue)
                    AndroidPermissions.set(app, g.rawValue, before == .denied ? .forever : .denied)
                case .once, .allow, .whileInUse, .approximate:
                    if a == .once {
                        AndroidPermissions.grantOnce(app, g.rawValue)
                    } else {
                        AndroidPermissions.set(app, g.rawValue, .granted)
                    }
                    if g == .location { AndroidPermissions.set(app, "location.approximate", a == .approximate ? .granted : nil) }
                    allowed = true
                    if let ios = g.ios {
                        switch ios.status {
                        case .granted: break
                        case .notDetermined: allowed = await ios.request()
                        case .denied:
                            allowed = false
                            if await ask(.blocked(g)) == .allow, let url = URL(string: UIApplication.openSettingsURLString) {
                                await UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            for (i, p) in permissions.enumerated() where AndroidPermissionGroup.of(p) == g {
                granted[i] = allowed && !(p.hasSuffix("ACCESS_FINE_LOCATION") && AndroidPermissions.choice(app, "location.approximate") == .granted)
            }
        }

        var mask: UInt32 = 0
        for (i, g) in granted.enumerated() where g && i < 32 { mask |= 1 << UInt32(i) }
        return mask
    }

    // MARK: the window

    private func show() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        previousKey = scene.windows.first { $0.isKeyWindow }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let host = PermissionHostingController(rootView: AndroidPermissionOverlay())
        host.view.backgroundColor = .clear
        host.orientations = scene.interfaceOrientation.isLandscape ? .landscape : .portrait
        w.rootViewController = host
        w.backgroundColor = .clear
        w.makeKeyAndVisible()
        window = w
    }

    private func hide() {
        window?.isHidden = true
        window = nil
        previousKey?.makeKey()
    }
}

/// Keeps the game's orientation and hides the status bar while a dialog is up.
private final class PermissionHostingController: UIHostingController<AndroidPermissionOverlay> {
    var orientations: UIInterfaceOrientationMask = .all
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { orientations }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

// MARK: - the dialogs

private struct AndroidPermissionOverlay: View {
    @ObservedObject private var prompter = AndroidPermissionPrompter.shared

    var body: some View {
        ZStack {
            if let screen = prompter.screen {
                switch screen {
                case .dialog, .blocked:
                    Color.black.opacity(0.4).ignoresSafeArea().transition(.opacity)
                    AndroidPermissionDialog(screen: screen)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                case .special(let s):
                    AndroidSpecialAccessPage(access: s, appID: prompter.appID, label: prompter.appLabel, icon: prompter.appIcon) {
                        prompter.answered(.allow)
                    }
                    .transition(.move(edge: .trailing))
                case .appInfo:
                    AndroidAppInfoPage(appID: prompter.appID, label: prompter.appLabel, icon: prompter.appIcon) {
                        prompter.answered(.allow)
                    }
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(Material3Root())
    }
}

/// Android 16's permission dialog: the group's icon, the question with the app's name in bold, and the choices stacked as
/// tonal buttons that round off at the top and bottom of the stack.
private struct AndroidPermissionDialog: View {
    let screen: AndroidPermissionPrompter.Screen
    @ObservedObject private var prompter = AndroidPermissionPrompter.shared
    @State private var precise = true

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    content
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(width: min(360, geo.size.width - 48))
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .scrollBounceBehaviorBasedOnSizeCompat()
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .dialog(let g, let location):
            Image(systemName: g.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color(uiColor: Material3.primary))
                .padding(.bottom, 16)
            (Text("Allow ") + Text(prompter.appLabel).bold() + Text(" to \(g.question)?"))
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, location ? 16 : 24)
            if location { accuracy }
            if g.ios != nil, g.ios?.status == .notDetermined {
                Text("The iPhone will also ask about \(g.ios!.title.lowercased()) for HuskPatch.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
            }
            if g.whileInUse {
                stack([("While using the app", { prompter.answered(precise ? .whileInUse : .approximate) }),
                       ("Only this time", { prompter.answered(.once) }),
                       ("Don't allow", { prompter.answered(.deny) })])
            } else {
                stack([("Allow", { prompter.answered(.allow) }),
                       ("Don't allow", { prompter.answered(.deny) })])
            }
        case .blocked(let g):
            Image(systemName: g.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color(uiColor: Material3.primary))
                .padding(.bottom, 16)
            Text("\(g.ios?.title ?? g.title) is turned off for HuskPatch")
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
            Text("\(prompter.appLabel) was allowed on Android, but the iPhone keeps it from HuskPatch. Turn it on in iOS Settings › HuskPatch.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
            stack([("Open Settings", { prompter.answered(.allow) }), ("Not now", { prompter.answered(.deny) })])
        default:
            EmptyView()
        }
    }

    /// Android 12+'s precise / approximate choice for location.
    private var accuracy: some View {
        HStack(spacing: 24) {
            accuracyTile("Precise", precise, icon: "scope") { precise = true }
            accuracyTile("Approximate", !precise, icon: "map") { precise = false }
        }
        .padding(.bottom, 20)
    }

    private func accuracyTile(_ title: String, _ on: Bool, icon: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color(uiColor: on ? Material3.primaryContainer : Material3.surfaceContainerHighest))
                    .frame(width: 84, height: 84)
                    .overlay(Image(systemName: icon).font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color(uiColor: on ? Material3.onPrimaryContainer : Material3.onSurfaceVariant)))
                    .overlay(Circle().stroke(Color(uiColor: Material3.primary), lineWidth: on ? 3 : 0))
                Text(title).font(.system(size: 14, weight: on ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
            }
        }
        .buttonStyle(.plain)
    }

    private func stack(_ buttons: [(String, () -> Void)]) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { i, b in
                Button(action: b.1) {
                    Text(b.0)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(uiColor: Material3.primaryContainer).opacity(0.75),
                                    in: StackedCorners(top: i == 0 ? 20 : 4, bottom: i == buttons.count - 1 ? 20 : 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(AndroidRippleStyle())
            }
        }
    }
}

/// A rectangle with one radius for its top corners and another for its bottom ones (iOS 16 has no UnevenRoundedRectangle).
struct StackedCorners: Shape {
    let top: CGFloat, bottom: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let t = min(top, r.height / 2), b = min(bottom, r.height / 2)
        p.move(to: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - t, y: r.minY + t), radius: t, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - b))
        p.addArc(center: CGPoint(x: r.maxX - b, y: r.maxY - b), radius: b, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + b, y: r.maxY - b), radius: b, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + t))
        p.addArc(center: CGPoint(x: r.minX + t, y: r.minY + t), radius: t, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// A press that dims, as Android's ripple settles.
struct AndroidRippleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// .scrollBounceBehavior(.basedOnSize) where it exists (iOS 16.4).
    @ViewBuilder func scrollBounceBehaviorBasedOnSizeCompat() -> some View {
        if #available(iOS 16.4, *) { scrollBounceBehavior(.basedOnSize) } else { self }
    }
}

// MARK: - Settings pages an app can open

/// A page in Android's Settings: a back arrow in a tonal circle and the title, on the surface colour.
struct AndroidSettingsPage<Content: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                            .frame(width: 40, height: 40)
                            .background(Color(uiColor: Material3.secondaryContainer), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            Text(title)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 0) { content }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: Material3.surface).ignoresSafeArea())
    }
}

/// Settings' grouped rows: a rounded card of rows, 2 points apart, the group's ends rounded more.
struct AndroidSettingsGroup<Content: View>: View {
    var header: String?
    @AppStorage(Android13.key) private var a13 = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.primary))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            // Android 13's Settings are flat lists; later versions group rows on cards
            VStack(spacing: a13 ? 0 : 2) { content }
                .clipShape(RoundedRectangle(cornerRadius: a13 ? 0 : 24, style: .continuous))
        }
        .padding(.bottom, a13 ? 8 : 16)
    }
}

/// One row of a group: an icon in a tinted circle, a title and a summary, and whatever goes at the end.
struct AndroidSettingsRow<Trailing: View>: View {
    var icon: String?
    var tint: UIColor = Material3.primary
    let title: String
    var summary: String?
    @ViewBuilder var trailing: Trailing
    @AppStorage(Android13.key) private var a13 = false

    var body: some View {
        HStack(spacing: a13 ? 22 : 16) {
            if let icon {
                // Android 13: the icon alone, in the accent's light tone; later: in a tinted circle
                Image(systemName: icon)
                    .font(.system(size: a13 ? 20 : 18, weight: .medium))
                    .foregroundStyle(a13 ? Color(uiColor: Material3.tone(.primary, 80)) : Color(uiColor: tint))
                    .frame(width: a13 ? 28 : 40, height: 40)
                    .background(a13 ? Color.clear : Color(uiColor: tint).opacity(0.14), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: a13 ? 19 : 17, design: a13 ? .default : .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14, design: a13 ? .default : .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: a13 ? 72 : 64)
        .background(Color(uiColor: a13 ? Material3.surface : Material3.surfaceContainer))
        .contentShape(Rectangle())
    }
}

extension AndroidSettingsRow where Trailing == EmptyView {
    init(icon: String? = nil, tint: UIColor = Material3.primary, title: String, summary: String? = nil) {
        self.init(icon: icon, tint: tint, title: title, summary: summary) { EmptyView() }
    }
}

/// An app's icon and name, at the top of its Settings pages.
struct AndroidAppHeader: View {
    let label: String
    let icon: String?

    var body: some View {
        VStack(spacing: 10) {
            AppIcon(path: icon, size: 72).clipShape(Circle())
            Text(label)
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// Special app access: the page an app sends you to for "Display over other apps" and the like.
struct AndroidSpecialAccessPage: View {
    let access: AndroidSpecialAccess
    let appID: String
    let label: String
    let icon: String?
    var onBack: () -> Void
    @State private var on = false

    var body: some View {
        AndroidSettingsPage(title: access.title, onBack: onBack) {
            AndroidAppHeader(label: label, icon: icon)
            AndroidSettingsGroup {
                AndroidSettingsRow(title: access.toggle) {
                    Toggle("", isOn: $on).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
                .onTapGesture { on.toggle() }
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Text(access.footer + "\n\nThis is Android's permission alone: iOS has nothing like it, so only the app is told.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            .padding(.horizontal, 8)
        }
        .onAppear {
            let c = AndroidPermissions.choice(appID, access.rawValue)
            on = c.map { $0 == .granted } ?? access.byDefault
        }
        .onChange(of: on) { v in AndroidPermissions.set(appID, access.rawValue, v ? .granted : .denied) }
    }
}

/// An app's App info › Permissions: every group it asks for, and what it was given.
struct AndroidAppInfoPage: View {
    let appID: String
    let label: String
    let icon: String?
    var onBack: (() -> Void)?
    @State private var refresh = 0

    private var app: TLApp? { TranslationLayerStore.shared.apps.first { $0.id == appID } }

    private var groups: [AndroidPermissionGroup] {
        var set: [AndroidPermissionGroup] = []
        for p in app.map(AndroidPermissions.declared) ?? [] {
            if let g = AndroidPermissionGroup.of(p), !set.contains(g) { set.append(g) }
        }
        for g in AndroidPermissionGroup.allCases where AndroidPermissions.choice(appID, g.rawValue) != nil && !set.contains(g) { set.append(g) }
        return set
    }

    private var specials: [AndroidSpecialAccess] {
        let declared = Set(app.map(AndroidPermissions.declared) ?? [])
        return AndroidSpecialAccess.allCases.filter { declared.contains($0.rawValue) || AndroidPermissions.choice(appID, $0.rawValue) != nil }
    }

    var body: some View {
        AndroidSettingsPage(title: "App info", onBack: onBack) {
            AndroidAppHeader(label: label, icon: icon)
            let allowed = groups.filter { AndroidPermissions.granted(appID, $0) }
            let denied = groups.filter { !AndroidPermissions.granted(appID, $0) }
            if groups.isEmpty {
                AndroidSettingsGroup(header: "Permissions") {
                    AndroidSettingsRow(icon: "checkmark.shield", title: "No permissions requested")
                }
            }
            if !allowed.isEmpty {
                AndroidSettingsGroup(header: "Allowed") { ForEach(allowed) { row($0) } }
            }
            if !denied.isEmpty {
                AndroidSettingsGroup(header: "Not allowed") { ForEach(denied) { row($0) } }
            }
            if !specials.isEmpty {
                AndroidSettingsGroup(header: "Special app access") {
                    ForEach(specials) { s in
                        AndroidSettingsRow(icon: s.icon, title: s.title, summary: "Android only") {
                            Toggle("", isOn: Binding(
                                get: { AndroidPermissions.choice(appID, s.rawValue).map { $0 == .granted } ?? s.byDefault },
                                set: { AndroidPermissions.set(appID, s.rawValue, $0 ? .granted : .denied); refresh += 1 }))
                                .labelsHidden().toggleStyle(Material3SwitchStyle())
                        }
                    }
                }
            }
            AndroidSettingsGroup {
                Button {
                    AndroidPermissions.reset(appID)
                    refresh += 1
                } label: {
                    AndroidSettingsRow(icon: "arrow.counterclockwise", title: "Reset permissions",
                                       summary: "The app asks again the next time it needs one")
                }
                .buttonStyle(AndroidRippleStyle())
            }
        }
        .id(refresh)
    }

    private func row(_ g: AndroidPermissionGroup) -> some View {
        let ios = g.ios
        let summary: String = {
            var s = AndroidPermissions.isOneTime(appID, g.rawValue) ? "Allowed only this time"
                : AndroidPermissions.choice(appID, g.rawValue) == .granted ? (g.whileInUse ? "Allowed only while in use" : "Allowed")
                : AndroidPermissions.choice(appID, g.rawValue) == .forever ? "Not allowed · won't ask again" : "Not allowed"
            if let ios {
                s += ios.status == .denied ? " · off for HuskPatch in iOS Settings" : " · also asked by iOS"
            } else {
                s += " · Android only"
            }
            return s
        }()
        return Menu {
            Button("Allow") {
                AndroidPermissions.set(appID, g.rawValue, .granted)
                refresh += 1
                if let ios, ios.status == .notDetermined { Task { _ = await ios.request(); refresh += 1 } }
            }
            Button("Don't allow", role: .destructive) { AndroidPermissions.set(appID, g.rawValue, .denied); refresh += 1 }
        } label: {
            AndroidSettingsRow(icon: g.icon, title: g.title, summary: summary)
        }
        .buttonStyle(.plain)
    }
}
