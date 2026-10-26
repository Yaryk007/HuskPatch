// SPDX-License-Identifier: GPL-2.0-or-later
import MediaPlayer
import SwiftUI
import UIKit

/// HuskPatch: Android 16's home screen, as Trebuchet draws it on LineageOS 23.2.
///
/// Pages you swipe between (dots above the dock while they move), each with its widgets and apps; the dock along the
/// bottom. Long-press the wallpaper for Wallpaper & style, Widgets, App list and Home settings; long-press a widget to
/// resize it (the dots on its edges) or drag it onto Remove. Swipe up for the app drawer and down for the shade -- both
/// follow the finger. Double-tap the wallpaper to turn the screen off.

// MARK: - widgets

struct HomeWidgetItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: Kind
    var page: Int
    var cols: Int
    var rows: Int

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case clock, media, battery, date
        var id: String { rawValue }
        var title: String {
            switch self {
            case .clock: return "Clock"
            case .media: return "Music"
            case .battery: return "Battery"
            case .date: return "At a glance"
            }
        }
        var app: String {
            switch self {
            case .clock: return "Clock"
            case .media: return "Media player"
            case .battery: return "Settings"
            case .date: return "Calendar"
            }
        }
        var size: (cols: Int, rows: Int) {
            switch self {
            case .clock: return (4, 2)
            case .media: return (4, 1)
            case .battery: return (2, 2)
            case .date: return (4, 1)
            }
        }
        var minCols: Int { self == .battery ? 2 : 3 }
    }
}

/// An app or a folder of apps on the home screen. Apps are kept by their ShellApp id.
struct HomeEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var app: String?
    var folder: Folder?

    struct Folder: Codable, Equatable {
        var name: String
        var apps: [String]
    }

    static func app(_ id: String) -> HomeEntry { HomeEntry(app: id) }
}

/// What is on the home screen -- each page's widgets and apps (and folders), the dock, the grid's size -- kept in the
/// preferences as it is arranged.
@MainActor
final class HomeLayout: ObservableObject {
    static let shared = HomeLayout()
    private static let widgetsKey = "huskpatch.home.widgets"
    private static let appsKey = "huskpatch.home.apps"
    private static let dockKey = "huskpatch.home.dock"
    private static let seenKey = "huskpatch.home.seen"
    static let columnsKey = "huskpatch.home.columns"
    static let rowsKey = "huskpatch.home.rows"
    static let addNewKey = "huskpatch.home.addNew"

    @Published var widgets: [HomeWidgetItem] { didSet { save(widgets, Self.widgetsKey) } }
    @Published var pageApps: [[HomeEntry]] { didSet { save(pageApps, Self.appsKey) } }
    @Published var dock: [String] { didSet { save(dock, Self.dockKey) } }

    init() {
        let d = UserDefaults.standard
        widgets = d.data(forKey: Self.widgetsKey).flatMap { try? JSONDecoder().decode([HomeWidgetItem].self, from: $0) }
            ?? [HomeWidgetItem(kind: .clock, page: 0, cols: 4, rows: 2), HomeWidgetItem(kind: .media, page: 1, cols: 4, rows: 1)]
        pageApps = d.data(forKey: Self.appsKey).flatMap { try? JSONDecoder().decode([[HomeEntry]].self, from: $0) }
            ?? [[.app(ShellApp.playStore.id)], [.app(ShellApp.system(.files).id), .app(ShellApp.system(.clock).id), .app(ShellApp.settings.id)]]
        dock = d.data(forKey: Self.dockKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
            ?? AndroidSystemApp.dock.map { ShellApp.system($0).id }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    var columns: Int { min(5, max(4, UserDefaults.standard.object(forKey: Self.columnsKey) as? Int ?? 4)) }
    var rows: Int { min(6, max(4, UserDefaults.standard.object(forKey: Self.rowsKey) as? Int ?? 5)) }

    var pages: Int { max(2, (widgets.map(\.page).max() ?? 0) + 1, pageApps.count) }

    func apps(on page: Int) -> [HomeEntry] { page < pageApps.count ? pageApps[page] : [] }

    /// How many apps fit on a page: the grid's rows, less the rows its widgets take.
    func capacity(of page: Int) -> Int {
        let widgetRows = widgets.filter { $0.page == page }.reduce(0) { $0 + $1.rows }
        return max(columns, (rows - widgetRows) * columns)
    }

    private func ensurePage(_ page: Int) {
        while pageApps.count <= page { pageApps.append([]) }
    }

    func contains(_ app: String) -> Bool {
        dock.contains(app) || pageApps.contains { $0.contains { $0.app == app || ($0.folder?.apps.contains(app) ?? false) } }
    }

    /// Put an app on the first page with room (as installing an app or "Add to Home screen" does).
    func addToHome(_ app: String) {
        guard !contains(app) else { return }
        var page = 0
        while apps(on: page).count >= capacity(of: page) { page += 1 }
        ensurePage(page)
        withAnimation(AndroidMotion.spatial) { pageApps[page].append(.app(app)) }
    }

    /// Apps installed since the home screen last looked go on it, as Android's "Add new apps to Home screen" does.
    func addNewApps(_ all: [ShellApp]) {
        let d = UserDefaults.standard
        let seen = Set(d.stringArray(forKey: Self.seenKey) ?? [])
        let ids = all.compactMap { app -> String? in if case .item = app { return app.id }; return nil }
        if seen.isEmpty {
            // first time: the most recent apps, as the old home screen had them
            for id in ids.prefix(11) { addToHome(id) }
        } else if d.object(forKey: Self.addNewKey) as? Bool ?? true {
            for id in ids where !seen.contains(id) { addToHome(id) }
        }
        d.set(Array(seen.union(ids)), forKey: Self.seenKey)
    }

    /// Take an entry (or an app out of a folder) off the home screen.
    func remove(entry id: UUID) {
        withAnimation(AndroidMotion.spatial) {
            for p in pageApps.indices { pageApps[p].removeAll { $0.id == id } }
        }
    }

    func removeFromDock(_ app: String) { withAnimation(AndroidMotion.spatial) { dock.removeAll { $0 == app } } }

    func removeFromFolder(_ folderID: UUID, app: String) {
        for p in pageApps.indices {
            guard let i = pageApps[p].firstIndex(where: { $0.id == folderID }), var folder = pageApps[p][i].folder else { continue }
            folder.apps.removeAll { $0 == app }
            withAnimation(AndroidMotion.spatial) {
                if folder.apps.count <= 1 {
                    // a folder of one is just that app
                    pageApps[p][i] = folder.apps.first.map { HomeEntry.app($0) } ?? pageApps[p][i]
                    if folder.apps.isEmpty { pageApps[p].remove(at: i) }
                } else {
                    pageApps[p][i].folder = folder
                }
                pageApps[p].insert(.app(app), at: min(i + 1, pageApps[p].count))
            }
            return
        }
    }

    func rename(_ folderID: UUID, to name: String) {
        for p in pageApps.indices {
            if let i = pageApps[p].firstIndex(where: { $0.id == folderID }) { pageApps[p][i].folder?.name = name }
        }
    }

    /// Where an entry is.
    func locate(_ id: UUID) -> (page: Int, index: Int)? {
        for p in pageApps.indices { if let i = pageApps[p].firstIndex(where: { $0.id == id }) { return (p, i) } }
        return nil
    }

    /// Move an entry to a place on a page.
    func move(_ id: UUID, to page: Int, index: Int) {
        guard let from = locate(id) else { return }
        ensurePage(page)
        withAnimation(AndroidMotion.spatial) {
            let entry = pageApps[from.page].remove(at: from.index)
            pageApps[page].insert(entry, at: min(max(0, index), pageApps[page].count))
        }
    }

    /// Drop an app onto another app or a folder: a new folder, or one more app in it.
    func merge(_ id: UUID, into target: UUID) {
        guard id != target, let from = locate(id), let to = locate(target) else { return }
        let moving = pageApps[from.page][from.index]
        let movingApps = moving.app.map { [$0] } ?? moving.folder?.apps ?? []
        withAnimation(AndroidMotion.spatial) {
            var t = pageApps[to.page][to.index]
            if var folder = t.folder {
                folder.apps += movingApps
                t.folder = folder
            } else if let app = t.app {
                t = HomeEntry(id: t.id, folder: .init(name: "Folder", apps: [app] + movingApps))
            }
            pageApps[to.page][to.index] = t
            if let again = locate(id) { pageApps[again.page].remove(at: again.index) }
        }
    }

    /// An app from the page into the dock, at a place (the dock holds five).
    func moveToDock(_ id: UUID, index: Int) {
        guard let from = locate(id), let app = pageApps[from.page][from.index].app else { return }
        withAnimation(AndroidMotion.spatial) {
            pageApps[from.page].remove(at: from.index)
            dock.insert(app, at: min(max(0, index), dock.count))
            if dock.count > 5 {
                // the last one goes back to the page
                let out = dock.removeLast()
                pageApps[from.page].insert(.app(out), at: min(from.index, pageApps[from.page].count))
            }
        }
    }

    /// An app from the dock onto a page.
    func moveFromDock(_ app: String, to page: Int, index: Int) {
        ensurePage(page)
        withAnimation(AndroidMotion.spatial) {
            dock.removeAll { $0 == app }
            pageApps[page].insert(.app(app), at: min(max(0, index), pageApps[page].count))
        }
    }

    func moveInDock(_ app: String, to index: Int) {
        guard let from = dock.firstIndex(of: app) else { return }
        withAnimation(AndroidMotion.spatial) {
            dock.remove(at: from)
            dock.insert(app, at: min(max(0, index), dock.count))
        }
    }

    func reset() {
        let d = UserDefaults.standard
        for key in [Self.widgetsKey, Self.appsKey, Self.dockKey, Self.seenKey] { d.removeObject(forKey: key) }
        let fresh = HomeLayout()
        withAnimation(AndroidMotion.spatial) {
            widgets = fresh.widgets
            pageApps = fresh.pageApps
            dock = fresh.dock
        }
    }

    // MARK: widgets

    func add(_ kind: HomeWidgetItem.Kind, page: Int) {
        // a full page (four rows of widgets) puts the new one on the next
        let used = widgets.filter { $0.page == page }.reduce(0) { $0 + $1.rows }
        let target = used + kind.size.rows > 4 ? page + 1 : page
        withAnimation(AndroidMotion.spatial) {
            widgets.append(HomeWidgetItem(kind: kind, page: target, cols: kind.size.cols, rows: kind.size.rows))
        }
    }

    func remove(_ id: UUID) { withAnimation(AndroidMotion.spatial) { widgets.removeAll { $0.id == id } } }

    func resize(_ id: UUID, cols: Int, rows: Int) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(AndroidMotion.spatial) {
            widgets[i].cols = min(4, max(widgets[i].kind.minCols, cols))
            widgets[i].rows = min(4, max(1, rows))
        }
    }
}

extension AndroidShellState {
    /// Every app the shell knows: the library's, Android, and the system apps.
    static func catalog(store: TranslationLayerStore, host: AndroidHost) -> [ShellApp] {
        Launcher.items(store: store, host: host).map(ShellApp.item) + [.item(.android), .settings, .playStore]
            + AndroidSystemApp.allCases.map(ShellApp.system)
    }
}

/// The music playing in the Music app (Apple Music), for the media widget.
@MainActor
final class MediaWidgetModel: ObservableObject {
    static let shared = MediaWidgetModel()
    private let player = MPMusicPlayerController.systemMusicPlayer
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var artwork: UIImage?
    @Published private(set) var playing = false
    private var started = false

    init() {
        if MPMediaLibrary.authorizationStatus() == .authorized { start() }
    }

    private func start() {
        guard !started else { return }
        started = true
        player.beginGeneratingPlaybackNotifications()
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange, .MPMusicPlayerControllerPlaybackStateDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let item = player.nowPlayingItem
        title = item?.title
        artist = item?.artist
        artwork = item?.artwork?.image(at: CGSize(width: 160, height: 160))
        playing = player.playbackState == .playing
    }

    /// Play or pause; the first time, asks for access to the music.
    func toggle() {
        if MPMediaLibrary.authorizationStatus() != .authorized {
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in if status == .authorized { self.start(); self.player.play(); self.refresh() } }
            }
            return
        }
        start()
        if player.playbackState == .playing { player.pause() } else { player.play() }
        refresh()
    }

    func skip(_ forward: Bool) {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return }
        if forward { player.skipToNextItem() } else { player.skipToPreviousItem() }
        refresh()
    }
}

/// One widget, drawn at its size.
struct HomeWidgetView: View {
    let item: HomeWidgetItem
    let size: CGSize

    var body: some View {
        switch item.kind {
        case .clock: AndroidClockWidget(large: item.rows >= 2)
        case .media: MediaWidget(rows: item.rows)
        case .battery: BatteryWidget()
        case .date: GlanceWidget()
        }
    }
}

private struct MediaWidget: View {
    let rows: Int
    @ObservedObject private var media = MediaWidgetModel.shared

    var body: some View {
        Group {
            if rows >= 2 {
                VStack(alignment: .leading, spacing: 12) {
                    art(72)
                    Spacer(minLength: 0)
                    titles
                    HStack(spacing: 26) {
                        control("backward.fill") { media.skip(false) }
                        control(media.playing ? "pause.fill" : "play.fill", big: true) { media.toggle() }
                        control("forward.fill") { media.skip(true) }
                    }
                }
            } else {
                HStack(spacing: 14) {
                    art(54)
                    titles
                    Spacer(minLength: 0)
                    control(media.playing ? "pause.fill" : "play.fill") { media.toggle() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Color(white: 0.06)
                if let a = media.artwork { Image(uiImage: a).resizable().scaledToFill().androidBlur(30).opacity(0.45) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .foregroundStyle(.white)
    }

    private func art(_ side: CGFloat) -> some View {
        Group {
            if let a = media.artwork { Image(uiImage: a).resizable().scaledToFill() }
            else {
                Image(systemName: "music.note").font(.system(size: side * 0.45, weight: .bold))
                    .frame(width: side, height: side)
                    .background(Color(white: 0.2))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var titles: some View {
        if let title = media.title {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
                if let artist = media.artist { Text(artist).font(.system(size: 13, design: .rounded)).opacity(0.75).lineLimit(1) }
            }
        }
    }

    private func control(_ icon: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 22 : 17, weight: .bold))
                .frame(width: big ? 54 : 40, height: big ? 54 : 40)
                .background(big ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(AndroidSquashStyle())
    }
}

private struct BatteryWidget: View {
    @StateObject private var status = DeviceStatus()

    var body: some View {
        ZStack {
            Circle().stroke(Color(uiColor: Material3.surfaceContainerHighest), lineWidth: 10)
            Circle().trim(from: 0, to: status.level)
                .stroke(status.charging ? Color(red: 0.2, green: 0.82, blue: 0.35) : Color(uiColor: Material3.primary),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Image(systemName: status.charging ? "bolt.fill" : "iphone").font(.system(size: 18, weight: .semibold))
                Text("\(Int((status.level * 100).rounded()))%").font(.system(size: 20, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: Material3.surfaceContainer), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct GlanceWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let next = AndroidAlarms.load().filter(\.on).compactMap { AndroidAlarms.next($0) }.min()
            VStack(alignment: .leading, spacing: 4) {
                Text(ctx.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                if let next {
                    Label(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()), systemImage: "alarm")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - the home screen

struct Android16HomeScreen: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @ObservedObject private var layout = HomeLayout.shared
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @AppStorage(HomeSettings.swipeDownKey) private var swipeDown = true
    @AppStorage(HomeSettings.doubleTapKey) private var doubleTap = true
    @AppStorage(HomeLayout.columnsKey) private var columns = 4

    @State private var page = 0
    @State private var dragX: CGFloat = 0
    @State private var axis: Axis?
    @State private var menuAt: CGPoint?
    @State private var picker = false
    @State private var settings = false
    @State private var editing: UUID?
    @State private var dotsVisible = false
    /// An app being moved (held, then dragged), where the finger is, and over which part of the screen.
    @State private var dragging: HomeDrag?
    /// The menu of an app held without moving; a folder that is open.
    @State private var iconMenu: IconMenuTarget?
    @State private var openFolder: UUID?
    @State private var gridFrames: [Int: CGRect] = [:]

    private var catalog: [String: ShellApp] {
        Dictionary(AndroidShellState.catalog(store: store, host: host).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let land = w > h
            let apps = catalog
            ZStack(alignment: .top) {
                // the empty wallpaper: long-press for the menu, double-tap to sleep, tap to leave editing
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if doubleTap, editing == nil, menuAt == nil { shell.powerOff() }
                    }
                    .onTapGesture { dismissAll() }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        guard editing == nil, dragging == nil else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let origin = geo.frame(in: .global).origin
                        let at = TouchTracker.last.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) } ?? CGPoint(x: w / 2, y: h / 2)
                        withAnimation(AndroidMotion.bouncy) { menuAt = at }
                    }

                // the pages, side by side
                HStack(spacing: 0) {
                    ForEach(0..<layout.pages, id: \.self) { p in
                        pageView(p, width: w, land: land, apps: apps)
                            .frame(width: w)
                    }
                }
                .frame(width: w, alignment: .leading)
                .offset(x: -CGFloat(page) * w + dragX)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 10) {
                    Spacer()
                    pageDots
                    dock(land: land, width: w, apps: apps)
                }

                if editing != nil || dragging != nil {
                    Text("✕  Remove")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).frame(height: 44)
                        .background((dragging?.overRemove ?? false) ? Color.red.opacity(0.55) : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 2))
                        .padding(.top, 34)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // the app being moved, under the finger
                if let d = dragging, let app = apps[d.app] {
                    AndroidAppIcon(app: app, size: 62)
                        .scaleEffect(1.12)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                        .position(d.location)
                        .allowsHitTesting(false)
                        .zIndex(5)
                }

                if let target = iconMenu, let app = apps[target.app] {
                    IconMenu(target: target, app: app, size: geo.size) { action in
                        withAnimation(AndroidMotion.spatialFast) { iconMenu = nil }
                        switch action {
                        case .info: openInfo(app)
                        case .remove:
                            if let id = target.entry { layout.remove(entry: id) } else { layout.removeFromDock(target.app) }
                        }
                    } dismiss: { withAnimation(AndroidMotion.spatialFast) { iconMenu = nil } }
                    .transition(.scale(scale: 0.85, anchor: UnitPoint(x: target.at.x / max(w, 1), y: target.at.y / max(h, 1))).combined(with: .opacity))
                    .zIndex(4)
                }

                if let id = openFolder, let loc = layout.locate(id), let folder = layout.pageApps[loc.page][loc.index].folder {
                    FolderPanel(id: id, folder: folder, apps: apps) { withAnimation(AndroidMotion.spatial) { openFolder = nil } }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .zIndex(6)
                }

                if let at = menuAt {
                    HomeMenu(at: at, size: geo.size) { action in
                        withAnimation(AndroidMotion.spatialFast) { menuAt = nil }
                        switch action {
                        case .wallpaper:
                            shell.settingsPath.append(AndroidSettingsRoute.wallpaper)
                            shell.launch(.settings)
                        case .widgets: withAnimation(AndroidMotion.spatial) { picker = true }
                        case .apps: withAnimation(AndroidMotion.spatial) { shell.drawer = true }
                        case .home: withAnimation(AndroidMotion.spatial) { settings = true }
                        }
                    } dismiss: { withAnimation(AndroidMotion.spatialFast) { menuAt = nil } }
                    .transition(.scale(scale: 0.85, anchor: UnitPoint(x: at.x / max(w, 1), y: at.y / max(h, 1))).combined(with: .opacity))
                    .zIndex(2)
                }
            }
            .coordinateSpace(name: "home")
            .contentShape(Rectangle())
            // swipes anywhere -- over icons and widgets too -- move between pages, open the drawer or the shade
            .simultaneousGesture(pageDrag(width: w, height: h))
            .overlay {
                if picker {
                    WidgetPicker(page: page) { withAnimation(AndroidMotion.spatial) { picker = false } }
                        .transition(.move(edge: .bottom))
                }
                if settings {
                    HomeSettings { withAnimation(AndroidMotion.spatial) { settings = false } }
                        .transition(.move(edge: .bottom))
                }
            }
            .onChange(of: layout.pages) { n in if page >= n { page = n - 1 } }
            .onAppear { layout.addNewApps(AndroidShellState.catalog(store: store, host: host)) }
            .onChange(of: store.apps.count) { _ in layout.addNewApps(AndroidShellState.catalog(store: store, host: host)) }
        }
    }

    private func dismissAll() {
        withAnimation(AndroidMotion.spatial) {
            editing = nil
            menuAt = nil
            iconMenu = nil
        }
    }

    private func openInfo(_ app: ShellApp) {
        if case .item(.game(let g)) = app { shell.settingsPath.append(AndroidSettingsRoute.appInfo(g.id)) }
        else { shell.settingsPath.append(AndroidSettingsRoute.apps) }
        shell.launch(.settings)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<layout.pages, id: \.self) { p in
                Capsule().fill(Color.white.opacity(p == page ? 0.95 : 0.5))
                    .frame(width: p == page ? 14 : 6, height: 6)
            }
        }
        .opacity(dotsVisible || editing != nil || dragging != nil ? 1 : 0)
        .animation(AndroidMotion.spatial, value: page)
        .animation(AndroidMotion.fade, value: dotsVisible)
    }

    private func dock(land: Bool, width: CGFloat, apps: [String: ShellApp]) -> some View {
        HStack {
            ForEach(layout.dock, id: \.self) { id in
                if let app = apps[id] {
                    HomeIcon(app: app, showsLabel: false, size: 54, hidden: dragging?.app == id && dragging?.entry == nil,
                             onLongPress: { at in showMenu(HomeDrag(app: id, entry: nil, location: at)) },
                             onDrag: { at in drag(HomeDrag(app: id, entry: nil, location: at)) },
                             onDrop: drop)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, land ? 120 : 18)
        .padding(.bottom, 14)
    }

    private func pageView(_ p: Int, width: CGFloat, land: Bool, apps: [String: ShellApp]) -> some View {
        let col = (width - 24) / 4
        let row: CGFloat = land ? 70 : 96
        let widgets = layout.widgets.filter { $0.page == p }
        return VStack(spacing: 12) {
            ForEach(widgets) { item in
                let size = CGSize(width: col * CGFloat(item.cols) - 8, height: row * CGFloat(item.rows) - 8)
                EditableWidget(item: item, size: size, col: col, row: row, editing: $editing)
                    .frame(maxWidth: .infinity, alignment: item.cols == 4 ? .center : .leading)
                    .padding(.horizontal, 12)
            }
            if p == 0 && !Launcher.jitOn {
                Button { jit.enable() } label: {
                    Label(jit.busy ? (jit.status ?? "Turning JIT on…") : "JIT is off — tap to turn on", systemImage: "bolt.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: land ? columns + 2 : columns), spacing: 18) {
                ForEach(layout.apps(on: p)) { entry in
                    entryView(entry, apps: apps)
                }
            }
            .padding(.horizontal, 12)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { gridFrames[p] = g.frame(in: .named("home")) }
                    .onChange(of: g.frame(in: .named("home"))) { gridFrames[p] = $0 }
            })
            .padding(.bottom, 110)
        }
        .padding(.top, land ? 30 : 46)
    }

    @ViewBuilder
    private func entryView(_ entry: HomeEntry, apps: [String: ShellApp]) -> some View {
        let size: CGFloat = columns >= 5 ? 50 : 58
        if let folder = entry.folder {
            FolderIcon(folder: folder, apps: apps, size: size)
                .opacity(dragging?.entry == entry.id ? 0.25 : 1)
                .onTapGesture { withAnimation(AndroidMotion.bouncy) { openFolder = entry.id } }
                .gesture(holdThenDrag { phase, at in
                    let d = HomeDrag(app: folder.apps.first ?? "", entry: entry.id, location: at)
                    switch phase {
                    case .held: showMenu(d)
                    case .moved: drag(d)
                    case .ended: drop()
                    }
                })
        } else if let id = entry.app, let app = apps[id] {
            HomeIcon(app: app, showsLabel: true, size: size, hidden: dragging?.entry == entry.id,
                     onLongPress: { at in showMenu(HomeDrag(app: id, entry: entry.id, location: at)) },
                     onDrag: { at in drag(HomeDrag(app: id, entry: entry.id, location: at)) },
                     onDrop: drop)
        }
    }

    private func showMenu(_ d: HomeDrag) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(AndroidMotion.bouncy) { iconMenu = IconMenuTarget(app: d.app, entry: d.entry, at: d.location) }
    }

    private func drag(_ d: HomeDrag) {
        if iconMenu != nil { withAnimation(AndroidMotion.fade) { iconMenu = nil } }
        var next = d
        next.overRemove = d.location.y < 110
        dragging = next
    }

    /// Where the app was let go: Remove, the dock, onto another app (a folder), or a place in this page's grid.
    private func drop() {
        guard let d = dragging else { return }
        defer { withAnimation(AndroidMotion.spatial) { dragging = nil } }
        let screen = UIScreen.main.bounds.size
        if d.location.y < 110 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let id = d.entry { layout.remove(entry: id) } else { layout.removeFromDock(d.app) }
            return
        }
        if d.location.y > screen.height - 170 {
            let slot = Int(d.location.x / (screen.width / CGFloat(max(1, layout.dock.count + (d.entry == nil ? 0 : 1)))))
            if let id = d.entry {
                if layout.apps(on: page).first(where: { $0.id == id })?.app != nil { layout.moveToDock(id, index: slot) }
            } else {
                layout.moveInDock(d.app, to: slot)
            }
            return
        }
        guard let grid = gridFrames[page] else { return }
        let entries = layout.apps(on: page)
        let cols = CGFloat(columns)
        let cellW = grid.width / cols
        let rowsUsed = max(1, Int(ceil(Double(entries.count) / Double(columns))))
        let cellH = max(80, grid.height / CGFloat(rowsUsed))
        let local = CGPoint(x: d.location.x - grid.minX, y: d.location.y - grid.minY)
        let colIdx = min(max(0, Int(local.x / cellW)), columns - 1)
        let rowIdx = max(0, Int(local.y / cellH))
        let index = min(rowIdx * columns + colIdx, entries.count)
        // onto another app or folder (near its middle): a folder
        if index < entries.count, entries[index].id != d.entry {
            let centre = CGPoint(x: grid.minX + (CGFloat(colIdx) + 0.5) * cellW, y: grid.minY + (CGFloat(rowIdx) + 0.42) * cellH)
            if hypot(d.location.x - centre.x, d.location.y - centre.y) < cellW * 0.3 {
                if let id = d.entry {
                    layout.merge(id, into: entries[index].id)
                } else {
                    layout.moveFromDock(d.app, to: page, index: entries.count)
                    if let added = layout.apps(on: page).last?.id { layout.merge(added, into: entries[index].id) }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
        }
        if let id = d.entry { layout.move(id, to: page, index: index) } else { layout.moveFromDock(d.app, to: page, index: index) }
    }

    private func pageDrag(width w: CGFloat, height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { v in
                guard editing == nil, dragging == nil, iconMenu == nil else { return }
                if axis == nil {
                    axis = abs(v.translation.width) > abs(v.translation.height) ? .horizontal : .vertical
                    if axis == .horizontal { withAnimation(AndroidMotion.fade) { dotsVisible = true } }
                }
                if axis == .horizontal {
                    var dx = v.translation.width
                    // resistance past the first and last pages
                    if (page == 0 && dx > 0) || (page == layout.pages - 1 && dx < 0) { dx /= 3 }
                    dragX = dx
                } else if v.translation.height < 0 {
                    shell.drawerPeek = min(1, -v.translation.height / (h * 0.55))
                } else if swipeDown {
                    shell.shadePeek = min(1, v.translation.height / 320)
                }
            }
            .onEnded { v in
                defer { axis = nil }
                guard editing == nil, dragging == nil, let axis else { return }
                if axis == .horizontal {
                    let travel = v.predictedEndTranslation.width
                    var next = page
                    if travel < -w / 3 { next = min(layout.pages - 1, page + 1) }
                    if travel > w / 3 { next = max(0, page - 1) }
                    withAnimation(AndroidMotion.spatial) { page = next; dragX = 0 }
                    Task {
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        withAnimation(AndroidMotion.fade) { dotsVisible = false }
                    }
                } else if v.translation.height < 0 {
                    let open = -v.translation.height > 90 || v.predictedEndTranslation.height < -300
                    withAnimation(AndroidMotion.spatial) {
                        if open { shell.drawer = true }
                        shell.drawerPeek = 0
                    }
                } else if swipeDown {
                    let dy = v.translation.height
                    if dy > 70 || v.predictedEndTranslation.height > 260 {
                        shell.openShade(expanded: dy > 330)
                        shell.shadePeek = 0
                    } else {
                        withAnimation(AndroidMotion.spatial) { shell.shadePeek = 0 }
                    }
                }
            }
    }
}

/// An app being moved on the home screen.
struct HomeDrag {
    var app: String
    var entry: UUID?
    var location: CGPoint
    var overRemove = false
}

struct IconMenuTarget: Equatable {
    var app: String
    var entry: UUID?
    var at: CGPoint
}

enum HoldPhase { case held, moved, ended }

/// Hold, then (optionally) drag: what moves an app on Android's home screen. `held` once the hold is long enough, `moved`
/// with every move after it, `ended` when the finger lifts. Locations are in the home screen's space.
func holdThenDrag(_ handler: @escaping (HoldPhase, CGPoint) -> Void) -> some Gesture {
    LongPressGesture(minimumDuration: 0.38)
        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("home")))
        .onChanged { value in
            if case .second(true, let drag?) = value {
                if hypot(drag.translation.width, drag.translation.height) > 8 { handler(.moved, drag.location) }
                else if drag.translation == .zero { handler(.held, drag.location) }
            }
        }
        .onEnded { value in
            if case .second(true, let drag) = value { handler(.ended, drag?.location ?? .zero) }
        }
}

/// An app on the home screen or in the dock: tap to open; hold for its menu; hold and drag to move it.
private struct HomeIcon: View {
    let app: ShellApp
    let showsLabel: Bool
    let size: CGFloat
    let hidden: Bool
    let onLongPress: (CGPoint) -> Void
    let onDrag: (CGPoint) -> Void
    let onDrop: () -> Void
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var held = false

    var body: some View {
        VStack(spacing: 6) {
            AndroidAppIcon(app: app, size: size)
            if showsLabel {
                Text(app.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .lineLimit(1)
                    .frame(maxWidth: size + 18)
            }
        }
        .scaleEffect(held ? 1.08 : 1)
        .opacity(hidden ? 0.25 : 1)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            shell.launchOrigin = TouchTracker.last
            shell.launch(app)
        }
        .gesture(holdThenDrag { phase, at in
            switch phase {
            case .held:
                withAnimation(AndroidMotion.bouncy) { held = true }
                onLongPress(at)
            case .moved:
                held = false
                onDrag(at)
            case .ended:
                withAnimation(AndroidMotion.spatial) { held = false }
                onDrop()
            }
        })
        .onChange(of: hidden) { h in if !h { withAnimation(AndroidMotion.spatial) { held = false } } }
        .onDisappear { held = false }
        .accessibilityLabel(app.title)
        .accessibilityAddTraits(.isButton)
    }
}

/// A folder on the home screen: up to four of its apps, small, on a round plate, its name under it.
private struct FolderIcon: View {
    let folder: HomeEntry.Folder
    let apps: [String: ShellApp]
    let size: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color(uiColor: Material3.surfaceContainerHigh).opacity(0.92))
                LazyVGrid(columns: [GridItem(.fixed(size * 0.3), spacing: 4), GridItem(.fixed(size * 0.3), spacing: 4)], spacing: 4) {
                    ForEach(folder.apps.prefix(4), id: \.self) { id in
                        if let app = apps[id] { AndroidAppIcon(app: app, size: size * 0.3).shadow(radius: 0) }
                    }
                }
            }
            .frame(width: size, height: size)
            Text(folder.name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                .lineLimit(1)
                .frame(maxWidth: size + 18)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// An open folder: its name (tap to rename) over its apps; hold an app to take it out.
private struct FolderPanel: View {
    let id: UUID
    let folder: HomeEntry.Folder
    let apps: [String: ShellApp]
    let close: () -> Void
    @ObservedObject private var layout = HomeLayout.shared
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var name = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { commit(); close() }
            VStack(spacing: 18) {
                TextField("Folder", text: $name)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .submitLabel(.done)
                    .onSubmit(commit)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 18) {
                    ForEach(folder.apps, id: \.self) { appID in
                        if let app = apps[appID] {
                            VStack(spacing: 6) {
                                AndroidAppIcon(app: app, size: 54)
                                Text(app.title).font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                                    .lineLimit(1)
                            }
                            .onTapGesture {
                                commit()
                                close()
                                shell.launchOrigin = TouchTracker.last
                                shell.launch(app)
                            }
                            .onLongPressGesture {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                layout.removeFromFolder(id, app: appID)
                                if folder.apps.count <= 2 { close() }
                            }
                        }
                    }
                }
                Text("Hold an app to take it out of the folder")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 20)
        }
        .onAppear { name = folder.name }
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty, n != folder.name { layout.rename(id, to: n) }
    }
}

/// The menu of an app held on the home screen: App info and Remove.
private struct IconMenu: View {
    enum Action { case info, remove }
    let target: IconMenuTarget
    let app: ShellApp
    let size: CGSize
    let pick: (Action) -> Void
    let dismiss: () -> Void

    var body: some View {
        let menuW: CGFloat = 220, menuH: CGFloat = 2 * 52 + 12
        let x = min(max(target.at.x - menuW / 2, 12), size.width - menuW - 12)
        let above = target.at.y - menuH - 50
        let y = above > 40 ? above : target.at.y + 50
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture(perform: dismiss)
            VStack(spacing: 0) {
                row("info.circle", "App info", .info)
                row("xmark", "Remove", .remove)
            }
            .padding(.vertical, 6)
            .frame(width: menuW)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .offset(x: x, y: y)
        }
    }

    private func row(_ icon: String, _ title: String, _ action: Action) -> some View {
        Button { pick(action) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 22)
                Text(title).font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 18)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(AndroidRippleStyle())
    }
}

/// A widget that, long-pressed, shows its outline and resize dots; dragged onto Remove (the top of the screen), it goes.
private struct EditableWidget: View {
    let item: HomeWidgetItem
    let size: CGSize
    let col: CGFloat
    let row: CGFloat
    @Binding var editing: UUID?
    @ObservedObject private var layout = HomeLayout.shared
    @State private var offset: CGSize = .zero
    @State private var grow: CGSize = .zero

    private var isEditing: Bool { editing == item.id }

    var body: some View {
        let shown = CGSize(width: max(col * 2 - 8, size.width + grow.width), height: max(row - 8, size.height + grow.height))
        HomeWidgetView(item: item, size: shown)
            .frame(width: shown.width, height: shown.height)
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color(uiColor: Material3.tone(.primary, 85)), lineWidth: 3)
                        .padding(-4)
                        .overlay(alignment: .trailing) { handle.offset(x: 11).gesture(resize(cols: true)) }
                        .overlay(alignment: .bottom) { handle.offset(y: 11).gesture(resize(cols: false)) }
                        .overlay(alignment: .leading) { handle.offset(x: -11) }
                        .overlay(alignment: .top) { handle.offset(y: -11) }
                }
            }
            .scaleEffect(isEditing && offset != .zero ? 1.04 : 1)
            .offset(offset)
            .zIndex(isEditing ? 1 : 0)
            .onLongPressGesture(minimumDuration: 0.4) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(AndroidMotion.bouncy) { editing = item.id }
            }
            .simultaneousGesture(isEditing ? DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { offset = $0.translation }
                .onEnded { v in
                    if v.location.y < 110 {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        editing = nil
                        layout.remove(item.id)
                    }
                    withAnimation(AndroidMotion.spatial) { offset = .zero }
                } : nil)
    }

    private var handle: some View {
        Circle().fill(Color(uiColor: Material3.tone(.primary, 85))).frame(width: 18, height: 18)
            .padding(8)
            .contentShape(Circle())
    }

    private func resize(cols: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in grow = cols ? CGSize(width: v.translation.width, height: 0) : CGSize(width: 0, height: v.translation.height) }
            .onEnded { _ in
                let c = item.cols + Int((grow.width / col).rounded())
                let r = item.rows + Int((grow.height / row).rounded())
                withAnimation(AndroidMotion.spatial) { grow = .zero }
                layout.resize(item.id, cols: c, rows: r)
            }
    }
}

// MARK: - menu, picker, settings

private struct HomeMenu: View {
    enum Action { case wallpaper, widgets, apps, home }
    let at: CGPoint
    let size: CGSize
    let pick: (Action) -> Void
    let dismiss: () -> Void

    var body: some View {
        let menuW: CGFloat = 250, menuH: CGFloat = 4 * 56 + 3 * 4
        let x = min(max(at.x - 40, 12), size.width - menuW - 12)
        let y = at.y + menuH + 20 > size.height ? at.y - menuH - 10 : at.y + 10
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture(perform: dismiss)
            VStack(spacing: 4) {
                row("paintpalette", "Wallpaper & style", .wallpaper)
                row("square.grid.2x2", "Widgets", .widgets)
                row("circle.grid.3x3.fill", "App list", .apps)
                row("gearshape", "Home settings", .home)
            }
            .frame(width: menuW)
            .offset(x: x, y: y)
        }
    }

    private func row(_ icon: String, _ title: String, _ action: Action) -> some View {
        Button { pick(action) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 24)
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(AndroidSquashStyle())
    }
}

/// The widget picker: each widget with a preview, added to the page you are on.
private struct WidgetPicker: View {
    let page: Int
    let close: () -> Void
    @ObservedObject private var layout = HomeLayout.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 0) {
                Capsule().fill(Color(uiColor: Material3.onSurfaceVariant).opacity(0.4)).frame(width: 36, height: 4).padding(.top, 10)
                Text("Widgets").font(.system(size: 26, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .padding(.vertical, 16)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(HomeWidgetItem.Kind.allCases) { kind in
                            Button {
                                layout.add(kind, page: page)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                close()
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(kind.app).font(.system(size: 16, weight: .semibold, design: .rounded))
                                        Spacer()
                                        Text("\(kind.size.cols) × \(kind.size.rows)").font(.system(size: 13, design: .rounded))
                                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                    }
                                    HomeWidgetView(item: HomeWidgetItem(kind: kind, page: 0, cols: kind.size.cols, rows: kind.size.rows),
                                                   size: CGSize(width: 300, height: CGFloat(kind.size.rows) * 80))
                                        .frame(height: CGFloat(kind.size.rows) * 80)
                                        .frame(maxWidth: kind.size.cols == 4 ? .infinity : 170)
                                        .background(AndroidWallpaper().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)))
                                        .allowsHitTesting(false)
                                    Text(kind.title).font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                }
                                .foregroundStyle(Color(uiColor: Material3.onSurface))
                                .padding(16)
                                .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                            .buttonStyle(AndroidSquashStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .frame(maxHeight: 620)
            .background(Color(uiColor: Material3.surfaceContainer), in: StackedCorners(top: 28, bottom: 0))
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Home settings: what the gestures on the home screen do.
struct HomeSettings: View {
    static let swipeDownKey = "huskpatch.home.swipeDown"
    static let doubleTapKey = "huskpatch.home.doubleTapSleep"
    let close: () -> Void
    @AppStorage(swipeDownKey) private var swipeDown = true
    @AppStorage(doubleTapKey) private var doubleTap = true
    @AppStorage(HomeLayout.columnsKey) private var columns = 4
    @AppStorage(HomeLayout.rowsKey) private var rows = 5
    @AppStorage(HomeLayout.addNewKey) private var addNew = true
    @State private var confirmReset = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color(uiColor: Material3.onSurfaceVariant).opacity(0.4)).frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity).padding(.top, 10)
                Text("Home settings").font(.system(size: 26, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .padding(.horizontal, 24).padding(.vertical, 16)
                ScrollView {
                    AndroidSettingsGroup(header: "App grid") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Columns").font(.system(size: 15, weight: .medium, design: .rounded))
                            ExpressiveSegmentedButtons(selection: $columns, options: [
                                .init(value: 4, label: "4"), .init(value: 5, label: "5"),
                            ])
                            Text("Rows").font(.system(size: 15, weight: .medium, design: .rounded))
                            ExpressiveSegmentedButtons(selection: $rows, options: [
                                .init(value: 4, label: "4"), .init(value: 5, label: "5"), .init(value: 6, label: "6"),
                            ])
                        }
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: Material3.surfaceContainerHigh))
                    }
                    AndroidSettingsGroup {
                        AndroidSettingsRow(icon: "plus.app", title: "Add new apps to Home screen",
                                           summary: "Apps you install appear on the home screen too") {
                            Toggle("", isOn: $addNew).labelsHidden().toggleStyle(Material3SwitchStyle())
                        }
                        AndroidSettingsRow(icon: "arrow.down.to.line", title: "Swipe down for notifications",
                                           summary: "On the home screen, pull down anywhere to open the shade") {
                            Toggle("", isOn: $swipeDown).labelsHidden().toggleStyle(Material3SwitchStyle())
                        }
                        AndroidSettingsRow(icon: "hand.tap", title: "Double tap to sleep",
                                           summary: "Double-tap an empty part of the home screen to turn the screen off") {
                            Toggle("", isOn: $doubleTap).labelsHidden().toggleStyle(Material3SwitchStyle())
                        }
                        Button { confirmReset = true } label: {
                            AndroidSettingsRow(icon: "arrow.counterclockwise", tint: Material3.error, title: "Reset home screen",
                                               summary: "Put apps, folders, the dock and widgets back as they were")
                        }
                        .buttonStyle(AndroidRippleStyle())
                    }
                    Text("Hold an app to move it, drop it on another app to make a folder, or on Remove. Hold the wallpaper for widgets.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .frame(maxHeight: 640)
            .background(Color(uiColor: Material3.surfaceContainer), in: StackedCorners(top: 28, bottom: 0))
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if confirmReset {
                    ConfirmDialog(title: "Reset the home screen?", confirm: "Reset") {
                        HomeLayout.shared.reset()
                        confirmReset = false
                        close()
                    } cancel: { confirmReset = false }
                }
            }
        }
    }
}
