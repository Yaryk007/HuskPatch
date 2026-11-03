import SwiftUI

/// Every real app in ModemOS. Each one's screen is in `Apps/`.
enum AppID: String, CaseIterable {
    case phone, messages, browser, camera
    case photos, settings, clock, maps, weather, music, calendar, contacts, health, notes, files
    case calculator, compass, flashlight, recorder
    /// A placeholder app in the Dummy Apps folder (its name, icon and colour live on its `HomeItem`).
    case dummy
    /// One of the host's apps (`ModemOSHost.apps`); its name, icon and screen live on its `HomeItem`.
    case host

    var name: String {
        switch self {
        case .phone: return "Phone"
        case .messages: return "Messages"
        case .browser: return "Browser"
        case .camera: return "Camera"
        case .photos: return "Photos"
        case .settings: return "Settings"
        case .clock: return "Clock"
        case .maps: return "Maps"
        case .weather: return "Weather"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .contacts: return "Contacts"
        case .health: return "Health"
        case .notes: return "Notes"
        case .files: return "Files"
        case .calculator: return "Calculator"
        case .compass: return "Compass"
        case .flashlight: return "Flashlight"
        case .recorder: return "Recorder"
        case .dummy: return "Dummy"
        case .host: return "App"
        }
    }

    var symbol: String {
        switch self {
        case .phone: return "phone.fill"
        case .messages: return "message.fill"
        case .browser: return "safari.fill"
        case .camera: return "camera.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .settings: return "gearshape.fill"
        case .clock: return "clock.fill"
        case .maps: return "map.fill"
        case .weather: return "cloud.sun.fill"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .contacts: return "person.crop.circle.fill"
        case .health: return "figure.walk"
        case .notes: return "note.text"
        case .files: return "folder.fill"
        case .calculator: return "plus.forwardslash.minus"
        case .compass: return "location.north.line.fill"
        case .flashlight: return "flashlight.on.fill"
        case .recorder: return "waveform"
        case .dummy: return "questionmark.app.dashed"
        case .host: return "app.fill"
        }
    }

    var color: Color {
        switch self {
        case .phone: return rgb(52, 199, 89)
        case .messages: return rgb(48, 176, 120)
        case .browser: return rgb(10, 132, 255)
        case .camera: return rgb(90, 90, 100)
        case .photos: return rgb(255, 120, 90)
        case .settings: return rgb(130, 130, 145)
        case .clock: return rgb(40, 40, 50)
        case .maps: return rgb(60, 180, 140)
        case .weather: return rgb(60, 140, 240)
        case .music: return rgb(250, 60, 90)
        case .calendar: return rgb(240, 80, 70)
        case .contacts: return rgb(150, 130, 110)
        case .health: return rgb(255, 90, 140)
        case .notes: return rgb(240, 180, 40)
        case .files: return rgb(40, 120, 230)
        case .calculator: return rgb(255, 150, 0)
        case .compass: return rgb(70, 70, 80)
        case .flashlight: return rgb(120, 100, 230)
        case .recorder: return rgb(220, 50, 60)
        case .dummy: return rgb(150, 150, 160)
        case .host: return rgb(60, 160, 90)
        }
    }
}

/// Something you can open: an app, or a folder that has apps inside it.
/// Apps open full screen; folders open as a panel over a blurred backdrop.
struct HomeItem: Identifiable, Equatable {
    enum Kind {
        case app, folder
    }

    let id: Int
    let name: String
    let symbol: String
    let color: Color
    let kind: Kind
    let app: AppID?
    /// The host app this opens (`app == .host`).
    var hostID: String? = nil

    init(_ id: Int, _ app: AppID) {
        self.id = id
        self.name = app.name
        self.symbol = app.symbol
        self.color = app.color
        self.kind = .app
        self.app = app
    }

    /// A dummy app: it opens, but only shows a placeholder screen.
    private init(dummy id: Int, _ name: String, _ symbol: String, _ color: Color) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.kind = .app
        self.app = .dummy
    }

    /// One of the host's apps.
    private init(host id: Int, _ app: ModemOSHostApp) {
        self.id = id
        self.name = app.name
        self.symbol = app.symbol
        self.color = app.color
        self.kind = .app
        self.app = .host
        self.hostID = app.id
    }

    private init(folderID: Int, name: String) {
        self.id = folderID
        self.name = name
        self.symbol = "square.grid.2x2"
        self.color = Color.white.opacity(0.22)
        self.kind = .folder
        self.app = nil
    }

    static func == (a: HomeItem, b: HomeItem) -> Bool { a.id == b.id }

    static let folderID = 30
    static let dummyFolderID = 31
    static let hostFolderID = 32

    static let toolsFolder = HomeItem(folderID: folderID, name: "Tools")
    static let dummyFolder = HomeItem(folderID: dummyFolderID, name: "Dummy Apps")
    static var hostFolder: HomeItem { HomeItem(folderID: hostFolderID, name: ModemOSHost.shared.folderName) }

    /// The host's apps, at most nine (a folder's three rows).
    static var hostApps: [HomeItem] {
        ModemOSHost.shared.apps.prefix(9).enumerated().map { HomeItem(host: 70 + $0.offset, $0.element) }
    }

    /// The apps inside a folder (the first four are the little icons on the folder's icon).
    static func children(of folder: Int) -> [HomeItem] {
        switch folder {
        case dummyFolderID: return dummyApps
        case hostFolderID: return hostApps
        default: return toolsApps
        }
    }

    static let toolsApps: [HomeItem] = [
        HomeItem(20, .calculator),
        HomeItem(21, .compass),
        HomeItem(22, .flashlight),
        HomeItem(23, .recorder),
    ]

    /// Placeholder apps. The folder is hidden until it is turned on in the Lab.
    static let dummyApps: [HomeItem] = [
        HomeItem(dummy: 60, "Blank", "square.dashed", rgb(120, 130, 150)),
        HomeItem(dummy: 61, "Lorem", "text.alignleft", rgb(230, 120, 80)),
        HomeItem(dummy: 62, "Ipsum", "text.quote", rgb(90, 170, 120)),
        HomeItem(dummy: 63, "Foo", "cube.fill", rgb(110, 110, 230)),
        HomeItem(dummy: 64, "Bar", "chart.bar.fill", rgb(240, 170, 40)),
        HomeItem(dummy: 65, "Baz", "sparkle", rgb(210, 90, 170)),
        HomeItem(dummy: 66, "Demo", "play.rectangle.fill", rgb(60, 160, 220)),
        HomeItem(dummy: 67, "Sample", "testtube.2", rgb(40, 180, 170)),
        HomeItem(dummy: 68, "Test", "checkmark.seal.fill", rgb(170, 110, 60)),
    ]

    /// The app drawer in reading order; the Tools folder sits in the fourth spot, Dummy Apps (if on) at the end.
    static func drawer(showDummy: Bool) -> [HomeItem] {
        var items: [HomeItem] = [
            HomeItem(0, .photos),
            HomeItem(1, .settings),
            HomeItem(2, .clock),
            toolsFolder,
            HomeItem(3, .maps),
            HomeItem(4, .weather),
            HomeItem(5, .music),
            HomeItem(6, .calendar),
            HomeItem(7, .contacts),
            HomeItem(8, .health),
            HomeItem(9, .notes),
            HomeItem(10, .files),
        ]
        if ModemOSHost.shared.hasFolder {
            items.append(hostFolder)
        }
        if showDummy {
            items.append(dummyFolder)
        }
        return items
    }

    /// The apps on the home screen, above the dock.
    static let home: [HomeItem] = [
        HomeItem(50, .settings),
        HomeItem(51, .photos),
        HomeItem(52, .clock),
        HomeItem(53, .weather),
        HomeItem(54, .maps),
        HomeItem(55, .notes),
        HomeItem(56, .calendar),
        HomeItem(57, .music),
    ]

    /// The four apps in the dock.
    static let dock: [HomeItem] = [
        HomeItem(40, .phone),
        HomeItem(41, .messages),
        HomeItem(42, .browser),
        HomeItem(43, .camera),
    ]
}
