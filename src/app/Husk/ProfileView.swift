// SPDX-License-Identifier: GPL-2.0-or-later
// The Husk account: the profile page (avatar, name, @handle, games, apps, playtime, recently played, achievements), sign in, editing.
import SwiftUI
import UIKit

// MARK: - profile

/// The account's page: who, how much has been played, what lately, and the achievements. Signed out, the way in.
struct ProfileView: View {
    @ObservedObject private var account = Account.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        NavigationStack {
            Group {
                if let user = account.user, account.signedIn { profile(user) } else { SignInView() }
            }
            .background(Console.page.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if account.signedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { editing = true } label: { Label("Edit Profile", systemImage: "pencil") }
                            if let u = account.user {
                                HuskShareLink(item: CompatibilityStore.site.appendingPathComponent("u").appendingPathComponent(u.username)) {
                                    Label("Share Profile", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button(role: .destructive) { Task { await account.signOut() } } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .sheet(isPresented: $editing) { EditProfileView() }
            .task { await account.refresh(); await account.syncLibrary() }
        }
    }

    private func profile(_ u: HuskUser) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    AccountAvatar(size: 92)
                    Text(u.displayName).font(.system(size: 24, weight: .bold)).foregroundStyle(Console.text)
                    Text("@" + u.username).font(.system(size: 14)).foregroundStyle(Console.textDim)
                }
                .padding(.top, 8)

                HStack {
                    stat("\(u.stats.games)", "Games")
                    stat("\(u.stats.apps)", "Apps")
                    stat(Playtime.text(u.stats.playtimeSeconds), "Total Playtime")
                }

                if !u.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Played").font(.system(size: 18, weight: .bold)).foregroundStyle(Console.text)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(u.recent) { p in recentTile(p) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Achievements").font(.system(size: 18, weight: .bold)).foregroundStyle(Console.text)
                    ForEach(u.achievements) { a in
                        HStack(spacing: 14) {
                            Image(systemName: a.unlocked ? "trophy.fill" : "lock.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(a.unlocked ? Theme.accent : Console.textDim)
                                .frame(width: 44, height: 44)
                                .background(Console.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Console.text)
                                Text(a.detail).font(.system(size: 12)).foregroundStyle(Console.textDim)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Console.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .opacity(a.unlocked ? 1 : 0.6)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(Console.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 12)).foregroundStyle(Console.textDim)
        }
        .frame(maxWidth: .infinity)
    }

    /// A recently played game: the icon from this iPhone when it is here, its name and when.
    private func recentTile(_ p: HuskUser.Played) -> some View {
        let here = Launcher.items(store: TranslationLayerStore.shared, host: AndroidHost.shared).first { $0.accountID == p.package }
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if let here { ItemIcon(item: here, size: 96) } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Console.raised).frame(width: 96, height: 96)
                        .overlay(Image(systemName: "gamecontroller.fill").foregroundStyle(Console.textDim))
                }
            }
            Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Console.text).lineLimit(1)
            if let s = p.lastPlayed, let d = ISO8601DateFormatter().date(from: s) {
                Text(RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date()))
                    .font(.system(size: 11)).foregroundStyle(Console.textDim).lineLimit(1)
            }
        }
        .frame(width: 96, alignment: .leading)
    }
}

/// Sign in, or make an account.
struct SignInView: View {
    @ObservedObject private var account = Account.shared
    @State private var creating = false
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HuskMark(size: 72).padding(.top, 24)
                Text(creating ? "Create a Husk Account" : "Sign In to Husk")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Console.text)
                Text("Your profile, playtime and achievements, on this iPhone and on itslevii.dev.")
                    .font(.subheadline).foregroundStyle(Console.textDim).multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    field("Username", text: $username)
                    if creating { field("Display name", text: $displayName) }
                    SecureField("Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                        .padding(.horizontal, 14).frame(height: 48)
                        .background(Console.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
                Button { Task { await submit() } } label: {
                    if account.busy { ProgressView().tint(.white) } else { Text(creating ? "Create Account" : "Sign In") }
                }
                .buttonStyle(ConsolePlayButtonStyle())
                .disabled(account.busy || username.count < 3 || password.count < (creating ? 8 : 1))
                Button(creating ? "I already have an account" : "Create an account") {
                    withAnimation { creating.toggle(); error = nil }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 24)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14).frame(height: 48)
            .background(Console.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submit() async {
        error = nil
        let name = username.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            if creating {
                try await account.signUp(username: name, password: password,
                                         displayName: displayName.isEmpty ? username : displayName)
            } else {
                try await account.signIn(username: name, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The name and picture others see.
struct EditProfileView: View {
    @ObservedObject private var account = Account.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var picking = false
    @State private var picked: UIImage?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            HuskForm {
                Section {
                    HStack {
                        Spacer()
                        Button { picking = true } label: {
                            Group {
                                if let picked { Image(uiImage: picked).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(Circle()) }
                                else { AccountAvatar(size: 92) }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill").font(.system(size: 13)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30).background(Theme.accent, in: Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Display Name") { TextField("Name", text: $name) }
                if account.avatar != nil {
                    Section { Button("Remove Picture", role: .destructive) { Task { try? await account.update(avatarPNG: .some(nil)) } } }
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                let png = picked.flatMap(Account.avatarPNG)
                                try await account.update(displayName: name.isEmpty ? nil : name, avatarPNG: png.map { .some($0) } ?? nil)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(account.busy)
                }
            }
            .onAppear { name = account.user?.displayName ?? "" }
            .sheet(isPresented: $picking) { PhotoPicker(image: $picked) }
        }
    }
}

/// The photo library, for one picture.
private struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
