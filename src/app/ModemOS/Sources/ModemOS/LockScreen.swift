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
