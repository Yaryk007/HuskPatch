// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// HuskPatch: the Android machine booted from a firmware image the user imported, instead of the LineageOS 23.2 image
/// Husk downloads -- a debloated build of it, say, for a lighter and faster guest.
///
/// What QEMU can boot here is a whole arm64 disk that UEFI starts from: a GPT disk with an EFI system partition, as Husk's
/// own `vda` is. It can be a qcow2 or a raw `.img` (gzipped is fine). An OTA zip, a factory image's partitions, or a
/// phone's sparse `system.img` are pieces of a phone, not a disk this machine can start, and the importer says so.
///
/// Each image gets its own userdata disk and UEFI variable store, created blank from the ones in the app, and its own
/// snapshot records -- so switching between images never restores one machine into another's disks, and the stock image's
/// data and snapshot are left exactly as they were.
struct FirmwareImage: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let file: String
    /// QEMU's block format: "qcow2" or "raw".
    let format: String
    let bytes: Int64
    let added: Date

    var diskPath: String { FirmwareStore.dir.appendingPathComponent(file).path }
    var userdataPath: String { FirmwareStore.dir.appendingPathComponent("\(id)-userdata.qcow2").path }
    var varsPath: String { FirmwareStore.dir.appendingPathComponent("\(id)-efi-vars.fd").path }
    /// Added to the names of the snapshot records (RAM size, display, memory layout) so each image has its own.
    var stampSuffix: String { ".fw-\(id)" }

    /// Blank userdata and UEFI variables for this image, the first time it boots.
    func prepare() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: userdataPath) {
            guard let seed = Bundle.main.path(forResource: "lineage-vdb-seed", ofType: "qcow2") else {
                throw FirmwareStore.Problem("lineage-vdb-seed.qcow2 missing from the app bundle")
            }
            try fm.copyItem(atPath: seed, toPath: userdataPath)
            HuskLog.log("firmware", "created a blank userdata disk for \(name)")
        }
        if !fm.fileExists(atPath: varsPath) {
            guard let seed = Bundle.main.path(forResource: "lineage-efi-vars-seed", ofType: "fd") else {
                throw FirmwareStore.Problem("lineage-efi-vars-seed.fd missing from the app bundle")
            }
            // The seed's boot entry points at Husk's image; for any other disk it fails to resolve and the firmware
            // falls back to \EFI\BOOT\BOOTAA64.EFI, which is what a removable-style GPT disk carries.
            try fm.copyItem(atPath: seed, toPath: varsPath)
        }
    }
}

@MainActor
final class FirmwareStore: ObservableObject {
    static let shared = FirmwareStore()

    /// Testing's developer toggle: the firmware section is shown, and the chosen image is booted.
    nonisolated static let enabledKey = "huskpatch.firmware.enabled"
    /// The image booted when the toggle is on, as JSON (UserDefaults, so QEMU's thread can read it).
    nonisolated static let activeKey = "huskpatch.firmware.active"

    struct Problem: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    @Published private(set) var images: [FirmwareImage] = []
    @Published private(set) var activeID: String?
    /// While an image is being copied in: what is happening.
    @Published private(set) var importing: String?
    @Published var lastError: String?

    nonisolated static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Firmware", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    nonisolated private static var indexURL: URL { dir.appendingPathComponent("index.json") }

    /// The image QEMU boots instead of Husk's, or nil for Husk's own.
    nonisolated static var active: FirmwareImage? {
        let d = UserDefaults.standard
        guard d.bool(forKey: enabledKey), let data = d.data(forKey: activeKey),
              let image = try? JSONDecoder().decode(FirmwareImage.self, from: data),
              FileManager.default.fileExists(atPath: image.diskPath) else { return nil }
        return image
    }

    init() {
        images = (try? Data(contentsOf: Self.indexURL)).flatMap { try? JSONDecoder().decode([FirmwareImage].self, from: $0) } ?? []
        activeID = Self.active?.id
    }

    private func save() {
        if let d = try? JSONEncoder().encode(images) { try? d.write(to: Self.indexURL, options: .atomic) }
    }

    /// Boot this image from the next start of Android (nil: Husk's LineageOS).
    func select(_ image: FirmwareImage?) {
        if let image, let d = try? JSONEncoder().encode(image) {
            UserDefaults.standard.set(d, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
        activeID = image?.id
        HuskLog.log("firmware", "next boot: \(image?.name ?? "Husk's LineageOS 23.2")")
        GuestImage.shared.refresh()
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        activeID = Self.active?.id
        GuestImage.shared.refresh()
    }

    func rename(_ image: FirmwareImage, to name: String) {
        guard let i = images.firstIndex(of: image), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        images[i].name = name
        save()
        if activeID == image.id { select(images[i]) }
    }

    /// Delete an image with its data and snapshot records.
    func remove(_ image: FirmwareImage) {
        if activeID == image.id { select(nil) }
        for path in [image.diskPath, image.userdataPath, image.varsPath] { try? FileManager.default.removeItem(atPath: path) }
        forgetSnapshot(image)
        images.removeAll { $0.id == image.id }
        save()
    }

    /// Factory reset: a blank userdata disk (and UEFI variables) on the next boot.
    func eraseData(_ image: FirmwareImage) {
        for path in [image.userdataPath, image.varsPath] { try? FileManager.default.removeItem(atPath: path) }
        forgetSnapshot(image)
    }

    private func forgetSnapshot(_ image: FirmwareImage) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["husk-snapshot.mib", "husk-snapshot.display", "husk-memory-strategy"] {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(name + image.stampSuffix))
        }
    }

    // MARK: importing

    func importImage(from url: URL) {
        guard importing == nil else { return }
        importing = "Reading \(url.lastPathComponent)…"
        lastError = nil
        let name = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        Task.detached(priority: .userInitiated) {
            let result: Result<FirmwareImage, Error>
            do { result = .success(try Self.copyIn(url, name: name) { note in Task { @MainActor in FirmwareStore.shared.importing = note } }) }
            catch { result = .failure(error) }
            await MainActor.run {
                let store = FirmwareStore.shared
                store.importing = nil
                switch result {
                case .success(let image):
                    store.images.append(image)
                    store.save()
                    HuskLog.log("firmware", "imported \(image.name): \(image.format), \(image.bytes) bytes")
                case .failure(let error):
                    store.lastError = error.localizedDescription
                    HuskLog.log("firmware", "import failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Copies (or gunzips) the picked file into Firmware/ and works out what it is.
    nonisolated private static func copyIn(_ url: URL, name: String, progress: @escaping (String) -> Void) throws -> FirmwareImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let id = UUID().uuidString.prefix(8).lowercased()
        let tmp = dir.appendingPathComponent("\(id).importing")
        try? fm.removeItem(at: tmp)

        let head = try read(url, count: 16)
        if head.starts(with: [0x1f, 0x8b]) {
            progress("Unpacking \(url.lastPathComponent)…")
            try GuestImage.gunzip(from: url, to: tmp)
        } else {
            progress("Copying \(url.lastPathComponent)…")
            try fm.copyItem(at: url, to: tmp)
        }

        do {
            let format = try identify(tmp)
            let file = "\(id).\(format == "qcow2" ? "qcow2" : "img")"
            try fm.moveItem(at: tmp, to: dir.appendingPathComponent(file))
            let size = ((try? fm.attributesOfItem(atPath: dir.appendingPathComponent(file).path))?[.size] as? NSNumber)?.int64Value ?? 0
            return FirmwareImage(id: String(id), name: name, file: file, format: format, bytes: size, added: Date())
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    /// "qcow2" or "raw" for a disk this machine can boot; otherwise an error naming what the file actually is.
    nonisolated static func identify(_ url: URL) throws -> String {
        let head = try read(url, count: 4096 + 520)
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        if head.starts(with: [0x51, 0x46, 0x49, 0xFB]) { return "qcow2" }
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            throw Problem("This is a zip (an OTA or flashable package, or a factory image archive). Unpack it on a computer and import the "
                        + "bootable disk image inside it, if it has one: Android's packages hold partitions, which this machine can't start on their own.")
        }
        if head.starts(with: [0x3A, 0xFF, 0x26, 0xED]) {
            throw Problem("This is an Android sparse image: one partition (system, vendor…) of a phone's firmware, not a whole disk. "
                        + "The Android machine needs a complete arm64 disk with an EFI system partition, like Husk's own image.")
        }
        if head.starts(with: Array("ANDROID!".utf8)) {
            throw Problem("This is an Android boot.img (a kernel and ramdisk), not a whole disk. Import a complete arm64 UEFI disk image.")
        }
        guard size >= 64 * 1024 * 1024 else {
            throw Problem("Too small to be a system disk (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))).")
        }
        // A GPT header ("EFI PART") at LBA 1, for 512-byte or 4096-byte sectors.
        let gpt = Array("EFI PART".utf8)
        let at512 = head.count >= 520 && Array(head[512..<520]) == gpt
        let at4096 = head.count >= 4104 && Array(head[4096..<4104]) == gpt
        guard at512 || at4096 else {
            throw Problem("No partition table found: this doesn't look like a bootable disk. The Android machine starts a GPT disk "
                        + "with an EFI system partition (qcow2 or raw .img), like Husk's own image.")
        }
        return "raw"
    }

    nonisolated private static func read(_ url: URL, count: Int) throws -> [UInt8] {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        return Array(try h.read(upToCount: count) ?? Data())
    }
}

// MARK: - the card

/// Testing › System's "Android firmware" card: the developer toggle, the images, and importing one.
struct AndroidFirmwareSection: View {
    @ObservedObject private var store = FirmwareStore.shared
    @ObservedObject private var runner = QemuRunner.shared
    @AppStorage(FirmwareStore.enabledKey) private var enabled = false
    @State private var picking = false
    @State private var confirmErase: FirmwareImage?
    @State private var confirmRemove: FirmwareImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { enabled }, set: { store.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom firmware").font(.system(size: 16, design: .rounded))
                    Text("Boot the Android machine from an image you import, such as a debloated build")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
            }
            .toggleStyle(Material3SwitchStyle())

            if enabled {
                VStack(spacing: 2) {
                    choice(title: "LineageOS 23.2 (Husk)", detail: "Android 16, as Husk downloads it", selected: store.activeID == nil) {
                        store.select(nil)
                    }
                    ForEach(store.images) { image in
                        choice(title: image.name,
                               detail: "\(image.format == "qcow2" ? "qcow2" : "Raw disk") · "
                                     + ByteCountFormatter.string(fromByteCount: image.bytes, countStyle: .file),
                               selected: store.activeID == image.id) { store.select(image) }
                            .contextMenu {
                                Button("Erase its data", systemImage: "eraser") { confirmErase = image }
                                Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = image }
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let note = store.importing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(note).font(.system(size: 14, design: .rounded))
                    }
                } else {
                    Button { picking = true } label: { Label("Import firmware", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.expressive(.tonal))
                }
                if let error = store.lastError {
                    Text(error).font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.error))
                }
                Text(runner.isRunning ? "Android is running: the choice applies the next time it starts." :
                        "Applies the next time Android starts. Long-press an image to erase its data or remove it.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                Text("Needs a complete arm64 disk that boots with UEFI (GPT with an EFI system partition), as qcow2 or raw .img, "
                   + "optionally gzipped. Each image gets its own data and snapshot. The library and app installs talk to Husk's "
                   + "bridge service on port 5599, so a debloated build should keep Husk's init scripts.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { store.importImage(from: url) }
        }
        .alert("Erase this image's data?", isPresented: Binding(get: { confirmErase != nil }, set: { if !$0 { confirmErase = nil } })) {
            Button("Erase", role: .destructive) { if let i = confirmErase { store.eraseData(i) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its userdata and saved machine go; it starts like a new phone.") }
        .alert("Remove this image?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove", role: .destructive) { if let i = confirmRemove { store.remove(i) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The image, its data and its saved machine are deleted.") }
    }

    private func choice(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(uiColor: selected ? Material3.primary : Material3.onSurfaceVariant))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
                    Text(detail).font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                }
                Spacer()
            }
            .foregroundStyle(Color(uiColor: Material3.onSurface))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(uiColor: Material3.surfaceContainerHigh))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
