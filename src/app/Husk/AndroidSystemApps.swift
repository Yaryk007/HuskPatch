// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's own apps, the ones LineageOS ships -- Phone, Messaging, Contacts, Browser (Jelly), Camera
/// (Aperture), Clock, Calculator and Files -- each drawn in Material 3 and working where the iPhone lets an app do the job:
/// calls and texts go through iOS's own call and message screens, the camera is the iPhone's, contacts are the iPhone's.
enum AndroidSystemApp: String, CaseIterable, Identifiable, Hashable {
    case phone, messages, contacts, browser, camera, clock, calculator, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "Phone"
        case .messages: return "Messaging"
        case .contacts: return "Contacts"
        case .browser: return "Browser"
        case .camera: return "Camera"
        case .clock: return "Clock"
        case .calculator: return "Calculator"
        case .files: return "Files"
        }
    }

    /// The dock along the bottom of the home screen, as LineageOS 22 sets it up.
    static let dock: [AndroidSystemApp] = [.phone, .messages, .contacts, .browser, .camera]

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .phone: AndroidDialerApp()
        case .messages: AndroidMessagingApp()
        case .contacts: AndroidContactsApp()
        case .browser: AndroidBrowserApp()
        case .camera: AndroidCameraApp()
        case .clock: AndroidClockApp()
        case .calculator: AndroidCalculatorApp()
        case .files: AndroidFilesApp()
        }
    }
}

// MARK: - icons

/// LineageOS 22's icons for its apps: a glyph on a round plate, in each app's own colours.
struct AndroidSystemAppIcon: View {
    let app: AndroidSystemApp
    let size: CGFloat

    var body: some View {
        ZStack {
            plate
            glyph
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var plate: some View {
        switch app {
        case .phone, .messages, .contacts: Circle().fill(Color(white: 0.96))
        case .browser: Circle().fill(LinearGradient(colors: [Color(red: 0.16, green: 0.52, blue: 1), Color(red: 0.1, green: 0.38, blue: 0.95)],
                                                    startPoint: .top, endPoint: .bottom))
        case .camera: Circle().fill(Color(red: 0.2, green: 0.21, blue: 0.23))
        case .clock: Circle().fill(Color(red: 0.13, green: 0.16, blue: 0.23))
        case .calculator: Circle().fill(Color(red: 0.98, green: 0.55, blue: 0.2))
        case .files: Circle().fill(Color(red: 0.24, green: 0.47, blue: 0.96))
        }
    }

    @ViewBuilder private var glyph: some View {
        switch app {
        case .phone:
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.42, blue: 0.95))
                .rotationEffect(.degrees(-12))
        case .messages:
            ZStack {
                Circle().stroke(Color(red: 0.12, green: 0.62, blue: 0.24), lineWidth: size * 0.09).frame(width: size * 0.5)
                Image(systemName: "ellipsis.bubble.fill")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.62, blue: 0.24))
            }
        case .contacts:
            ZStack {
                Circle().fill(Color(red: 0.2, green: 0.45, blue: 0.95)).frame(width: size * 0.5)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .browser:
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        case .camera:
            Image(systemName: "camera.fill")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(Color(white: 0.92))
        case .clock:
            ZStack {
                Circle().stroke(Color(red: 0.55, green: 0.8, blue: 1), lineWidth: size * 0.05).frame(width: size * 0.56)
                Rectangle().fill(Color(red: 0.55, green: 0.8, blue: 1)).frame(width: size * 0.05, height: size * 0.2).offset(y: -size * 0.09)
                Rectangle().fill(Color(red: 0.55, green: 0.8, blue: 1)).frame(width: size * 0.16, height: size * 0.05).offset(x: size * 0.07)
            }
        case .calculator:
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        case .files:
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - parts the apps share

/// A system app's top app bar: an optional back arrow, the title, and actions on the right.
struct SystemAppBar<Actions: View>: View {
    let title: String
    var large = false
    var onBack: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium)).frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                if !large {
                    Text(title).font(.system(size: 22, weight: .regular, design: .rounded)).lineLimit(1)
                        .padding(.leading, onBack == nil ? 12 : 0)
                }
                Spacer(minLength: 0)
                actions
            }
            .frame(height: 64)
            .padding(.horizontal, 4)
            if large {
                Text(title)
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .foregroundStyle(Color(uiColor: Material3.onSurface))
    }
}

extension SystemAppBar where Actions == EmptyView {
    init(title: String, large: Bool = false, onBack: (() -> Void)? = nil) {
        self.init(title: title, large: large, onBack: onBack) { EmptyView() }
    }
}

/// An action icon in a top app bar.
struct SystemBarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium)).frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Material 3's floating action button: a rounded square in the primary container, optionally with a label (extended).
struct AndroidFAB: View {
    let icon: String
    var label: String?
    var large = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: large ? 30 : 22, weight: .semibold))
                if let label { Text(label).font(.system(size: 16, weight: .semibold, design: .rounded)) }
            }
            .foregroundStyle(Color(uiColor: Material3.onPrimaryContainer))
            .padding(.horizontal, label == nil ? 0 : 20)
            .frame(minWidth: large ? 96 : 56, minHeight: large ? 96 : 56)
            .background(Color(uiColor: Material3.primaryContainer),
                        in: RoundedRectangle(cornerRadius: large ? 28 : 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .buttonStyle(AndroidSquashStyle())
        .accessibilityLabel(label ?? icon)
    }
}

/// Material 3's navigation bar for an app's own sections.
struct SystemNavigationBar<Tab: Hashable>: View {
    @Binding var selection: Tab
    let items: [(tab: Tab, title: String, icon: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let selected = selection == item.tab
                Button {
                    if !selected {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) { selection = item.tab }
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Capsule().fill(Color(uiColor: Material3.secondaryContainer))
                                .frame(width: selected ? 64 : 24, height: 32)
                                .opacity(selected ? 1 : 0)
                            Image(systemName: item.icon).font(.system(size: 19, weight: selected ? .semibold : .regular))
                        }
                        .frame(height: 32)
                        Text(item.title).font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
                    }
                    .foregroundStyle(Color(uiColor: selected ? Material3.onSurface : Material3.onSurfaceVariant))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Color(uiColor: Material3.surfaceContainer))
    }
}

/// A list row in a system app: a leading view, a title and a line under it, and something at the end.
struct SystemListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, design: .rounded)).foregroundStyle(Color(uiColor: Material3.onSurface)).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant)).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

/// A person's initial in a tonal circle, as Android's apps draw a contact without a photo.
struct AndroidLetterAvatar: View {
    let name: String
    var size: CGFloat = 40
    var image: UIImage?

    private var tint: Material3.Palette {
        // a hash that stays the same from launch to launch (String's hashValue is seeded per run)
        [Material3.Palette.primary, .secondary, .tertiary][name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 3]
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "#")
                    .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.tone(tint, 30)))
                    .frame(width: size, height: size)
                    .background(Color(uiColor: Material3.tone(tint, 88)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// The empty state of a list: a big icon in a tonal circle and a line of text.
struct SystemEmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color(uiColor: Material3.onSecondaryContainer))
                .frame(width: 96, height: 96)
                .background(Color(uiColor: Material3.secondaryContainer), in: Circle())
            Text(text)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// While a system app is open, what Android's back does inside it: return true when it went back a step.
struct SystemBackHandler: ViewModifier {
    let handler: () -> Bool
    @State private var owner = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { AndroidShellState.shared.setAppBack(owner, handler) }
            // only its own: an app opening another sees the new one appear before it disappears
            .onDisappear { AndroidShellState.shared.clearAppBack(owner) }
    }
}

extension View {
    /// Android's back, inside a system app (a page to pop, a dialog to close) before it goes home.
    func onAndroidBack(_ handler: @escaping () -> Bool) -> some View { modifier(SystemBackHandler(handler: handler)) }
}
