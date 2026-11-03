import SwiftUI
import AVFoundation
import Photos
import Contacts
import CoreLocation
import CoreMotion
import MediaPlayer
import EventKit

/// One place for every iOS permission ModemOS's apps use (setup shows them all as a list).
final class PermissionsCenter: ObservableObject {
    static let shared = PermissionsCenter()

    enum Kind: String, CaseIterable, Identifiable {
        case photos, camera, microphone, contacts, location, motion, music, calendar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .photos: return "Photos"
            case .camera: return "Camera"
            case .microphone: return "Microphone"
            case .contacts: return "Contacts"
            case .location: return "Location"
            case .motion: return "Motion & Fitness"
            case .music: return "Music library"
            case .calendar: return "Calendar"
            }
        }

        var detail: String {
            switch self {
            case .photos: return "Photos app and saving camera shots"
            case .camera: return "Camera app and flashlight"
            case .microphone: return "Recorder app"
            case .contacts: return "Phone, Messages and Contacts"
            case .location: return "Maps, Weather and Compass"
            case .motion: return "Steps in the Health app"
            case .music: return "Music app"
            case .calendar: return "Events in the Calendar app"
            }
        }

        var symbol: String {
            switch self {
            case .photos: return "photo.on.rectangle"
            case .camera: return "camera.fill"
            case .microphone: return "mic.fill"
            case .contacts: return "person.2.fill"
            case .location: return "location.fill"
            case .motion: return "figure.walk"
            case .music: return "music.note"
            case .calendar: return "calendar"
            }
        }
    }

    enum Status {
        case notAsked, allowed, denied
    }

    /// Bumped whenever a status may have changed, so views re-read them.
    @Published private(set) var revision = 0

    func status(_ kind: Kind) -> Status {
        switch kind {
        case .photos:
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .notDetermined: return .notAsked
            case .authorized, .limited: return .allowed
            default: return .denied
            }
        case .camera:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .notDetermined: return .notAsked
            case .authorized: return .allowed
            default:
                // iOS 18 adds "limited", which still lets us read the chosen contacts.
                return CNContactStore.authorizationStatus(for: .contacts).rawValue == 4 ? .allowed : .denied
            }
        case .location:
            switch LocationProvider.shared.authorization {
            case .notDetermined: return .notAsked
            case .authorizedWhenInUse, .authorizedAlways: return .allowed
            default: return .denied
            }
        case .motion:
            switch CMPedometer.authorizationStatus() {
            case .notDetermined: return .notAsked
            case .authorized: return .allowed
            default: return .denied
            }
        case .music:
            switch MPMediaLibrary.authorizationStatus() {
            case .notDetermined: return .notAsked
            case .authorized: return .allowed
            default: return .denied
            }
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined: return .notAsked
            case .fullAccess: return .allowed
            default: return .denied
            }
        }
    }

    func request(_ kind: Kind, done: (() -> Void)? = nil) {
        let finish: (Bool) -> Void = { granted in
            DispatchQueue.main.async {
                OSLogger.shared.log("Permissions", "\(kind.title): \(granted ? "allowed" : "denied")", level: granted ? .info : .warn)
                self.revision += 1
                done?()
            }
        }
        OSLogger.shared.log("Permissions", "Asking for \(kind.title)")
        switch kind {
        case .photos:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                finish(status == .authorized || status == .limited)
            }
        case .camera:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: finish)
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: finish)
        case .contacts:
            CNContactStore().requestAccess(for: .contacts) { granted, _ in finish(granted) }
        case .location:
            LocationProvider.shared.requestAccess { granted in finish(granted) }
        case .motion:
            // Motion access is asked for the first time the pedometer is queried.
            let pedometer = CMPedometer()
            let start = Calendar.current.startOfDay(for: Date())
            pedometer.queryPedometerData(from: start, to: Date()) { _, error in
                finish(error == nil)
                _ = pedometer
            }
        case .music:
            MPMediaLibrary.requestAuthorization { status in finish(status == .authorized) }
        case .calendar:
            if #available(iOS 17.0, *) { EKEventStore().requestFullAccessToEvents { granted, _ in finish(granted) } } else { EKEventStore().requestAccess(to: .event) { granted, _ in finish(granted) } }
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .notDetermined: return .notAsked
        case .authorized: return .allowed
        default: return .denied
        }
    }
}

/// The phone's location and compass heading, shared by Maps, Weather and Compass.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLHeading?
    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var pending: [(Bool) -> Void] = []
    private var users = 0
    private var headingUsers = 0

    private override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
    }

    var allowed: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func requestAccess(_ done: @escaping (Bool) -> Void) {
        if authorization != .notDetermined {
            done(allowed)
            return
        }
        pending.append(done)
        manager.requestWhenInUseAuthorization()
    }

    /// Call `start` when an app needs updates and `stop` when it goes away.
    func start(heading wantsHeading: Bool = false) {
        users += 1
        if wantsHeading { headingUsers += 1 }
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        if headingUsers > 0 && CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop(heading wantsHeading: Bool = false) {
        users = max(0, users - 1)
        if wantsHeading { headingUsers = max(0, headingUsers - 1) }
        if headingUsers == 0 { manager.stopUpdatingHeading() }
        if users == 0 { manager.stopUpdatingLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization != .notDetermined {
            let waiting = pending
            pending = []
            waiting.forEach { $0(allowed) }
        }
        if allowed && users > 0 {
            manager.startUpdatingLocation()
        }
        PermissionsCenter.shared.objectWillChange.send()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        OSLogger.shared.log("Location", error.localizedDescription, level: .warn)
    }
}
