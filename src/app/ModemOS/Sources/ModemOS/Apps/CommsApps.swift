import SwiftUI
import Contacts
import MessageUI
import WebKit

// MARK: - Contacts (shared by Phone, Messages and Contacts)

final class ContactsModel: ObservableObject {
    static let shared = ContactsModel()

    struct Person: Identifiable {
        let id: String
        let name: String
        let phones: [String]
        let emails: [String]
        let organization: String
        let thumbnail: Data?

        var initials: String {
            let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
            return letters.isEmpty ? "#" : String(letters).uppercased()
        }
    }

    @Published private(set) var people: [Person] = []
    @Published private(set) var status = CNContactStore.authorizationStatus(for: .contacts)
    private var loaded = false

    var allowed: Bool { status == .authorized || status.rawValue == 4 }

    func load() {
        status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            CNContactStore().requestAccess(for: .contacts) { _, _ in
                DispatchQueue.main.async { self.load() }
            }
            return
        }
        guard allowed, !loaded else { return }
        loaded = true
        DispatchQueue.global(qos: .userInitiated).async {
            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            var found: [Person] = []
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
                found.append(Person(
                    id: contact.identifier,
                    name: name.isEmpty ? "—" : name,
                    phones: contact.phoneNumbers.map { $0.value.stringValue },
                    emails: contact.emailAddresses.map { $0.value as String },
                    organization: contact.organizationName,
                    thumbnail: contact.thumbnailImageData
                ))
            }
            DispatchQueue.main.async {
                self.people = found
                OSLogger.shared.log("Contacts", "Loaded \(found.count) contacts")
            }
        }
    }

    static func call(_ number: String) {
        let digits = number.filter { "0123456789+*#".contains($0) }
        openURL("tel://\(digits)")
    }
}

private struct Avatar: View {
    let person: ContactsModel.Person
    let size: CGFloat

    var body: some View {
        Group {
            if let data = person.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(color)
                    Text(person.initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var color: Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]
        return palette[abs(person.name.hashValue) % palette.count]
    }
}

/// A searchable contact list, used by three apps.
private struct ContactList: View {
    let title: String
    let onSelect: (ContactsModel.Person) -> Void

    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var contacts = ContactsModel.shared
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            AppTitle(title: title, subtitle: contacts.people.isEmpty ? nil : "\(contacts.people.count) " + os.t("contacts"))
            if !contacts.allowed && contacts.status != .notDetermined {
                PermissionView(
                    symbol: "person.2.fill",
                    title: "Contacts access is off",
                    message: "Allow access to your contacts to see them here.",
                    denied: true,
                    request: {}
                )
            } else {
                OSSearchField(prompt: "Search", text: $search)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                List(filtered) { person in
                    Button {
                        onSelect(person)
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(person: person, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name).foregroundColor(.primary)
                                if let phone = person.phones.first {
                                    Text(phone).font(.system(size: 13)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .osListRow()
                }
                .osList()
            }
        }
        .onAppear { contacts.load() }
    }

    private var filtered: [ContactsModel.Person] {
        guard !search.isEmpty else { return contacts.people }
        return contacts.people.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.phones.contains { $0.contains(search) }
        }
    }
}

private struct ContactDetail: View {
    let person: ContactsModel.Person
    let onBack: () -> Void
    var onMessage: ((String) -> Void)?

    @EnvironmentObject private var os: OSSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)

                Avatar(person: person, size: 110)
                Text(person.name).font(.system(size: 28, weight: .bold))
                if !person.organization.isEmpty {
                    Text(person.organization).foregroundColor(.secondary)
                }

                HStack(spacing: 14) {
                    action("phone.fill", "Call", enabled: !person.phones.isEmpty) {
                        if let phone = person.phones.first { ContactsModel.call(phone) }
                    }
                    action("message.fill", "Message", enabled: !person.phones.isEmpty) {
                        if let phone = person.phones.first {
                            if let onMessage = onMessage { onMessage(phone) } else { openURL("sms:\(phone)") }
                        }
                    }
                    action("envelope.fill", "Email", enabled: !person.emails.isEmpty) {
                        if let email = person.emails.first { openURL("mailto:\(email)") }
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    ForEach(person.phones, id: \.self) { phone in
                        Card {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(os.t("Phone")).font(.system(size: 13)).foregroundColor(.secondary)
                                    Text(phone).font(.system(size: 17))
                                }
                                Spacer()
                                Button { ContactsModel.call(phone) } label: { Image(systemName: "phone.fill") }
                            }
                        }
                    }
                    ForEach(person.emails, id: \.self) { email in
                        Card {
                            VStack(alignment: .leading) {
                                Text(os.t("Email")).font(.system(size: 13)).foregroundColor(.secondary)
                                Text(email).font(.system(size: 17))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func action(_ symbol: String, _ title: String, enabled: Bool, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(os.t(title)).font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.osAccent.opacity(0.14)))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

struct ContactsApp: View {
    @State private var selected: ContactsModel.Person?

    var body: some View {
        ZStack {
            ContactList(title: "Contacts") { person in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { selected = person }
            }
            if let person = selected {
                ContactDetail(person: person) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { selected = nil }
                }
                .background(Color.osPage)
                .transition(.move(edge: .trailing))
            }
        }
    }
}

// MARK: - Phone

struct PhoneApp: View {
    @EnvironmentObject private var os: OSSettings
    @State private var tab = 0
    @State private var number = ""
    @State private var selected: ContactsModel.Person?

    private let keys: [(String, String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", ""),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if tab == 0 {
                    keypad
                } else {
                    ContactList(title: "Contacts") { person in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { selected = person }
                    }
                    if let person = selected {
                        ContactDetail(person: person) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { selected = nil }
                        }
                        .background(Color.osPage)
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            .frame(maxHeight: .infinity)

            OSTabBar(selection: $tab, items: [(0, "Keypad", "circle.grid.3x3.fill"), (1, "Contacts", "person.2.fill")])
        }
    }

    private var keypad: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(number.isEmpty ? " " : number)
                .font(.system(size: 38, weight: .light))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 30)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 24), count: 3), spacing: 16) {
                ForEach(keys, id: \.0) { key in
                    Button {
                        Haptics.tap()
                        if number.count < 20 { number += key.0 }
                    } label: {
                        VStack(spacing: 0) {
                            Text(key.0).font(.system(size: 34, weight: .regular))
                            Text(key.1).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .simultaneousGesture(
                        LongPressGesture().onEnded { _ in
                            if key.0 == "0" { number = String(number.dropLast()) + "+" }
                        }
                    )
                }
            }
            HStack(spacing: 24) {
                Color.clear.frame(width: 80, height: 80)
                Button {
                    guard !number.isEmpty else { return }
                    OSLogger.shared.log("Phone", "Calling \(number)")
                    ContactsModel.call(number)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Color.green))
                }
                .buttonStyle(PressScaleStyle())
                Button {
                    if !number.isEmpty { number.removeLast() }
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                        .frame(width: 80, height: 80)
                }
                .opacity(number.isEmpty ? 0 : 1)
            }
            Spacer()
        }
    }
}

// MARK: - Messages

/// The system message composer (the only way an app may send an SMS / iMessage).
struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            OSLogger.shared.log("Messages", result == .sent ? "Message sent" : "Composer closed")
            onDone()
        }
    }
}

struct MessagesApp: View {
    @State private var composing: [String]?

    var body: some View {
        ContactList(title: "Messages") { person in
            if let phone = person.phones.first { compose([phone]) }
        }
        .overlay(alignment: .bottomTrailing) {
            OSFab(symbol: "square.and.pencil") { compose([]) }
                .padding(22)
        }
        .sheet(isPresented: Binding(get: { composing != nil }, set: { if !$0 { composing = nil } })) {
            MessageComposer(recipients: composing ?? []) { composing = nil }
                .ignoresSafeArea()
        }
    }

    private func compose(_ recipients: [String]) {
        if MFMessageComposeViewController.canSendText() {
            composing = recipients
        } else {
            OSLogger.shared.log("Messages", "This device cannot send messages", level: .warn)
            openURL("sms:\(recipients.first ?? "")")
        }
    }
}

// MARK: - Browser

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let web: WKWebView
    @Published var address = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private var observers: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        super.init()
        web.navigationDelegate = self
        observers = [
            web.observe(\.estimatedProgress) { [weak self] web, _ in
                DispatchQueue.main.async { self?.progress = web.estimatedProgress }
            },
            web.observe(\.url) { [weak self] web, _ in
                DispatchQueue.main.async {
                    self?.address = web.url?.absoluteString ?? ""
                    self?.canGoBack = web.canGoBack
                    self?.canGoForward = web.canGoForward
                }
            },
        ]
        go("https://www.google.com")
    }

    func go(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if trimmed.contains(".") && !trimmed.contains(" ") {
            url = URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "https://www.google.com/search?q=\(query)")
        }
        if let url = url {
            OSLogger.shared.log("Browser", "Load \(url.host ?? url.absoluteString)")
            web.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        OSLogger.shared.log("Browser", error.localizedDescription, level: .warn)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        OSLogger.shared.log("Browser", error.localizedDescription, level: .warn)
    }
}

private struct WebView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var browser = BrowserModel()
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            WebView(web: browser.web)
                .overlay(alignment: .top) {
                    if browser.progress < 1 {
                        ProgressView(value: browser.progress)
                            .tint(.accentColor)
                    }
                }

            HStack(spacing: 14) {
                Button { browser.web.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack)
                Button { browser.web.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward)
                TextField(os.t("Search or type URL"), text: $browser.address)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($editing)
                    .submitLabel(.go)
                    .onSubmit { browser.go(browser.address) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glass(Capsule(), tint: 1.5)
                Button { browser.web.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Notes

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var edited: Date

    var title: String {
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty ? "New note" : first
    }
}

final class NotesStore: ObservableObject {
    @Published var notes: [Note] = [] {
        didSet { save() }
    }

    init() {
        if let data = OSSettings.store.data(forKey: "notes"),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            OSSettings.store.set(data, forKey: "notes")
        }
    }
}

struct NotesApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var store = NotesStore()
    @State private var editing: UUID?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                AppTitle(title: "Notes", subtitle: "\(store.notes.count) " + os.t("notes"))
                if store.notes.isEmpty {
                    Spacer()
                    Text(os.t("No notes")).foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(store.notes.sorted { $0.edited > $1.edited }) { note in
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { editing = note.id }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(os.t(note.title)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                        Text(note.text).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(5)
                                        Spacer(minLength: 0)
                                        Text(DateFormatter.localizedString(from: note.edited, dateStyle: .short, timeStyle: .short))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.yellow.opacity(0.18)))
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.notes.removeAll { $0.id == note.id }
                                    } label: {
                                        Label(os.t("Delete"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                OSFab(symbol: "plus") {
                    let note = Note(text: "", edited: Date())
                    store.notes.append(note)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { editing = note.id }
                }
                .padding(22)
            }

            if let id = editing, let index = store.notes.firstIndex(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            if store.notes[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                store.notes.remove(at: index)
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { editing = nil }
                        } label: {
                            Label(os.t("Notes"), systemImage: "chevron.left").font(.system(size: 17, weight: .semibold))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    TextEditor(text: Binding(
                        get: { store.notes[index].text },
                        set: {
                            store.notes[index].text = $0
                            store.notes[index].edited = Date()
                        }
                    ))
                    .font(.system(size: 17))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                }
                .background(Color.osPage)
                .transition(.move(edge: .trailing))
            }
        }
    }
}
