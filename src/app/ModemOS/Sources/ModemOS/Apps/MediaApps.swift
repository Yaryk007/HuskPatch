import SwiftUI
import AVFoundation
import MediaPlayer
import QuickLook
import UniformTypeIdentifiers

// MARK: - Recorder

final class RecorderModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var recordings: [URL] = []
    @Published private(set) var recording = false
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var playing: URL?
    @Published private(set) var denied = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meter: Timer?

    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        recordings = files.filter { $0.pathExtension == "m4a" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func toggle() {
        recording ? stop() : start()
    }

    static func askMicrophone(_ done: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: done)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(done)
        }
    }

    private func start() {
        Self.askMicrophone { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.denied = true
                    OSLogger.shared.log("Recorder", "Microphone denied", level: .warn)
                    return
                }
                self.begin()
            }
        }
    }

    private func begin() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = Self.folder.appendingPathComponent("Recording \(formatter.string(from: Date())).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            newRecorder.record()
            recorder = newRecorder
            recording = true
            OSLogger.shared.log("Recorder", "Recording started")
            meter = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                self.level = CGFloat(max(0, (power + 50) / 50))
            }
        } catch {
            OSLogger.shared.log("Recorder", error.localizedDescription, level: .error)
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        meter?.invalidate()
        meter = nil
        recording = false
        level = 0
        OSLogger.shared.log("Recorder", "Recording saved")
        load()
    }

    func play(_ url: URL) {
        if playing == url {
            player?.stop()
            playing = nil
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
        playing = url
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        load()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.playing = nil }
    }

    static func duration(_ url: URL) -> String {
        let seconds = Int(((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct RecorderApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var model = RecorderModel()

    var body: some View {
        VStack(spacing: 0) {
            AppTitle(title: "Recorder")
            List {
                if model.recordings.isEmpty {
                    Text(os.t("No recordings yet")).foregroundColor(.secondary)
                }
                ForEach(model.recordings, id: \.self) { url in
                    Button {
                        model.play(url)
                    } label: {
                        HStack {
                            Image(systemName: model.playing == url ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text(url.deletingPathExtension().lastPathComponent).foregroundColor(.primary)
                                Text(RecorderModel.duration(url)).font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }
                    }
                    .osListRow()
                }
                .onDelete { offsets in
                    offsets.map { model.recordings[$0] }.forEach(model.delete)
                }
            }
            .osList()

            VStack(spacing: 14) {
                HStack(spacing: 3) {
                    ForEach(0..<30, id: \.self) { bar in
                        Capsule()
                            .fill(Color.red.opacity(model.recording ? 0.9 : 0.25))
                            .frame(width: 4, height: 6 + model.level * 50 * CGFloat(abs(sin(Double(bar) * 0.7)) + 0.2))
                    }
                }
                .frame(height: 60)
                .animation(.easeOut(duration: 0.08), value: model.level)

                if model.denied {
                    Text(os.t("Microphone access is off")).foregroundColor(.secondary)
                }

                Button {
                    Haptics.tap(.medium)
                    model.toggle()
                } label: {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.3), lineWidth: 4).frame(width: 76, height: 76)
                        RoundedRectangle(cornerRadius: model.recording ? 8 : 30)
                            .fill(Color.red)
                            .frame(width: model.recording ? 32 : 60, height: model.recording ? 32 : 60)
                    }
                }
                .buttonStyle(PressScaleStyle())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.recording)
            }
            .padding(.vertical, 16)
        }
        .onAppear { model.load() }
        .onDisappear { if model.recording { model.stop() } }
    }
}

// MARK: - Music

final class MusicModel: ObservableObject {
    @Published private(set) var status = MPMediaLibrary.authorizationStatus()
    @Published private(set) var songs: [MPMediaItem] = []
    @Published private(set) var nowPlaying: MPMediaItem?
    @Published private(set) var isPlaying = false

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []

    func load() {
        if status == .notDetermined {
            MPMediaLibrary.requestAuthorization { _ in
                DispatchQueue.main.async {
                    self.status = MPMediaLibrary.authorizationStatus()
                    self.load()
                }
            }
            return
        }
        guard status == .authorized else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = MPMediaQuery.songs().items ?? []
            DispatchQueue.main.async {
                self.songs = items
                OSLogger.shared.log("Music", "Library has \(items.count) songs")
            }
        }
        if observers.isEmpty {
            player.beginGeneratingPlaybackNotifications()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { [weak self] _ in
                self?.refresh()
            })
            observers.append(center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        refresh()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        player.endGeneratingPlaybackNotifications()
    }

    private func refresh() {
        nowPlaying = player.nowPlayingItem
        isPlaying = player.playbackState == .playing
    }

    func play(_ song: MPMediaItem) {
        player.setQueue(with: MPMediaItemCollection(items: songs))
        player.nowPlayingItem = song
        player.play()
        OSLogger.shared.log("Music", "Playing \(song.title ?? "?")")
    }

    func toggle() {
        isPlaying ? player.pause() : player.play()
    }

    func next() { player.skipToNextItem() }
    func previous() { player.skipToPreviousItem() }
}

struct MusicApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var music = MusicModel()
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            if music.status == .denied || music.status == .restricted {
                PermissionView(
                    symbol: "music.note",
                    title: "Music needs access",
                    message: "Allow access to your music library to play your songs.",
                    denied: true,
                    request: {}
                )
            } else {
                AppTitle(title: "Music", subtitle: music.songs.isEmpty ? nil : "\(music.songs.count) " + os.t("songs"))
                OSSearchField(prompt: "Search", text: $search)
                    .padding(.horizontal, 16)
                List(filtered, id: \.persistentID) { song in
                    Button {
                        music.play(song)
                    } label: {
                        SongRow(song: song, current: song.persistentID == music.nowPlaying?.persistentID)
                    }
                    .osListRow()
                }
                .osList()
                .overlay {
                    if music.status == .authorized && music.songs.isEmpty {
                        Text(os.t("No songs in your library")).foregroundColor(.secondary)
                    }
                }
                if let song = music.nowPlaying {
                    nowPlaying(song)
                }
            }
        }
        .onAppear { music.load() }
    }

    private var filtered: [MPMediaItem] {
        guard !search.isEmpty else { return music.songs }
        return music.songs.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(search) || ($0.artist ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    private func nowPlaying(_ song: MPMediaItem) -> some View {
        HStack(spacing: 12) {
            Artwork(song: song, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(song.artist ?? "").font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: music.previous) { Image(systemName: "backward.fill") }
            Button(action: music.toggle) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26))
            }
            .frame(width: 44)
            Button(action: music.next) { Image(systemName: "forward.fill") }
        }
        .font(.system(size: 20))
        .foregroundColor(.primary)
        .padding(12)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

private struct SongRow: View {
    let song: MPMediaItem
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            Artwork(song: song, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? "—")
                    .foregroundColor(current ? Color.osAccent : .primary)
                    .lineLimit(1)
                Text(song.artist ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct Artwork: View {
    let song: MPMediaItem
    let size: CGFloat

    var body: some View {
        Group {
            if let image = song.artwork?.image(at: CGSize(width: size * 2, height: size * 2)) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.pink.opacity(0.2)
                    Image(systemName: "music.note").foregroundColor(.pink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Files

struct FilesApp: View {
    @EnvironmentObject private var os: OSSettings
    @State private var folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    @State private var items: [URL] = []
    @State private var importing = false
    @State private var preview: URL?

    private var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if folder != root {
                    Button {
                        folder = folder.deletingLastPathComponent()
                        load()
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    }
                    .padding(.leading, 16)
                }
                AppTitle(title: folder == root ? "Files" : folder.lastPathComponent)
                Button {
                    importing = true
                } label: {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 20, weight: .semibold))
                }
                .padding(.trailing, 20)
            }

            let storage = DeviceInfo.storage
            if storage.total > 0 {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(os.t("Internal storage")).font(.system(size: 15, weight: .semibold))
                        ProgressView(value: Double(storage.total - storage.free), total: Double(storage.total))
                        Text(
                            ByteCountFormatter.string(fromByteCount: storage.total - storage.free, countStyle: .file) + " / "
                                + ByteCountFormatter.string(fromByteCount: storage.total, countStyle: .file)
                        )
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            List {
                if items.isEmpty {
                    Text(os.t("No files. Tap the import button to add some.")).foregroundColor(.secondary)
                }
                ForEach(items, id: \.self) { url in
                    Button {
                        if isFolder(url) {
                            folder = url
                            load()
                        } else {
                            preview = url
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isFolder(url) ? "folder.fill" : symbol(url))
                                .font(.system(size: 24))
                                .foregroundColor(isFolder(url) ? .blue : .secondary)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent).foregroundColor(.primary).lineLimit(1)
                                Text(details(url)).font(.system(size: 12)).foregroundColor(.secondary)
                            }
                        }
                    }
                    .osListRow()
                }
                .onDelete { offsets in
                    offsets.map { items[$0] }.forEach { try? FileManager.default.removeItem(at: $0) }
                    load()
                }
            }
            .osList()
        }
        .onAppear(perform: load)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                let target = folder.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: target)
                if scoped { url.stopAccessingSecurityScopedResource() }
                OSLogger.shared.log("Files", "Imported \(url.lastPathComponent)")
            }
            load()
        }
        .quickLookPreview($preview)
    }

    private func load() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        items = found.sorted { a, b in
            if isFolder(a) != isFolder(b) { return isFolder(a) }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func details(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        let date = values?.contentModificationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? ""
        return isFolder(url) ? date : "\(size) · \(date)"
    }

    private func symbol(_ url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .text) { return "doc.text" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        return "doc"
    }
}
