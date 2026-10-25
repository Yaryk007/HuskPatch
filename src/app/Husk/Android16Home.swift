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

/// The widgets on the home screen, kept in the preferences.
@MainActor
final class HomeLayout: ObservableObject {
    static let shared = HomeLayout()
    private static let key = "huskpatch.home.widgets"

    @Published var widgets: [HomeWidgetItem] {
        didSet { if let d = try? JSONEncoder().encode(widgets) { UserDefaults.standard.set(d, forKey: Self.key) } }
    }

    init() {
        widgets = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([HomeWidgetItem].self, from: $0) }
            ?? [HomeWidgetItem(kind: .clock, page: 0, cols: 4, rows: 2), HomeWidgetItem(kind: .media, page: 1, cols: 4, rows: 1)]
    }

    var pages: Int { max(2, (widgets.map(\.page).max() ?? 0) + 1) }

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
                if let a = media.artwork { Image(uiImage: a).resizable().scaledToFill().blur(radius: 30).opacity(0.45) }
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

    @State private var page = 0
    @State private var dragX: CGFloat = 0
    @State private var axis: Axis?
    @State private var touch: CGPoint = .zero
    @State private var menuAt: CGPoint?
    @State private var picker = false
    @State private var settings = false
    @State private var editing: UUID?
    @State private var dotsVisible = false

    /// The first page's apps: Play Store and what Home shows, most recent first.
    private var firstPageApps: [ShellApp] {
        let all = Launcher.byRecent(Launcher.items(store: store, host: host))
        let lead = all.first { $0.lastUsed != nil } ?? all.first
        let items = lead.map { [$0] + all.filter { $0 != lead } } ?? []
        return [.playStore] + items.prefix(11).map(ShellApp.item)
    }

    private func apps(on page: Int) -> [ShellApp] {
        switch page {
        case 0: return firstPageApps
        case 1: return [.system(.files), .system(.clock), .settings]
        default: return []
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let land = w > h
            ZStack(alignment: .top) {
                // the pages, side by side
                HStack(spacing: 0) {
                    ForEach(0..<layout.pages, id: \.self) { p in
                        pageView(p, width: w, land: land)
                            .frame(width: w)
                    }
                }
                .frame(width: w, alignment: .leading)
                .offset(x: -CGFloat(page) * w + dragX)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 10) {
                    Spacer()
                    pageDots
                    dock(land: land)
                }

                if editing != nil {
                    Text("✕  Remove")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).frame(height: 44)
                        .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 2))
                        .padding(.top, 34)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { touch = $0.startLocation })
            .gesture(pageDrag(width: w, height: h))
            .onLongPressGesture(minimumDuration: 0.45) {
                guard editing == nil else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(AndroidMotion.bouncy) { menuAt = touch }
            }
            .onTapGesture(count: 2) {
                if doubleTap, editing == nil, menuAt == nil { shell.powerOff() }
            }
            .onTapGesture {
                if editing != nil { withAnimation(AndroidMotion.spatial) { editing = nil } }
                if menuAt != nil { withAnimation(AndroidMotion.spatialFast) { menuAt = nil } }
            }
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
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<layout.pages, id: \.self) { p in
                Capsule().fill(Color.white.opacity(p == page ? 0.95 : 0.5))
                    .frame(width: p == page ? 14 : 6, height: 6)
            }
        }
        .opacity(dotsVisible || editing != nil ? 1 : 0)
        .animation(AndroidMotion.spatial, value: page)
        .animation(AndroidMotion.fade, value: dotsVisible)
    }

    private func dock(land: Bool) -> some View {
        HStack {
            ForEach(AndroidSystemApp.dock) { a in
                AndroidAppIconButton(app: .system(a), showsLabel: false, size: 54)
            }
        }
        .padding(.horizontal, land ? 120 : 18)
        .padding(.bottom, 14)
    }

    private func pageView(_ p: Int, width: CGFloat, land: Bool) -> some View {
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: land ? 6 : 4), spacing: 18) {
                ForEach(apps(on: p)) { AndroidAppIconButton(app: $0) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 110)
        }
        .padding(.top, land ? 30 : 46)
    }

    private func pageDrag(width w: CGFloat, height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { v in
                guard editing == nil else { return }
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
                guard editing == nil else { return }
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

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color(uiColor: Material3.onSurfaceVariant).opacity(0.4)).frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity).padding(.top, 10)
                Text("Home settings").font(.system(size: 26, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                    .padding(.horizontal, 24).padding(.vertical, 16)
                AndroidSettingsGroup {
                    AndroidSettingsRow(icon: "arrow.down.to.line", title: "Swipe down for notifications",
                                       summary: "On the home screen, pull down anywhere to open the shade") {
                        Toggle("", isOn: $swipeDown).labelsHidden().toggleStyle(Material3SwitchStyle())
                    }
                    AndroidSettingsRow(icon: "hand.tap", title: "Double tap to sleep",
                                       summary: "Double-tap an empty part of the home screen to turn the screen off") {
                        Toggle("", isOn: $doubleTap).labelsHidden().toggleStyle(Material3SwitchStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Color(uiColor: Material3.surfaceContainer), in: StackedCorners(top: 28, bottom: 0))
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
