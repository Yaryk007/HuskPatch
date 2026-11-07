import SwiftUI

/// The parts every ModemOS screen is built from. Each one draws itself for the chosen look.

/// A switch: Material's, or the system's in the accent colour (real glass once Liquid Glass is on).
struct OSToggleStyle: ToggleStyle {
    @ObservedObject private var os = OSSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        if os.design == .expressive {
            Toggle(configuration).toggleStyle(ExpressiveSwitchStyle())
        } else {
            Toggle(configuration).toggleStyle(.switch).tint(os.palette.primary)
        }
    }
}

/// How much a button matters.
enum OSButtonKind {
    case filled, tonal, plain
}

/// A button: Expressive's shape-morphing pill, or a glass capsule.
struct OSButtonStyle: ButtonStyle {
    var kind: OSButtonKind = .filled
    @ObservedObject private var os = OSSettings.shared

    init(_ kind: OSButtonKind = .filled) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let p = os.palette
        return configuration.label
            .font(.system(size: 16, weight: .semibold, design: os.design == .expressive ? .rounded : .default))
            .foregroundColor(foreground(p))
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .background {
                switch (kind, os.design) {
                case (.filled, _): shape.fill(p.primary)
                case (.tonal, .expressive): shape.fill(p.secondaryContainer)
                case (.tonal, .liquidGlass): Glass(shape: shape)
                case (.plain, _): Color.clear
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: configuration.isPressed && os.design == .expressive ? 14 : 24, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }

    private func foreground(_ p: OSPalette) -> Color {
        switch kind {
        case .filled: return p.onPrimary
        case .tonal: return os.design == .expressive ? p.onSecondaryContainer : p.onSurface
        case .plain: return p.primary
        }
    }
}

/// A slider. Material's is a thick track with a slim handle; glass keeps the system's.
struct OSSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var symbol: String?

    @EnvironmentObject private var os: OSSettings
    @State private var held = false

    var body: some View {
        if os.design == .expressive {
            GeometryReader { geo in
                let span = range.upperBound - range.lowerBound
                let fraction = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
                let handle = max(8, min(geo.size.width - 8, geo.size.width * fraction))
                let p = os.palette

                ZStack(alignment: .leading) {
                    Capsule().fill(p.secondaryContainer)
                    Capsule().fill(p.primary).frame(width: max(0, handle - 5))
                    Capsule()
                        .fill(p.primary)
                        .frame(width: held ? 3 : 4, height: 44)
                        .offset(x: handle - 2)
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(fraction > 0.14 ? p.onPrimary : p.onSurfaceVariant)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 36)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            held = true
                            let x = min(1, max(0, drag.location.x / max(1, geo.size.width)))
                            value = range.lowerBound + Double(x) * span
                        }
                        .onEnded { _ in
                            held = false
                            Haptics.tap()
                        }
                )
            }
            .frame(height: 44)
        } else {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundColor(.secondary)
                }
                Slider(value: $value, in: range).tint(os.palette.primary)
            }
        }
    }
}

/// A row of choices in one capsule; the chosen one is filled.
struct OSSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        let p = os.palette
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { selection = option.value }
                } label: {
                    Text(os.t(option.title))
                        .font(.system(size: 14, weight: on ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundColor(on ? p.onPrimary : p.onSurface)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(on ? p.primary : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glass(Capsule(), tint: 1.5)
    }
}

/// A search box.
struct OSSearchField: View {
    let prompt: String
    @Binding var text: String

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
            TextField(os.t(prompt), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16))
        .foregroundColor(os.palette.onSurfaceVariant)
        .padding(.horizontal, 18)
        .frame(height: 50)
        .glass(Capsule(), tint: 2)
    }
}

/// A page of an app: a large title that sits under the status bar, then its content.
struct OSPage<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// Set on a page pushed from another: shows the back arrow.
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 8) {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(os.palette.onSurface)
                                .frame(width: 44, height: 44)
                                .glass(Circle(), tint: 1.5)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                    Spacer()
                    trailing
                }
                .frame(minHeight: onBack == nil ? 0 : 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(os.t(title))
                        .font(os.display(36))
                        .foregroundColor(os.palette.onSurface)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 15)).foregroundColor(os.palette.onSurfaceVariant)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)

                content
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
    }
}

extension OSPage where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, onBack: onBack, trailing: { EmptyView() }, content: content)
    }
}

/// Rows that belong together. Android 16's settings: separate rows that share one rounded outline; with glass, one pane.
struct OSGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(os.t(title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(os.design == .expressive ? os.palette.primary : os.palette.onSurfaceVariant)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
            VStack(spacing: os.design == .expressive ? 2 : 0) { content }
                .padding(.top, os.design == .expressive ? 0 : -0.5)
                .background {
                    if os.design == .liquidGlass {
                        Glass(shape: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

/// A round icon at the start of a row.
struct OSRowIcon: View {
    let symbol: String
    let color: Color

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        let colors = OSPalette.iconColors(for: color, dark: os.theme == .dark)
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(os.design == .expressive ? colors.glyph : .white)
            .frame(width: 38, height: 38)
            .background(
                Circle().fill(os.design == .expressive ? colors.fill : color)
            )
    }
}

/// The body of a row in a group: what the row's kind adds goes in `trailing`.
struct OSRow<Trailing: View>: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    var subtitle: String?
    /// The text is already in the system's language (a device name, a number).
    var verbatim = false
    @ViewBuilder var trailing: Trailing

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        HStack(spacing: 14) {
            if let symbol { OSRowIcon(symbol: symbol, color: color) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim ? title : os.t(title))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(os.palette.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(os.palette.onSurfaceVariant)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .modifier(OSRowSurface(indented: symbol != nil))
        .contentShape(Rectangle())
    }
}

extension OSRow where Trailing == EmptyView {
    init(symbol: String? = nil, color: Color = .gray, title: String, subtitle: String? = nil, verbatim: Bool = false) {
        self.init(symbol: symbol, color: color, title: title, subtitle: subtitle, verbatim: verbatim, trailing: { EmptyView() })
    }
}

/// A row's own background in Material, and the hairline above it in a glass pane.
struct OSRowSurface: ViewModifier {
    var indented = true
    @EnvironmentObject private var os: OSSettings

    func body(content: Content) -> some View {
        if os.design == .expressive {
            content.background(os.palette.surfaceHigh.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
        } else {
            content.overlay(alignment: .top) {
                Rectangle()
                    .fill(os.palette.onSurface.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.leading, indented ? 68 : 16)
            }
        }
    }
}

/// A row with a value on the right, like "Software version  2.0".
struct OSValueRow: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    let value: String

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        OSRow(symbol: symbol, color: color, title: title) {
            Text(value)
                .font(.system(size: 15))
                .foregroundColor(os.palette.onSurfaceVariant)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A row with a switch.
struct OSToggleRow: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        OSRow(symbol: symbol, color: color, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(OSToggleStyle())
        }
    }
}

/// A row that opens a page.
struct OSLinkRow<Destination: View>: View {
    var symbol: String
    var color: Color
    let title: String
    var subtitle: String?
    @ViewBuilder var destination: Destination

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        NavigationLink {
            OSPushedPage { destination }
        } label: {
            OSRow(symbol: symbol, color: color, title: title, subtitle: subtitle)
        }
        .buttonStyle(PressDimStyle())
    }
}

/// A pushed page: the app's background, with the system's navigation bar out of the way.
struct OSPushedPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            OSAppBackground().ignoresSafeArea()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// An app's sections along the bottom: Material's navigation bar, or a floating glass capsule.
struct OSTabBar<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, title: String, symbol: String)]

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        let p = os.palette
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                let on = item.value == selection
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) { selection = item.value }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(on ? (os.design == .expressive ? p.onSecondaryContainer : p.primary) : p.onSurfaceVariant)
                            .frame(width: 58, height: 30)
                            .background(Capsule().fill(on && os.design == .expressive ? p.secondaryContainer : Color.clear))
                        Text(os.t(item.title))
                            .font(.system(size: 11, weight: on ? .bold : .medium))
                            .foregroundColor(on && os.design == .liquidGlass ? p.primary : p.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background {
            if os.design == .liquidGlass {
                Glass(shape: Capsule())
            } else {
                p.surfaceContainer
            }
        }
        .padding(.horizontal, os.design == .liquidGlass ? 14 : 0)
        .padding(.bottom, os.design == .liquidGlass ? 6 : 0)
    }
}

/// Android's floating action button.
struct OSFab: View {
    let symbol: String
    let action: () -> Void

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(os.design == .expressive ? os.palette.onPrimaryContainer : os.palette.onSurface)
                .frame(width: 60, height: 60)
                .background {
                    if os.design == .expressive {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(os.palette.primaryContainer)
                    } else {
                        Glass(shape: Circle())
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
    }
}

extension View {
    /// A List's look: the page shows through, and rows take the system's surface.
    func osList() -> some View {
        listStyle(.insetGrouped).scrollContentBackground(.hidden)
    }

    /// A row in a List.
    func osListRow() -> some View {
        modifier(OSListRowSurface())
    }
}

private struct OSListRowSurface: ViewModifier {
    @EnvironmentObject private var os: OSSettings

    func body(content: Content) -> some View {
        content.listRowBackground(os.design == .expressive ? os.palette.surfaceHigh : os.palette.onSurface.opacity(0.08))
    }
}
