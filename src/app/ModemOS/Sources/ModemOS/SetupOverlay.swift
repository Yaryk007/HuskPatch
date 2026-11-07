import SwiftUI

/// Setup: "Hello" fades in out of a blur, then glass pages slide in one after another
/// (language, theme, wallpaper, navigation, animations, permissions). The last page says "You are all set up"
/// with a Start button in the middle. Everything you pick applies live behind the pages.
struct SetupOverlay: View {
    var onFinished: () -> Void

    private enum Step: Int, CaseIterable {
        case language, design, theme, wallpaper, navigation, motion, permissions
    }

    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var permissions = PermissionsCenter.shared

    /// The page being shown, as a float: -1 = "Hello", 0...5 = the steps, 6 = the final card.
    @StateObject private var page = Animator(-1)
    /// 0 = final card in place, 1 = swiped off to the right.
    @StateObject private var leave = Animator(0)
    @State private var current = -1
    @State private var helloBlur: CGFloat = 18
    @State private var helloOpacity: Double = 0

    private var finalIndex: Int { Step.allCases.count }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let ch = min(w * 16 / 9, h)

            ZStack {
                // Same wallpaper as the home screen underneath; it also hides the home screen until you start.
                Wallpaper()

                Text(os.t("Hello"))
                    .font(os.display(w * 0.2))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 10)
                    .blur(radius: helloBlur)
                    .opacity(helloOpacity * Double(clamp01(-page.value)))
                    .position(x: w * 0.49, y: h * 0.49)

                ForEach(Step.allCases, id: \.rawValue) { step in
                    let offset = CGFloat(step.rawValue) - page.value
                    if abs(offset) < 1.2 {
                        stepCard(step, w: w, h: h, ch: ch)
                            .offset(x: offset * w)
                            .scaleEffect(1 - 0.06 * min(1, abs(offset)))
                            .opacity(Double(1 - 0.4 * min(1, abs(offset))))
                    }
                }

                let finalOffset = CGFloat(finalIndex) - page.value
                if finalOffset < 1.2 {
                    finalCard(w: w, h: h, ch: ch)
                        .offset(x: max(0, finalOffset) * w + leave.value * w)
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .onAppear(perform: runIntro)
    }

    // MARK: - Step pages

    private func stepCard(_ step: Step, w: CGFloat, h: CGFloat, ch: CGFloat) -> some View {
        let top = max(SafeArea.insets.top, ch * 0.05) + 10
        let bottom = max(SafeArea.insets.bottom, ch * 0.03) + 10

        return VStack(alignment: .leading, spacing: 0) {
            Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
            Text(os.t(title(step)))
                .font(os.display(w * 0.095))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(os.t(subtitle(step)))
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .padding(.top, 6)
                .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                content(step)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 12) {
                if step.rawValue > 0 {
                    Button {
                        go(to: step.rawValue - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(PressScaleStyle())
                }
                Spacer()
                dots(step.rawValue)
                Spacer()
                Button {
                    go(to: step.rawValue + 1)
                } label: {
                    HStack(spacing: 6) {
                        Text(os.t(step == .permissions ? "Finish" : "Next"))
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(os.palette.onPrimary)
                    .padding(.horizontal, 22)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.osAccent))
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.top, 12)
        }
        .foregroundColor(.primary)
        .padding(22)
        .frame(width: w - 24, height: h - top - bottom)
        .glass(RoundedRectangle(cornerRadius: w * 0.08, style: .continuous), tint: 1.6)
        .position(x: w / 2, y: top + (h - top - bottom) / 2)
        .allowsHitTesting(current == step.rawValue)
    }

    private func dots(_ index: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<Step.allCases.count, id: \.self) { dot in
                Capsule()
                    .fill(Color.primary.opacity(dot == index ? 0.9 : 0.25))
                    .frame(width: dot == index ? 18 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
    }

    private func title(_ step: Step) -> String {
        switch step {
        case .language: return "Language"
        case .design: return "Your look"
        case .theme: return "Light or dark?"
        case .wallpaper: return "Wallpaper"
        case .navigation: return "Navigation"
        case .motion: return "Animations"
        case .permissions: return "Permissions"
        }
    }

    private func subtitle(_ step: Step) -> String {
        switch step {
        case .language: return "Choose the language for ModemOS."
        case .design: return "It changes every screen and every app. You can switch any time."
        case .theme: return "Everything follows it, from the panels to the apps."
        case .wallpaper: return "Pick one. You can change it any time in the Lab."
        case .navigation: return "How do you want to get around?"
        case .motion: return "How apps open and close. Fine-tune it later in the Lab."
        case .permissions: return "Let the apps use the real data on this phone. You can skip any of these."
        }
    }

    @ViewBuilder
    private func content(_ step: Step) -> some View {
        switch step {
        case .language:
            LanguagePicker()
        case .design:
            DesignPicker()
        case .theme:
            ThemePicker()
        case .wallpaper:
            WallpaperGrid(columns: 3, height: 150)
        case .navigation:
            NavModePicker()
        case .motion:
            VStack(spacing: 16) {
                AnimStylePicker()
                LabeledSlider(title: "Animation speed", value: $os.animSpeed, range: 0.25...3) {
                    String(format: "%.2gx", $0)
                }
                .padding(.horizontal, 4)
            }
        case .permissions:
            VStack(spacing: 8) {
                ForEach(PermissionsCenter.Kind.allCases) { kind in
                    permissionRow(kind)
                }
            }
        }
    }

    private func permissionRow(_ kind: PermissionsCenter.Kind) -> some View {
        let status = permissions.status(kind)
        return HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.osAccent))
            VStack(alignment: .leading, spacing: 2) {
                Text(os.t(kind.title)).font(.system(size: 16, weight: .semibold))
                Text(os.t(kind.detail)).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer(minLength: 6)
            switch status {
            case .allowed:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundColor(.green)
            case .denied:
                Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundColor(.red)
            case .notAsked:
                Button(os.t("Allow")) {
                    permissions.request(kind)
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.osAccent))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    // MARK: - Final card: "You are all set up" and a Start button

    private func finalCard(w: CGFloat, h: CGFloat, ch: CGFloat) -> some View {
        let top = ch * 0.07
        let bottom = h - ch * 0.043
        let dark = os.theme == .dark

        return ZStack {
            // The card with the words cut out of it, so the wallpaper shows through the letters.
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.075, style: .continuous)
                    .fill(dark ? Color.black : Color.white)

                Text(os.t("You are all set up"))
                    .font(os.display(w * 0.142))
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(.black)
                    .padding(.leading, w * 0.1)
                    .padding(.trailing, w * 0.06)
                    .padding(.top, w * 0.1)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()

            Button {
                start()
            } label: {
                HStack(spacing: 10) {
                    Text(os.t("Start"))
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: w * 0.06, weight: .bold))
                .foregroundColor(dark ? .black : .white)
                .padding(.horizontal, w * 0.1)
                .padding(.vertical, w * 0.045)
                .background(Capsule().fill(dark ? Color.white : Color.black))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            }
            .buttonStyle(PressScaleStyle())

            Button {
                go(to: finalIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(dark ? .white : .black)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill((dark ? Color.white : Color.black).opacity(0.12)))
            }
            .buttonStyle(PressScaleStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(w * 0.06)
        }
        .frame(width: w * 0.88, height: bottom - top)
        .position(x: w / 2, y: (top + bottom) / 2)
        .allowsHitTesting(current == finalIndex)
    }

    private func start() {
        guard current == finalIndex else { return }
        current = finalIndex + 1
        OSLogger.shared.log("Setup", "Finished")
        Haptics.tap(.medium)
        leave.animate(to: 1, response: 0.55, damping: 1, ease: true) {
            onFinished()
        }
    }

    // MARK: - Flow

    private func go(to index: Int) {
        Haptics.tap()
        current = index
        page.animate(to: CGFloat(index), response: 0.55, damping: 1, ease: true)
        if index <= finalIndex - 1 && index >= 0 {
            OSLogger.shared.log("Setup", "Step: \(title(Step(rawValue: index)!))", level: .debug)
        }
    }

    private func runIntro() {
        page.set(-1)
        leave.set(0)
        current = -1
        withAnimation(.easeInOut(duration: 0.9).delay(0.15)) {
            helloBlur = 0
            helloOpacity = 1
        }
        after(2.1) {
            go(to: 0)
        }
    }
}
