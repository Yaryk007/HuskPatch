import SwiftUI
import Photos
import AVKit

/// The photo library on this iPhone, newest first, grouped by day. Updates live (e.g. after a camera shot).
final class PhotoLibraryModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    struct Day: Identifiable {
        let id: Date
        let assets: [PHAsset]
    }

    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var days: [Day] = []
    @Published private(set) var all: [PHAsset] = []

    let images = PHCachingImageManager()
    private var result: PHFetchResult<PHAsset>?
    private var observing = false

    var allowed: Bool { status == .authorized || status == .limited }

    func load() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async { self.load() }
            }
            return
        }
        guard allowed else { return }
        if !observing {
            PHPhotoLibrary.shared().register(self)
            observing = true
        }
        fetch()
    }

    deinit {
        if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    private func fetch() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        let fetched = PHAsset.fetchAssets(with: options)
        result = fetched
        DispatchQueue.global(qos: .userInitiated).async {
            var list: [PHAsset] = []
            list.reserveCapacity(fetched.count)
            fetched.enumerateObjects { asset, _, _ in list.append(asset) }

            let calendar = Calendar.current
            var grouped: [Day] = []
            var currentDay: Date?
            var bucket: [PHAsset] = []
            for asset in list {
                let day = calendar.startOfDay(for: asset.creationDate ?? .distantPast)
                if day != currentDay, let previous = currentDay {
                    grouped.append(Day(id: previous, assets: bucket))
                    bucket = []
                }
                currentDay = day
                bucket.append(asset)
            }
            if let last = currentDay {
                grouped.append(Day(id: last, assets: bucket))
            }

            DispatchQueue.main.async {
                self.all = list
                self.days = grouped
                OSLogger.shared.log("Photos", "Loaded \(list.count) items")
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let result = result, changeInstance.changeDetails(for: result) != nil else { return }
        DispatchQueue.main.async { self.fetch() }
    }
}

struct PhotosApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var library = PhotoLibraryModel()
    @State private var viewing: Int?
    @State private var columns = 4

    var body: some View {
        ZStack {
            if library.status == .notDetermined || library.allowed {
                grid
            } else {
                PermissionView(
                    symbol: "photo.on.rectangle.angled",
                    title: "Photos needs access",
                    message: "Allow access to show the photos and videos on this phone.",
                    denied: true,
                    request: {}
                )
            }

            if let index = viewing {
                PhotoViewer(library: library, index: index) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { viewing = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(1)
            }
        }
        .onAppear { library.load() }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                AppTitle(title: "Photos", subtitle: library.all.isEmpty ? nil : "\(library.all.count) " + os.t("items"))

                if library.allowed && library.all.isEmpty {
                    Text(os.t("No photos yet"))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }

                ForEach(library.days) { day in
                    Text(dayTitle(day.id))
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
                        spacing: 2
                    ) {
                        ForEach(day.assets, id: \.localIdentifier) { asset in
                            PhotoThumb(asset: asset, images: library.images)
                                .onTapGesture {
                                    if let index = library.all.firstIndex(of: asset) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { viewing = index }
                                    }
                                }
                        }
                    }
                }
            }
        }
        .simultaneousGesture(
            MagnificationGesture().onEnded { scale in
                withAnimation(.spring()) {
                    columns = scale > 1 ? max(2, columns - 1) : min(6, columns + 1)
                }
            }
        )
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return os.t("Today") }
        if calendar.isDateInYesterday(date) { return os.t("Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = os.language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
        return formatter.string(from: date)
    }
}

private struct PhotoThumb: View {
    let asset: PHAsset
    let images: PHCachingImageManager

    @State private var image: UIImage?

    var body: some View {
        Color.osCard
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Group {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
            )
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(Self.duration(asset.duration))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if asset.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onAppear(perform: load)
    }

    private func load() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let side = 220 * UIScreen.main.scale / 2
        images.requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result { image = result }
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Full-screen viewer: swipe sideways for the next photo, down to close, double-tap to zoom.
private struct PhotoViewer: View {
    @ObservedObject var library: PhotoLibraryModel
    @State var index: Int
    let onClose: () -> Void

    @EnvironmentObject private var os: OSSettings
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var drag: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var showInfo = true

    var body: some View {
        let asset = index < library.all.count ? library.all[index] : nil
        let dismiss = max(0, drag.height) / 400

        ZStack {
            Color.black.opacity(Double(1 - dismiss))
                .ignoresSafeArea()

            Group {
                if let player = player {
                    VideoPlayer(player: player)
                } else if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .offset(drag)
            .scaleEffect(1 - dismiss * 0.3)
            .onTapGesture(count: 2) {
                withAnimation(.spring()) { zoom = zoom > 1 ? 1 : 2.5 }
            }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) { showInfo.toggle() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard zoom == 1 else { return }
                        drag = value.translation
                    }
                    .onEnded { value in
                        guard zoom == 1 else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if dy > 120 && abs(dy) > abs(dx) {
                            onClose()
                        } else if dx < -80 && index + 1 < library.all.count {
                            step(1)
                        } else if dx > 80 && index > 0 {
                            step(-1)
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = .zero }
                    }
            )

            if showInfo, let asset = asset {
                VStack {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .glass(Circle())
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(dateString(asset.creationDate))
                                .font(.system(size: 15, weight: .semibold))
                            Text(timeString(asset.creationDate))
                                .font(.system(size: 12))
                                .opacity(0.8)
                        }
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)

                    Spacer()

                    HStack(spacing: 18) {
                        Label("\(asset.pixelWidth)×\(asset.pixelHeight)", systemImage: "aspectratio")
                        if asset.isFavorite {
                            Label(os.t("Favourite"), systemImage: "heart.fill")
                        }
                        Text("\(index + 1) / \(library.all.count)")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glass(Capsule())
                }
                .opacity(Double(1 - dismiss * 2))
                .transition(.opacity)
            }
        }
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
    }

    private func step(_ delta: Int) {
        index += delta
        zoom = 1
        load()
    }

    private func load() {
        guard index < library.all.count else { return }
        let asset = library.all[index]
        image = nil
        player?.pause()
        player = nil
        let wanted = index

        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                DispatchQueue.main.async {
                    guard wanted == index, let item = item else { return }
                    let newPlayer = AVPlayer(playerItem: item)
                    player = newPlayer
                    newPlayer.play()
                }
            }
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let bounds = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        library.images.requestImage(
            for: asset,
            targetSize: CGSize(width: bounds.width * scale, height: bounds.height * scale),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if wanted == index, let result = result { image = result }
        }
    }

    private func dateString(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = os.language.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: date)
    }

    private func timeString(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return ClockText.string(for: date, h24: os.clock24h)
    }
}
