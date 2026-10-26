// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Android 16's desktop windowing, as LineageOS 23.2 offers it from an app's menu in recents ("Desktop"): the
/// app leaves full screen for a window over the wallpaper, with a caption bar -- the app's chip (its menu), minimise,
/// maximise and close. The caption moves it, the corner resizes it, and the window touched comes to the front. Home leaves
/// the desktop with its windows kept; opening one of them again (from recents) returns to it.
struct DesktopWindow: Identifiable, Equatable {
    let app: ShellApp
    var frame: CGRect
    var minimized = false
    var id: String { app.id }
}

extension AndroidShellState {
    /// Moves an app into a desktop window (from recents' menu).
    func openInDesktop(_ app: ShellApp) {
        if case .item(.game(let g)) = app {
            // one engine at a time: another app on the translation layer offers to restart into this one
            guard canRun(g) else { return }
        }
        captureSnapshot()
        recentApps.removeAll { $0 == app }
        recentApps.insert(app, at: 0)
        let b = UIScreen.main.bounds
        let size = CGSize(width: min(b.width * 0.86, 520), height: min(b.height * 0.62, 760))
        let cascade = CGFloat(desktop.count % 4) * 26
        let frame = CGRect(x: (b.width - size.width) / 2 + cascade, y: b.height * 0.1 + cascade, width: size.width, height: size.height)
        withAnimation(AndroidMotion.spatial) {
            desktop.removeAll { $0.app == app }
            desktop.append(DesktopWindow(app: app, frame: frame))
            if open == app { open = nil }
            split = nil
            recents = false
            drawer = false
            desktopActive = true
        }
    }

    /// Back to a window of the desktop (opening an app that has one).
    func focusDesktop(_ app: ShellApp) {
        guard let i = desktop.firstIndex(where: { $0.app == app }) else { return }
        withAnimation(AndroidMotion.spatial) {
            var w = desktop.remove(at: i)
            w.minimized = false
            desktop.append(w)
            open = nil
            recents = false
            drawer = false
            desktopActive = true
        }
    }

    func bringToFront(_ id: String) {
        guard let i = desktop.firstIndex(where: { $0.id == id }), i != desktop.count - 1 else { return }
        desktop.append(desktop.remove(at: i))
    }

    func minimizeDesktopWindow(_ id: String) {
        withAnimation(AndroidMotion.spatial) {
            if let i = desktop.firstIndex(where: { $0.id == id }) { desktop[i].minimized = true }
            if desktop.allSatisfy(\.minimized) { desktopActive = false }
        }
    }

    /// Maximise: the app leaves the desktop for full screen.
    func maximizeDesktopWindow(_ id: String) {
        guard let w = desktop.first(where: { $0.id == id }) else { return }
        withAnimation(AndroidMotion.spatial) {
            desktop.removeAll { $0.id == id }
            if desktop.allSatisfy(\.minimized) { desktopActive = false }
        }
        launch(w.app)
    }

    func closeDesktopWindow(_ id: String) {
        guard let w = desktop.first(where: { $0.id == id }) else { return }
        withAnimation(AndroidMotion.spatial) {
            desktop.removeAll { $0.id == id }
            if desktop.allSatisfy(\.minimized) { desktopActive = false }
        }
        forget(w.app)
    }
}

/// The desktop: the wallpaper and the windows on it.
struct AndroidDesktopView: View {
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(shell.desktop.filter { !$0.minimized }) { w in
                    AndroidDesktopWindowView(window: w, area: geo.size)
                        .transition(.scale(scale: 0.86).combined(with: .opacity))
                }
            }
        }
        .clipped()
    }
}

private struct AndroidDesktopWindowView: View {
    let window: DesktopWindow
    let area: CGSize
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var move: CGSize = .zero
    @State private var grow: CGSize = .zero
    @State private var menu = false

    private static let caption: CGFloat = 40
    private static let minSize = CGSize(width: 240, height: 280)

    private var focused: Bool { shell.desktop.last(where: { !$0.minimized })?.id == window.id }

    private var frame: CGRect {
        var f = window.frame
        f.origin.x += move.width
        f.origin.y += move.height
        f.size.width = max(Self.minSize.width, f.width + grow.width)
        f.size.height = max(Self.minSize.height, f.height + grow.height)
        return f
    }

    var body: some View {
        let f = frame
        VStack(spacing: 0) {
            captionBar
            AndroidAppContainer(app: window.app, windowed: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .environment(\.horizontalSizeClass, .compact)
        }
        .frame(width: f.width, height: f.height)
        .background(Color(uiColor: Material3.surface))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color(uiColor: Material3.outlineVariant).opacity(focused ? 0.9 : 0.5), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .shadow(color: .black.opacity(focused ? 0.35 : 0.18), radius: focused ? 22 : 10, y: 8)
        .overlay(alignment: .topLeading) {
            if menu { captionMenu.offset(x: 8, y: Self.caption + 4) }
        }
        .offset(x: f.minX, y: f.minY)
        .simultaneousGesture(TapGesture().onEnded { shell.bringToFront(window.id) })
        .animation(AndroidMotion.spatialFast, value: menu)
    }

    // MARK: caption

    private var captionBar: some View {
        HStack(spacing: 4) {
            Button { withAnimation { menu.toggle() } } label: {
                HStack(spacing: 6) {
                    AndroidAppIcon(app: window.app, size: 20)
                    Text(window.app.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                    Image(systemName: menu ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .padding(.leading, 6).padding(.trailing, 10).frame(height: 28)
                .background(Color(uiColor: Material3.surfaceContainerHighest), in: Capsule())
            }
            .buttonStyle(AndroidSquashStyle())
            Spacer(minLength: 8)
            captionButton("minus", "Minimise") { shell.minimizeDesktopWindow(window.id) }
            captionButton("square", "Maximise") { shell.maximizeDesktopWindow(window.id) }
            captionButton("xmark", "Close") { shell.closeDesktopWindow(window.id) }
        }
        .foregroundStyle(Color(uiColor: Material3.onSurface))
        .padding(.horizontal, 6)
        .frame(height: Self.caption)
        .background(Color(uiColor: focused ? Material3.surfaceContainerHigh : Material3.surfaceContainer))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                if move == .zero { shell.bringToFront(window.id) }
                move = v.translation
            }
            .onEnded { _ in commit() })
        .onTapGesture(count: 2) { shell.maximizeDesktopWindow(window.id) }
    }

    private func captionButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34)
        }
        .buttonStyle(AndroidSquashStyle())
        .accessibilityLabel(label)
    }

    /// The chip's menu: the window's options, as Android 16's app header has them.
    private var captionMenu: some View {
        VStack(spacing: 0) {
            menuItem("arrow.up.left.and.arrow.down.right", "Fullscreen") { shell.maximizeDesktopWindow(window.id) }
            menuItem("viewfinder", "Screenshot") { shell.saveScreenshot(windowSnapshot()) }
            menuItem("info.circle", "App info") {
                shell.minimizeDesktopWindow(window.id)
                if case .item(.game(let g)) = window.app { shell.settingsPath.append(AndroidSettingsRoute.appInfo(g.id)) }
                else { shell.settingsPath.append(AndroidSettingsRoute.apps) }
                shell.launch(.settings)
            }
            menuItem("xmark", "Close") { shell.closeDesktopWindow(window.id) }
        }
        .padding(.vertical, 6)
        .frame(width: 210)
        .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
    }

    private func menuItem(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button { menu = false; action() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 22)
                Text(title).font(.system(size: 15, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(AndroidRippleStyle())
    }

    // MARK: resizing

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if grow == .zero { shell.bringToFront(window.id) }
                    grow = v.translation
                }
                .onEnded { _ in commit() })
            .accessibilityLabel("Resize")
    }

    /// Writes the moved or resized frame back, kept on screen with at least the caption reachable.
    private func commit() {
        var f = frame
        f.size.width = min(f.width, area.width)
        f.size.height = min(f.height, area.height)
        f.origin.x = min(max(f.minX, -f.width + 80), area.width - 80)
        f.origin.y = min(max(f.minY, 0), area.height - Self.caption)
        move = .zero
        grow = .zero
        if let i = shell.desktop.firstIndex(where: { $0.id == window.id }) {
            withAnimation(AndroidMotion.spatialFast) { shell.desktop[i].frame = f }
        }
    }

    private func windowSnapshot() -> UIImage? {
        guard let w = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }
        let rect = frame
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            w.drawHierarchy(in: CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: w.bounds.size), afterScreenUpdates: false)
        }
    }
}
