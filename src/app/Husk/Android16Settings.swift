// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Settings pages from LineageOS 23.2 -- System › System updates (Updater), which checks HuskPatch's own
/// releases on GitHub, and System › Gestures.

/// LineageOS's logo: the ring with its dot, and a small circle on either side joined to it.
struct LineageLogo: View {
    var size: CGFloat = 60

    var body: some View {
        Canvas { ctx, s in
            let h = s.height, cy = h / 2
            let ring = h * 0.36, small = h * 0.14, line = h * 0.09
            let cx = s.width / 2
            var bar = Path()
            bar.move(to: CGPoint(x: cx - ring * 2.4, y: cy)); bar.addLine(to: CGPoint(x: cx + ring * 2.4, y: cy))
            ctx.stroke(bar, with: .color(.white), lineWidth: line)
            for x in [cx - ring * 2.4, cx + ring * 2.4] {
                let r = CGRect(x: x - small, y: cy - small, width: small * 2, height: small * 2)
                ctx.fill(Path(ellipseIn: r), with: .color(Color(uiColor: Material3.tone(.primary, 45))))
                ctx.stroke(Path(ellipseIn: r), with: .color(.white), lineWidth: line)
            }
            let big = CGRect(x: cx - ring, y: cy - ring, width: ring * 2, height: ring * 2)
            ctx.fill(Path(ellipseIn: big), with: .color(Color(uiColor: Material3.tone(.primary, 45))))
            ctx.stroke(Path(ellipseIn: big), with: .color(.white), lineWidth: line * 1.2)
            let dot = ring * 0.45
            ctx.fill(Path(ellipseIn: CGRect(x: cx - dot, y: cy - dot, width: dot * 2, height: dot * 2)), with: .color(.white))
        }
        .frame(width: size * 3.2, height: size)
    }
}

/// System › System updates: the version card, Recent changes and Report issues, and the check -- against HuskPatch's
/// latest release on GitHub.
struct AndroidSystemUpdatesPage: View {
    enum State: Equatable { case idle, checking, upToDate, available(String, URL), failed }
    @SwiftUI.State private var state: State = .idle
    @AppStorage("huskpatch.updates.lastChecked") private var lastChecked: Double = 0

    private static let repo = "Yaryk007/HuskPatch"

    var body: some View {
        AndroidSettingsPage(title: "System updates", onBack: AndroidSettingsRoute.pop) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 6) {
                        LineageLogo(size: 52)
                        Text("23.2").font(.system(size: 74, weight: .light, design: .rounded))
                    }
                    Spacer(minLength: 40)
                    HStack(alignment: .top, spacing: 18) {
                        info("LineageOS 23.2", "Android 16")
                        info("Build date", Bundle.main.buildDate.formatted(.dateTime.day().month(.abbreviated)))
                        info("Security update", Bundle.main.buildDate.formatted(.dateTime.month(.abbreviated).year()))
                    }
                }
                .foregroundStyle(.white)
                .padding(22)
                .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
                .background(Color(uiColor: Material3.tone(.primary, 45)))
                HStack(spacing: 0) {
                    link("Recent changes", "https://github.com/\(Self.repo)/commits/main")
                    link("Report issues", "https://github.com/\(Self.repo)/issues")
                }
                .padding(.vertical, 8)
                .background(Color(uiColor: Material3.surfaceContainerHigh))
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.bottom, 20)

            Button(action: check) {
                HStack(spacing: 12) {
                    if state == .checking { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    Text(state == .checking ? "Checking for updates" : "Check for updates")
                }
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color(uiColor: Material3.surfaceContainer), in: Capsule())
            }
            .buttonStyle(AndroidSquashStyle())
            .disabled(state == .checking)

            if lastChecked > 0 {
                Text("Last checked: " + Date(timeIntervalSince1970: lastChecked).formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 14)
            }

            result.padding(.top, 30)
        }
    }

    @ViewBuilder private var result: some View {
        switch state {
        case .upToDate:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 92))
                    .foregroundStyle(Color(uiColor: Material3.tone(.primary, 80)))
                Text("No updates available").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("New builds for this device will appear here when available.")
                    .font(.system(size: 16, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
        case .available(let tag, let url):
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 80))
                    .foregroundStyle(Color(uiColor: Material3.primary))
                Text("HuskPatch \(tag) is available").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("You have \(Bundle.main.version). The IPA is on its release page.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Button("Download") { UIApplication.shared.open(url) }.buttonStyle(.expressive(.filled))
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
        case .failed:
            Text("Couldn't check for updates. Check your connection and try again.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.error))
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 14, design: .rounded)).opacity(0.85)
            Text(value).font(.system(size: 18, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Button { if let u = URL(string: url) { UIApplication.shared.open(u) } } label: {
            Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .frame(maxWidth: .infinity).frame(height: 52)
        }
        .buttonStyle(AndroidRippleStyle())
    }

    private func check() {
        withAnimation(AndroidMotion.fade) { state = .checking }
        Task {
            var next: State = .failed
            if let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest"),
               let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let newer = latest.compare(Bundle.main.version, options: .numeric) == .orderedDescending
                let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(Self.repo)/releases")!
                next = newer ? .available(latest, page) : .upToDate
            }
            lastChecked = Date().timeIntervalSince1970
            withAnimation(AndroidMotion.spatial) { state = next }
        }
    }
}

extension Bundle {
    /// When this build was made: the executable's date.
    var buildDate: Date {
        (executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }) ?? Date()
    }
}

/// System › Gestures: the navigation mode and what the home screen's gestures do.
struct AndroidGesturesPage: View {
    @AppStorage(AndroidOS.Navigation.key) private var navigation = AndroidOS.Navigation.buttons
    @AppStorage(HomeSettings.swipeDownKey) private var swipeDown = true
    @AppStorage(HomeSettings.doubleTapKey) private var doubleTap = true

    var body: some View {
        AndroidSettingsPage(title: "Gestures", onBack: AndroidSettingsRoute.pop) {
            AndroidSettingsGroup {
                SettingsLink(route: .navigation, icon: "hand.draw.fill", tint: .systemGray, title: "Navigation mode", summary: navigation.title)
            }
            AndroidSettingsGroup(header: "Home screen") {
                AndroidSettingsRow(icon: "arrow.down.to.line", title: "Swipe down for notifications",
                                   summary: "Pull down anywhere on the home screen") {
                    Toggle("", isOn: $swipeDown).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
                AndroidSettingsRow(icon: "hand.tap", title: "Double tap to sleep",
                                   summary: "Double-tap an empty part of the home screen to turn the screen off") {
                    Toggle("", isOn: $doubleTap).labelsHidden().toggleStyle(Material3SwitchStyle())
                }
            }
        }
    }
}
