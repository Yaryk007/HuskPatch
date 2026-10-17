// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import Photos
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's Camera, after LineageOS's Aperture: the viewfinder, the flash and grid toggles at the top, the
/// modes (Photo, QR) over a shutter row with the last picture on the left and the switch between cameras on the right.
/// Photos go to the iPhone's photo library; a QR code read in QR mode offers to open its link in Browser.
@MainActor
final class AndroidCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    enum Mode: String, CaseIterable { case photo = "Photo", qr = "QR" }
    enum Flash: CaseIterable { case off, auto, on }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let queue = DispatchQueue(label: "huskpatch.camera")
    private var input: AVCaptureDeviceInput?

    @Published var allowed: Bool?
    @Published var front = false
    @Published var flash = Flash.off
    @Published var lastPhoto: UIImage?
    @Published var flashing = false
    @Published var code: String?
    @Published var mode = Mode.photo { didSet { configureMetadata() } }
    @Published var zoom: CGFloat = 1

    func start() async {
        var ok = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            ok = await AVCaptureDevice.requestAccess(for: .video)
        }
        allowed = ok
        guard ok else { return }
        if session.inputs.isEmpty { configure() }
        let s = session
        queue.async { if !s.isRunning { s.startRunning() } }
    }

    func stop() {
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        attachCamera()
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        }
        session.commitConfiguration()
        configureMetadata()
    }

    private func attachCamera() {
        if let input { session.removeInput(input) }
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
        guard let device, let i = try? AVCaptureDeviceInput(device: device), session.canAddInput(i) else { return }
        session.addInput(i)
        input = i
        zoom = 1
    }

    private func configureMetadata() {
        let types: [AVMetadataObject.ObjectType] = mode == .qr ? [.qr, .ean13, .ean8, .code128, .dataMatrix, .pdf417, .aztec] : []
        metadataOutput.metadataObjectTypes = types.filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
        if mode != .qr { code = nil }
    }

    func flip() {
        front.toggle()
        session.beginConfiguration()
        attachCamera()
        session.commitConfiguration()
    }

    func setZoom(_ z: CGFloat) {
        guard let device = input?.device else { return }
        let clamped = min(max(z, 1), min(device.activeFormat.videoMaxZoomFactor, 10))
        try? device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
        zoom = clamped
    }

    func capture() {
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.on) {
            settings.flashMode = flash == .on ? .on : flash == .auto ? .auto : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
        withAnimation(.easeOut(duration: 0.08)) { flashing = true }
        Task { try? await Task.sleep(nanoseconds: 120_000_000); withAnimation(.easeIn(duration: 0.15)) { flashing = false } }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        let image = UIImage(data: data)
        Task { @MainActor in self.lastPhoto = image }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        Task { @MainActor in
            if let value, value != self.code {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self.code = value
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ v: PreviewView, context: Context) {}
}

struct AndroidCameraApp: View {
    @StateObject private var camera = AndroidCamera()
    @State private var grid = false
    @State private var pinchBase: CGFloat = 1
    @State private var viewing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.allowed == false {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
                    Text("Camera needs permission. Allow HuskPatch to use the camera in iOS Settings.")
                        .font(.system(size: 15, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Button("Open iOS Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                        .buttonStyle(.expressive(.filled))
                }
            } else {
                VStack(spacing: 0) {
                    topBar
                    viewfinder
                    controls
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .fullScreenCover(isPresented: $viewing) {
            if let img = camera.lastPhoto {
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button { viewing = false } label: {
                        Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium)).foregroundStyle(.white).frame(width: 48, height: 48)
                    }
                    .padding(8)
                }
            }
        }
        .onAndroidBack {
            if camera.code != nil { camera.code = nil; return true }
            return false
        }
    }

    private var topBar: some View {
        HStack(spacing: 28) {
            Button { camera.flash = AndroidCamera.Flash.allCases[(AndroidCamera.Flash.allCases.firstIndex(of: camera.flash)! + 1) % 3] } label: {
                Image(systemName: camera.flash == .off ? "bolt.slash" : camera.flash == .on ? "bolt.fill" : "bolt.badge.automatic")
            }
            Button { grid.toggle() } label: { Image(systemName: grid ? "squareshape.split.3x3" : "square") }
            Text(String(format: "%.1fx", camera.zoom)).font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .frame(height: 52)
    }

    private var viewfinder: some View {
        ZStack {
            CameraPreview(session: camera.session)
            if grid {
                GeometryReader { g in
                    Path { p in
                        for i in 1...2 {
                            let x = g.size.width * CGFloat(i) / 3, y = g.size.height * CGFloat(i) / 3
                            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height))
                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y))
                        }
                    }
                    .stroke(.white.opacity(0.45), lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            if camera.mode == .qr {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .allowsHitTesting(false)
            }
            Color.white.opacity(camera.flashing ? 0.85 : 0).allowsHitTesting(false)
            if let code = camera.code {
                VStack {
                    Spacer()
                    Button {
                        if let u = URL(string: code), u.scheme != nil {
                            if ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
                                AndroidShellState.shared.launch(.system(.browser))
                                AndroidBrowser.shared.open(u)
                            } else {
                                UIApplication.shared.open(u)
                            }
                        } else {
                            UIPasteboard.general.string = code
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: URL(string: code)?.scheme != nil ? "link" : "doc.on.doc")
                            Text(code).lineLimit(2).font(.system(size: 15, design: .rounded))
                        }
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .padding(16)
                        .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(AndroidSquashStyle())
                    .padding(16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .gesture(MagnificationGesture()
            .onChanged { camera.setZoom(pinchBase * $0) }
            .onEnded { _ in pinchBase = camera.zoom })
        .animation(.snappy, value: camera.code)
    }

    private var controls: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                ForEach(AndroidCamera.Mode.allCases, id: \.self) { m in
                    Button { withAnimation(.snappy) { camera.mode = m } } label: {
                        Text(m.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(camera.mode == m ? Color(uiColor: Material3.onPrimaryContainer) : .white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(camera.mode == m ? Color(uiColor: Material3.primaryContainer) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            HStack {
                Button { if camera.lastPhoto != nil { viewing = true } } label: {
                    Group {
                        if let img = camera.lastPhoto { Image(uiImage: img).resizable().scaledToFill() }
                        else { Color.white.opacity(0.12) }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
                }
                .buttonStyle(AndroidSquashStyle())
                .accessibilityLabel("Last photo")
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    camera.capture()
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
                        Circle().fill(camera.mode == .qr ? Color.white.opacity(0.3) : .white).frame(width: 64, height: 64)
                    }
                }
                .buttonStyle(AndroidSquashStyle())
                .disabled(camera.mode == .qr)
                .accessibilityLabel("Take photo")
                Spacer()
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { camera.flip() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.white.opacity(0.12), in: Circle())
                        .rotationEffect(.degrees(camera.front ? 180 : 0))
                }
                .buttonStyle(AndroidSquashStyle())
                .accessibilityLabel("Switch camera")
            }
            .padding(.horizontal, 36)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
