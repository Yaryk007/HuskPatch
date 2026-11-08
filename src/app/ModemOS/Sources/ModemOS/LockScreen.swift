import SwiftUI

/// The lock screen at each start: the time over the blurred home screen. Swipe up, or tap, to go in.
struct LockScreen: View {
    var unlocked: () -> Void

    @EnvironmentObject private var os: OSSettings
    @State private var drag: CGFloat = 0
    @State private var leaving = false

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    Text(time(context.date))
                        .font(.system(size: 92, weight: .light))
                        .monospacedDigit()
                    Text(date(context.date))
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Text(os.t("Swipe up to unlock"))
                        .font(.system(size: 14))
                        .padding(.bottom, 52)
                }
                .padding(.top, geo.size.width / 390 * 130)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
            }
            .background { ZStack { Rectangle().fill(.ultraThinMaterial); Color.black.opacity(0.28) } }
            .contentShape(Rectangle())
            .offset(y: leaving ? -geo.size.height : min(0, drag))
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag = $0.translation.height }
                    .onEnded { value in
                        if value.predictedEndTranslation.height < -geo.size.height * 0.3 { leave() } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { drag = 0 }
                        }
                    }
            )
            .onTapGesture { leave() }
        }
        .ignoresSafeArea()
    }

    private func leave() {
        guard !leaving else { return }
        OSLogger.shared.log("Keyguard", "Unlocked")
        Haptics.tap(.soft)
        withAnimation(.easeOut(duration: 0.3)) { leaving = true }
        NotificationCenter.default.post(name: .modemOSUnlocked, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { unlocked() }
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = os.clock24h ? "HH:mm" : "h:mm"
        return formatter.string(from: date)
    }

    private func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = os.language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }
}

extension Notification.Name {
    /// The lock screen opened: the home screen's icons come in.
    static let modemOSUnlocked = Notification.Name("ModemOSUnlocked")
}

/// The prototype's boot: log lines creep in, the ModemOS mark pulses with its signal bars, then the black screen closes
/// into a circle in the middle. Tap to skip.
struct ModemBootView: View {
    var finished: () -> Void

    private static let lines = [
        "[    0.000] modem: claiming the display",
        "[    0.012] modem: mapping guest memory",
        "[    0.041] init: first stage mount",
        "[    0.128] android: starting zygote",
        "[    0.164] husk: claiming JIT",
        "[    0.203] surfaceflinger: composer ready",
        "[    0.311] ios: refusing to let go",
        "[    0.312] modem: retrying",
        "[    0.355] husk: translation layer up",
        "[    0.398] system_server: services up",
        "[    0.466] launcher: taking over",
    ]

    @State private var shown = 0
    @State private var closing = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<shown, id: \.self) { index in
                        Text(Self.lines[index])
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(red: 0.62, green: 0.91, blue: 0.65))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 54)
                VStack(spacing: 14) {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(0..<4, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 8, height: CGFloat(10 + bar * 8))
                                .opacity(pulse ? 0.35 : 1)
                                .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(bar) * 0.12), value: pulse)
                        }
                    }
                    Text("ModemOS").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 120)
            }
            .mask(
                Circle()
                    .frame(width: closing ? 0 : hypot(geo.size.width, geo.size.height) * 1.2,
                           height: closing ? 0 : hypot(geo.size.width, geo.size.height) * 1.2)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            )
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .onAppear {
            pulse = true
            for index in 1...Self.lines.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.23 * Double(index)) {
                    if !closing { shown = index }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.23 * Double(Self.lines.count + 1)) { close() }
        }
    }

    private func close() {
        guard !closing else { return }
        withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: 0.7)) { closing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { finished() }
    }
}
