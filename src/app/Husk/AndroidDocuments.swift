// SPDX-License-Identifier: GPL-2.0-or-later
import PhotosUI
import QuickLook
import UIKit
import UniformTypeIdentifiers

/// HuskPatch: an Android app's activities for files, answered by the iPhone (husk-tl-docs.c).
///
/// "Open a file" (ACTION_GET_CONTENT, ACTION_OPEN_DOCUMENT, Flutter's file_picker) shows the Files picker, a photo or video the
/// Photos picker, "open a folder" the Files picker for folders. What the user picks is copied into the app's storage (the
/// folder the runtime names: Download/, Pictures/... of its sdcard) and the copies' paths go back to the app, which sees
/// them as documents. The other way, a file of the app's is saved to Files, opened in Quick Look or shared.
enum AndroidDocuments {
    /// Registers HuskPatch as the translation layer's file host. At launch.
    static func install() {
        husk_docs_set_host({ id, mimes, flags, dest in
            let types = mimes.map { String(cString: $0) } ?? ""
            let dir = dest.map { URL(fileURLWithPath: String(cString: $0), isDirectory: true) }
            Task { @MainActor in
                guard let dir else { husk_docs_result(id, nil); return }
                AndroidDocumentPicker.shared.pick(id: id, mimes: types, flags: flags, into: dir)
            }
        }, { path, mode in
            guard let path else { return }
            let url = URL(fileURLWithPath: String(cString: path))
            Task { @MainActor in AndroidDocumentPicker.shared.export(url, mode: mode) }
        })
    }

    /// The types the picker offers for Android MIME types ("image/*", "application/pdf") and extensions (".pdf").
    static func contentTypes(_ mimes: String) -> [UTType] {
        var out: [UTType] = []
        for raw in mimes.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) where !raw.isEmpty {
            if raw.hasPrefix(".") {
                if let t = UTType(filenameExtension: String(raw.dropFirst())) { out.append(t) }
                continue
            }
            switch raw {
            case "*/*", "*": return [.item]
            case "image/*": out.append(.image)
            case "video/*": out.append(.movie); out.append(.video)
            case "audio/*": out.append(.audio)
            case "text/*": out.append(.text)
            case "application/*": out.append(.data)
            case "application/zip", "application/x-zip-compressed": out.append(.zip)
            case "application/vnd.android.package-archive": out.append(UTType(filenameExtension: "apk") ?? .data)
            default:
                if let t = UTType(mimeType: raw) { out.append(t) }
                else if raw.hasSuffix("/*") { out.append(.item) }
            }
        }
        return out.isEmpty ? [.item] : out
    }

    /// `name` in `dir`, numbered as Android's Files app does when it is taken: "photo (1).jpg".
    static func unique(_ name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        var url = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        for n in 1... {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            if !fm.fileExists(atPath: url.path) { return url }
        }
        return url
    }

    /// A copy of `src` (a file or a folder) in `dir`; nil when it could not be read.
    static func copy(_ src: URL, into dir: URL) -> URL? {
        let fm = FileManager.default
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = unique(src.lastPathComponent, in: dir)
        do {
            try fm.copyItem(at: src, to: dst)
        } catch {
            // a file provider's item may need a coordinated read first (iCloud Drive, not downloaded yet)
            var copied: URL?
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: src, options: [.forUploading], error: &err) { readable in
                if (try? fm.copyItem(at: readable, to: dst)) != nil { copied = dst }
            }
            if copied == nil { HuskLog.log("docs", "copying \(src.lastPathComponent) failed: \(error.localizedDescription)") }
            return copied
        }
        // the picker's own copy (asCopy) in HuskPatch's temporary folder: not needed twice
        if src.path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path) || src.path.hasPrefix(NSTemporaryDirectory()) {
            try? fm.removeItem(at: src)
        }
        return dst
    }
}

/// The pickers, one at a time, over whatever is on screen.
@MainActor
final class AndroidDocumentPicker: NSObject {
    static let shared = AndroidDocumentPicker()

    private struct Pick { let id: Int32; let flags: Int32; let dir: URL }
    private var current: Pick?
    private var queue: [(Pick, String)] = []

    private var testHandlers: [Int32: ([URL]?) -> Void] = [:]
    private var nextTestID: Int32 = -1

    /// The Testing page's pick: the same pickers and copies, answered to `done` instead of an app.
    func pickForTest(mimes: String, flags: Int32, into dir: URL, done: @escaping ([URL]?) -> Void) {
        let id = nextTestID
        nextTestID -= 1
        testHandlers[id] = done
        pick(id: id, mimes: mimes, flags: flags, into: dir)
    }

    func pick(id: Int32, mimes: String, flags: Int32, into dir: URL) {
        let p = Pick(id: id, flags: flags, dir: dir)
        if current != nil { queue.append((p, mimes)); return }
        show(p, mimes)
    }

    private func show(_ p: Pick, _ mimes: String) {
        guard let top = Self.topController() else { finish(p, nil); return }
        current = p
        let multiple = p.flags & 1 != 0, folder = p.flags & 2 != 0, media = p.flags & 4 != 0
        HuskLog.log("docs", "pick \(p.id): \(folder ? "a folder" : media ? "photos" : "files") (\(mimes.replacingOccurrences(of: "\n", with: ", ")))")
        if media && !folder {
            var config = PHPickerConfiguration()
            config.selectionLimit = multiple ? 0 : 1
            let types = AndroidDocuments.contentTypes(mimes)
            let images = types.contains { $0.conforms(to: .image) }, videos = types.contains { $0.conforms(to: .movie) }
            config.filter = images && !videos ? .images : videos && !images ? .videos : .any(of: [.images, .videos])
            config.preferredAssetRepresentationMode = .compatible
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            top.present(picker, animated: true)
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: folder ? [.folder] : AndroidDocuments.contentTypes(mimes),
                                                    asCopy: !folder)
        picker.allowsMultipleSelection = multiple && !folder
        picker.delegate = self
        top.present(picker, animated: true)
    }

    /// Copies what was picked into the app's storage, off the main thread, and answers the app.
    private func picked(_ urls: [URL]) {
        guard let p = current else { return }
        Task.detached(priority: .userInitiated) {
            let copies = urls.compactMap { AndroidDocuments.copy($0, into: p.dir) }
            await MainActor.run { self.finish(p, copies) }
        }
    }

    private func finish(_ p: Pick, _ copies: [URL]?) {
        if let test = testHandlers.removeValue(forKey: p.id) {
            test(copies?.isEmpty == false ? copies : nil)
        } else if let copies, !copies.isEmpty {
            HuskLog.log("docs", "pick \(p.id): copied " + copies.map(\.lastPathComponent).joined(separator: ", "))
            copies.map(\.path).joined(separator: "\n").withCString { husk_docs_result(p.id, $0) }
        } else {
            husk_docs_result(p.id, nil)
        }
        if current?.id == p.id { current = nil }
        if !queue.isEmpty { let (next, mimes) = queue.removeFirst(); show(next, mimes) }
    }

    // MARK: - files to the iPhone

    private var previewing: URL?

    func export(_ url: URL, mode: Int32) {
        guard FileManager.default.fileExists(atPath: url.path), let top = Self.topController() else { return }
        switch mode {
        case 0:
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            top.present(picker, animated: true)
        case 1:
            previewing = url
            let ql = QLPreviewController()
            ql.dataSource = self
            top.present(ql, animated: true)
        default:
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1)
            }
            top.present(sheet, animated: true)
        }
    }

    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows).filter { !$0.isHidden }
        // the permission dialogs' window is above the app, but it is not where a picker belongs once it goes
        let window = windows.first { $0.isKeyWindow && $0.windowLevel == .normal } ?? windows.first { $0.windowLevel == .normal } ?? windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

extension AndroidDocumentPicker: UIDocumentPickerDelegate {
    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { @MainActor in self.picked(urls) }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in if let p = self.current { self.finish(p, nil) } }
    }
}

extension AndroidDocumentPicker: PHPickerViewControllerDelegate {
    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            guard let p = self.current else { return }
            guard !results.isEmpty else { self.finish(p, nil); return }
            let dir = p.dir
            Task.detached(priority: .userInitiated) {
                var copies: [URL] = []
                for r in results {
                    if let u = await Self.copyMedia(r.itemProvider, into: dir) { copies.append(u) }
                }
                await MainActor.run { self.finish(p, copies) }
            }
        }
    }

    /// A photo or video's file, copied into `dir` while the provider's temporary file still exists.
    nonisolated private static func copyMedia(_ item: NSItemProvider, into dir: URL) async -> URL? {
        let id = item.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .movie) == true }
            ?? item.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? item.registeredTypeIdentifiers.first
        guard let id else { return nil }
        return await withCheckedContinuation { cont in
            item.loadFileRepresentation(forTypeIdentifier: id) { url, error in
                guard let url else {
                    HuskLog.log("docs", "a picked photo could not be read: \(error?.localizedDescription ?? "?")")
                    cont.resume(returning: nil)
                    return
                }
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var name = url.lastPathComponent
                if let suggested = item.suggestedName, !suggested.isEmpty {
                    name = (suggested as NSString).pathExtension.isEmpty && !url.pathExtension.isEmpty ? "\(suggested).\(url.pathExtension)" : suggested
                }
                let dst = AndroidDocuments.unique(name, in: dir)
                cont.resume(returning: (try? FileManager.default.copyItem(at: url, to: dst)) != nil ? dst : nil)
            }
        }
    }
}

extension AndroidDocumentPicker: QLPreviewControllerDataSource {
    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        MainActor.assumeIsolated { (previewing ?? URL(fileURLWithPath: "/")) as NSURL }
    }
}
