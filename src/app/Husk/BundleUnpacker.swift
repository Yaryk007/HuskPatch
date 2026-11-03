// SPDX-License-Identifier: GPL-2.0-or-later
import Compression
import Foundation

/// Takes the APKs out of an app bundle: an .xapk (APKPure), .apkm (APKMirror) or .apks (bundletool), which are zip files holding a base APK and its splits and asset packs.
///
/// Only what is needed is read: the zip's central directory, then each APK's bytes copied across in chunks. An APK inside a bundle is usually stored, not compressed (it is
/// already a zip); a deflated one is inflated as it streams. Either way a 200 MB asset pack costs a few megabytes of memory, not 200.
enum BundleUnpacker {
    static let extensions: Set<String> = ["xapk", "apkm", "apks"]

    enum Failure: LocalizedError {
        case notAZip, unsupported(String)
        var errorDescription: String? {
            switch self {
            case .notAZip: return "That file is not a bundle Husk can read."
            case .unsupported(let why): return why
            }
        }
    }

    /// Whether an APK is a split or an asset pack, as the bundle formats name them, rather than the app itself.
    static func isSplit(_ name: String) -> Bool {
        let n = name.lowercased()
        if n == "base.apk" || n == "base-master.apk" { return false }
        return n.hasPrefix("config.") || n.hasPrefix("split_") || n.hasPrefix("asset_pack") || n.hasPrefix("base-") || n.hasPrefix("install_time")
    }

    /// The fallback order when an APK's manifest cannot be read: the app itself, then its 64-bit libraries and asset packs,
    /// then the language and screen-density splits, which it does not need.
    ///
    /// `siblings` are the app's other APK names. Besides Android's own split names (config.*, split_*), a split may be named
    /// after the base: com.game.apk beside com.game.config.arm64_v8a.apk and com.game.SomeAssetPack.apk, the way Google
    /// Play hands them out. A name that is another's name plus ".something" is that one's split.
    static func rank(_ name: String, siblings: [String] = []) -> Int {
        let n = name.lowercased()
        let named = siblings.contains { other in
            let o = other.lowercased()
            guard o != n, o.hasSuffix(".apk") else { return false }
            return n.hasPrefix(String(o.dropLast(4)) + ".")
        }
        if !isSplit(n) && !named { return 0 }
        if n.contains("arm64") { return 1 }
        if n.hasPrefix("asset_pack") || n.hasPrefix("install_time") || (named && !n.contains(".config.")) { return 2 }
        return 3
    }

    /// Read each manifest once, before sorting. A manifest-confirmed base takes precedence over every filename guess;
    /// a manifest-confirmed split can never be promoted to base just because it is named models.apk or textures.apk.
    static func orderedAPKs(_ paths: [String], manifest: (String) -> Data?) -> [String] {
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let ranked = paths.map { path -> (path: String, priority: Int) in
            let name = (path as NSString).lastPathComponent
            let fallback = rank(name, siblings: names)
            let split = manifest(path).flatMap { ApkMetadata.isSplit($0) }
            let priority: Int
            switch split {
            case false?: priority = -1
            case true?: priority = fallback == 0 ? 2 : fallback
            case nil: priority = fallback
            }
            return (path, priority)
        }
        return ranked.sorted {
            $0.priority != $1.priority ? $0.priority < $1.priority : $0.path < $1.path
        }.map { $0.path }
    }

    /// Copies every APK in `bundle` into `dir`, and its expansion files (Android/obb/<package>/*.obb, which XAPKs carry) into `dir`/obb. Returns their names.
    @discardableResult
    static func unpack(_ bundle: URL, into dir: URL) throws -> [String] {
        let scoped = bundle.startAccessingSecurityScopedResource()
        defer { if scoped { bundle.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: bundle)
        defer { try? file.close() }

        let size = try file.seekToEnd()
        // The end-of-central-directory record is in the last 64 KB plus 22 bytes.
        let tail = min(size, 70_000)
        try file.seek(toOffset: size - tail)
        guard let end = try file.read(upToCount: Int(tail)), end.count >= 22 else { throw Failure.notAZip }
        let bytes = [UInt8](end)
        var e = bytes.count - 22
        while e >= 0, !(bytes[e] == 0x50 && bytes[e + 1] == 0x4b && bytes[e + 2] == 5 && bytes[e + 3] == 6) { e -= 1 }
        guard e >= 0 else { throw Failure.notAZip }
        var count = UInt64(le16(bytes, e + 10))
        var dirSize = UInt64(le32(bytes, e + 12)), dirOffset = UInt64(le32(bytes, e + 16))
        if dirOffset == 0xffff_ffff || count == 0xffff || dirSize == 0xffff_ffff {
            // Zip64 (bundles over 4 GB, or with over 65535 entries): the locator just before the record points at the 64-bit record
            guard e >= 20, le32(bytes, e - 20) == 0x0706_4b50 else { throw Failure.notAZip }
            try file.seek(toOffset: le64(bytes, e - 20 + 8))
            guard let rec = try file.read(upToCount: 56), rec.count == 56 else { throw Failure.notAZip }
            let r = [UInt8](rec)
            guard le32(r, 0) == 0x0606_4b50 else { throw Failure.notAZip }
            count = le64(r, 32); dirSize = le64(r, 40); dirOffset = le64(r, 48)
        }

        try file.seek(toOffset: dirOffset)
        guard let directory = try file.read(upToCount: Int(dirSize)), directory.count == Int(dirSize) else { throw Failure.notAZip }
        let cd = [UInt8](directory)

        var names: [String] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, le32(cd, p) == 0x0201_4b50 else { break }
            let method = le16(cd, p + 10)
            var compressed = UInt64(le32(cd, p + 20)), uncompressed = UInt64(le32(cd, p + 24))
            let nameLen = Int(le16(cd, p + 28)), extraLen = Int(le16(cd, p + 30)), commentLen = Int(le16(cd, p + 32))
            var localOffset = UInt64(le32(cd, p + 42))
            guard p + 46 + nameLen + extraLen <= cd.count else { break }
            let name = String(decoding: cd[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            // Zip64 sizes and offset: in extra field 1, only the ones the header marks 0xffffffff, in this order
            var x = p + 46 + nameLen
            let xend = x + extraLen
            while x + 4 <= xend {
                let id = le16(cd, x), len = Int(le16(cd, x + 2))
                if id == 1 {
                    var q = x + 4
                    if uncompressed == 0xffff_ffff, q + 8 <= x + 4 + len { uncompressed = le64(cd, q); q += 8 }
                    if compressed == 0xffff_ffff, q + 8 <= x + 4 + len { compressed = le64(cd, q); q += 8 }
                    if localOffset == 0xffff_ffff, q + 8 <= x + 4 + len { localOffset = le64(cd, q) }
                }
                x += 4 + len
            }
            p += 46 + nameLen + extraLen + commentLen

            let base = (name as NSString).lastPathComponent
            let lower = base.lowercased()
            let isOBB = lower.hasSuffix(".obb")
            guard lower.hasSuffix(".apk") || isOBB, !name.hasSuffix("/"), !base.hasPrefix(".") else { continue }
            guard method == 0 || method == 8 else { throw Failure.unsupported("\(base) is packed in a way (zip method \(method)) Husk cannot unpack.") }

            // The local header has its own name and extra lengths; the data follows them.
            try file.seek(toOffset: localOffset)
            guard let local = try file.read(upToCount: 30), local.count == 30 else { throw Failure.notAZip }
            let lh = [UInt8](local)
            let dataStart = localOffset + 30 + UInt64(le16(lh, 26)) + UInt64(le16(lh, 28))
            try file.seek(toOffset: dataStart)

            // An expansion file goes to obb/ under its own name: the runtime finds it there when the game asks for Android/obb/<package>/<name>
            var destDir = dir
            if isOBB {
                destDir = dir.appendingPathComponent("obb")
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            }
            let dest = destDir.appendingPathComponent(base)
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            let out = try FileHandle(forWritingTo: dest)
            defer { try? out.close() }
            // Deflated entries (some XAPK makers compress everything) are inflated as they stream, so memory stays at a chunk
            var inflate: OutputFilter?
            if method == 8 { inflate = try OutputFilter(.decompress, using: .zlib) { data in if let data { try out.write(contentsOf: data) } } }
            var left = compressed
            while left > 0 {
                let chunk = Int(min(left, 4 << 20))
                guard let data = try file.read(upToCount: chunk), !data.isEmpty else { throw Failure.notAZip }
                if let inflate { try inflate.write(data) } else { try out.write(contentsOf: data) }
                left -= UInt64(data.count)
            }
            try inflate?.finalize()
            if method == 8, let written = try? out.offset(), written != uncompressed {
                throw Failure.unsupported("\(base) did not unpack whole (\(written) of \(uncompressed) bytes).")
            }
            names.append(isOBB ? "obb/" + base : base)
        }
        if !names.contains(where: { $0.lowercased().hasSuffix(".apk") }) { throw Failure.unsupported("There are no APKs in that bundle.") }
        return names
    }

    private static func le16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    private static func le64(_ b: [UInt8], _ o: Int) -> UInt64 { UInt64(le32(b, o)) | UInt64(le32(b, o + 4)) << 32 }
}
