// SPDX-License-Identifier: GPL-2.0-or-later
import Photos
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import UserNotifications

/// HuskPatch: Android 16's system UI around the apps, from LineageOS 23.2: recents with each app's last picture and its
/// menu (App info, Split screen, Screenshot, Clear), split screen, the splash an app shows while it starts, "Phone is
/// starting…" after the first unlock, and the notification permission an app asks for the first time it opens.

/// Android 16's motion, in SwiftUI springs: the spatial spring moves things (apps opening, panels, cards), the effects
/// curve fades and colours them. Material 3 Expressive's "standard" scheme (stiffness ~700-1400, damping ~0.9).
enum AndroidMotion {
    static let spatial = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let spatialFast = Animation.spring(response: 0.3, dampingFraction: 0.88)
    static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.72)
    static let fade = Animation.easeOut(duration: 0.2)
}

// MARK: - snapshots

extension AndroidShellState {
    /// The window as it is, for the open app's card in recents (taken as it is left).
    func captureSnapshot() {
        guard let open, let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        snapshots[open.id] = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    /// Saves a picture to Photos and says so with a notification.
    func saveScreenshot(_ image: UIImage?) {
        guard let image else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                Task { @MainActor in
                    AndroidShellState.shared.post(ShellNotification(icon: "photo", app: "System UI",
                                                                    title: ok ? "Screenshot saved" : "Couldn't save screenshot",
                                                                    text: ok ? "Saved to Photos" : "Allow HuskPatch to add photos"))
                }
            }
        }
    }

    /// "Phone is starting…": a moment after the first unlock since HuskPatch opened (or a restart), as Android shows it while
    /// its apps finish starting.
    func showStarting() {
        withAnimation(AndroidMotion.fade) { starting = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            withAnimation(.easeOut(duration: 0.35)) { starting = false }
        }
    }

    /// Split screen: `first` on top, `second` under it. Apps on the translation layer cannot share the screen (one engine
    /// draws at a time).
    func startSplit(_ first: ShellApp, _ second: ShellApp) {
        splitPicking = nil
        guard first != second else { return }
        if case .item(.game) = first { notice = "\(first.title) doesn't support split screen."; return }
        if case .item(.game) = second { notice = "\(second.title) doesn't support split screen."; return }
        for app in [first, second] where !recentApps.contains(app) { recentApps.insert(app, at: 0) }
        withAnimation(AndroidMotion.spatial) {
            recents = false
            drawer = false
            open = first
            split = SplitPair(top: first, bottom: second)
        }
    }

    /// The notification permission a system app asks for when it first opens, as Android 13 and later do.
    func askNotificationsIfNeeded(_ app: AndroidSystemApp) {
        guard [.phone, .messages, .contacts, .clock].contains(app),
              UserDefaults.standard.object(forKey: "huskpatch.notifications.\(app.rawValue)") == nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            if open == .system(app) { withAnimation(AndroidMotion.spatial) { notificationPrompt = app } }
        }
    }
}

struct SplitPair: Equatable {
    var top: ShellApp
    var bottom: ShellApp
    var ratio: CGFloat = 0.5
}

// MARK: - recents

/// Android 16's recents: the wallpaper blurred behind a row of app cards -- each its last picture, with a chip for the
/// app's name and menu -- and Screenshot under them. Swiping a card up closes the app; tapping it opens it.
struct Android16Recents: View {
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var menuFor: ShellApp?
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            let cardW = land ? geo.size.width * 0.34 : geo.size.width * 0.7
            let cardH = land ? geo.size.height * 0.72 : geo.size.height * 0.66
            ZStack {
                AndroidWallpaper().blur(radius: 30).overlay(Color.black.opacity(0.28)).ignoresSafeArea()
                    .onTapGesture { menuFor = nil; shell.back() }
                if shell.recentApps.isEmpty {
                    Text("No recent items")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    VStack(spacing: 22) {
                        Spacer(minLength: 0)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 18) {
                                ForEach(shell.recentApps) { app in
                                    A16RecentCard(app: app, width: cardW, height: cardH) { menuFor = app }
                                }
                                Button("Clear all") { shell.clearRecents() }
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                                    .padding(.horizontal, 20).frame(height: 44)
                                    .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                                    .padding(.horizontal, 24)
                            }
                            .padding(.horizontal, (geo.size.width - cardW) / 2)
                        }
                        .frame(height: cardH)
                        Button {
                            if let first = shell.recentApps.first { shell.saveScreenshot(shell.snapshots[first.id]) }
                        } label: {
                            Label("Screenshot", systemImage: "viewfinder")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(uiColor: Material3.onSurface))
                                .padding(.horizontal, 20).frame(height: 44)
                                .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                        }
                        .buttonStyle(AndroidSquashStyle())
                        Spacer(minLength: 0)
                    }
                    .scaleEffect(appeared ? 1 : 1.08)
                    .opacity(appeared ? 1 : 0)
                }

                if shell.splitPicking != nil {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Text("To split the screen, choose another app")
                                .font(.system(size: 15, design: .rounded))
                            Spacer(minLength: 4)
                            Button("Cancel") { withAnimation(AndroidMotion.spatial) { shell.splitPicking = nil } }
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                        .padding(.horizontal, 22).padding(.vertical, 16)
                        .background(Color(uiColor: Material3.primaryContainer), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let app = menuFor {
                    RecentMenu(app: app) { menuFor = nil }
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                }
            }
            .animation(AndroidMotion.spatial, value: menuFor)
        }
        .onAppear { withAnimation(AndroidMotion.spatial) { appeared = true } }
    }
}

private struct A16RecentCard: View {
    let app: ShellApp
    let width: CGFloat
    let height: CGFloat
    let openMenu: () -> Void
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image = shell.snapshots[app.id] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(uiColor: Material3.surface)
                        .overlay(AndroidAppIcon(app: app, size: 84))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Button(action: openMenu) {
                HStack(spacing: 8) {
                    AndroidAppIcon(app: app, size: 26)
                    Text(app.title).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .padding(.leading, 6).padding(.trailing, 12).frame(height: 38)
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
                .frame(maxWidth: width - 24, alignment: .leading)
            }
            .buttonStyle(AndroidSquashStyle())
            .padding(12)
        }
        .frame(width: width, height: height)
        .offset(y: drag)
        .opacity(1 - Double(min(abs(drag) / 320, 0.85)))
        .scaleEffect(1 - min(abs(drag) / 2000, 0.08))
        .contentShape(Rectangle())
        .onTapGesture {
            if let first = shell.splitPicking { shell.startSplit(first, app) }
            else {
                shell.launchOrigin = nil
                shell.launch(app)
            }
        }
        .gesture(DragGesture(minimumDistance: 10)
            .onChanged { drag = min(0, $0.translation.height) }
            .onEnded { v in
                if v.translation.height < -140 || v.predictedEndTranslation.height < -420 {
                    withAnimation(AndroidMotion.spatialFast) { drag = -height }
                    shell.forget(app)
                } else {
                    withAnimation(AndroidMotion.spatial) { drag = 0 }
                }
            })
    }
}

/// The menu under an app's chip in recents.
private struct RecentMenu: View {
    let app: ShellApp
    let close: () -> Void
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.2).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 0) {
                item("info.circle.fill", "App info") {
                    if case .item(.game(let g)) = app { shell.settingsPath.append(AndroidSettingsRoute.appInfo(g.id)) }
                    else { shell.settingsPath.append(AndroidSettingsRoute.apps) }
                    shell.launch(.settings)
                }
                item("rectangle.split.1x2", "Split screen") {
                    if case .item(.game) = app { shell.notice = "\(app.title) doesn't support split screen." }
                    else { withAnimation(AndroidMotion.spatial) { shell.splitPicking = app } }
                }
                item("viewfinder", "Screenshot") { shell.saveScreenshot(shell.snapshots[app.id]) }
                item("xmark", "Clear") { shell.forget(app) }
            }
            .padding(.vertical, 6)
            .frame(width: 250)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .padding(.top, 150)
        }
    }

    private func item(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button { close(); action() } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 24)
                Text(title).font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 20)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(AndroidRippleStyle())
    }
}

// MARK: - split screen

/// Two apps, one over the other, with the divider's handle between them: drag it to share the screen differently, or all
/// the way to an edge to give the screen back to one of them.
struct AndroidSplitView: View {
    let pair: SplitPair
    @ObservedObject private var shell = AndroidShellState.shared
    @State private var dragRatio: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let ratio = dragRatio ?? pair.ratio
            VStack(spacing: 0) {
                AndroidAppContainer(app: pair.top)
                    .frame(height: max(0, h * ratio - 6))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                ZStack {
                    Color.black
                    Capsule().fill(Color.white.opacity(0.9)).frame(width: 52, height: 4)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(DragGesture(coordinateSpace: .named("split"))
                    .onChanged { dragRatio = min(0.92, max(0.08, $0.location.y / max(h, 1))) }
                    .onEnded { v in
                        let r = v.location.y / max(h, 1)
                        withAnimation(AndroidMotion.spatial) {
                            dragRatio = nil
                            if r < 0.15 { shell.split = nil; shell.open = pair.bottom }
                            else if r > 0.85 { shell.split = nil; shell.open = pair.top }
                            else { shell.split?.ratio = min(0.75, max(0.25, r)) }
                        }
                    })
                AndroidAppContainer(app: pair.bottom)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .background(Color.black)
            .coordinateSpace(name: "split")
        }
    }
}

// MARK: - splash, starting, permission

/// The splash an app shows while it starts (Android 12+): its icon, large, on the app's background.
struct AndroidSplash: View {
    let app: ShellApp

    var body: some View {
        ZStack {
            Color(uiColor: Material3.surface)
            AndroidAppIcon(app: app, size: 150)
                .shadow(color: .clear, radius: 0)
        }
        .ignoresSafeArea()
    }
}

/// "Phone is starting…" over the dimmed wallpaper, with a progress line.
struct PhoneStartingView: View {
    @State private var sweep = false

    var body: some View {
        ZStack {
            AndroidWallpaper()
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Phone is starting…")
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color(uiColor: Material3.tone(.primary, 80)))
                        .frame(width: 100)
                        .offset(x: sweep ? 160 : -10)
                }
                .frame(width: 260, height: 3)
                .clipped()
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { sweep = true } }
    }
}

/// "Allow Contacts to send you notifications?" -- the dialog every app shows the first time on Android 13 and later.
/// Allowing it asks iOS too, so the Clock's alarms and timers can ring.
struct NotificationPermissionDialog: View {
    let app: AndroidSystemApp
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(uiColor: Material3.primary))
                (Text("Allow ") + Text(app.title).bold() + Text(" to send you notifications?"))
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                VStack(spacing: 8) {
                    choice("Allow", true)
                    choice("Don't allow", false)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func choice(_ title: String, _ allow: Bool) -> some View {
        Button {
            UserDefaults.standard.set(allow, forKey: "huskpatch.notifications.\(app.rawValue)")
            if allow { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
            withAnimation(AndroidMotion.spatial) { shell.notificationPrompt = nil }
        } label: {
            Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color(uiColor: Material3.tone(.primary, 82)), in: Capsule())
        }
        .buttonStyle(AndroidSquashStyle())
    }
}

/// Where the last touch on the screen began, so an app opens out of the icon that was tapped (and closes back into it).
/// A recogniser on the window that only looks: it fails at once, so every touch goes on to the views as before.
final class TouchTracker: UIGestureRecognizer {
    static var last: CGPoint?

    @MainActor static func install() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: \.isKeyWindow), !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchTracker }) else { return }
        let tracker = TouchTracker(target: nil, action: nil)
        tracker.cancelsTouchesInView = false
        tracker.delaysTouchesBegan = false
        tracker.delaysTouchesEnded = false
        window.addGestureRecognizer(tracker)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        Self.last = touches.first?.location(in: view)
        state = .failed
    }
}
