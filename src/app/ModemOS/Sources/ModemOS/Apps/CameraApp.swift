import SwiftUI
import AVFoundation
import Photos

/// The real camera: live preview, shutter, flash, front/back, zoom. Shots are saved to the photo library.
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()

    @Published private(set) var authorized: Bool?
    @Published private(set) var running = false
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published var flash: AVCaptureDevice.FlashMode = .off
    @Published private(set) var lastPhoto: UIImage?
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var shutterFlash = false
    @Published private(set) var message: String?

    private let queue = DispatchQueue(label: "modemos.camera")
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            queue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorized = granted
                    OSLogger.shared.log("Permissions", "Camera: \(granted ? "allowed" : "denied")")
                    if granted { self.queue.async { self.configureAndRun() } }
                }
            }
        default:
            authorized = false
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                OSLogger.shared.log("Camera", "Session stopped")
            }
            DispatchQueue.main.async { self.running = false }
        }
    }

    private func configureAndRun() {
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .photo
            if let device = Self.device(.back), let newInput = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(newInput) {
                session.addInput(newInput)
                input = newInput
            } else {
                DispatchQueue.main.async { self.message = "No camera found" }
                OSLogger.shared.log("Camera", "No camera available", level: .error)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.maxPhotoQualityPrioritization = .balanced
            }
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning {
            session.startRunning()
            OSLogger.shared.log("Camera", "Session started (\(position == .back ? "back" : "front"))")
        }
        DispatchQueue.main.async { self.running = self.session.isRunning }
    }

    private static func device(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
        return discovery.devices.first
    }

    func flip() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        queue.async {
            guard let device = Self.device(next), let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            if let old = self.input { self.session.removeInput(old) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
            } else if let old = self.input {
                self.session.addInput(old)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.position = next
                self.zoom = 1
            }
            OSLogger.shared.log("Camera", "Switched to \(next == .back ? "back" : "front") camera")
        }
    }

    /// The zoom factor shown as "1x" on multi-camera iPhones (their widest lens is 0.5x).
    private var baseZoom: CGFloat {
        guard let device = input?.device else { return 1 }
        if device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera {
            return 2
        }
        return 1
    }

    var hasUltraWide: Bool { baseZoom > 1 }

    /// `factor` as the user sees it (0.5x, 1x, 2x ...).
    func setZoom(_ factor: CGFloat) {
        queue.async {
            guard let device = self.input?.device else { return }
            let raw = min(max(factor * self.baseZoom, device.minAvailableVideoZoomFactor), min(device.maxAvailableVideoZoomFactor, 15 * self.baseZoom))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = raw
                device.unlockForConfiguration()
                let shown = raw / self.baseZoom
                DispatchQueue.main.async { self.zoom = shown }
            } catch {
                OSLogger.shared.log("Camera", "Zoom failed: \(error.localizedDescription)", level: .warn)
            }
        }
    }

    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.input?.device else { return }
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    func capture() {
        guard running else { return }
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(flash) {
            settings.flashMode = flash
        }
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            connection.isVideoMirrored = position == .front
        }
        output.capturePhoto(with: settings, delegate: self)
        Haptics.tap(.rigid)
        shutterFlash = true
        after(0.12) { self.shutterFlash = false }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            OSLogger.shared.log("Camera", "Capture failed: \(error.localizedDescription)", level: .error)
            return
        }
        guard let data = photo.fileDataRepresentation() else { return }
        let image = UIImage(data: data)
        DispatchQueue.main.async { self.lastPhoto = image }
        OSLogger.shared.log("Camera", "Photo taken (\(data.count / 1024) KB)")
        save(data)
    }

    private func save(_ data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                OSLogger.shared.log("Camera", "Not allowed to save to Photos", level: .warn)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }) { ok, error in
                OSLogger.shared.log(
                    "Camera",
                    ok ? "Saved to Photos" : "Save failed: \(error?.localizedDescription ?? "?")",
                    level: ok ? .info : .error
                )
            }
        }
    }
}

/// A UIView whose layer is the live camera preview.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}

struct CameraApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var camera = CameraModel()
    @State private var reviewing = false
    @State private var focusPoint: CGPoint?
    @State private var pinchStart: CGFloat?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if camera.authorized == false {
                    PermissionView(
                        symbol: "camera.fill",
                        title: "Camera needs access",
                        message: "Allow camera access to take photos.",
                        denied: true,
                        request: {}
                    )
                    .environment(\.colorScheme, .dark)
                } else {
                    viewfinder(geo.size)
                }

                if camera.shutterFlash {
                    Color.black.ignoresSafeArea()
                }

                if reviewing, let photo = camera.lastPhoto {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                    }
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { reviewing = false } }
                    .transition(.opacity)
                }
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func viewfinder(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.bottom, 8)

            ZStack {
                CameraPreview(session: camera.session)
                    .overlay {
                        if !camera.running {
                            ProgressView().tint(.white)
                        }
                    }
                    .overlay {
                        if let message = camera.message {
                            Text(os.t(message)).foregroundColor(.white)
                        }
                    }
                    .overlay {
                        if let point = focusPoint {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.yellow, lineWidth: 1.5)
                                .frame(width: 70, height: 70)
                                .position(point)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            let frame = CGSize(width: size.width, height: size.width * 4 / 3)
                            camera.focus(at: CGPoint(x: value.location.y / frame.height, y: 1 - value.location.x / frame.width))
                            withAnimation(.easeOut(duration: 0.15)) { focusPoint = value.location }
                            after(1.2) { withAnimation { focusPoint = nil } }
                        }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                if pinchStart == nil { pinchStart = camera.zoom }
                                camera.setZoom((pinchStart ?? 1) * scale)
                            }
                            .onEnded { _ in pinchStart = nil }
                    )

                zoomButtons
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
            }
            .frame(width: size.width, height: size.width * 4 / 3)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 8)

            Text(os.t("PHOTO"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.yellow)
                .padding(.bottom, 12)

            controls
                .padding(.bottom, 12)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                let modes: [AVCaptureDevice.FlashMode] = [.off, .auto, .on]
                let index = modes.firstIndex(of: camera.flash) ?? 0
                camera.flash = modes[(index + 1) % modes.count]
                Haptics.tap()
            } label: {
                Image(systemName: flashSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(camera.flash == .off ? .white : .yellow)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text(camera.position == .back ? os.t("Back camera") : os.t("Front camera"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
    }

    private var flashSymbol: String {
        switch camera.flash {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic.fill"
        default: return "bolt.slash.fill"
        }
    }

    private var zoomButtons: some View {
        let stops: [CGFloat] = camera.hasUltraWide ? [0.5, 1, 2, 3] : [1, 2, 3]
        return HStack(spacing: 8) {
            ForEach(stops, id: \.self) { stop in
                let selected = abs(camera.zoom - stop) < 0.05
                Button {
                    camera.setZoom(stop)
                    Haptics.tap()
                } label: {
                    Text(selected ? String(format: "%gx", Double(stop)) : String(format: "%g", Double(stop)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selected ? .yellow : .white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Button {
                if camera.lastPhoto != nil {
                    withAnimation(.easeOut(duration: 0.2)) { reviewing = true }
                }
            } label: {
                Group {
                    if let photo = camera.lastPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.15)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(PressScaleStyle())

            Spacer()

            Button {
                camera.capture()
            } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(Color.white).frame(width: 64, height: 64)
                }
            }
            .buttonStyle(PressScaleStyle(pressedScale: 0.88))

            Spacer()

            Button {
                camera.flip()
                Haptics.tap()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 32)
    }
}
