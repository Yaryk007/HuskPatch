// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import ReplayKit
import Photos

/// HuskPatch: Android 16's screen recorder (the Screen record tile). Its dialog -- what to record, audio, quality, the size
/// limit, the 3-second timer -- then a countdown, the red chip with the time in the status bar while it records, and the
/// video saved to Photos when it stops. ReplayKit does the recording, so iOS asks for permission the first time.
@MainActor
final class AndroidScreenRecorder: ObservableObject {
    static let shared = AndroidScreenRecorder()

    enum State: Equatable {
        case idle
        case countdown(Int)
        case recording(since: Date)
    }
    @Published private(set) var state: State = .idle

    var isRecording: Bool { if case .recording = state { return true }; return false }

    var tileSubtitle: String {
        switch state {
        case .idle: return "Start"
        case .countdown(let n): return "\(n)…"
        case .recording: return "Stop"
        }
    }

    func start(audio: Bool, skipTimer: Bool) {
        guard state == .idle else { return }
        Task {
            if !skipTimer {
                for n in stride(from: 3, through: 1, by: -1) {
                    state = .countdown(n)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if state == .idle { return }
                }
            }
            let recorder = RPScreenRecorder.shared()
            recorder.isMicrophoneEnabled = audio
            recorder.startRecording { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.state = .idle
                        AndroidShellState.shared.post(ShellNotification(icon: "record.circle", app: "Screen recorder",
                                                                        title: "Couldn't start recording", text: error.localizedDescription))
                    } else {
                        withAnimation(AndroidMotion.bouncy) { self.state = .recording(since: Date()) }
                    }
                }
            }
        }
    }

    func cancelCountdown() {
        if case .countdown = state { state = .idle }
    }

    func stop() {
        guard isRecording else { cancelCountdown(); return }
        withAnimation(AndroidMotion.fade) { state = .idle }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Screen recording \(Int(Date().timeIntervalSince1970)).mp4")
        RPScreenRecorder.shared().stopRecording(withOutput: url) { error in
            Task { @MainActor in
                if let error {
                    AndroidShellState.shared.post(ShellNotification(icon: "record.circle", app: "Screen recorder",
                                                                    title: "Couldn't save recording", text: error.localizedDescription))
                    return
                }
                Self.saveToPhotos(url)
            }
        }
    }

    private static func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    AndroidShellState.shared.post(ShellNotification(icon: "record.circle", app: "Screen recorder",
                                                                    title: "Couldn't save recording", text: "Allow HuskPatch to add photos"))
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { ok, _ in
                try? FileManager.default.removeItem(at: url)
                Task { @MainActor in
                    AndroidShellState.shared.post(ShellNotification(icon: "record.circle", app: "Screen recorder",
                                                                    title: ok ? "Screen recording saved" : "Couldn't save recording",
                                                                    text: ok ? "Saved to Photos" : "Try again"))
                }
            }
        }
    }
}

/// "Record your screen?": Android 16's dialog before a recording.
struct ScreenRecordDialog: View {
    let done: () -> Void
    @State private var entireScreen = true
    @State private var audio = false
    @State private var lowerQuality = false
    @State private var largerLimit = false
    @State private var skipTimer = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: done)
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color(uiColor: Material3.error))
                    Text("Record your screen?")
                        .font(.system(size: 24, design: .rounded))
                        .multilineTextAlignment(.center)

                    Menu {
                        Button("Record one app") { entireScreen = false }
                        Button("Record entire screen") { entireScreen = true }
                    } label: {
                        HStack {
                            Text(entireScreen ? "Record entire screen" : "Record one app")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color(uiColor: Material3.onSurface))
                        .padding(.horizontal, 18).frame(height: 52)
                        .overlay(Capsule().strokeBorder(Color(uiColor: Material3.outline), lineWidth: 1))
                    }

                    VStack(spacing: 14) {
                        option("mic", "Record audio", "Device audio", $audio)
                        option("photo", "Lower quality", "For smaller file size", $lowerQuality)
                        option("list.bullet.rectangle", "Larger file size limit", "Limit recording size to 15 GB", $largerLimit)
                        option("timer", "Skip timer", "Remove the 3 second wait", $skipTimer)
                    }

                    Text(entireScreen
                         ? "While you're recording, Android has access to anything that's visible on your screen or played on your device. So be careful with things like passwords, payment details, messages, photos, and audio and video."
                         : "When you're recording an app, anything shown or played in that app is recorded. So be careful with things like passwords, payment details, messages, photos, and audio and video.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel", action: done).buttonStyle(.expressive(.outlined))
                        Button(entireScreen ? "Start" : "Next") {
                            done()
                            AndroidShellState.shared.closeShade()
                            AndroidScreenRecorder.shared.start(audio: audio, skipTimer: skipTimer)
                        }
                        .buttonStyle(.expressive(.filled))
                    }
                }
                .foregroundStyle(Color(uiColor: Material3.onSurface))
                .padding(24)
            }
            .scrollBounceBehaviorBasedOnSizeCompat()
            .frame(maxHeight: 640)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(uiColor: Material3.surfaceContainerHigh), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private func option(_ icon: String, _ title: String, _ subtitle: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 24)
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .medium, design: .rounded))
                Text(subtitle).font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
            }
            Spacer()
            Toggle("", isOn: value).labelsHidden().toggleStyle(Material3SwitchStyle())
        }
    }
}

/// Android 16's status bar chip while the screen is recorded: red, a dot and the time.
struct ScreenRecordChip: View {
    @ObservedObject private var recorder = AndroidScreenRecorder.shared

    var body: some View {
        if case .recording(let since) = recorder.state {
            TimelineView(.periodic(from: since, by: 1)) { ctx in
                let s = max(0, Int(ctx.date.timeIntervalSince(since)))
                HStack(spacing: 4) {
                    Circle().fill(.white).frame(width: 6, height: 6)
                    Text(String(format: "%d:%02d", s / 60, s % 60))
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).frame(height: 20)
                .background(Color(red: 0.86, green: 0.18, blue: 0.16), in: Capsule())
            }
            .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
        }
    }
}
