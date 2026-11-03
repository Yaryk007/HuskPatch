// SPDX-License-Identifier: GPL-2.0-or-later
// husk://game/<package>, from a game's page on the website ("Open in Husk"): its page here when it is added, else the Store's.
import Foundation

@MainActor enum GameLink {
    static func handle(_ url: URL) -> Bool {
        guard url.scheme == "husk", url.host == "game" || url.host == "app" else { return false }
        let id = url.lastPathComponent
        guard !id.isEmpty, id != "/" else { return true }
        let router = Router.shared
        if let item = Launcher.items(store: TranslationLayerStore.shared, host: AndroidHost.shared).first(where: { $0.accountID == id }) {
            router.tab = .home
            router.home = [item.route]
        } else {
            router.tab = .store
            router.storePackage = id
        }
        HuskLog.log("ui", "game link \(id)")
        return true
    }
}
