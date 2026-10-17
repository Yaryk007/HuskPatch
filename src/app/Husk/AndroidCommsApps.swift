// SPDX-License-Identifier: GPL-2.0-or-later
import Contacts
import ContactsUI
import MessageUI
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's Phone, Contacts and Messaging, as LineageOS 22 lays them out (AOSP Dialer, Contacts and
/// Messaging). The people are the iPhone's contacts. A call is placed by iOS (the tel: link asks first), a text goes through
/// iOS's message sheet; what was called and sent from here is remembered here, so Recents and the conversations fill up.

// MARK: - contacts

@MainActor
final class AndroidContactsStore: ObservableObject {
    static let shared = AndroidContactsStore()

    struct Person: Identifiable, Hashable {
        let id: String
        let name: String
        let phones: [String]
        let emails: [String]
        let image: Data?
    }

    @Published private(set) var people: [Person] = []
    @Published private(set) var status = CNContactStore.authorizationStatus(for: .contacts)
    private var loaded = false

    var allowed: Bool {
        if status == .authorized { return true }
        if #available(iOS 18, *), status == .limited { return true }
        return false
    }

    func load(force: Bool = false) async {
        if loaded && !force { return }
        let store = CNContactStore()
        if status == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
            status = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard allowed else { return }
        let found = await Task.detached(priority: .userInitiated) { () -> [Person] in
            let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                           CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor,
                                           CNContactThumbnailImageDataKey as CNKeyDescriptor]
            var out: [Person] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            try? CNContactStore().enumerateContacts(with: request) { c, _ in
                let name = CNContactFormatter.string(from: c, style: .fullName) ?? c.phoneNumbers.first?.value.stringValue ?? "No name"
                out.append(Person(id: c.identifier, name: name, phones: c.phoneNumbers.map { $0.value.stringValue },
                                  emails: c.emailAddresses.map { $0.value as String }, image: c.thumbnailImageData))
            }
            return out
        }.value
        people = found
        loaded = true
    }

    func person(forNumber number: String) -> Person? {
        let digits = AndroidComms.digits(number)
        guard digits.count >= 4 else { return nil }
        return people.first { $0.phones.contains { AndroidComms.digits($0).hasSuffix(String(digits.suffix(9))) } }
    }
}

enum AndroidComms {
    static func digits(_ s: String) -> String { s.filter { $0.isNumber } }

    /// iOS places the call (and asks first): the number as a tel: link, # and * escaped.
    @MainActor static func call(_ number: String, name: String? = nil) {
        let dial = number.filter { "0123456789+*#,".contains($0) }
        guard !dial.isEmpty,
              let url = URL(string: "tel:" + (dial.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "+,"))) ?? dial))
        else { return }
        AndroidCallLog.add(number: number, name: name)
        UIApplication.shared.open(url)
    }

    @MainActor static func email(_ address: String) {
        if let url = URL(string: "mailto:" + address) { UIApplication.shared.open(url) }
    }
}

/// The calls placed from the Phone app, newest first.
enum AndroidCallLog {
    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var number: String
        var name: String?
        var date = Date()
    }
    static let key = "huskpatch.phone.recents"

    static func load() -> [Entry] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }
    static func add(number: String, name: String?) {
        var all = load()
        all.insert(Entry(number: number, name: name), at: 0)
        if let data = try? JSONEncoder().encode(Array(all.prefix(200))) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// The search pill at the top of Phone and Contacts.
private struct CommsSearchPill: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium))
            TextField(prompt, text: $text)
                .font(.system(size: 16, design: .rounded))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// When the iPhone's contacts are not shared with HuskPatch.
private struct ContactsAccessPrompt: View {
    @ObservedObject private var store = AndroidContactsStore.shared

    var body: some View {
        VStack(spacing: 16) {
            SystemEmptyState(icon: "person.crop.circle.badge.questionmark",
                             text: store.status == .notDetermined
                                ? "Allow access to show the contacts on this iPhone."
                                : "HuskPatch can't see your contacts. Allow access in iOS Settings › HuskPatch › Contacts.")
            Button(store.status == .notDetermined ? "Allow" : "Open iOS Settings") {
                if store.status == .notDetermined {
                    Task { await store.load(force: true) }
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.expressive(.filled))
        }
    }
}

private struct ContactList: View {
    let people: [AndroidContactsStore.Person]
    let onTap: (AndroidContactsStore.Person) -> Void

    private var sections: [(String, [AndroidContactsStore.Person])] {
        let groups: [String: [AndroidContactsStore.Person]] = Dictionary(grouping: people) { (p: AndroidContactsStore.Person) -> String in
            guard let c = p.name.first, c.isLetter else { return "#" }
            return String(c).uppercased()
        }
        // letters in order, "#" last
        let keys = groups.keys.sorted { (a: String, b: String) -> Bool in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }
        return keys.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
            ForEach(sections, id: \.0) { letter, group in
                HStack(alignment: .top, spacing: 0) {
                    Text(letter)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.primary))
                        .frame(width: 36, alignment: .center)
                        .padding(.top, 22)
                    VStack(spacing: 2) {
                        ForEach(group) { p in
                            Button { onTap(p) } label: {
                                SystemListRow(title: p.name) {
                                    AndroidLetterAvatar(name: p.name, image: p.image.flatMap(UIImage.init(data:)))
                                } trailing: { EmptyView() }
                            }
                            .buttonStyle(AndroidRippleStyle())
                            .background(Color(uiColor: Material3.surfaceContainerLow))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// One person: the big avatar and name, Call / Text / Email, then each number and address.
private struct ContactDetail: View {
    let person: AndroidContactsStore.Person
    let onBack: () -> Void
    var onText: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: "", onBack: onBack)
            ScrollView {
                VStack(spacing: 18) {
                    AndroidLetterAvatar(name: person.name, size: 120, image: person.image.flatMap(UIImage.init(data:)))
                    Text(person.name).font(.system(size: 30, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 28) {
                        action("phone", "Call", enabled: !person.phones.isEmpty) { AndroidComms.call(person.phones[0], name: person.name) }
                        action("message", "Text", enabled: !person.phones.isEmpty) { onText?(person.phones[0]) }
                        action("envelope", "Email", enabled: !person.emails.isEmpty) { AndroidComms.email(person.emails[0]) }
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contact info").font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color(uiColor: Material3.surfaceContainerLow))
                        ForEach(person.phones, id: \.self) { n in
                            infoRow("phone", n, "Mobile") { AndroidComms.call(n, name: person.name) } trailing: {
                                Button { onText?(n) } label: { Image(systemName: "message") }.buttonStyle(.plain)
                            }
                        }
                        ForEach(person.emails, id: \.self) { e in
                            infoRow("envelope", e, "Email") { AndroidComms.email(e) } trailing: { EmptyView() }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: Material3.surface))
    }

    private func action(_ icon: String, _ title: String, enabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                    .frame(width: 64, height: 40)
                    .background(Color(uiColor: Material3.secondaryContainer), in: Capsule())
                Text(title).font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .opacity(enabled ? 1 : 0.38)
        }
        .buttonStyle(AndroidSquashStyle())
        .disabled(!enabled)
    }

    private func infoRow<T: View>(_ icon: String, _ value: String, _ kind: String, _ run: @escaping () -> Void,
                                  @ViewBuilder trailing: () -> T) -> some View {
        Button(action: run) {
            SystemListRow(title: value, subtitle: kind) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 40)
            } trailing: { trailing() }
            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
        }
        .buttonStyle(AndroidRippleStyle())
        .background(Color(uiColor: Material3.surfaceContainerLow))
    }
}

// MARK: - Contacts

struct AndroidContactsApp: View {
    @ObservedObject private var store = AndroidContactsStore.shared
    @State private var query = ""
    @State private var open: AndroidContactsStore.Person?
    @State private var creating = false

    private var shown: [AndroidContactsStore.Person] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? store.people : store.people.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.phones.contains { AndroidComms.digits($0).contains(AndroidComms.digits(q)) && !AndroidComms.digits(q).isEmpty }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                CommsSearchPill(text: $query, prompt: "Search contacts")
                if !store.allowed {
                    ContactsAccessPrompt()
                } else if store.people.isEmpty {
                    SystemEmptyState(icon: "person.2", text: "No contacts yet")
                } else {
                    ScrollView { ContactList(people: shown) { p in withAnimation(.snappy) { open = p } }.padding(.bottom, 96) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if store.allowed {
                    AndroidFAB(icon: "plus") { creating = true }.padding(20)
                }
            }

            if let p = open {
                ContactDetail(person: p, onBack: { withAnimation(.snappy) { open = nil } }) { n in
                    AndroidShellState.shared.launch(.system(.messages))
                    AndroidMessagingRoute.shared.compose(to: n, name: p.name)
                }
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .background(Color(uiColor: Material3.surface))
        .task { await store.load() }
        .sheet(isPresented: $creating, onDismiss: { Task { await store.load(force: true) } }) { NewContactSheet() }
        .onAndroidBack {
            if open != nil { withAnimation(.snappy) { open = nil }; return true }
            return false
        }
    }
}

/// iOS's new-contact form, so a contact made here is a real one on the iPhone.
private struct NewContactSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(forNewContact: nil)
        vc.contactStore = CNContactStore()
        vc.delegate = context.coordinator
        return UINavigationController(rootViewController: vc)
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) { dismiss() }
    }
}

// MARK: - Phone

struct AndroidDialerApp: View {
    enum Tab: Hashable { case favorites, recents, contacts }

    @ObservedObject private var store = AndroidContactsStore.shared
    @State private var tab = Tab.recents
    @State private var query = ""
    @State private var dialpad = false
    @State private var recents = AndroidCallLog.load()
    @State private var open: AndroidContactsStore.Person?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                CommsSearchPill(text: $query, prompt: "Search contacts & places")
                Group {
                    if !query.isEmpty {
                        ScrollView { ContactList(people: matches) { p in open = p } }
                    } else {
                        switch tab {
                        case .favorites: favorites
                        case .recents: recentsList
                        case .contacts:
                            if store.allowed { ScrollView { ContactList(people: store.people) { p in open = p }.padding(.bottom, 96) } }
                            else { ContactsAccessPrompt() }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                SystemNavigationBar(selection: $tab, items: [(.favorites, "Favorites", "star"), (.recents, "Recents", "clock"),
                                                              (.contacts, "Contacts", "person.2")])
            }
            .overlay(alignment: .bottomTrailing) {
                AndroidFAB(icon: "circle.grid.3x3.fill") { withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { dialpad = true } }
                    .padding(.trailing, 20)
                    .padding(.bottom, 96)
            }

            if dialpad {
                Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { closePad() }
                VStack { Spacer(); AndroidDialpad { n in AndroidComms.call(n, name: store.person(forNumber: n)?.name); recents = AndroidCallLog.load() } }
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }

            if let p = open {
                ContactDetail(person: p, onBack: { withAnimation(.snappy) { open = nil } }) { n in
                    AndroidShellState.shared.launch(.system(.messages))
                    AndroidMessagingRoute.shared.compose(to: n, name: p.name)
                }
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .background(Color(uiColor: Material3.surface))
        .task { await store.load() }
        .onAppear { recents = AndroidCallLog.load() }
        .onAndroidBack {
            if open != nil { withAnimation(.snappy) { open = nil }; return true }
            if dialpad { closePad(); return true }
            if !query.isEmpty { query = ""; return true }
            return false
        }
    }

    private func closePad() { withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { dialpad = false } }

    private var matches: [AndroidContactsStore.Person] {
        store.people.filter { $0.name.localizedCaseInsensitiveContains(query) || (!AndroidComms.digits(query).isEmpty && $0.phones.contains { AndroidComms.digits($0).contains(AndroidComms.digits(query)) }) }
    }

    /// The people called most, as round tiles.
    private var favorites: some View {
        let counts = Dictionary(grouping: recents, by: { AndroidComms.digits($0.number) }).mapValues(\.count)
        let top = counts.sorted { $0.value > $1.value }.prefix(12).compactMap { key, _ in recents.first { AndroidComms.digits($0.number) == key } }
        return Group {
            if top.isEmpty {
                SystemEmptyState(icon: "star", text: "No favorites yet. The people you call most show here.")
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                        ForEach(top) { e in
                            Button { AndroidComms.call(e.number, name: e.name); recents = AndroidCallLog.load() } label: {
                                VStack(spacing: 8) {
                                    AndroidLetterAvatar(name: e.name ?? e.number, size: 84)
                                    Text(e.name ?? e.number).font(.system(size: 14, design: .rounded)).lineLimit(1)
                                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                                }
                            }
                            .buttonStyle(AndroidSquashStyle())
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var recentsList: some View {
        Group {
            if recents.isEmpty {
                SystemEmptyState(icon: "phone.arrow.up.right", text: "No recent calls. Calls you make from Phone show here.")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(recents) { e in
                            Button { AndroidComms.call(e.number, name: e.name); recents = AndroidCallLog.load() } label: {
                                SystemListRow(title: e.name ?? e.number,
                                              subtitle: "↗ " + e.date.formatted(.relative(presentation: .named))) {
                                    AndroidLetterAvatar(name: e.name ?? e.number)
                                } trailing: {
                                    Image(systemName: "phone").foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                }
                            }
                            .buttonStyle(AndroidRippleStyle())
                            .background(Color(uiColor: Material3.surfaceContainerLow))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 96)
                    Button("Clear call history") { AndroidCallLog.clear(); recents = [] }
                        .buttonStyle(.expressive(.text))
                        .padding(.bottom, 96)
                }
            }
        }
    }
}

/// The dialpad: the number, twelve keys with their letters, and the green call button.
private struct AndroidDialpad: View {
    let onCall: (String) -> Void
    @State private var number = ""

    private let keys: [(String, String)] = [("1", ""), ("2", "ABC"), ("3", "DEF"), ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
                                            ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"), ("*", ""), ("0", "+"), ("#", "")]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer().frame(width: 44)
                Text(number.isEmpty ? " " : number)
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                Button { if !number.isEmpty { number.removeLast() } } label: {
                    Image(systemName: "delete.left").font(.system(size: 22)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .opacity(number.isEmpty ? 0 : 1)
                .simultaneousGesture(LongPressGesture().onEnded { _ in number = "" })
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.top, 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(keys, id: \.0) { k, letters in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        number.append(k)
                    } label: {
                        VStack(spacing: 0) {
                            Text(k).font(.system(size: 30, weight: .regular, design: .rounded))
                            Text(letters.isEmpty ? " " : letters).font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        }
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .frame(width: 84, height: 64)
                        .background(Color(uiColor: Material3.surfaceContainerHighest), in: Capsule())
                    }
                    .buttonStyle(AndroidSquashStyle())
                    .simultaneousGesture(LongPressGesture().onEnded { _ in if k == "0" { number.append("+") } })
                }
            }
            .padding(.horizontal, 24)

            Button { if !number.isEmpty { onCall(number) } } label: {
                Image(systemName: "phone.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 112, height: 64)
                    .background(Color(red: 0.12, green: 0.62, blue: 0.3), in: Capsule())
            }
            .buttonStyle(AndroidSquashStyle())
            .padding(.bottom, 16)
            .accessibilityLabel("Call")
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: Material3.surfaceContainer), in: StackedCorners(top: 28, bottom: 0))
    }
}

// MARK: - Messaging

/// The conversations kept on this side: what was sent from Messaging (iOS does not let an app read texts).
enum AndroidMessageStore {
    struct Message: Codable, Hashable, Identifiable {
        var id = UUID()
        var text: String
        var date = Date()
    }
    struct Thread: Codable, Hashable, Identifiable {
        var id: String { number }
        var number: String
        var name: String?
        var messages: [Message]
    }
    static let key = "huskpatch.messages.threads"

    static func load() -> [Thread] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Thread].self, from: $0) } ?? []
    }
    static func save(_ threads: [Thread]) {
        if let data = try? JSONEncoder().encode(threads) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func append(_ text: String, to number: String, name: String?) {
        var all = load()
        var t = all.first { $0.number == number } ?? Thread(number: number, name: name, messages: [])
        all.removeAll { $0.number == number }
        t.messages.append(Message(text: text))
        if t.name == nil { t.name = name }
        all.insert(t, at: 0)
        save(all)
    }
}

/// Where Messaging should open next: Contacts and Phone send a person here to text them.
@MainActor
final class AndroidMessagingRoute: ObservableObject {
    static let shared = AndroidMessagingRoute()
    @Published var pending: (number: String, name: String?)?
    func compose(to number: String, name: String?) { pending = (number, name) }
}

struct AndroidMessagingApp: View {
    @ObservedObject private var route = AndroidMessagingRoute.shared
    @ObservedObject private var contacts = AndroidContactsStore.shared
    @State private var threads = AndroidMessageStore.load()
    @State private var open: AndroidMessageStore.Thread?
    @State private var newChat = false
    @State private var to = ""

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SystemAppBar(title: "Messaging", large: true) {
                    SystemBarButton(icon: "magnifyingglass", label: "Search") { newChat = true }
                }
                if threads.isEmpty {
                    SystemEmptyState(icon: "message", text: "Once you start a new conversation, you'll see it listed here")
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(threads) { t in
                                Button { withAnimation(.snappy) { open = t } } label: {
                                    SystemListRow(title: t.name ?? t.number, subtitle: t.messages.last.map { "You: " + $0.text }) {
                                        AndroidLetterAvatar(name: t.name ?? t.number, size: 48)
                                    } trailing: {
                                        Text(t.messages.last.map { short($0.date) } ?? "")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                    }
                                }
                                .buttonStyle(AndroidRippleStyle())
                            }
                        }
                        .padding(.bottom, 96)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                AndroidFAB(icon: "message", label: "Start chat") { withAnimation(.snappy) { newChat = true } }.padding(20)
            }

            if newChat {
                newChatPage.transition(.move(edge: .trailing)).zIndex(1)
            }
            if let t = open {
                AndroidConversation(thread: t, onBack: { withAnimation(.snappy) { open = nil }; threads = AndroidMessageStore.load() })
                    .transition(.move(edge: .trailing)).zIndex(2)
            }
        }
        .background(Color(uiColor: Material3.surface))
        .onAppear(perform: takeRoute)
        .onChange(of: route.pending?.number) { _ in takeRoute() }
        .onAndroidBack {
            if open != nil { withAnimation(.snappy) { open = nil }; threads = AndroidMessageStore.load(); return true }
            if newChat { withAnimation(.snappy) { newChat = false }; return true }
            return false
        }
    }

    private func takeRoute() {
        guard let p = route.pending else { return }
        route.pending = nil
        newChat = false
        open = threads.first { $0.number == p.number } ?? AndroidMessageStore.Thread(number: p.number, name: p.name, messages: [])
    }

    private func short(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : d.formatted(.dateTime.month(.abbreviated).day())
    }

    private var newChatPage: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: "New conversation", onBack: { withAnimation(.snappy) { newChat = false } })
            HStack(spacing: 10) {
                Text("To").foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                TextField("Type name, phone number, or email", text: $to)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit { start(number: to, name: nil) }
            }
            .font(.system(size: 16, design: .rounded))
            .padding(.horizontal, 20).frame(height: 56)
            .background(Color(uiColor: Material3.surfaceContainerHigh))
            ScrollView {
                if !AndroidComms.digits(to).isEmpty {
                    Button { start(number: to, name: nil) } label: {
                        SystemListRow(title: "Send to \(to)") {
                            Image(systemName: "number").frame(width: 40, height: 40)
                                .background(Color(uiColor: Material3.secondaryContainer), in: Circle())
                        } trailing: { EmptyView() }
                    }
                    .buttonStyle(AndroidRippleStyle())
                }
                if contacts.allowed {
                    let list = contacts.people.filter { !$0.phones.isEmpty && (to.isEmpty || $0.name.localizedCaseInsensitiveContains(to)) }
                    ContactList(people: list) { p in start(number: p.phones[0], name: p.name) }
                }
            }
        }
        .background(Color(uiColor: Material3.surface))
        .task { await contacts.load() }
    }

    private func start(number: String, name: String?) {
        guard !number.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.snappy) {
            newChat = false
            to = ""
            open = threads.first { $0.number == number } ?? AndroidMessageStore.Thread(number: number, name: name ?? contacts.person(forNumber: number)?.name, messages: [])
        }
    }
}

/// One conversation: the bubbles sent, and the compose bar. Send hands the text to iOS's message sheet.
private struct AndroidConversation: View {
    @State var thread: AndroidMessageStore.Thread
    let onBack: () -> Void
    @State private var draft = ""
    @State private var composing: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: thread.name ?? thread.number, onBack: onBack) {
                SystemBarButton(icon: "phone", label: "Call") { AndroidComms.call(thread.number, name: thread.name) }
            }
            .background(Color(uiColor: Material3.surfaceContainer))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        AndroidLetterAvatar(name: thread.name ?? thread.number, size: 72).padding(.top, 24)
                        Text(thread.name ?? thread.number).font(.system(size: 20, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurface))
                        Text(thread.number).font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                            .padding(.bottom, 20)
                        ForEach(thread.messages) { m in
                            HStack {
                                Spacer(minLength: 60)
                                Text(m.text)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundStyle(Color(uiColor: Material3.onPrimary))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color(uiColor: Material3.primary), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .id(m.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .onAppear { if let last = thread.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: thread.messages.count) { _ in
                    if let last = thread.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            HStack(spacing: 8) {
                TextField("Text message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .font(.system(size: 16, design: .rounded))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                Button(action: send) {
                    Image(systemName: "paperplane.fill").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(uiColor: draft.isEmpty ? Material3.onSurfaceVariant : Material3.onPrimary))
                        .frame(width: 48, height: 48)
                        .background(Color(uiColor: draft.isEmpty ? Material3.surfaceContainerHigh : Material3.primary), in: Circle())
                }
                .buttonStyle(AndroidSquashStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .background(Color(uiColor: Material3.surface))
        .sheet(item: Binding(get: { composing.map(IdentifiedText.init) }, set: { composing = $0?.text })) { c in
            MessageComposer(recipient: thread.number, body: c.text) { sent in
                composing = nil
                if sent {
                    AndroidMessageStore.append(c.text, to: thread.number, name: thread.name)
                    thread.messages.append(.init(text: c.text))
                    draft = ""
                }
            }
            .ignoresSafeArea()
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        focused = false
        if MFMessageComposeViewController.canSendText() {
            composing = text
        } else if let url = URL(string: "sms:" + AndroidComms.digits(thread.number) + "&body=" + (text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
            UIApplication.shared.open(url)
            AndroidMessageStore.append(text, to: thread.number, name: thread.name)
            thread.messages.append(.init(text: text))
            draft = ""
        }
    }
}

private struct IdentifiedText: Identifiable {
    let text: String
    var id: String { text }
}

/// iOS's message sheet, filled in.
private struct MessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = [recipient]
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            done(result == .sent)
        }
    }
}
