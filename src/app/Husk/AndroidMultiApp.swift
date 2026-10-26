// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit
import UserNotifications

/// HuskPatch: Android OS mode's apps beyond one at a time, and the system bars an app in landscape keeps out of its way.
///
/// - Translation layer apps in split screen and desktop windows: the app's one screen (TLUnityScreen's view), scaled to
///   the window when its engine draws at a fixed size, as Husk's own multitasking windows do.
/// - Switching to another Android app: an engine cannot be unloaded, so a second one needs a fresh process. HuskPatch
///   restarts into it -- it remembers the app, leaves, and a notification opens it again straight into that app.
/// - Immersive mode: an app on the translation layer in landscape gets the whole screen, without the status bar or the
///   navigation. A swipe in from the right edge (or up from the bottom, or down from the top) shows them over the app for
///   a few seconds, working as they always do, as Android's transient bars do.

// MARK: - an app on the translation layer in a window

struct AndroidTLWindowContent: View {
    let app: TLApp
    @StateObject private var model = TLUnityModel()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onAppear {
                TranslationLayerStore.shared.markPlayed(app)
                model.start()
            }
            .onDisappear { model.stop() }
    }

    @ViewBuilder private var content: some View {
        if app.report?.webKind != nil {
            WebAppSurface(app: app)
        } else if let apk = app.apks.first {
            let settings = TLAppSettings.load(app.id)
            TLWindowScreen(apk: apk, extraApks: Array(app.apks.dropFirst()), dataDir: app.nativeDataDir,
                           engine: app.screenEngine, portrait: app.drawsPortrait(settings), scale: settings.resolution.scale)
                .overlay {
                    if model.frames == 0 {
                        ProgressView().tint(.white).allowsHitTesting(false)
                    }
                }
        }
    }
}

// MARK: - switching apps

extension AndroidShellState {
    static let pendingLaunchKey = "huskpatch.androidOS.pendingLaunch"

    /// The app on the translation layer that is loaded in this run, if one is.
    var loadedGameTitle: String? {
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }) else { return nil }
        return TranslationLayerStore.shared.apps.first { $0.apks.first == loaded }?.label ?? (loaded as NSString).lastPathComponent
    }

    /// Restart HuskPatch into `g`: remember it, post the notification that opens HuskPatch again, and leave. The new run
    /// opens `g` as soon as JIT is on (resumePendingLaunch).
    func restartInto(_ g: TLApp) {
        UserDefaults.standard.set(g.id, forKey: Self.pendingLaunchKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            let content = UNMutableNotificationContent()
            content.title = "Open \(g.label)"
            content.body = "Tap to open HuskPatch again. \(g.label) starts as it opens."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "huskpatch.relaunch", content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            UNUserNotificationCenter.current().add(request) { _ in
                DispatchQueue.main.async {
                    // to the home screen first, so leaving looks like closing the app rather than a crash
                    UIApplication.shared.perform(NSSelectorFromString("suspend"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(0) }
                }
            }
        }
    }

    /// The app a restart was for: opened once JIT is on (turning JIT on if it is off), within three minutes.
    func resumePendingLaunch() {
        let d = UserDefaults.standard
        guard let id = d.string(forKey: Self.pendingLaunchKey) else { return }
        d.removeObject(forKey: Self.pendingLaunchKey)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["huskpatch.relaunch"])
        Task { @MainActor in
            // the library loads as HuskPatch starts
            var asked = false
            for _ in 0..<360 {
                if let g = TranslationLayerStore.shared.apps.first(where: { $0.id == id }) {
                    if g.report?.webKind != nil || Launcher.jitOn {
                        launch(.item(.game(g)))
                        return
                    }
                    if !asked {
                        asked = true
                        JITCoordinator.shared.enable()
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

// MARK: - immersive mode

extension AndroidShellState {
    /// Shows the status bar and the navigation over an app in immersive mode, for a few seconds after the last touch on them.
    func revealBars() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(AndroidMotion.spatial) { barsRevealed = true }
        keepBars()
    }

    /// Restarts the time the revealed bars stay.
    func keepBars() {
        guard barsRevealed else { return }
        barsToken &+= 1
        let token = barsToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if barsToken == token, !shade { withAnimation(AndroidMotion.spatial) { barsRevealed = false } }
        }
    }

    func hideBars() {
        if barsRevealed { withAnimation(AndroidMotion.spatial) { barsRevealed = false } }
    }
}

/// The edges an app in immersive mode can be swiped in from to show the bars: the right edge (swiped left), and in
/// landscape also the bottom (swiped up) and the top (swiped down). In portrait, a game without a status bar strip has
/// only the top.
struct AndroidImmersiveEdges: View {
    let landscape: Bool
    @ObservedObject private var shell = AndroidShellState.shared

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                edge(width: geo.size.width, height: 22) { $0.height > 20 }
                if landscape {
                    edge(width: 24, height: geo.size.height) { $0.width < -20 }
                        .offset(x: geo.size.width - 24)
                    edge(width: geo.size.width, height: 20) { $0.height < -20 }
                        .offset(y: geo.size.height - 20)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func edge(width: CGFloat, height: CGFloat, reveals: @escaping (CGSize) -> Bool) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onEnded { v in if reveals(v.translation) { shell.revealBars() } })
    }
}

/// The bars over an app in immersive mode, once revealed: the status bar along the top (pulled down, the shade), and the
/// navigation -- the three buttons down the right edge, as Android puts them in landscape, or the gesture handle along
/// the bottom with back from either edge.
struct AndroidTransientBars: View {
    let landscape: Bool
    let navigation: AndroidOS.Navigation
    @ObservedObject private var shell = AndroidShellState.shared
    @AppStorage(AndroidDev.hideStatusBarKey) private var hideStatusBar = false
    @AppStorage(AndroidDev.hideNavBarKey) private var hideNavBar = false

    var body: some View {
        ZStack {
            if !hideStatusBar {
                ZStack {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 44)
                        Spacer()
                    }
                    .ignoresSafeArea()
                    AndroidStatusBar(material: true, transparent: true)
                }
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if landscape, !hideNavBar {
                if navigation == .buttons {
                    HStack(spacing: 0) {
                        Spacer()
                        AndroidNavigationButtons(solid: false, overApp: true, vertical: true, floating: true)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        Spacer()
                        AndroidGestureBar(solid: false, overApp: true, floating: true)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
        }
    }
}
