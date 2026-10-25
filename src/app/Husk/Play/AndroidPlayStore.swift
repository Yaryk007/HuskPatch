// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// HuskPatch: the Play Store app of Android OS mode, laid out as Google Play is on a phone -- Games, Apps, Search and You
/// along the bottom; a search pill and the account at the top; chips for For you, Top charts and Categories; carousels
/// of apps; and an app's page with its big Install button, screenshots and About. Underneath it is the same Play client
/// as the Store tab (PlayStoreManager), so installing goes through the same chooser.
struct AndroidPlayStore: View {
    enum Tab: String, CaseIterable { case games = "Games", apps = "Apps", search = "Search", you = "You" }

    @ObservedObject private var manager = PlayStoreManager.shared
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var tab: Tab = .games
    @State private var showSignIn = false
    @State private var query = ""

    var body: some View {
        SwiftUI.NavigationStack(path: $shell.storePath) {
            Group {
                if !manager.isSignedIn {
                    PlaySignInPage(showSignIn: $showSignIn)
                } else {
                    ZStack {
                        switch tab {
                        case .games: PlayHomePage(kind: .games, openSearch: openSearch)
                        case .apps: PlayHomePage(kind: .apps, openSearch: openSearch)
                        case .search: PlaySearchPage(query: $query)
                        case .you: PlayYouPage(showSignIn: $showSignIn)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { PlayNavigationBar(tab: $tab) }
                }
            }
            .background(Color(uiColor: PlayColors.background).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PlayAPI.PlayApp.self) { PlayAppPage(app: $0) }
        }
        .task(id: manager.isSignedIn) { await manager.loadSections() }
        .sheet(isPresented: $showSignIn) { GoogleSignInSheet() }
        .alert("Google Play", isPresented: Binding(get: { manager.errorMessage != nil }, set: { if !$0 { manager.errorMessage = nil } })) {
            Button("OK", role: .cancel) { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }

    private func openSearch(_ q: String) {
        query = q
        withAnimation(.snappy) { tab = .search }
    }
}

// MARK: - pieces

/// Google Play's own colours, not the wallpaper's: its green for Install and the chosen tab, white (or Google's near
/// black) behind everything.
enum PlayColors {
    static let green = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.37, green: 0.82, blue: 0.62, alpha: 1)
                                                                  : UIColor(red: 0.004, green: 0.53, blue: 0.37, alpha: 1) }
    static let onGreen = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.0, green: 0.22, blue: 0.14, alpha: 1) : .white }
    static let greenContainer = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.06, green: 0.3, blue: 0.21, alpha: 1)
                                                                           : UIColor(red: 0.84, green: 0.95, blue: 0.89, alpha: 1) }
    static let background = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.075, green: 0.075, blue: 0.08, alpha: 1) : .white }
    static let bar = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.12, blue: 0.125, alpha: 1)
                                                               : UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1) }
}

/// An app's icon from Play, in the store's rounded square.
struct PlayIcon: View {
    let url: String?
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Color(uiColor: Material3.surfaceContainerHighest)
                    .overlay(Image(systemName: "app.fill").foregroundStyle(Color(uiColor: Material3.outline)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .stroke(Color(uiColor: Material3.outlineVariant), lineWidth: 0.5))
    }
}

/// Play's account picture: the account's initial in a coloured circle.
private struct PlayAvatar: View {
    @ObservedObject private var manager = PlayStoreManager.shared
    var size: CGFloat = 34

    var body: some View {
        let s = manager.session
        Circle()
            .fill(Color(uiColor: PlayColors.green))
            .frame(width: size, height: size)
            .overlay {
                if s?.isAnonymous == false, let c = s?.email.first {
                    Text(String(c).uppercased())
                        .font(.system(size: size * 0.45, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(uiColor: PlayColors.onGreen))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Color(uiColor: PlayColors.onGreen))
                }
            }
    }
}

/// What Play shows under an app's name: its rating, or where it comes from.
private func ratingLine(_ app: PlayAPI.PlayApp) -> String {
    var parts: [String] = []
    if app.rating > 0 { parts.append(String(format: "%.1f ★", app.rating)) }
    if app.sizeBytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file)) }
    if !app.isFree { parts.append(app.formattedPrice) }
    return parts.joined(separator: "  ·  ")
}

/// Whether an app from Play is already in the library, and so opens rather than installs.
@MainActor private func installed(_ app: PlayAPI.PlayApp) -> TLApp? {
    TranslationLayerStore.shared.apps.first { $0.packageName == app.id }
}

/// The bottom bar: Games, Apps, Search, You, with Material 3's pill behind the chosen one.
private struct PlayNavigationBar: View {
    @Binding var tab: AndroidPlayStore.Tab

    private func icon(_ t: AndroidPlayStore.Tab) -> String {
        switch t {
        case .games: return "gamecontroller"
        case .apps: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .you: return "person.crop.circle"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AndroidPlayStore.Tab.allCases, id: \.self) { t in
                let selected = tab == t
                Button {
                    if tab != t {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) { tab = t }
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Capsule()
                                .fill(Color(uiColor: PlayColors.greenContainer))
                                .frame(width: selected ? 64 : 24, height: 32)
                                .opacity(selected ? 1 : 0)
                            Image(systemName: selected && t != .search ? icon(t) + ".fill" : icon(t))
                                .font(.system(size: 20, weight: selected ? .semibold : .regular))
                                .foregroundStyle(Color(uiColor: selected ? Material3.onSurface : Material3.onSurfaceVariant))
                        }
                        .frame(height: 32)
                        Text(t.rawValue)
                            .font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(Color(uiColor: selected ? Material3.onSurface : Material3.onSurfaceVariant))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.rawValue)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(uiColor: PlayColors.bar))
    }
}

// MARK: - Games and Apps

private struct PlayHomePage: View {
    enum Kind { case games, apps }
    let kind: Kind
    let openSearch: (String) -> Void
    @ObservedObject private var manager = PlayStoreManager.shared
    @State private var chip = "For you"

    private var items: [PlayAPI.PlayApp] { kind == .games ? manager.games : manager.apps }
    private var chips: [String] { ["For you", "Top charts", kind == .games ? "Premium" : "Kids", "Categories"] }

    private var categories: [(String, String)] {
        kind == .games
            ? [("Action", "flame.fill"), ("Adventure", "map.fill"), ("Arcade", "gamecontroller.fill"), ("Board", "checkerboard.rectangle"),
               ("Card", "suit.spade.fill"), ("Casual", "face.smiling.fill"), ("Puzzle", "puzzlepiece.fill"), ("Racing", "car.fill"),
               ("Role Playing", "shield.lefthalf.filled"), ("Simulation", "building.2.fill"), ("Sports", "sportscourt.fill"),
               ("Strategy", "flag.2.crossed.fill")]
            : [("Art & Design", "paintpalette.fill"), ("Books", "book.fill"), ("Communication", "message.fill"),
               ("Education", "graduationcap.fill"), ("Entertainment", "tv.fill"), ("Music & Audio", "music.note"),
               ("Photography", "camera.fill"), ("Productivity", "checklist"), ("Social", "person.2.fill"), ("Tools", "wrench.and.screwdriver.fill"),
               ("Travel", "airplane"), ("Video Players", "play.rectangle.fill")]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    chipRow
                    if items.isEmpty {
                        loading
                    } else {
                        switch chip {
                        case "Top charts": topCharts(items)
                        case "Categories": categoryList
                        case "Premium": premium
                        case "Kids": carouselSection("Teacher approved", Array(items.prefix(8)))
                        default: forYou
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await manager.loadSections(force: true) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { openSearch("") } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium))
                    Text("Search apps & games").font(.system(size: 16, design: .rounded))
                    Spacer()
                    Image(systemName: "mic.fill").font(.system(size: 17))
                }
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
            }
            .buttonStyle(.plain)
            PlayAvatar()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { c in
                    let on = chip == c
                    Button { withAnimation(.snappy) { chip = c } } label: {
                        HStack(spacing: 6) {
                            if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                            Text(c).font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .foregroundStyle(Color(uiColor: on ? Material3.onPrimaryContainer : Material3.onSurfaceVariant))
                        .background(on ? Color(uiColor: PlayColors.greenContainer) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: Material3.outlineVariant), lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(manager.sectionsLoading ? "Loading Google Play…" : "Nothing to show. Pull down to try again.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder private var forYou: some View {
        if let lead = items.first(where: { !$0.screenshotURLs.isEmpty }) ?? items.first {
            NavigationLink(value: lead) { banner(lead) }.buttonStyle(.plain)
        }
        carouselSection(kind == .games ? "Recommended for you" : "Suggested for you", Array(items.prefix(8)))
        carouselSection(kind == .games ? "Popular games" : "Popular apps", Array(items.dropFirst(4)))
        listSection(kind == .games ? "Top free games" : "Top free apps", Array(items.filter(\.isFree).prefix(5)))
    }

    @ViewBuilder private var premium: some View {
        let paid = items.filter { !$0.isFree }
        if paid.isEmpty {
            Text("Premium games you can buy once and play without ads appear here.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .padding(16)
            carouselSection("Free to play", Array(items.prefix(8)))
        } else {
            listSection("Premium", paid)
        }
    }

    /// The feature at the top: the app's first screenshot, its icon and name over the bottom of it.
    private func banner(_ app: PlayAPI.PlayApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: URL(string: app.screenshotURLs.first ?? app.iconURL ?? "")) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                else { Color(uiColor: PlayColors.greenContainer) }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            HStack(spacing: 12) {
                PlayIcon(url: app.iconURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.title).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                    Text(app.developer).font(.system(size: 13, design: .rounded)).lineLimit(1)
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
                Spacer()
                PlayInstallButton(app: app, compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
            Spacer()
            Image(systemName: "arrow.right").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func carouselSection(_ title: String, _ apps: [PlayAPI.PlayApp]) -> some View {
        if !apps.isEmpty {
            sectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(apps) { app in
                        NavigationLink(value: app) {
                            VStack(alignment: .leading, spacing: 6) {
                                PlayIcon(url: app.iconURL, size: 96)
                                Text(app.title).font(.system(size: 13, design: .rounded)).lineLimit(2)
                                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                                    .frame(width: 96, alignment: .leading)
                                if app.rating > 0 {
                                    Text(String(format: "%.1f ★", app.rating)).font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder private func listSection(_ title: String, _ apps: [PlayAPI.PlayApp]) -> some View {
        if !apps.isEmpty {
            sectionHeader(title)
            topCharts(apps)
        }
    }

    private func topCharts(_ apps: [PlayAPI.PlayApp]) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { i, app in
                NavigationLink(value: app) { PlayAppRow(app: app, rank: i + 1) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var categoryList: some View {
        VStack(spacing: 2) {
            ForEach(categories, id: \.0) { name, icon in
                Button { openSearch(name + (kind == .games ? " games" : " apps")) } label: {
                    AndroidSettingsRow(icon: icon, title: name)
                }
                .buttonStyle(AndroidRippleStyle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// An app in a list: its place in the chart, icon, name, developer and rating.
private struct PlayAppRow: View {
    let app: PlayAPI.PlayApp
    var rank: Int?

    var body: some View {
        HStack(spacing: 14) {
            if let rank {
                Text("\(rank)").font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    .frame(width: 22)
            }
            PlayIcon(url: app.iconURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.title).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                Text(app.developer.isEmpty ? app.id : app.developer).font(.system(size: 13, design: .rounded)).lineLimit(1)
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                let line = ratingLine(app)
                if !line.isEmpty {
                    Text(line).font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Install, Open, or the download's progress: Play's filled pill (or a smaller one in a list).
private struct PlayInstallButton: View {
    let app: PlayAPI.PlayApp
    var compact = false
    @ObservedObject private var manager = PlayStoreManager.shared
    @ObservedObject private var store = TranslationLayerStore.shared

    var body: some View {
        let progress = manager.downloadProgress[app.id]
        if progress != nil || manager.installingPackages.contains(app.id) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress ?? 0.05).tint(Color(uiColor: PlayColors.green))
                if !compact {
                    Text("Downloading… \(Int((progress ?? 0) * 100))%").font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
            }
            .frame(width: compact ? 72 : nil)
            .frame(maxWidth: compact ? nil : .infinity)
        } else if let tl = installed(app) {
            Button { AndroidShellState.shared.launch(.item(.game(tl))) } label: { label("Open") }.buttonStyle(.plain)
        } else {
            Button { manager.downloadAndInstall(app: app) } label: { label(app.isFree ? "Install" : app.formattedPrice) }.buttonStyle(.plain)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: compact ? 14 : 15, weight: .medium, design: .rounded))
            .foregroundStyle(Color(uiColor: PlayColors.onGreen))
            .padding(.horizontal, compact ? 18 : 0)
            .frame(maxWidth: compact ? nil : .infinity)
            .frame(height: compact ? 34 : 44)
            .background(Color(uiColor: PlayColors.green), in: Capsule())
    }
}

// MARK: - an app's page

private struct PlayAppPage: View {
    let app: PlayAPI.PlayApp
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var aboutOpen = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { if !shell.storePath.isEmpty { shell.storePath.removeLast() } } label: {
                    Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                Spacer()
                ShareLink(item: URL(string: "https://play.google.com/store/apps/details?id=\(app.id)")!) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        PlayIcon(url: app.iconURL, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.title).font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(uiColor: Material3.onSurface)).lineLimit(2)
                            Text(app.developer).font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(uiColor: PlayColors.green)).lineLimit(1)
                            if !app.isFree {
                                Text(app.formattedPrice).font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                            }
                        }
                    }
                    metrics
                    PlayInstallButton(app: app)
                    if !app.screenshotURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(app.screenshotURLs, id: \.self) { url in
                                    AsyncImage(url: URL(string: url)) { phase in
                                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fit) }
                                        else { Color(uiColor: Material3.surfaceContainerHigh).frame(width: 120) }
                                    }
                                    .frame(height: 210)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                    if !app.summary.isEmpty {
                        Button { withAnimation(.snappy) { aboutOpen.toggle() } } label: {
                            HStack {
                                Text("About this app").font(.system(size: 18, weight: .medium, design: .rounded))
                                Spacer()
                                Image(systemName: aboutOpen ? "chevron.up" : "arrow.right").font(.system(size: 16, weight: .medium))
                            }
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                        }
                        .buttonStyle(.plain)
                        Text(app.summary)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                            .lineLimit(aboutOpen ? nil : 4)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("App info").font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                        info("Package", app.id)
                        if !app.versionString.isEmpty { info("Version", app.versionString) }
                        if !app.downloads.isEmpty { info("Downloads", app.downloads) }
                    }
                    Text("Runs on HuskPatch's translation layer when it has 64-bit (arm64-v8a) code and an engine HuskPatch drives; otherwise in Emulation.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.outline))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: PlayColors.background).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Rating, downloads and size, in columns with thin rules between, as Play draws them.
    private var metrics: some View {
        HStack(spacing: 0) {
            metric(app.rating > 0 ? String(format: "%.1f ★", app.rating) : "—", "Rating")
            divider
            metric(app.downloads.isEmpty ? "—" : app.downloads, "Downloads")
            divider
            metric(app.sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file) : "—", "Size")
        }
        .frame(height: 44)
    }

    private var divider: some View {
        Rectangle().fill(Color(uiColor: Material3.outlineVariant)).frame(width: 1, height: 24)
    }

    private func metric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                .foregroundStyle(Color(uiColor: Material3.onSurface))
            Text(title).font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
        }
        .frame(maxWidth: .infinity)
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            Spacer()
            Text(v).foregroundStyle(Color(uiColor: Material3.onSurface)).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 14, design: .rounded))
    }
}

// MARK: - Search

private struct PlaySearchPage: View {
    @Binding var query: String
    @ObservedObject private var manager = PlayStoreManager.shared
    @State private var searched = ""

    private let suggestions = ["Minecraft", "Geometry Dash", "Subway Surfers", "Racing games", "Puzzle games", "Emulators", "VLC"]

    var body: some View {
        VStack(spacing: 0) {
            Material3SearchBar(text: $query, prompt: "Search apps & games")
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if searched.isEmpty || query.isEmpty {
                        Text("Popular searches").font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                            .padding(.vertical, 8)
                        ForEach(suggestions, id: \.self) { s in
                            Button { query = s } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                    Text(s).font(.system(size: 16, design: .rounded))
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                }
                                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                .frame(height: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else if manager.isSearching {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if manager.searchResults.isEmpty {
                        Text("No results for \u{201C}\(searched)\u{201D}")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        ForEach(manager.searchResults) { app in
                            HStack {
                                NavigationLink(value: app) { PlayAppRow(app: app) }.buttonStyle(.plain)
                                PlayInstallButton(app: app, compact: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .task(id: query) {
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
                searched = query
                if !query.isEmpty { await manager.search(query: query) }
            } catch {}
        }
    }
}

// MARK: - You

private struct PlayYouPage: View {
    @Binding var showSignIn: Bool
    @ObservedObject private var manager = PlayStoreManager.shared
    @ObservedObject private var store = TranslationLayerStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    PlayAvatar(size: 72)
                    Text(manager.session?.isAnonymous == true ? "Guest account" : (manager.session?.email ?? ""))
                        .font(.system(size: 20, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                    if manager.session?.isAnonymous == true {
                        Text("An anonymous account from Aurora Store's dispenser")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    }
                }
                .padding(.vertical, 24)

                AndroidSettingsGroup(header: "Manage apps & device") {
                    let apps = store.apps
                    if apps.isEmpty {
                        AndroidSettingsRow(icon: "square.grid.2x2", title: "No apps yet", summary: "Apps you install appear here")
                    }
                    ForEach(apps) { app in
                        Button { AndroidShellState.shared.launch(.item(.game(app))) } label: {
                            HStack(spacing: 16) {
                                AppIcon(path: app.iconPath, size: 40).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.label).font(.system(size: 16, design: .rounded)).lineLimit(1)
                                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                                    Text(app.packageName ?? app.id).font(.system(size: 12, design: .rounded)).lineLimit(1)
                                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                }
                                Spacer()
                                Text("Open").font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(uiColor: PlayColors.green))
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 64)
                            .background(Color(uiColor: PlayColors.bar))
                        }
                        .buttonStyle(AndroidRippleStyle())
                    }
                }

                AndroidSettingsGroup(header: "Account") {
                    if manager.session?.isAnonymous == true {
                        Button { showSignIn = true } label: {
                            AndroidSettingsRow(icon: "person.badge.key.fill", title: "Sign in with Google",
                                               summary: "Use your own account instead of the guest one")
                        }
                        .buttonStyle(AndroidRippleStyle())
                    }
                    Button { manager.signOut() } label: {
                        AndroidSettingsRow(icon: "rectangle.portrait.and.arrow.right", tint: .systemRed, title: "Sign out")
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - signed out

private struct PlaySignInPage: View {
    @Binding var showSignIn: Bool
    @ObservedObject private var manager = PlayStoreManager.shared

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            GooglePlayLogo().frame(width: 64, height: 70)
            Text("Google Play").font(.system(size: 28, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
            Text("Sign in to find the latest Android apps and games, or browse with a guest account.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            if manager.isLoading {
                ProgressView(manager.statusMessage ?? "Signing in…").padding(.bottom, 40)
            } else {
                VStack(spacing: 10) {
                    Button { showSignIn = true } label: {
                        Text("Sign in").font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(uiColor: PlayColors.onGreen))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(uiColor: PlayColors.green), in: Capsule())
                    }
                    Button { Task { await manager.signInAsGuest() } } label: {
                        Text("Use a guest account").font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(uiColor: PlayColors.greenContainer), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
