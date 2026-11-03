// SPDX-License-Identifier: GPL-2.0-or-later
// A Husk account on the website (itslevii.dev): sign in, the profile (avatar, name, @handle, games, apps, playtime, recently
// played, achievements), and the library it shows, sent from here. The session token lives in the Keychain.
import Foundation
import Security
import SwiftUI
import UIKit

// MARK: - what the site answers

struct HuskUser: Codable, Equatable {
    struct Stats: Codable, Equatable { var games: Int; var apps: Int; var playtimeSeconds: Double }
    struct Played: Codable, Equatable, Identifiable {
        var package: String
        var name: String
        var platform: String
        var type: String
        var playtimeSeconds: Double
        var lastPlayed: String?
        var id: String { package }
    }
    struct Achievement: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var unlockedAt: String?
        var unlocked: Bool
    }
    var id: String
    var username: String
    var displayName: String
    var avatarUrl: String?
    var createdAt: String
    var stats: Stats
    var recent: [Played]
    var achievements: [Achievement]
}

private struct AuthAnswer: Codable { var token: String; var user: HuskUser }
private struct SiteError: Codable { var error: String }

struct AccountError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - playtime

/// How long each game has been played from Husk, kept on this iPhone: a session starts when its screen appears and is
/// counted when it goes.
@MainActor enum Playtime {
    private static let key = "husk.playtime"
    private static var started: [String: Date] = [:]

    static var all: [String: Double] { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
    static func seconds(_ id: String) -> Double { all[id] ?? 0 }

    static func begin(_ id: String) { started[id] = Date() }
    static func end(_ id: String) {
        guard let s = started.removeValue(forKey: id) else { return }
        let add = Date().timeIntervalSince(s)
        guard add > 2, add < 24 * 3600 else { return }
        var d = all
        d[id, default: 0] += add
        UserDefaults.standard.set(d, forKey: key)
        Account.shared.librarySoon()
    }

    /// "3h 42m", "12m", "0m".
    static func text(_ seconds: Double) -> String {
        let m = Int(seconds / 60), h = m / 60
        return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
    }
}

// MARK: - the account

@MainActor final class Account: ObservableObject {
    static let shared = Account()

    @Published private(set) var user: HuskUser?
    @Published private(set) var avatar: UIImage?
    @Published var busy = false

    var signedIn: Bool { token != nil }

    private static let userKey = "husk.account.user"
    private var token: String? { Keychain.read() }
    private var syncTask: Task<Void, Never>?

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.userKey), let u = try? JSONDecoder().decode(HuskUser.self, from: d) { user = u }
        if let d = try? Data(contentsOf: Self.avatarFile) { avatar = UIImage(data: d) }
    }

    private static var avatarFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("account-avatar.png")
    }

    // MARK: talking to the site

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil, auth: Bool = true) async throws -> Data {
        var last: Error = AccountError(message: "The Husk website did not answer.")
        for site in CompatibilityStore.sites {
            var r = URLRequest(url: site.appendingPathComponent(path))
            r.httpMethod = method
            r.timeoutInterval = 20
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if auth, let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
            do {
                let (data, resp) = try await URLSession.shared.data(for: r)
                guard let http = resp as? HTTPURLResponse else { continue }
                // the site's database is down: its answer, not an outage to try the old address for
                if CompatibilityStore.isMaintenance(http, data) { throw AccountError(message: CompatibilityStore.maintenanceMessage) }
                if http.statusCode >= 500 { last = AccountError(message: "The Husk website had a problem (\(http.statusCode))."); continue }
                if http.statusCode == 401, auth { forget() }
                if http.statusCode >= 400 {
                    let msg = (try? JSONDecoder().decode(SiteError.self, from: data))?.error ?? "Something went wrong (\(http.statusCode))."
                    throw AccountError(message: msg)
                }
                return data
            } catch let e as AccountError {
                throw e
            } catch {
                last = error
            }
        }
        throw last
    }

    private func take(_ u: HuskUser) {
        user = u
        if let d = try? JSONEncoder().encode(u) { UserDefaults.standard.set(d, forKey: Self.userKey) }
        Task { await loadAvatar() }
    }

    private func loadAvatar() async {
        guard let u = user, let s = u.avatarUrl else { avatar = nil; try? FileManager.default.removeItem(at: Self.avatarFile); return }
        let url = URL(string: s, relativeTo: CompatibilityStore.site) ?? CompatibilityStore.site
        guard let (d, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: d) else { return }
        avatar = img
        try? d.write(to: Self.avatarFile)
    }

    private func forget() {
        Keychain.delete()
        user = nil
        avatar = nil
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        try? FileManager.default.removeItem(at: Self.avatarFile)
    }

    // MARK: what the screens do

    func signUp(username: String, password: String, displayName: String) async throws {
        busy = true; defer { busy = false }
        let d = try await call("POST", "api/auth/signup", body: ["username": username, "password": password, "displayName": displayName], auth: false)
        let a = try JSONDecoder().decode(AuthAnswer.self, from: d)
        Keychain.write(a.token)
        take(a.user)
        await syncLibrary()
    }

    func signIn(username: String, password: String) async throws {
        busy = true; defer { busy = false }
        let d = try await call("POST", "api/auth/login", body: ["username": username, "password": password], auth: false)
        let a = try JSONDecoder().decode(AuthAnswer.self, from: d)
        Keychain.write(a.token)
        take(a.user)
        await syncLibrary()
    }

    func signOut() async {
        _ = try? await call("POST", "api/auth/logout")
        forget()
    }

    func refresh() async {
        guard signedIn, let d = try? await call("GET", "api/me"), let u = try? JSONDecoder().decode(HuskUser.self, from: d) else { return }
        take(u)
    }

    func update(displayName: String? = nil, avatarPNG: Data?? = nil) async throws {
        var body: [String: Any] = [:]
        if let displayName { body["displayName"] = displayName }
        if let avatarPNG { body["avatarPng"] = avatarPNG.map { $0.base64EncodedString() } ?? NSNull() }
        busy = true; defer { busy = false }
        let d = try await call("PATCH", "api/me", body: body)
        // the site kept the change for later (its database was down): show the new name until then
        if (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["queued"] as? Bool == true {
            if let displayName, var u = user { u.displayName = displayName; take(u) }
            return
        }
        take(try JSONDecoder().decode(HuskUser.self, from: d))
    }

    /// The library, a moment after something changed (a session ended), so several changes go as one.
    func librarySoon() {
        guard signedIn else { return }
        syncTask?.cancel()
        syncTask = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if !Task.isCancelled { await syncLibrary() } }
    }

    /// Every game and app here, with its playtime and when it was last played, replaces what the account had.
    func syncLibrary() async {
        guard signedIn else { return }
        let iso = ISO8601DateFormatter()
        let items = Launcher.items(store: TranslationLayerStore.shared, host: AndroidHost.shared).filter { $0 != .android }
        let rows: [[String: Any]] = items.prefix(2000).compactMap { i in
            guard let id = i.accountID else { return nil }
            return ["package": id, "name": String(i.title.prefix(80)), "platform": i.isPS4 ? "ps4" : "android",
             "type": i.isGame ? "game" : "app", "playtimeSeconds": Playtime.seconds(i.id).rounded(),
             "lastPlayed": i.lastUsed.map { iso.string(from: $0) } ?? NSNull()]
        }
        guard let d = try? await call("PUT", "api/me/library", body: ["items": rows]),
              let u = try? JSONDecoder().decode(HuskUser.self, from: d) else { return }
        take(u)
    }

    /// The avatar picked for the profile, made small and square before it goes.
    static func avatarPNG(_ image: UIImage) -> Data? {
        let side: CGFloat = 256
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            let s = image.size, k = max(side / s.width, side / s.height)
            let w = s.width * k, h = s.height * k
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return img.pngData()
    }
}

extension LibraryItem {
    /// What the account knows it by: the Android package, or a PS4 game's title ID.
    var accountID: String? {
        if case .ps4(let g) = self { return g.titleID }
        return packageName
    }
}

// MARK: - Keychain

private enum Keychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "com.husk.account",
                                               kSecAttrAccount as String: "session"]
    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func write(_ token: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
}

// MARK: - the avatar

/// The account's picture, or a person in a circle when there is none.
struct AccountAvatar: View {
    var size: CGFloat = 36
    @ObservedObject private var account = Account.shared

    var body: some View {
        Group {
            if let img = account.avatar {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Console.raised)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }
}
