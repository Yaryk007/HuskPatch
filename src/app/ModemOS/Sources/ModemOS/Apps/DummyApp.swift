import SwiftUI

/// A placeholder app from the Dummy Apps folder: it opens like a real app, but only shows its icon,
/// a tap counter and some filler text.
struct DummyApp: View {
    let item: HomeItem

    @EnvironmentObject private var os: OSSettings
    @State private var taps = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AppTitle(title: item.name, subtitle: os.t("Dummy Apps"))

                AppIconView(item: item, size: 120, radius: 120 * CGFloat(os.iconRoundness))
                    .scaleEffect(1 + CGFloat(taps % 2) * 0.04)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: taps)
                    .padding(.top, 20)

                Text(os.t("This is a dummy app."))
                    .font(.system(size: 22, weight: .bold))
                Text(os.t("It doesn't do anything yet."))
                    .foregroundColor(.secondary)

                Button {
                    Haptics.tap(.medium)
                    taps += 1
                } label: {
                    Text(os.t("Tap me"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(item.color))
                }
                .buttonStyle(PressScaleStyle())

                Text("\(os.t("Taps")): \(taps)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)

                VStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(item.color.opacity(0.25))
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule().fill(Color.primary.opacity(0.15)).frame(width: CGFloat(120 + row * 17 % 80), height: 10)
                                Capsule().fill(Color.primary.opacity(0.08)).frame(width: CGFloat(80 + row * 29 % 90), height: 8)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05)))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 20)
        }
    }
}
