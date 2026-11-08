import SwiftUI

/// Home screen: a glass dock that is the peeking top of the app drawer, full-screen apps and folder panels,
/// the control center (the status bar), the Lab panel (swipe in from either side edge), and either swipe
/// gestures or three navigation buttons.
///
/// Everything that moves is driven by an `Animator` (a spring that can be grabbed mid-flight), so you can
/// touch and swipe at any moment. Windows live in a `WindowManager`, so:
/// - an icon really turns into its window (and back): the icon steps aside while its window is out;
/// - you can drag a window around freely and let go to send it back to its icon;
/// - you can swipe an app closed the instant it starts opening (or halfway through);
/// - you can tap another app while one is opening or closing - nothing waits for an animation to finish.
struct HomeScreen: View {
    /// false while setup is on screen; the status bar and dock slide in once it is true.
    let revealed: Bool

    private enum PanelSide {
        case left, right
    }

    @EnvironmentObject private var os: OSSettings

    @StateObject private var intro = Animator(0)
    /// 0 -> 1 as the icons come in after unlocking.
    @StateObject private var cascadeAnim = Animator(1)
    /// 0 = closed, 1 = open.
    @StateObject private var drawer = Animator(0)
    @StateObject private var shade = Animator(0)
    /// The Lab panel.
    @StateObject private var panel = Animator(0)
    @StateObject private var recentsAnim = Animator(0)
    @StateObject private var windows = WindowManager()
    @StateObject private var fps = FPSCounter()
    @ObservedObject private var controls = SystemControls.shared
    @ObservedObject private var host = ModemOSHost.shared
    /// What the app drawer's search box holds.
    @State private var drawerQuery = ""

    /// Where each animator is heading, so a plain tap on a gesture zone can resume it.
    @State private var drawerGoal: CGFloat = 0
    @State private var shadeGoal: CGFloat = 0
    @State private var panelGoal: CGFloat = 0
    @State private var panelSide: PanelSide = .left

    /// Value each animator had when the finger touched down (nil = no drag in progress).
    @State private var drawerStart: CGFloat?
    @State private var shadeStart: CGFloat?
    @State private var panelStart: CGFloat?
    @State private var windowStart: CGFloat?
    @State private var dragSession: WindowSession?

    /// Holding the gesture line: the pending timer, whether this touch already started one, and whether it fired.
    @State private var holdWork: DispatchWorkItem?
    @State private var holdArmed = false
    @State private var holdFired = false

    /// Swipe up and pause: where the finger last moved, the pending pause timer, and whether Recents is armed.
    @State private var pausePoint: CGPoint?
    @State private var pauseWork: DispatchWorkItem?
    @State private var recentsArmed = false

    var body: some View {
        GeometryReader { geo in
            let L = HomeLayout(size: geo.size, buttons: os.navMode == .buttons)
            let i = intro.value
            let d = drawer.value
            let s = max(-0.04, shade.value)
            let pv = panel.value
            let rv = recentsAnim.value
            let anyP = clamp01(windows.anyProgress)
            let covered = max(anyP, rv)
            let blurAmount = CGFloat(os.blurStrength) * anyP
            let pushBack = 1 - CGFloat(os.homeZoom) * covered - 0.03 * pv
            let depth = motionDepth(L)
            // The control center, the Lab and Recents frost everything behind them, open apps included.
            let frost = max(s, pv, rv)
            // Inside an app the control center shrinks to just its text.
            let textOnly = clamp01(windows.appProgress * 2)

            ZStack {
                backdrop(L, d, i, wall: depth)
                    .scaleEffect(lerp(pushBack, depth.backScale, d))
                    .offset(depth.backShift * d)
                    .brightness(-os.homeDim * Double(covered))
                    .blur(radius: blurAmount)

                sheetLayers(L, d, i)

                iconsLayer(L, d, i)
                    .scaleEffect(pushBack)
                    .offset(depth.homeShift)
                    .blur(radius: blurAmount)

                drawerLayer(L, d, i)
                    .scaleEffect(depth.backScale)
                    .offset(depth.backShift)

                dockLayer(L, d, i)
                    .scaleEffect(lerp(pushBack, depth.backScale, d))
                    .offset(depth.backShift * d)

                windowsLayer(L)

                frostLayer(frost)

                recentsLayer(L, rv)

                shadeDismiss(s)

                // The control center sits in front of apps and folders too.
                statusBar(L, s, i, textOnly)

                shadeArea(L, s)

                shadeContents(L, s)

                zones(L)

                closeBar(L)

                homeGestureLine(L, d, i)

                navBar(L, i)

                panelLayer(L, pv)
            }
            .frame(width: L.w, height: L.h)
            .coordinateSpace(name: "home")
            .onChange(of: windows.front?.item.hostID) { id in host.frontChanged?(id) }
            .onChange(of: host.openRequest) { id in
                guard let id, let item = (HomeItem.installedApps + HomeItem.hostApps).first(where: { $0.hostID == id }) else { return }
                host.openRequest = nil
                let size = L.iconSize
                windows.launch(
                    item,
                    from: CGRect(x: L.w / 2 - size / 2, y: L.h / 2 - size / 2, width: size, height: size),
                    labelCenter: CGPoint(x: L.w / 2, y: L.h / 2),
                    labelSize: size * 0.2
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            fps.run(os.showFPS)
            Haptics.prepare()
            // With the boot sequence off there is no moment it turns true: the home screen is there from the start.
            if revealed { intro.animate(to: 1, response: 0.8, damping: 1, ease: true) }
        }
        .onChange(of: os.showFPS) { on in fps.run(on) }
        .onReceive(NotificationCenter.default.publisher(for: .modemOSUnlocked)) { _ in
            cascadeAnim.set(0)
            cascadeAnim.animate(to: 1, response: 0.9, damping: os.uiDamping)
        }
        .onChange(of: revealed) { isRevealed in
            if isRevealed {
                intro.animate(to: 1, response: 0.8, damping: 1, ease: true)
            } else {
                // Setup is running again: tidy everything away behind it.
                windows.closeAll()
                moveDrawer(to: 0, velocity: 0)
                moveShade(to: 0, velocity: 0)
                movePanel(to: 0, velocity: 0)
                moveRecents(to: 0)
                intro.animate(to: 0, response: 0.5, damping: 1, ease: true)
            }
        }
    }

    // MARK: - Backdrop: wallpaper and the glass drawer sheet (whose peeking top is the dock)

    /// The dock's bar, which grows into the drawer. It reaches the sides and the bottom of the screen as it opens.
    private func sheetRect(_ L: HomeLayout, _ d: CGFloat, _ i: CGFloat) -> CGRect {
        let top = L.sheetTop(drawer: d)
        let hide = L.ch * 0.2 * (1 - i)
        let bottom = lerp(L.sheetBottom, L.h + 40, clamp01(d))
        return CGRect(
            x: lerp(L.sheetX, 0, clamp01(d)),
            y: top + hide,
            width: lerp(L.sheetWidth, L.w, clamp01(d)),
            height: bottom - top
        )
    }

    private func backdrop(_ L: HomeLayout, _ d: CGFloat, _ i: CGFloat, wall: MotionDepth) -> some View {
        ZStack {
            // Oversized so blurring never shows a dark rim at the screen edges.
            Wallpaper()
                .frame(width: L.w + 160, height: L.h + 160)
                .scaleEffect(wall.wallScale)
                .offset(wall.wallShift)
                .position(x: L.w / 2, y: L.h / 2)

            // Material's dock has no bar: its icons sit on the wallpaper, and the sheet only exists once it is pulled up.
            GlassSurface(
                shape: RoundedRectangle(cornerRadius: L.sheetRadius, style: .continuous),
                rect: sheetRect(L, d, i),
                opacity: 1,
                tint: 2
            )
        }
        .frame(width: L.w, height: L.h)
    }

    // MARK: - App drawer

    private func drawerItems() -> [HomeItem] {
        let query = drawerQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return HomeItem.drawer(showDummy: os.dummyFolder, translate: os.t) }
        return HomeItem.searchable(translate: os.t).filter { os.t($0.name).localizedCaseInsensitiveContains(query) }
    }

    /// Every app, in a list that scrolls: as many as are installed.
    @ViewBuilder
    private func drawerLayer(_ L: HomeLayout, _ d: CGFloat, _ i: CGFloat) -> some View {
        if d > 0.02 {
            let rect = sheetRect(L, d, i)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
            let fade = Double(clamp01((d - 0.25) * 2.5))
            let height = min(rect.height, L.h - rect.minY)

            VStack(spacing: 0) {
                // The dock stays at the top of the open sheet, and drags it; the list scrolls.
                Color.clear
                    .frame(height: L.dockPeek)
                    .contentShape(Rectangle())
                    .simultaneousGesture(drawerGesture(L, tap: .resume))

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 18 * L.u) {
                        ForEach(Array(drawerItems().enumerated()), id: \.element.id) { pair in
                            // Each row arrives a moment after the one above as the drawer opens.
                            let arrive = clamp01((d - 0.55) * 3.2 - CGFloat(min(pair.offset, 12)) * 0.06)
                            drawerCell(pair.element, L)
                                .scaleEffect(lerp(0.86, 1, arrive))
                                .offset(y: 26 * L.u * (1 - arrive))
                                .opacity(Double(arrive))
                        }
                    }
                    .padding(.horizontal, 12 * L.u)
                    .padding(.top, 8 * L.u)
                    .padding(.bottom, L.navHeight + 60 * L.u)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: DrawerPullKey.self, value: geo.frame(in: .named("drawer")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "drawer")
                .onPreferenceChange(DrawerPullKey.self) { y in
                    // Pulled down past the top of the list: the sheet goes away, as Android's does.
                    if y > 90 * L.u, drawerGoal > 0.5, windows.front == nil {
                        moveDrawer(to: 0, velocity: 0)
                    }
                }
            }
            .frame(width: rect.width, height: height)
            .position(x: rect.midX, y: rect.minY + height / 2)
            .opacity(fade)
            .allowsHitTesting(d > 0.9)
        }
    }

    private func drawerCell(_ item: HomeItem, _ L: HomeLayout) -> some View {
        let size = 56 * L.u
        let session = windows.session(item.id)
        let visible = session == nil || !WindowMotion.morphs(session!.style, os)

        return VStack(spacing: 6 * L.u) {
            GeometryReader { geo in
                let rect = geo.frame(in: .named("home"))

                Button {
                    windows.launch(
                        item,
                        from: rect,
                        labelCenter: CGPoint(x: rect.midX, y: rect.maxY + L.labelSize),
                        labelSize: L.labelSize
                    )
                } label: {
                    iconShape(item, size: size, radius: L.iconRadius(os.iconRoundness) * size / L.iconSize)
                }
                .buttonStyle(PressScaleStyle())
                .scaleEffect(iconGrowth)
            }
            .frame(width: size, height: size)
            .opacity(visible ? 1 : 0)

            Text(os.t(item.name))
                .font(.system(size: L.labelSize, weight: .medium))
                .foregroundColor(os.palette.onSurface)
                .lineLimit(1)
                .opacity(visible ? 1 : 0)
        }
    }

    // MARK: - Icons (drawer and dock)

    private func iconsLayer(_ L: HomeLayout, _ d: CGFloat, _ i: CGFloat) -> some View {
        let dockFade = clamp01(1 - d * 3) * clamp01((i - 0.3) * 2)
        let hide = L.ch * 0.2 * (1 - i)
        let homeList = HomeItem.homeWithInstalled
        let homeItems = os.homeApps ? Array(homeList.enumerated()) : []
        let homeRows = (homeList.count + 3) / 4

        return ZStack {
            if os.clockWidget {
                clockWidget(L)
                    .offset(y: -L.ch * 0.1 * (1 - i))
                    .opacity(Double(dockFade))
                    .allowsHitTesting(false)
            }
            ForEach(homeItems, id: \.element.id) { pair in
                iconView(
                    pair.element,
                    L.homeIcon(pair.offset, rows: homeRows).offsetBy(dx: 0, dy: hide),
                    fade: dockFade,
                    label: true,
                    L
                )
            }
        }
        .frame(width: L.w, height: L.h)
    }

    /// The dock: it rides the top of the sheet, closed or open.
    private func dockLayer(_ L: HomeLayout, _ d: CGFloat, _ i: CGFloat) -> some View {
        let hide = L.ch * 0.2 * (1 - i)
        return ZStack {
            ForEach(Array(HomeItem.dock.enumerated()), id: \.element.id) { pair in
                iconView(
                    pair.element,
                    L.dockIcon(pair.offset, drawer: d).offsetBy(dx: 0, dy: hide),
                    fade: clamp01((i - 0.3) * 2),
                    label: false,
                    L
                )
            }
        }
        .frame(width: L.w, height: L.h)
    }

    @ViewBuilder
    private func iconShape(_ item: HomeItem, size: CGFloat, radius: CGFloat) -> some View {
        switch item.kind {
        case .app:
            AppIconView(item: item, size: size, radius: radius)
        case .folder:
            FolderGlyph(folderID: item.id, cornerRadius: radius, showBackground: true)
                .frame(width: size, height: size)
        }
    }

    private func iconView(_ item: HomeItem, _ rect: CGRect, fade: CGFloat, label: Bool, _ L: HomeLayout) -> some View {
        let tappable = fade > 0.3 && canTap(item, rect: rect, L)
        // While its window is out, the icon has turned into the window, so it steps aside.
        let session = windows.session(item.id)
        let visible = session == nil || (item.kind == .app && !WindowMotion.morphs(session!.style, os))
        let showLabel = label && os.showLabels
        let labelY = rect.maxY + L.labelSize * 1.15
        let radius = L.iconRadius(os.iconRoundness) * rect.width / L.iconSize

        let arrive = cascade(rect, L)
        return ZStack {
            iconShape(item, size: rect.width, radius: radius)
                .scaleEffect(iconGrowth * lerp(0.86, 1, arrive))
                .offset(y: 26 * L.u * (1 - arrive))
                .opacity(Double(arrive))
                .opacity(visible ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    windows.launch(
                        item,
                        from: rect,
                        labelCenter: showLabel ? CGPoint(x: rect.midX, y: labelY) : CGPoint(x: rect.midX, y: rect.midY),
                        labelSize: showLabel ? L.labelSize : rect.width * 0.2
                    )
                }
                .gesture(iconDrawerGesture(L))
                .allowsHitTesting(tappable)
                .position(x: rect.midX, y: rect.midY)

            if showLabel {
                // Over the wallpaper: white whatever the theme, with a shadow to hold on a bright one.
                Text(os.t(item.name))
                    .font(.system(size: L.labelSize, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .lineLimit(1)
                    .frame(width: rect.width * 1.3)
                    .position(x: rect.midX, y: labelY)
                    .offset(y: 26 * L.u * (1 - arrive))
                    .opacity(visible ? Double(arrive) : 0)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: L.w, height: L.h)
        .opacity(Double(fade))
    }

    /// The app in front, or the one on its way back to its icon: what everything else reacts to.
    private var movingWindow: WindowSession? {
        windows.sessions.filter { $0.item.kind == .app }.max { $0.t.value < $1.t.value }
    }

    /// Each icon grows where it sits, in step with the app: unchanged while it starts, at its largest once it is open.
    /// Tied to the window's own progress, so a finger dragging it moves them too.
    private var iconGrowth: CGFloat {
        guard os.rippleEnabled, let window = movingWindow else { return 1 }
        let p = clamp01(window.t.value)
        return 1 + 0.3 * follow(p)
    }

    /// While a finger holds the window the background tracks it one to one; on its own it eases in and out.
    /// (A smoothstep is flat near open, so a swipe barely moved the background until the window let go.)
    private func follow(_ p: CGFloat) -> CGFloat {
        dragSession != nil ? p : p * p * (3 - 2 * p)
    }

    /// Icons come in one after another after the lock screen, from the top left down, as in the prototype.
    private func cascade(_ rect: CGRect, _ L: HomeLayout) -> CGFloat {
        let lag = rect.minY / L.h * 0.45 + rect.minX / L.w * 0.12
        return clamp01((cascadeAnim.value * 1.6 - lag) / 0.55)
    }

    /// How the layers behind sit at this moment. Each moves by its own amount, which is what gives the parallax:
    /// the icons most, the wallpaper a third of that, the drawer and folders in between.
    struct MotionDepth {
        var homeShift = CGSize.zero
        var wallShift = CGSize.zero
        var wallScale: CGFloat = 1
        var backShift = CGSize.zero
        var backScale: CGFloat = 1
    }

    private func motionDepth(_ L: HomeLayout) -> MotionDepth {
        guard os.parallax else { return MotionDepth() }
        let s = clamp01(shade.value), pv = clamp01(panel.value), rv = clamp01(recentsAnim.value), d = clamp01(drawer.value)
        let window = movingWindow
        let p = window.map { clamp01($0.t.value) } ?? 0
        let eased = follow(p)
        let ox = window.map { $0.origin.midX - L.w / 2 } ?? 0
        let oy = window.map { $0.origin.midY - L.h / 2 } ?? 0
        let side: CGFloat = panelSide == .left ? 1 : -1
        let home = CGSize(width: -ox * 0.18 * eased + side * 46 * L.u * pv,
                          height: -oy * 0.18 * eased - 70 * L.u * d + 40 * L.u * s)
        let behind = max(eased, rv, s * 0.7, pv * 0.7)
        return MotionDepth(
            homeShift: home,
            wallShift: CGSize(width: home.width / 3, height: home.height / 3),
            wallScale: 1 + 0.3 * max(behind, d * 0.8),
            backShift: CGSize(width: -ox * 0.1 * eased + side * 26 * L.u * pv, height: -oy * 0.1 * eased + 24 * L.u * s),
            backScale: 1 - 0.1 * behind
        )
    }

    /// An icon can be tapped unless something else has the screen. A window that is still opening or
    /// closing only blocks the part of the screen it actually covers, so you never have to wait.
    private func canTap(_ item: HomeItem, rect: CGRect, _ L: HomeLayout) -> Bool {
        guard shade.value < 0.02, panel.value < 0.02, recentsAnim.value < 0.02 else { return false }
        guard drawerStart == nil, shadeStart == nil else { return false }
        if let front = windows.front, front.t.value > 0.98 { return false }

        let point = CGPoint(x: rect.midX, y: rect.midY)
        for session in windows.sessions where session.item.id != item.id {
            // A window that has only just started opening does not stop you from tapping another icon.
            if session.goal == 1 && session.t.value < 0.35 { continue }
            if windowRect(session, L).contains(point) { return false }
        }
        return true
    }

    // MARK: - Control center: the status bar, which grows into the control panel

    /// Android's status bar: the time on the left, the phone's state on the right. It is the top of the quick settings, which
    /// grow out of it. An app running full screen has none until the shade comes down.
    private func statusBar(_ L: HomeLayout, _ s: CGFloat, _ i: CGFloat, _ textOnly: CGFloat) -> some View {
        let hidden = -(L.barTop + L.barHeight + L.ch * 0.02) * (1 - i)
        let textOffset = L.statusCenterY - L.statusSize * 0.6
        let immersive = windows.front.map { ModemOSHost.shared.app($0.item.hostID)?.fullScreen == true } ?? false
        let textFade = immersive ? Double(clamp01(s * 4)) : 1
        // In an app the bar's text sits on the app's page; on the home screen, on the wallpaper.
        let ink: Color = textOnly > 0.5 ? os.palette.onSurface : .white

        return ZStack(alignment: .topLeading) {
            ClockText(size: L.statusSize)
                .fixedSize()
                .offset(x: 26 * L.u, y: textOffset)
                .opacity(textFade)

            if os.showFPS {
                Text("\(fps.fps) FPS")
                    .font(.system(size: L.statusSize * 0.8, weight: .bold, design: .monospaced))
                    .foregroundColor(fps.fps >= 55 ? .green : .orange)
                    .fixedSize()
                    .frame(width: L.w)
                    .offset(y: textOffset + L.statusSize * 2)
            }

            HStack(spacing: L.statusSize * 0.42) {
                Image(systemName: "cellularbars")
                if os.showBattery {
                    BatteryText(size: L.statusSize)
                        .fixedSize()
                } else {
                    Image(systemName: "battery.75")
                }
            }
            .font(.system(size: L.statusSize * 0.95, weight: .semibold))
            .padding(.trailing, 26 * L.u)
            .frame(width: L.w, alignment: .trailing)
            .offset(y: textOffset)
            .opacity(textFade)
        }
        .foregroundColor(ink)
        .frame(width: L.w, height: L.h, alignment: .topLeading)
        .offset(y: hidden)
        .allowsHitTesting(false)
    }

    private var brightnessBinding: Binding<Double> {
        Binding(get: { Double(controls.brightness) }, set: { controls.setBrightness(CGFloat($0)) })
    }

    private var volumeBinding: Binding<Double> {
        Binding(get: { Double(controls.volume) }, set: { controls.setVolume(CGFloat($0)) })
    }

    /// Control Center: a card that comes down from under the status bar with the two sliders and four tiles.
    @ViewBuilder
    private func shadeContents(_ L: HomeLayout, _ s: CGFloat) -> some View {
        if s > 0.01 {
            let columns = [GridItem(.flexible(), spacing: 10 * L.u), GridItem(.flexible())]
            let card = RoundedRectangle(cornerRadius: 34 * L.u, style: .continuous)

            VStack(spacing: 10 * L.u) {
                shadeSlider("Brightness", brightnessBinding, L)
                shadeSlider("Volume", volumeBinding, L)
                LazyVGrid(columns: columns, spacing: 10 * L.u) {
                    quickTile("flashlight.on.fill", "Flashlight", on: Torch.isOn, L) {
                        Torch.toggle()
                        controls.objectWillChange.send()
                    }
                    quickTile("moon.fill", "Dark mode", on: os.theme == .dark, L) {
                        os.theme = os.theme == .dark ? .light : .dark
                    }
                    quickTile("waveform.path", "Vibration", on: os.haptics, L) {
                        os.haptics.toggle()
                    }
                    quickTile("flask.fill", "Lab", on: false, L) {
                        moveShade(to: 0, velocity: 0)
                        panelSide = .left
                        movePanel(to: 1, velocity: 0)
                    }
                }
            }
            .padding(14 * L.u)
            .frame(width: L.w - 20 * L.u)
            .glass(card, tint: 1)
            .offset(x: 10 * L.u, y: 46 * L.u + (s - 1) * 420 * L.u)
            .frame(width: L.w, height: L.h, alignment: .topLeading)
            .allowsHitTesting(s > 0.6)
        }
    }

    private func shadeSlider(_ title: String, _ value: Binding<Double>, _ L: HomeLayout) -> some View {
        HStack(spacing: 12 * L.u) {
            Text(os.t(title)).font(.system(size: 13, weight: .medium)).foregroundColor(os.palette.onSurface)
            Slider(value: value, in: 0...1).tint(os.palette.primary)
        }
        .padding(.horizontal, 16 * L.u)
        .frame(height: 56 * L.u)
        .background(RoundedRectangle(cornerRadius: 28 * L.u, style: .continuous).fill(tileFill))
    }

    private var tileFill: Color {
        os.design == .expressive ? os.palette.surfaceHigh : Color.white.opacity(0.16)
    }

    /// A quick settings tile: a pill with its icon and name, filled when on.
    private func quickTile(_ symbol: String, _ title: String, on: Bool, _ L: HomeLayout, action: @escaping () -> Void) -> some View {
        let p = os.palette
        return Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10 * L.u) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(os.t(title))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundColor(on ? p.onPrimary : p.onSurface)
            .padding(.horizontal, 14 * L.u)
            .frame(height: 68 * L.u)
            .background(
                RoundedRectangle(cornerRadius: (on ? 18 : 34) * L.u, style: .continuous)
                    .fill(on ? p.primary : tileFill)
            )
            .animation(.spring(response: 0.38, dampingFraction: os.uiDamping), value: on)
        }
        .buttonStyle(PressScaleStyle(pressedScale: 0.96))
    }

    @ViewBuilder
    private func shadeDismiss(_ s: CGFloat) -> some View {
        if s > 0.3 {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { moveShade(to: 0, velocity: 0) }
        }
    }

    /// Lets you drag the open control panel back up.
    @ViewBuilder
    private func shadeArea(_ L: HomeLayout, _ s: CGFloat) -> some View {
        if s > 0.01 {
            Color.clear
                .frame(width: L.w, height: 46 * L.u)
                .contentShape(Rectangle())
                .gesture(shadeGesture(L))
                .frame(width: L.w, height: L.h, alignment: .top)
        }
    }

    // MARK: - Windows (app = full screen, folder = panel)

    /// Where a window would be at progress `p` on its way from icon to open, for its animation style.
    private func pathRect(_ session: WindowSession, _ L: HomeLayout, _ p: CGFloat) -> CGRect {
        if session.item.kind == .folder {
            return lerp(session.origin, L.folderRect, max(p, -0.04))
        }
        let full = CGRect(x: 0, y: 0, width: L.w, height: L.h)
        return WindowMotion.rect(session.style, os, origin: session.origin, full: full, p: p)
    }

    /// Where a window is right now: on its path from icon to open, unless a finger is holding it.
    private func windowRect(_ session: WindowSession, _ L: HomeLayout) -> CGRect {
        let morph = pathRect(session, L, session.t.value)
        let k = session.k.value
        if k >= 0.999 { return morph }

        let center = CGPoint(
            x: session.heldCenter.x + session.heldOffset.width,
            y: session.heldCenter.y + session.heldOffset.height
        )
        let held = CGRect(
            x: center.x - morph.width / 2,
            y: center.y - morph.height / 2,
            width: morph.width,
            height: morph.height
        )
        return lerp(held, morph, k)
    }

    private func windowsLayer(_ L: HomeLayout) -> some View {
        ZStack {
            // Behind the windows: drag a window from anywhere on it while it is still moving, drag an open
            // folder from anywhere, and tap outside a folder to close it.
            if let front = windows.front, front.t.value > 0.35 {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(windowGesture(L, minimumDistance: 6))
                    .onTapGesture {
                        if front.item.kind == .folder && front.t.value > 0.9 {
                            windows.close(front, velocity: 0)
                        }
                    }
            }

            // Running apps too: hidden, but their views stay alive, so an app comes back exactly as you left it.
            ForEach(windows.all) { session in
                windowView(session, L)
            }
        }
        .frame(width: L.w, height: L.h)
    }

    @ViewBuilder
    private func windowView(_ session: WindowSession, _ L: HomeLayout) -> some View {
        switch session.item.kind {
        case .app:
            appWindow(session, L)
        case .folder:
            // A folder is in the background too once one of its apps opens over it.
            let depth = windows.front?.parentID == session.item.id ? motionDepth(L) : MotionDepth()
            folderWindow(session, L)
                .scaleEffect(depth.backScale)
                .offset(depth.backShift)
        }
    }

    private func appInsets(_ L: HomeLayout) -> EdgeInsets {
        let safe = SafeArea.insets
        let top = max(safe.top, L.barTop + L.barHeight) + 8 * L.u
        let bottom = os.navMode == .buttons ? L.navHeight + 4 * L.u : max(safe.bottom, 16 * L.u) + 12 * L.u
        return EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
    }

    /// The app, scaled to fill its window. With the icon styles the icon grows into the app; the Home Up
    /// styles also turn see-through mid-flight, wash toward the icon's colour as the window shrinks,
    /// squash with speed and leave ghost copies behind.
    private func appWindow(_ session: WindowSession, _ L: HomeLayout) -> some View {
        let p = session.t.value
        let rect = windowRect(session, L)
        let style = session.style
        let look = WindowMotion.look(style, os)
        let iconRadius = L.iconRadius(os.iconRoundness) * session.origin.width / L.iconSize
        let radius = WindowMotion.radius(style, os, iconRadius: iconRadius, displayRadius: L.displayRadius, p: p)
        let opacity = WindowMotion.opacity(style, os, p: p)
        let iconAlpha = WindowMotion.iconAlpha(style, os, p: p)
        let tint = WindowMotion.tint(look, p: p)
        let glow = WindowMotion.glow(look, p: p)
        let glyphAlpha = look.tint > 0 ? Double(clamp01(1 - p * 2.2)) : 0
        let scale = max(0.01, max(rect.width / L.w, rect.height / L.h))
        let active = session.goal == 1 && p > 0.97 && dragSession !== session
        session.sample(rect, p: p)
        let squash = WindowMotion.squash(look, velocity: session.speed)

        return ZStack {
            ghosts(session, look, rect: rect, radius: radius, L)

            windowBody(session, L, rect: rect, scale: scale, active: active, iconAlpha: iconAlpha, tint: tint, glow: glow, glyphAlpha: glyphAlpha)
                .frame(width: max(1, rect.width), height: max(1, rect.height))
                .clipShape(RoundedRectangle(cornerRadius: max(0, radius), style: .continuous))
                .scaleEffect(x: squash.width, y: squash.height)
                .rotationEffect(.degrees(WindowMotion.rotation(style, os, p: p)))
                .opacity(session.parked ? 0 : opacity)
                .position(x: rect.midX, y: rect.midY)
        }
        .frame(width: L.w, height: L.h)
        .allowsHitTesting(active)
    }

    /// Home Up ghost trail: faded copies of the window where it was a few frames ago.
    @ViewBuilder
    private func ghosts(_ session: WindowSession, _ look: WindowMotion.Look, rect: CGRect, radius: CGFloat, _ L: HomeLayout) -> some View {
        let trail = session.trail
        if look.trail > 0 && trail.count > 2 {
            ForEach(1...look.trail, id: \.self) { index in
                let back = trail.count - 1 - index * 2
                if back >= 0 {
                    let ghost = trail[back]
                    let moved = hypot(ghost.midX - rect.midX, ghost.midY - rect.midY) + abs(ghost.width - rect.width) * 0.5
                    let strength = Double(clamp01(moved / 24)) * 0.32 * Double(look.trail + 1 - index) / Double(look.trail)
                    if strength > 0.01 {
                        RoundedRectangle(cornerRadius: max(0, radius), style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.85), session.item.color.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(1, ghost.width), height: max(1, ghost.height))
                            .opacity(strength)
                            .position(x: ghost.midX, y: ghost.midY)
                    }
                }
            }
        }
    }

    private func windowBody(
        _ session: WindowSession,
        _ L: HomeLayout,
        rect: CGRect,
        scale: CGFloat,
        active: Bool,
        iconAlpha: Double,
        tint: Double,
        glow: Double,
        glyphAlpha: Double
    ) -> some View {
        ZStack {
            if !session.parked { OSAppBackground() }

            // A new look rebuilds an app's views, but never an app running full screen: that would restart its engine.
            AppContentView(item: session.item, insets: appInsets(L), active: active)
                .id(ModemOSHost.shared.app(session.item.hostID)?.fullScreen == true ? "app" : os.lookID)
                .frame(width: L.w, height: L.h)
                .scaleEffect(scale)
                .frame(width: max(1, rect.width), height: max(1, rect.height))

            // Home Up: the window washes toward its icon's colour as it shrinks, with a soft glow mid-flight.
            if tint > 0.005 {
                session.item.color.opacity(tint)
                    .allowsHitTesting(false)
            }
            if glow > 0.005 {
                Color.white.opacity(glow)
                    .allowsHitTesting(false)
            }
            if glyphAlpha > 0.005 {
                Image(systemName: session.item.symbol)
                    .font(.system(size: session.origin.width * 0.44, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .opacity(glyphAlpha)
                    .allowsHitTesting(false)
            }

            if iconAlpha > 0 {
                ZStack {
                    LinearGradient(
                        colors: [session.item.color.opacity(0.78), session.item.color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .background(Color.white)
                    Image(systemName: session.item.symbol)
                        .font(.system(size: session.origin.width * 0.44, weight: .semibold))
                        .foregroundColor(.white)
                }
                .opacity(iconAlpha)
                .allowsHitTesting(false)
            }
        }
    }

    /// The folder icon grows into the glass panel, and its four little icons grow into the apps inside.
    private func folderWindow(_ session: WindowSession, _ L: HomeLayout) -> some View {
        let p = session.t.value
        let rect = windowRect(session, L)
        let morph = lerp(session.origin, L.folderRect, p)
        let delta = CGSize(width: rect.midX - morph.midX, height: rect.midY - morph.midY)
        let iconRadius = L.iconRadius(os.iconRoundness) * session.origin.width / L.iconSize
        let radius = max(0, lerp(iconRadius, L.w * 0.09, p))
        let titleFont = L.w * 0.096
        let titleScale = lerp(session.labelSize / titleFont, 1, p)
        let titlePosition = lerp(session.labelCenter, L.folderTitle, p)

        return ZStack {
            Glass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .frame(width: max(1, rect.width), height: max(1, rect.height))
                .contentShape(Rectangle())
                .gesture(windowGesture(L, minimumDistance: 6))
                .onTapGesture {}
                .position(x: rect.midX, y: rect.midY)

            // The folder title grows out of the icon's label.
            Text(os.t(session.item.name))
                .font(.system(size: titleFont, weight: .bold))
                .foregroundColor(.primary)
                .scaleEffect(max(0.01, titleScale))
                .opacity(Double(clamp01((p - 0.1) * 2)))
                .position(x: titlePosition.x + delta.width, y: titlePosition.y + delta.height)
                .allowsHitTesting(false)

            ForEach(0..<HomeItem.children(of: session.item.id).count, id: \.self) { index in
                folderChild(index, session, L, p, delta)
            }
        }
        .frame(width: L.w, height: L.h)
        // A closing folder lets touches through, so the next app can be opened straight away.
        .allowsHitTesting(session.goal == 1)
    }

    private func folderChild(
        _ index: Int,
        _ session: WindowSession,
        _ L: HomeLayout,
        _ p: CGFloat,
        _ delta: CGSize
    ) -> some View {
        let item = HomeItem.children(of: session.item.id)[index]
        // The first four grow out of the little icons on the folder; the rest grow out of its middle.
        let from = index < 4
            ? L.miniRect(index, in: session.origin)
            : CGRect(x: session.origin.midX - 4, y: session.origin.midY - 4, width: 8, height: 8)
        let extraFade = (index < 4 ? 1 : Double(clamp01((p - 0.2) * 2))) * Double(clamp01((p - 0.3) * 2.6 - CGFloat(index) * 0.08 + 0.3))
        let rect = lerp(from, L.folderChild(index), p).offsetBy(dx: delta.width, dy: delta.height)
        let radius = lerp(from.width * 0.28, L.iconRadius(os.iconRoundness), p)
        let child = windows.session(item.id)
        let visible = child == nil || !WindowMotion.morphs(child!.style, os)
        let tappable = session.goal == 1 && p > 0.85 && windows.front === session

        return ZStack {
            Button {
                windows.launch(
                    item,
                    from: rect,
                    labelCenter: CGPoint(x: rect.midX, y: rect.midY),
                    labelSize: rect.width * 0.2,
                    parent: session.item.id
                )
            } label: {
                AppIconView(item: item, size: max(1, rect.width), radius: max(0, radius))
            }
            .buttonStyle(PressDimStyle())
            .scaleEffect(iconGrowth)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(tappable)
            .opacity(visible ? extraFade : 0)

            if os.showLabels {
                Text(os.t(item.name))
                    .font(.system(size: L.labelSize, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: rect.midX, y: rect.maxY + L.labelSize * 1.15)
                    .opacity(Double(clamp01((p - 0.7) * 3.3)) * (visible ? extraFade : 0))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: L.w, height: L.h)
    }

    // MARK: - Frost (behind the control center, the Lab and Recents)

    /// Real blur over everything behind (open apps too, including camera and web views, which a plain
    /// SwiftUI blur cannot reach).
    @ViewBuilder
    private func frostLayer(_ frost: CGFloat) -> some View {
        if frost > 0.005 {
            Group {
                if os.design == .expressive {
                    // Material scrims rather than blurs.
                    os.palette.surface.opacity(0.78)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .opacity(Double(clamp01(frost)))
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Clock widget

    private func clockWidget(_ L: HomeLayout) -> some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text(ClockText.string(for: context.date, h24: os.clock24h))
                    .font(.system(size: 76 * L.u, weight: .light))
                    .tracking(-2)
                    .monospacedDigit()
                Text(dateLine(context.date))
                    .font(.system(size: 16 * L.u, weight: .medium))
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
            .offset(x: 28 * L.u, y: 74 * L.u)
            .frame(width: L.w, height: L.h, alignment: .topLeading)
        }
    }

    private func dateLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = os.language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date).capitalized(with: os.language.locale)
    }

    // MARK: - Recents

    @ViewBuilder
    private func recentsLayer(_ L: HomeLayout, _ rv: CGFloat) -> some View {
        if rv > 0.01 {
            let grid = os.recentsLayout == .grid

            ZStack {
                Color.black.opacity(0.2)
                    .contentShape(Rectangle())
                    .onTapGesture { moveRecents(to: 0) }

                if windows.recents.isEmpty {
                    Text(os.t("No recent apps"))
                        .font(.system(size: L.w * 0.05, weight: .semibold))
                        .foregroundColor(.primary)
                } else if grid {
                    let cardWidth = (L.w - 3 * 16 * L.u) / 2
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16 * L.u), GridItem(.flexible())], spacing: 16 * L.u) {
                            ForEach(windows.recents) { item in
                                recentCard(item, L, width: cardWidth, height: cardWidth * 1.45, swipeUp: false)
                            }
                        }
                        .padding(.horizontal, 16 * L.u)
                        .padding(.top, SafeArea.insets.top + 40 * L.u)
                        .padding(.bottom, 120 * L.u)
                    }
                } else {
                    let cardWidth = L.w * 0.62
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: L.w * 0.05) {
                            ForEach(windows.recents) { item in
                                recentCard(item, L, width: cardWidth, height: L.h * 0.52, swipeUp: true)
                            }
                        }
                        .padding(.horizontal, (L.w - cardWidth) / 2)
                        .frame(height: L.h)
                    }
                }

                if !windows.recents.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { windows.forgetAll() }
                        OSLogger.shared.log("Recents", "Closed all")
                        Haptics.tap(.medium)
                    } label: {
                        Text(os.t("Close all"))
                            .font(.system(size: L.w * 0.04, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .glass(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, L.navHeight + max(SafeArea.insets.bottom, 16 * L.u) + 16 * L.u)
                }
            }
            .frame(width: L.w, height: L.h)
            .opacity(Double(clamp01(rv)))
            .scaleEffect(lerp(1.08, 1, rv))
            .allowsHitTesting(rv > 0.5)
        }
    }

    private func recentCard(_ item: HomeItem, _ L: HomeLayout, width: CGFloat, height: CGFloat, swipeUp: Bool) -> some View {
        RecentCard(
            item: item, width: width, height: height, swipeUp: swipeUp,
            image: windows.snapshot(of: item), running: windows.isRunning(item)
        ) {
            moveRecents(to: 0)
            let size = L.iconSize
            windows.launch(
                item,
                from: CGRect(x: L.w / 2 - size / 2, y: L.h / 2 - size / 2, width: size, height: size),
                labelCenter: CGPoint(x: L.w / 2, y: L.h / 2),
                labelSize: size * 0.2
            )
        } onDismiss: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                windows.forget(item)
            }
            OSLogger.shared.log("Recents", "Removed \(item.name)")
        }
    }

    private func moveRecents(to target: CGFloat) {
        if target == 1 && recentsAnim.value < 0.5 {
            OSLogger.shared.log("Recents", "Shown")
            windows.captureFront()
        }
        recentsAnim.animate(to: target, response: 0.4, damping: os.uiDamping, ease: true, stages: os.uiStages)
    }

    // MARK: - Holding the gesture line opens Recents

    /// Starts the hold timer (once per touch); `fire` runs if the finger stays still for a moment.
    private func armHold(_ translation: CGSize, fire: @escaping () -> Void) {
        guard os.holdForRecents, !holdFired else { return }
        let moved = hypot(translation.width, translation.height)
        if moved > 10 {
            cancelHold()
            holdArmed = true
            return
        }
        guard !holdArmed else { return }
        holdArmed = true
        let work = DispatchWorkItem {
            holdFired = true
            Haptics.tap(.heavy)
            fire()
            moveRecents(to: 1)
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }

    private func cancelHold() {
        holdWork?.cancel()
        holdWork = nil
    }

    /// Call when the finger lifts. Returns true if the touch was a hold (so the swipe should be ignored).
    private func endHold() -> Bool {
        cancelHold()
        holdArmed = false
        let fired = holdFired
        holdFired = false
        return fired
    }

    // MARK: - Swipe up and pause opens Recents

    /// While swiping up from the gesture line: once the finger has risen `minRise` and then stops for a
    /// moment, Recents peeks in (with a tick). Letting go then opens it; moving on cancels the peek.
    private func trackPause(_ value: DragGesture.Value, minRise: CGFloat) {
        guard os.holdForRecents else { return }
        guard let last = pausePoint else {
            pausePoint = value.location
            return
        }
        // Small jitter does not count as moving, so the pause timer keeps running.
        if hypot(value.location.x - last.x, value.location.y - last.y) < 7 { return }

        pausePoint = value.location
        pauseWork?.cancel()
        pauseWork = nil
        if recentsArmed {
            recentsArmed = false
            recentsAnim.animate(to: 0, response: 0.3, damping: 1, ease: true)
        }
        guard -value.translation.height > minRise else { return }
        let work = DispatchWorkItem {
            recentsArmed = true
            Haptics.tap(.medium)
            recentsAnim.animate(to: 0.4, response: 0.3, damping: 1, ease: true)
        }
        pauseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    /// Call when the finger lifts. Returns true if Recents was armed (the caller then opens it).
    private func endPause() -> Bool {
        pauseWork?.cancel()
        pauseWork = nil
        pausePoint = nil
        let armed = recentsArmed
        recentsArmed = false
        return armed
    }

    // MARK: - Close bar (gesture navigation: drag the window; swipe up to close it; hold for Recents)

    @ViewBuilder
    private func closeBar(_ L: HomeLayout) -> some View {
        if os.navMode == .gestures, let front = windows.front {
            let isApp = front.item.kind == .app
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(width: L.w, height: isApp ? 36 * L.u : max(L.h * 0.22, 150 * L.u))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                armHold(value.translation) {
                                    // Put the window back where it was, then show Recents over it.
                                    if let session = dragSession {
                                        dragSession = nil
                                        windowStart = nil
                                        session.k.animate(to: 1, response: 0.3, damping: 1, ease: true)
                                        windows.open(session, velocity: 0)
                                    }
                                }
                                guard !holdFired else { return }
                                dragWindow(value, range: L.h * 0.5, L)
                                trackPause(value, minRise: 50 * L.u)
                            }
                            .onEnded { value in
                                let paused = endPause()
                                if endHold() { return }
                                if paused {
                                    // Swiped up and paused: the app goes back to full screen behind Recents.
                                    if let session = dragSession {
                                        dragSession = nil
                                        windowStart = nil
                                        session.k.animate(to: 1, response: 0.34, damping: 1, ease: true)
                                        windows.open(session, velocity: 0)
                                    }
                                    Haptics.tap(.heavy)
                                    moveRecents(to: 1)
                                    return
                                }
                                endWindow(value, range: L.h * 0.5, L)
                            }
                    )

                Capsule()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: L.w * 0.34, height: 5 * L.u)
                    .padding(.bottom, 10 * L.u)
                    .opacity(Double(clamp01((front.t.value - 0.5) * 2)))
                    .allowsHitTesting(false)
            }
            .frame(width: L.w, height: L.h, alignment: .bottom)
        }
    }

    /// On the home screen (gesture navigation): the line under the dock. Swipe up for the drawer,
    /// hold it for Recents.
    @ViewBuilder
    private func homeGestureLine(_ L: HomeLayout, _ d: CGFloat, _ i: CGFloat) -> some View {
        if os.navMode == .gestures && windows.front == nil && i > 0.95 {
            let range = (L.sheetClosedTop - L.sheetOpenTop) * 0.8
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(width: L.w, height: max(L.gestureStrip, 22 * L.u))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                armHold(value.translation) {
                                    drawerStart = nil
                                    moveDrawer(to: drawerGoal, velocity: 0)
                                }
                                guard !holdFired else { return }
                                dragDrawer(value, range: range)
                                trackPause(value, minRise: 50 * L.u)
                            }
                            .onEnded { value in
                                let paused = endPause()
                                if endHold() { return }
                                if paused {
                                    // Swiped up and paused: Recents instead of the drawer.
                                    drawerStart = nil
                                    moveDrawer(to: 0, velocity: 0)
                                    Haptics.tap(.heavy)
                                    moveRecents(to: 1)
                                    return
                                }
                                endDrawer(value, range: range, tap: .resume)
                            }
                    )

                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .frame(width: L.w * 0.34, height: 5 * L.u)
                    .padding(.bottom, max(4 * L.u, (L.gestureStrip - 5 * L.u) / 2))
                    .opacity(Double(clamp01(1 - d * 3)))
                    .allowsHitTesting(false)
            }
            .frame(width: L.w, height: L.h, alignment: .bottom)
        }
    }

    // MARK: - Three-button navigation bar

    @ViewBuilder
    private func navBar(_ L: HomeLayout, _ i: CGFloat) -> some View {
        if os.navMode == .buttons && i > 0.01 {
            let icon = L.w * 0.055

            // Android's order and shapes: back, home, recents.
            HStack(spacing: 0) {
                navButton(L) {
                    Image(systemName: "arrowtriangle.left.fill")
                        .font(.system(size: icon * 0.82, weight: .regular))
                } action: {
                    goBack()
                }
                navButton(L) {
                    Circle()
                        .frame(width: icon * 0.95, height: icon * 0.95)
                } action: {
                    goHome()
                }
                navButton(L) {
                    RoundedRectangle(cornerRadius: icon * 0.14, style: .continuous)
                        .frame(width: icon * 0.82, height: icon * 0.82)
                } action: {
                    moveRecents(to: recentsAnim.value > 0.5 ? 0 : 1)
                }
            }
            .foregroundColor(os.palette.onSurface)
            .frame(width: L.w, height: L.navHeight)
            .background {
                if os.design == .expressive {
                    os.palette.surfaceContainer
                } else {
                    Glass(shape: Rectangle(), tint: 1.2)
                }
            }
            .frame(width: L.w, height: L.h, alignment: .bottom)
            .offset(y: L.navHeight * 1.5 * (1 - i))
        }
    }

    private func navButton<Label: View>(_ L: HomeLayout, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.navUp()
            action()
        } label: {
            label()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(NavKeyStyle(size: L.navHeight * 0.9))
    }

    private func goBack() {
        OSLogger.shared.log("Nav", "Back")
        if recentsAnim.value > 0.5 {
            moveRecents(to: 0)
        } else if panelGoal > 0.5 {
            movePanel(to: 0, velocity: 0)
        } else if shadeGoal > 0.5 {
            moveShade(to: 0, velocity: 0)
        } else if let front = windows.front {
            // The window shrinks back into its icon; if it came from the drawer, the drawer is still there.
            windows.close(front, velocity: 0)
        } else if drawerGoal > 0.5 {
            moveDrawer(to: 0, velocity: 0)
        }
    }

    /// Home closes whatever is in front. Apps opened from the drawer go back to the drawer;
    /// press Home again to close the drawer too.
    private func goHome() {
        OSLogger.shared.log("Nav", "Home")
        var closedSomething = false
        if recentsAnim.value > 0.5 { moveRecents(to: 0); closedSomething = true }
        if panelGoal > 0.5 { movePanel(to: 0, velocity: 0); closedSomething = true }
        if shadeGoal > 0.5 { moveShade(to: 0, velocity: 0); closedSomething = true }
        if windows.front != nil { windows.closeAll(); closedSomething = true }
        if !closedSomething {
            moveDrawer(to: 0, velocity: 0)
        }
    }

    // MARK: - Lab panel (swipe in from the left or right edge)

    private func panelWidth(_ L: HomeLayout) -> CGFloat {
        min(L.w - 24 * L.u, 420)
    }

    @ViewBuilder
    private func panelLayer(_ L: HomeLayout, _ pv: CGFloat) -> some View {
        if pv > 0.001 {
            let width = panelWidth(L)
            let top = 46 * L.u
            let bottom = 16 * L.u + L.navHeight
            let height = L.h - top - bottom
            let openX = panelSide == .left ? 12 * L.u + width / 2 : L.w - 12 * L.u - width / 2
            let closedX = panelSide == .left ? -width / 2 - 20 : L.w + width / 2 + 20

            ZStack {
                Color.black.opacity(Double(0.25 * clamp01(pv)))
                    .contentShape(Rectangle())
                    .onTapGesture { movePanel(to: 0, velocity: 0) }

                LabPanel(
                    onClose: { movePanel(to: 0, velocity: 0) },
                    onRunSetup: {
                        movePanel(to: 0, velocity: 0)
                        os.setupDone = false
                    }
                )
                .frame(width: width, height: height)
                .glass(RoundedRectangle(cornerRadius: 34 * L.u, style: .continuous), tint: 1.3)
                .clipShape(RoundedRectangle(cornerRadius: 34 * L.u, style: .continuous))
                .simultaneousGesture(panelCloseGesture(L))
                .position(x: lerp(closedX, openX, pv), y: top + height / 2)
            }
            .frame(width: L.w, height: L.h)
            .allowsHitTesting(pv > 0.3 || panelStart != nil)
        }
    }

    private func edgeGesture(_ side: PanelSide, _ L: HomeLayout) -> some Gesture {
        let width = panelWidth(L)
        return DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if panelStart == nil {
                    panelSide = side
                    panel.stop()
                    panelStart = panel.value
                }
                let dx = side == .left ? value.translation.width : -value.translation.width
                panel.set(clamp01((panelStart ?? 0) + dx / width))
            }
            .onEnded { value in
                guard panelStart != nil else { return }
                panelStart = nil
                let velocity = (side == .left ? value.velocity.width : -value.velocity.width) / width
                let projected = panel.value + velocity * 0.2
                movePanel(to: projected > 0.4 ? 1 : 0, velocity: velocity)
            }
    }

    /// Swipe the open panel back toward its edge to close it (vertical drags are left to its scroll view).
    private func panelCloseGesture(_ L: HomeLayout) -> some Gesture {
        let width = panelWidth(L)
        return DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
                if panelStart == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    panel.stop()
                    panelStart = panel.value
                }
                let dx = panelSide == .left ? value.translation.width : -value.translation.width
                panel.set(clamp01((panelStart ?? 1) + min(0, dx) / width))
            }
            .onEnded { value in
                guard panelStart != nil else { return }
                panelStart = nil
                let velocity = (panelSide == .left ? value.velocity.width : -value.velocity.width) / width
                let projected = panel.value + velocity * 0.2
                movePanel(to: projected > 0.6 ? 1 : 0, velocity: velocity)
            }
    }

    private func movePanel(to target: CGFloat, velocity: CGFloat) {
        if target != panelGoal {
            OSLogger.shared.log("Lab", target > 0.5 ? "Panel opened" : "Panel closed", level: .debug)
            if target > 0.5 { Haptics.tap(.medium) }
        }
        panelGoal = target
        panel.animate(to: target, response: 0.46, damping: os.uiDamping, velocity: velocity, ease: true, stages: os.uiStages)
    }

    // MARK: - Gesture zones

    @ViewBuilder
    private func sheetLayers(_ L: HomeLayout, _ d: CGFloat, _ i: CGFloat) -> some View {
        if windows.front == nil && i > 0.95 {
            // Anywhere on the screen: swipe up to open the drawer, down to close it; a tap outside the
            // open drawer closes it.
            Color.clear
                .contentShape(Rectangle())
                .gesture(drawerGesture(L, tap: d > 0.3 ? .close : .resume))
            // The sheet itself (the dock while it is closed): a tap on its empty space opens it.
            let top = L.sheetTop(drawer: d)
            Color.clear
                .frame(width: L.w, height: max(0, L.h - top))
                .contentShape(Rectangle())
                .gesture(drawerGesture(L, tap: d < 0.5 ? .open : .resume))
                .frame(width: L.w, height: L.h, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func zones(_ L: HomeLayout) -> some View {
        if revealed {
            // Top: swipe down on the status bar for the control panel (works inside apps too). Over an app running full
            // screen the strip is thin, so the app keeps its touches.
            let immersive = windows.front.map { ModemOSHost.shared.app($0.item.hostID)?.fullScreen == true } ?? false
            Color.clear
                .frame(width: L.w, height: (immersive ? 18 : 60) * L.u)
                .contentShape(Rectangle())
                .gesture(shadeGesture(L))
                .frame(width: L.w, height: L.h, alignment: .top)

            // Left and right edges: swipe toward the middle for the Lab panel.
            if panel.value < 0.01 && shade.value < 0.01 {
                let edge = 16 * L.u
                let top = 60 * L.u
                let height = L.h - top - L.navHeight - 40 * L.u
                Color.clear
                    .frame(width: edge, height: height)
                    .contentShape(Rectangle())
                    .gesture(edgeGesture(.left, L))
                    .position(x: edge / 2, y: top + height / 2)
                Color.clear
                    .frame(width: edge, height: height)
                    .contentShape(Rectangle())
                    .gesture(edgeGesture(.right, L))
                    .position(x: L.w - edge / 2, y: top + height / 2)
            }
        }
    }

    /// What a plain tap (no swipe) on a drawer zone does.
    private enum DrawerTap {
        case resume, open, close
    }

    private func drawerGesture(_ L: HomeLayout, tap: DrawerTap) -> some Gesture {
        // The sheet travels a little faster than the finger, so a short swipe is enough.
        let range = (L.sheetClosedTop - L.sheetOpenTop) * 0.8
        return DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in dragDrawer(value, range: range) }
            .onEnded { value in endDrawer(value, range: range, tap: tap) }
    }

    /// Starting a swipe on an icon moves the drawer too (a plain tap still opens the app).
    private func iconDrawerGesture(_ L: HomeLayout) -> some Gesture {
        let range = (L.sheetClosedTop - L.sheetOpenTop) * 0.8
        return DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in dragDrawer(value, range: range) }
            .onEnded { value in endDrawer(value, range: range, tap: .resume) }
    }

    private func shadeGesture(_ L: HomeLayout) -> some Gesture {
        let range = (L.barOpenHeight - L.barHeight) * 0.8
        return DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in dragShade(value, range: range) }
            .onEnded { value in endShade(value, range: range) }
    }

    private func windowGesture(_ L: HomeLayout, minimumDistance: CGFloat = 0) -> some Gesture {
        // The bar at the bottom is active from the very first frame of the opening animation,
        // so you can grab the window at once.
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .global)
            .onChanged { value in dragWindow(value, range: L.h * 0.5, L) }
            .onEnded { value in endWindow(value, range: L.h * 0.5, L) }
    }

    // MARK: - Drawer

    private func dragDrawer(_ value: DragGesture.Value, range: CGFloat) {
        guard windows.front == nil, shade.value < 0.01, panel.value < 0.01 else { return }
        if drawerStart == nil {
            drawer.stop()
            drawerStart = drawer.value
        }
        drawer.set(clamp01((drawerStart ?? 0) - value.translation.height / range))
    }

    private func endDrawer(_ value: DragGesture.Value, range: CGFloat, tap: DrawerTap) {
        guard drawerStart != nil else { return }
        drawerStart = nil
        if abs(value.translation.height) < 10 && abs(value.translation.width) < 10 {
            switch tap {
            case .open: moveDrawer(to: 1, velocity: 0)
            case .close: moveDrawer(to: 0, velocity: 0)
            case .resume: moveDrawer(to: drawerGoal, velocity: 0)
            }
            return
        }
        let velocity = -value.velocity.height / range
        let projected = drawer.value + velocity * 0.2
        moveDrawer(to: projected > 0.5 ? 1 : 0, velocity: velocity)
    }

    private func moveDrawer(to target: CGFloat, velocity: CGFloat) {
        if target != drawerGoal {
            OSLogger.shared.log("Drawer", target > 0.5 ? "Opened" : "Closed", level: .debug)
        }
        drawerGoal = target
        if target == 0 { drawerQuery = "" }
        drawer.animate(to: target, response: 0.52, damping: os.uiDamping, velocity: velocity, ease: true, stages: os.uiStages)
    }

    // MARK: - Control panel

    private func dragShade(_ value: DragGesture.Value, range: CGFloat) {
        // Not while the drawer is open on the home screen; inside an app it always works.
        guard windows.front != nil || drawer.value < 0.01 else { return }
        if shadeStart == nil {
            shade.stop()
            shadeStart = shade.value
        }
        shade.set(clamp01((shadeStart ?? 0) + value.translation.height / range))
    }

    private func endShade(_ value: DragGesture.Value, range: CGFloat) {
        guard shadeStart != nil else { return }
        shadeStart = nil
        if abs(value.translation.height) < 10 {
            moveShade(to: shadeGoal, velocity: 0)
            return
        }
        let velocity = value.velocity.height / range
        let projected = shade.value + velocity * 0.2
        moveShade(to: projected > 0.5 ? 1 : 0, velocity: velocity)
    }

    private func moveShade(to target: CGFloat, velocity: CGFloat) {
        if target != shadeGoal {
            OSLogger.shared.log("Control center", target > 0.5 ? "Opened" : "Closed", level: .debug)
        }
        shadeGoal = target
        shade.animate(to: target, response: 0.5, damping: os.uiDamping, velocity: velocity, ease: true, stages: os.uiStages)
    }

    // MARK: - Dragging a window around

    private func dragWindow(_ value: DragGesture.Value, range: CGFloat, _ L: HomeLayout) {
        guard let session = dragSession ?? windows.front else { return }
        if windowStart == nil {
            dragSession = session
            session.t.stop()
            session.k.stop()
            // Pick the window up exactly where it is, so nothing jumps.
            let current = windowRect(session, L)
            session.heldCenter = CGPoint(x: current.midX, y: current.midY)
            session.heldOffset = .zero
            windowStart = session.t.value
            session.k.set(0)
        }

        // Dragging up shrinks the window; it follows the finger in every direction.
        let dy = value.translation.height
        session.t.set(clamp01((windowStart ?? 1) + dy / range))
        session.heldOffset = CGSize(width: value.translation.width, height: dy > 0 ? dy * 0.4 : dy)
    }

    private func endWindow(_ value: DragGesture.Value, range: CGFloat, _ L: HomeLayout) {
        guard let session = dragSession, windowStart != nil else { return }
        dragSession = nil
        windowStart = nil

        // Let go: the window carries on from wherever it was dragged to.
        session.k.animate(to: 1, response: 0.34, damping: 1, ease: true)

        let dx = value.translation.width
        let dy = value.translation.height
        if abs(dx) < 10 && abs(dy) < 10 {
            windows.resume(session)
            return
        }

        let velocity = value.velocity.height / range
        let projected = session.t.value + velocity * 0.2
        let sideways = abs(dx) > L.w * 0.35 || abs(value.velocity.width) > 1000
        if projected < 0.5 || sideways {
            windows.close(session, velocity: velocity)
        } else {
            windows.open(session, velocity: velocity)
        }
    }
}

/// A card on the Recents screen. Swipe it away (up in the carousel, sideways in the grid) or tap its x to forget the app.
private struct RecentCard: View {
    let item: HomeItem
    let width: CGFloat
    let height: CGFloat
    let swipeUp: Bool
    /// What it last looked like.
    var image: UIImage?
    /// Still running in the background.
    var running = false
    let onOpen: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var os: OSSettings
    @State private var offset: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                AppIconView(item: item, size: 28, radius: 28 * CGFloat(os.iconRoundness))
                VStack(alignment: .leading, spacing: 0) {
                    Text(os.t(item.name))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(os.palette.onSurface)
                        .lineLimit(1)
                    if running {
                        Text(os.t("Running"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(os.palette.primary)
                    }
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 26, height: 26)
                        .glass(Circle())
                }
            }
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                } else {
                    OSAppBackground()
                    AppIconView(item: item, size: width * 0.34, radius: width * 0.34 * CGFloat(os.iconRoundness))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: min(30, width * 0.12), style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .frame(width: width)
        .offset(x: swipeUp ? 0 : offset, y: swipeUp ? offset : 0)
        .opacity(Double(1 - min(1, abs(offset) / 400)))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if swipeUp {
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        offset = min(0, value.translation.height)
                    } else {
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        offset = value.translation.width
                    }
                }
                .onEnded { value in
                    let distance = swipeUp ? -value.translation.height : abs(value.translation.width)
                    let speed = swipeUp ? -value.velocity.height : abs(value.velocity.width)
                    if (distance > 120 || speed > 800) && offset != 0 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { offset = 0 }
                    }
                }
        )
    }

    private func dismiss() {
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.2)) { offset = swipeUp ? -900 : (offset < 0 ? -600 : 600) }
        after(0.2) { onDismiss() }
    }
}

/// A navigation key: a round highlight grows under it while pressed, with a crisp click on press-down
/// (the soft release thump is played by the button's action).
private struct NavKeyStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .background(
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0))
                    .frame(width: size, height: size)
                    .scaleEffect(configuration.isPressed ? 1 : 0.5)
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { Haptics.navDown() }
            }
    }
}

/// The folder icon: a frosted square with the folder's apps as little icons in it.
struct FolderGlyph: View {
    let folderID: Int
    let cornerRadius: CGFloat
    let showBackground: Bool

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let mini = side * 0.32
            let gap = side * 0.08

            ZStack {
                if showBackground {
                    Glass(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: 1.4)
                }

                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        miniIcon(0, mini)
                        miniIcon(1, mini)
                    }
                    HStack(spacing: gap) {
                        miniIcon(2, mini)
                        miniIcon(3, mini)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func miniIcon(_ index: Int, _ size: CGFloat) -> some View {
        let children = HomeItem.children(of: folderID)
        if index < children.count {
            AppIconView(item: children[index], size: size, radius: size * 0.28)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// Where the top of the drawer's list is.
private struct DrawerPullKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
