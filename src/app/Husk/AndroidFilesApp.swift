// SPDX-License-Identifier: GPL-2.0-or-later
import ImageIO
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// HuskPatch: Android OS mode's Files, after Android's DocumentsUI: a search pill, the category chips, recent files, and the
/// storage roots -- Internal storage (what the Android apps here see as /sdcard) and HuskPatch's own files. A folder lists
/// its files with icons, sizes and dates; a file opens in a preview or goes to the share sheet; new folders, renaming and
/// deleting, and importing from the iPhone's Files.
struct AndroidFilesApp: View {
    struct Root: Identifiable, Hashable {
        let id: String
        let title: String
        let icon: String
        let url: URL
    }

    static var roots: [Root] {
        [Root(id: "sdcard", title: "Internal storage", icon: "internaldrive", url: TranslationLayer.sharedStorage),
         Root(id: "huskpatch", title: "HuskPatch", icon: "folder.badge.gearshape",
              url: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])]
    }

    enum Category: String, CaseIterable, Identifiable {
        case images = "Images", videos = "Videos", audio = "Audio", documents = "Documents", downloads = "Downloads"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .images: return "photo"
            case .videos: return "film"
            case .audio: return "music.note"
            case .documents: return "doc.text"
            case .downloads: return "arrow.down.to.line"
            }
        }
        func matches(_ url: URL) -> Bool {
            let type = UTType(filenameExtension: url.pathExtension)
            switch self {
            case .images: return type?.conforms(to: .image) ?? false
            case .videos: return type?.conforms(to: .movie) ?? false
            case .audio: return type?.conforms(to: .audio) ?? false
            case .documents: return (type?.conforms(to: .text) ?? false) || (type?.conforms(to: .pdf) ?? false)
                || ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "epub"].contains(url.pathExtension.lowercased())
            case .downloads: return url.pathComponents.contains("Download")
            }
        }
    }

    /// Where the app is: home, a category, or a folder (a stack of them).
    @State private var path: [URL] = []
    @State private var category: Category?
    @State private var query = ""
    @State private var recent: [FileItem] = []
    @State private var preview: URL?

    var body: some View {
        ZStack {
            home
            if let category {
                FileListPage(title: category.rawValue, items: Self.all().filter { category.matches($0.url) }, onBack: { withAnimation(.snappy) { self.category = nil } },
                             onOpen: open)
                    .transition(.move(edge: .trailing)).zIndex(1)
            }
            if let dir = path.last {
                FolderPage(dir: dir, onBack: { withAnimation(.snappy) { _ = path.popLast() } }, onOpen: open)
                    .id(dir)
                    .transition(.move(edge: .trailing)).zIndex(2)
            }
        }
        .background(Color(uiColor: Material3.surface))
        .onAppear { recent = Array(Self.all().sorted { $0.date > $1.date }.prefix(8)) }
        .sheet(item: Binding(get: { preview.map(IdentifiedURL.init) }, set: { preview = $0?.url })) { p in
            FilePreview(url: p.url).ignoresSafeArea()
        }
        .onAndroidBack {
            if !path.isEmpty { withAnimation(.snappy) { _ = path.popLast() }; return true }
            if category != nil { withAnimation(.snappy) { category = nil }; return true }
            if !query.isEmpty { query = ""; return true }
            return false
        }
    }

    private func open(_ item: FileItem) {
        if item.folder { withAnimation(.snappy) { path.append(item.url) } } else { preview = item.url }
    }

    private var home: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                TextField("Search files", text: $query).textInputAutocapitalization(.never).disableAutocorrection(true)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            }
            .font(.system(size: 16, design: .rounded))
            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            .padding(.horizontal, 18).frame(height: 52)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: Capsule())
            .padding(.horizontal, 16).padding(.vertical, 8)

            if !query.isEmpty {
                ScrollView {
                    FileRows(items: Self.all().filter { $0.name.localizedCaseInsensitiveContains(query) }, onOpen: open)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Category.allCases) { c in
                                    Button { withAnimation(.snappy) { category = c } } label: {
                                        Label(c.rawValue, systemImage: c.icon)
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                                            .padding(.horizontal, 14).frame(height: 36)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: Material3.outline), lineWidth: 1))
                                    }
                                    .buttonStyle(AndroidSquashStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        if !recent.isEmpty {
                            Text("Recent files").font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(uiColor: Material3.onSurface)).padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(recent) { f in
                                        Button { open(f) } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                FileThumb(item: f, size: 120)
                                                Text(f.name).font(.system(size: 13, design: .rounded)).lineLimit(1)
                                                    .foregroundStyle(Color(uiColor: Material3.onSurface))
                                            }
                                            .frame(width: 120)
                                        }
                                        .buttonStyle(AndroidSquashStyle())
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        Text("Browse").font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(uiColor: Material3.onSurface)).padding(.horizontal, 20)
                        VStack(spacing: 2) {
                            ForEach(Self.roots) { r in
                                Button { withAnimation(.snappy) { path = [r.url] } } label: {
                                    SystemListRow(title: r.title, subtitle: freeSpace) {
                                        Image(systemName: r.icon).font(.system(size: 18))
                                            .foregroundStyle(Color(uiColor: Material3.onSecondaryContainer))
                                            .frame(width: 40, height: 40)
                                            .background(Color(uiColor: Material3.secondaryContainer), in: Circle())
                                    } trailing: { EmptyView() }
                                }
                                .buttonStyle(AndroidRippleStyle())
                                .background(Color(uiColor: Material3.surfaceContainerLow))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var freeSpace: String {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return "" }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " free of "
            + ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    /// Every file under the roots (not into the translation layer's own app folders), for search, categories and recents.
    static func all() -> [FileItem] {
        var out: [FileItem] = []
        for r in roots {
            guard let e = FileManager.default.enumerator(at: r.url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else { continue }
            for case let u as URL in e {
                if u.lastPathComponent == "TranslationLayer" || u.lastPathComponent == "Shared Storage" && r.id == "huskpatch" { e.skipDescendants(); continue }
                if let f = FileItem(u), !f.folder { out.append(f) }
                if out.count > 4000 { return out }
            }
        }
        return out
    }
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let folder: Bool
    let size: Int64
    let date: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }

    init?(_ url: URL) {
        guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else { return nil }
        self.url = url
        folder = v.isDirectory ?? false
        size = Int64(v.fileSize ?? 0)
        date = v.contentModificationDate ?? .distantPast
    }

    var icon: String {
        if folder { return "folder.fill" }
        let t = UTType(filenameExtension: url.pathExtension)
        if t?.conforms(to: .image) == true { return "photo" }
        if t?.conforms(to: .movie) == true { return "film" }
        if t?.conforms(to: .audio) == true { return "music.note" }
        if t?.conforms(to: .archive) == true || url.pathExtension.lowercased() == "zip" { return "doc.zipper" }
        if ["apk", "xapk", "apks"].contains(url.pathExtension.lowercased()) { return "shippingbox.fill" }
        if t?.conforms(to: .pdf) == true { return "doc.richtext" }
        return "doc"
    }
}

/// A file's picture: the image itself for a picture, otherwise its kind's icon on a tonal square.
private struct FileThumb: View {
    let item: FileItem
    var size: CGFloat = 40
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                Image(systemName: item.icon).font(.system(size: size * 0.42))
                    .foregroundStyle(Color(uiColor: item.folder ? Material3.onPrimaryContainer : Material3.onSurfaceVariant))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: item.folder ? Material3.primaryContainer : Material3.surfaceContainerHighest))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 16 : 10, style: .continuous))
        .task(id: item.url) {
            guard !item.folder, UTType(filenameExtension: item.url.pathExtension)?.conforms(to: .image) == true, item.size < 40_000_000 else { return }
            let url = item.url, px = size * 3
            image = await Task.detached {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                           kCGImageSourceThumbnailMaxPixelSize: px] as CFDictionary)
                else { return nil }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}

private struct FileRows: View {
    let items: [FileItem]
    let onOpen: (FileItem) -> Void
    var onRename: ((FileItem) -> Void)?
    var onDelete: ((FileItem) -> Void)?
    @State private var share: URL?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { f in
                Button { onOpen(f) } label: {
                    SystemListRow(title: f.name, subtitle: f.folder ? f.date.formatted(date: .abbreviated, time: .omitted)
                                  : ByteCountFormatter.string(fromByteCount: f.size, countStyle: .file) + " · " + f.date.formatted(date: .abbreviated, time: .omitted)) {
                        FileThumb(item: f)
                    } trailing: { EmptyView() }
                }
                .buttonStyle(AndroidRippleStyle())
                .contextMenu {
                    if !f.folder { Button { share = f.url } label: { Label("Share", systemImage: "square.and.arrow.up") } }
                    if let onRename { Button { onRename(f) } label: { Label("Rename", systemImage: "pencil") } }
                    Button { UIPasteboard.general.string = f.url.path } label: { Label("Copy path", systemImage: "doc.on.doc") }
                    if let onDelete { Button(role: .destructive) { onDelete(f) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .sheet(item: Binding(get: { share.map(IdentifiedURL.init) }, set: { share = $0?.url })) { ShareSheet(items: [$0.url]) }
    }
}

private struct FileListPage: View {
    let title: String
    let items: [FileItem]
    let onBack: () -> Void
    let onOpen: (FileItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: title, onBack: onBack)
            if items.isEmpty { SystemEmptyState(icon: "doc", text: "No items") }
            else { ScrollView { FileRows(items: items.sorted { $0.date > $1.date }, onOpen: onOpen) } }
        }
        .background(Color(uiColor: Material3.surface))
    }
}

/// One folder: its files and folders, sorted folders first, with new folder, import and sort.
private struct FolderPage: View {
    let dir: URL
    let onBack: () -> Void
    let onOpen: (FileItem) -> Void
    @State private var items: [FileItem] = []
    @State private var byDate = false
    @State private var naming: (title: String, text: String, target: FileItem?)?
    @State private var deleting: FileItem?
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            SystemAppBar(title: AndroidFilesApp.roots.first { $0.url.standardizedFileURL == dir.standardizedFileURL }?.title ?? dir.lastPathComponent,
                         onBack: onBack) {
                SystemBarButton(icon: byDate ? "calendar" : "textformat", label: "Sort") { byDate.toggle(); load() }
                SystemBarButton(icon: "square.and.arrow.down", label: "Import from iPhone") { importing = true }
            }
            if items.isEmpty { SystemEmptyState(icon: "folder", text: "No items") }
            else {
                ScrollView {
                    FileRows(items: items, onOpen: onOpen,
                             onRename: { f in naming = ("Rename", f.name, f) },
                             onDelete: { f in deleting = f })
                        .padding(.bottom, 96)
                }
            }
        }
        .background(Color(uiColor: Material3.surface))
        .overlay(alignment: .bottomTrailing) {
            AndroidFAB(icon: "folder.badge.plus") { naming = ("New folder", "", nil) }.padding(20)
        }
        .overlay { nameDialog }
        .overlay {
            if let f = deleting {
                ConfirmDialog(title: "Delete \(f.name)?", confirm: "Delete") {
                    try? FileManager.default.removeItem(at: f.url)
                    deleting = nil
                    load()
                } cancel: { deleting = nil }
            }
        }
        .sheet(isPresented: $importing) {
            ImportPicker { urls in
                for u in urls {
                    let ok = u.startAccessingSecurityScopedResource()
                    _ = AndroidDocuments.copy(u, into: dir)
                    if ok { u.stopAccessingSecurityScopedResource() }
                }
                load()
            }
            .ignoresSafeArea()
        }
        .onAppear(perform: load)
    }

    private func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                                                                options: [.skipsHiddenFiles])) ?? []
        items = urls.compactMap(FileItem.init).sorted {
            if $0.folder != $1.folder { return $0.folder }
            return byDate ? $0.date > $1.date : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder private var nameDialog: some View {
        if let n = naming {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { naming = nil }
                VStack(alignment: .leading, spacing: 16) {
                    Text(n.title).font(.system(size: 24, design: .rounded)).foregroundStyle(Color(uiColor: Material3.onSurface))
                    TextField("Name", text: Binding(get: { naming?.text ?? "" }, set: { naming?.text = $0 }))
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: Material3.primary), lineWidth: 2))
                    HStack {
                        Spacer()
                        Button("Cancel") { naming = nil }.buttonStyle(.expressive(.text))
                        Button("OK") {
                            let name = n.text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
                            if !name.isEmpty {
                                if let t = n.target {
                                    try? FileManager.default.moveItem(at: t.url, to: dir.appendingPathComponent(name))
                                } else {
                                    try? FileManager.default.createDirectory(at: dir.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: false)
                                }
                            }
                            naming = nil
                            load()
                        }
                        .buttonStyle(.expressive(.text))
                    }
                }
                .padding(24)
                .frame(maxWidth: 340)
                .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 24)
            }
        }
    }
}

/// Android's confirmation dialog: a headline and two text buttons.
struct ConfirmDialog: View {
    let title: String
    let confirm: String
    let action: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.system(size: 22, design: .rounded)).foregroundStyle(Color(uiColor: Material3.onSurface))
                HStack {
                    Spacer()
                    Button("Cancel", action: cancel).buttonStyle(.expressive(.text))
                    Button(confirm, action: action).buttonStyle(.expressive(.text))
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 24)
        }
    }
}

private struct ImportPicker: UIViewControllerRepresentable {
    let done: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        p.allowsMultipleSelection = true
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let done: ([URL]) -> Void
        init(done: @escaping ([URL]) -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls) }
    }
}

private struct FilePreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        return UINavigationController(rootViewController: ql)
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
