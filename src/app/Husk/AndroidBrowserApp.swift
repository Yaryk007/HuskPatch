// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit
import WebKit

/// HuskPatch: Android OS mode's Browser, after LineageOS's Jelly: the address bar along the top with the site's icon and a
/// menu (back, forward, reload, share, desktop site, incognito), a progress line under it, and a page of shortcuts when it
/// opens. Android's back goes back a page.
@MainActor
final class AndroidBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = AndroidBrowser()
    static let homeKey = "huskpatch.browser.home"
    static let engineKey = "huskpatch.browser.engine"

    enum Engine: String, CaseIterable, Identifiable {
        case google, duckduckgo, bing, startpage
        var id: String { rawValue }
        var title: String {
            switch self {
            case .google: return "Google"
            case .duckduckgo: return "DuckDuckGo"
            case .bing: return "Bing"
            case .startpage: return "Startpage"
            }
        }
        func search(_ q: String) -> URL? {
            let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            switch self {
            case .google: return URL(string: "https://www.google.com/search?q=" + e)
            case .duckduckgo: return URL(string: "https://duckduckgo.com/?q=" + e)
            case .bing: return URL(string: "https://www.bing.com/search?q=" + e)
            case .startpage: return URL(string: "https://www.startpage.com/do/search?q=" + e)
            }
        }
    }

    private(set) var web: WKWebView
    @Published var progress: Double = 0
    @Published var loading = false
    @Published var url: URL?
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var incognito = false { didSet { if incognito != oldValue { rebuild() } } }
    @Published var desktop = false {
        didSet {
            web.customUserAgent = desktop ? "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36" : Self.mobileAgent
            web.reload()
        }
    }
    /// Shows the start page instead of a site.
    @Published var showingStart = true
    private var observers: [NSKeyValueObservation] = []

    /// Chrome on Android's agent, so sites send their Android pages.
    static let mobileAgent = "Mozilla/5.0 (Linux; Android 15; LineageOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"

    override init() {
        web = WKWebView()
        super.init()
        rebuild()
    }

    private func rebuild() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = incognito ? .nonPersistent() : .default()
        config.allowsInlineMediaPlayback = true
        let w = WKWebView(frame: .zero, configuration: config)
        w.allowsBackForwardNavigationGestures = false
        w.customUserAgent = desktop ? nil : Self.mobileAgent
        w.navigationDelegate = self
        w.uiDelegate = self
        observers = [
            w.observe(\.estimatedProgress) { [weak self] w, _ in Task { @MainActor in self?.progress = w.estimatedProgress } },
            w.observe(\.isLoading) { [weak self] w, _ in Task { @MainActor in self?.loading = w.isLoading } },
            w.observe(\.url) { [weak self] w, _ in Task { @MainActor in self?.url = w.url } },
            w.observe(\.title) { [weak self] w, _ in Task { @MainActor in self?.title = w.title ?? "" } },
            w.observe(\.canGoBack) { [weak self] w, _ in Task { @MainActor in self?.canGoBack = w.canGoBack } },
            w.observe(\.canGoForward) { [weak self] w, _ in Task { @MainActor in self?.canGoForward = w.canGoForward } },
        ]
        web = w
        showingStart = true
        objectWillChange.send()
    }

    var engine: Engine { Engine(rawValue: UserDefaults.standard.string(forKey: Self.engineKey) ?? "") ?? .google }

    /// What was typed: a web address when it looks like one, otherwise a search.
    func go(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var target: URL?
        if t.contains("://"), let u = URL(string: t) { target = u }
        else if !t.contains(" "), t.contains("."), let u = URL(string: "https://" + t) { target = u }
        else { target = engine.search(t) }
        if let target { open(target) }
    }

    func open(_ url: URL) {
        showingStart = false
        web.load(URLRequest(url: url))
    }

    /// Back a page; from the first page, back to the start page. False when there is nowhere to go back to.
    func back() -> Bool {
        if web.canGoBack { web.goBack(); return true }
        if !showingStart { showingStart = true; return true }
        return false
    }

    // A link that opens a new window opens here.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // tel:, mailto:, sms: and app links go to iOS
        if let u = navigationAction.request.url, let s = u.scheme?.lowercased(), !["http", "https", "about", "data", "blob", "file"].contains(s) {
            UIApplication.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

private struct WebViewHost: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: UIView, context: Context) {
        if web.superview !== v {
            v.subviews.forEach { $0.removeFromSuperview() }
            web.frame = v.bounds
            web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.addSubview(web)
        }
    }
}

struct AndroidBrowserApp: View {
    @ObservedObject private var browser = AndroidBrowser.shared
    @AppStorage(AndroidBrowser.engineKey) private var engine = AndroidBrowser.Engine.google
    @State private var typing = ""
    @State private var editing = false
    @State private var menu = false
    @State private var share: URL?
    @FocusState private var focused: Bool

    private let shortcuts: [(String, String)] = [("LineageOS", "https://lineageos.org"), ("Wikipedia", "https://wikipedia.org"),
                                                 ("F-Droid", "https://f-droid.org"), ("YouTube", "https://m.youtube.com"),
                                                 ("GitHub", "https://github.com"), ("Reddit", "https://www.reddit.com"),
                                                 ("DuckDuckGo", "https://duckduckgo.com"), ("Husk", "https://github.com/Leviidev/Husk")]

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ZStack(alignment: .top) {
                WebViewHost(web: browser.web)
                    .opacity(browser.showingStart ? 0 : 1)
                if browser.showingStart { startPage }
                if browser.loading && !browser.showingStart {
                    GeometryReader { g in
                        Rectangle().fill(Color(uiColor: Material3.primary))
                            .frame(width: g.size.width * browser.progress, height: 3)
                            .animation(.easeOut(duration: 0.2), value: browser.progress)
                    }
                    .frame(height: 3)
                }
            }
        }
        .background(Color(uiColor: browser.incognito ? Material3.inverseSurface : Material3.surface))
        .overlay(alignment: .topTrailing) { if menu { overflowMenu } }
        .sheet(item: Binding(get: { share.map(IdentifiedURL.init) }, set: { share = $0?.url })) { ShareSheet(items: [$0.url]) }
        .onAndroidBack {
            if menu { menu = false; return true }
            if editing { focused = false; editing = false; return true }
            return browser.back()
        }
    }

    private var shownAddress: String {
        if browser.showingStart { return "" }
        guard let u = browser.url else { return "" }
        return u.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? u.absoluteString
    }

    private var addressBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: browser.incognito ? "eyeglasses" : browser.url?.scheme == "https" && !browser.showingStart ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                TextField("Search or type URL", text: $typing)
                    .focused($focused)
                    .font(.system(size: 16, design: .rounded))
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.go)
                    .onSubmit { browser.go(typing); focused = false }
                    .onChange(of: focused) { f in
                        editing = f
                        typing = f ? (browser.showingStart ? "" : browser.url?.absoluteString ?? "") : shownAddress
                    }
                    .onChange(of: browser.url) { _ in if !focused { typing = shownAddress } }
                    .onChange(of: browser.showingStart) { _ in if !focused { typing = shownAddress } }
                if editing && !typing.isEmpty {
                    Button { typing = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                } else if !browser.showingStart {
                    Button { if browser.loading { browser.web.stopLoading() } else { browser.web.reload() } } label: {
                        Image(systemName: browser.loading ? "xmark" : "arrow.clockwise")
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
            SystemBarButton(icon: "ellipsis", label: "More") { withAnimation(.snappy) { menu.toggle() } }
                .rotationEffect(.degrees(90))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: browser.incognito ? Material3.inverseSurface : Material3.surfaceContainer))
    }

    private var startPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                AndroidSystemAppIcon(app: .browser, size: 72).padding(.top, 48)
                Text(browser.incognito ? "Incognito" : "Browser")
                    .font(.system(size: 28, design: .rounded))
                    .foregroundStyle(Color(uiColor: browser.incognito ? Material3.inverseOnSurface : Material3.onSurface))
                if browser.incognito {
                    Text("Pages you view here won't be kept: no history, cookies or site data once you leave incognito.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.inverseOnSurface).opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18) {
                    ForEach(shortcuts, id: \.1) { name, link in
                        Button { if let u = URL(string: link) { browser.open(u) } } label: {
                            VStack(spacing: 8) {
                                Text(String(name.prefix(1)))
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(uiColor: Material3.onSecondaryContainer))
                                    .frame(width: 56, height: 56)
                                    .background(Color(uiColor: Material3.secondaryContainer), in: Circle())
                                Text(name).font(.system(size: 12, design: .rounded)).lineLimit(1)
                                    .foregroundStyle(Color(uiColor: browser.incognito ? Material3.inverseOnSurface : Material3.onSurface))
                            }
                        }
                        .buttonStyle(AndroidSquashStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var overflowMenu: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { withAnimation(.snappy) { menu = false } }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    iconItem("arrow.left", enabled: browser.canGoBack) { browser.web.goBack() }
                    iconItem("arrow.right", enabled: browser.canGoForward) { browser.web.goForward() }
                    iconItem("arrow.clockwise", enabled: !browser.showingStart) { browser.web.reload() }
                    iconItem("square.and.arrow.up", enabled: browser.url != nil && !browser.showingStart) { share = browser.url }
                }
                Divider().overlay(Color(uiColor: Material3.outlineVariant))
                item(browser.incognito ? "Leave incognito" : "New incognito tab") { browser.incognito.toggle() }
                item(browser.desktop ? "Mobile site" : "Desktop site") { browser.desktop.toggle() }
                item("Start page") { browser.showingStart = true }
                Menu {
                    Picker("Search engine", selection: $engine) {
                        ForEach(AndroidBrowser.Engine.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Text("Search engine: \(engine.title)").font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).frame(height: 48)
                }
            }
            .frame(width: 250)
            .padding(.vertical, 6)
            .background(Color(uiColor: Material3.surfaceContainer), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(.top, 56)
            .padding(.trailing, 8)
            .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private func iconItem(_ icon: String, enabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button { menu = false; run() } label: {
            Image(systemName: icon).font(.system(size: 18)).frame(maxWidth: .infinity).frame(height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(uiColor: Material3.onSurface))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    private func item(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { menu = false }; run() } label: {
            Text(title).font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).frame(height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(AndroidRippleStyle())
    }
}
