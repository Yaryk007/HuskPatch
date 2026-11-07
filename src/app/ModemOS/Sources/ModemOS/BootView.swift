import SwiftUI

/// Boot animation: Android being forced onto an iPhone.
///
/// 1. The iPhone powers on: white screen, black Apple logo.
/// 2. Exploit logs creep in at the top; one step fails and the screen shakes. A pixel Tux eats into the Apple logo.
/// 3. The screen tears, then goes black: two Tux penguins at the top and a flood of kernel / Android init logs.
///    Halfway through iOS fights back (the log freezes, the screen shakes), then it carries on faster.
/// 4. A glitchy green Android head, then the home screen.
///
/// It only runs with "Boot sequence" on in the Lab; off, ModemOS starts straight at the home screen.
struct BootView: View {
    var onFinished: () -> Void

    @EnvironmentObject private var os: OSSettings
    @State private var start = Date()
    @State private var finished = false

    /// Everything is timed from `start` (seconds).
    private enum T {
        static let screenOn = 0.3
        static let whiteLogs = 0.9
        static let whiteStep = 0.2
        static let failLine = 5
        static let corruptStart = 1.6
        static let corruptFull = 2.9
        static let glitch = 2.9
        static let black = 3.15
        static let hiccup = 4.7
        static let hiccupEnd = 5.0
        static let logsEnd = 6.0
        static let android = 6.0
        static let fadeOut = 6.9
        static let end = 7.2
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start)
                let frame = Int(t * 60)

                ZStack {
                    Color.black

                    forced(t: t, frame: frame, w: w, h: h)
                }
                .frame(width: w, height: h)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { finish() }
        .onAppear(perform: schedule)
    }

    // MARK: - The forced boot

    @ViewBuilder
    private func forced(t: Double, frame: Int, w: CGFloat, h: CGFloat) -> some View {
        let shake = shakeOffset(t: t, frame: frame, w: w)

        ZStack {
            if t >= T.screenOn && t < T.black {
                whitePhase(t: t, frame: frame, w: w, h: h)
            }
            if t >= T.black && t < T.fadeOut + 0.4 {
                blackPhase(t: t, w: w, h: h)
                    .opacity(t > T.android ? max(0, 1 - (t - T.android) * 4) : 1)
            }
            if t >= T.android {
                androidPhase(t: t, frame: frame, w: w, h: h)
            }
            if isGlitching(t) {
                GlitchBands(frame: frame, strength: glitchStrength(t))
                    .allowsHitTesting(false)
            }
        }
        .offset(shake)
        .colorInvert(when: t >= T.glitch && t < T.black && frame % 5 < 2)
        .opacity(t > T.fadeOut ? max(0, 1 - (t - T.fadeOut) / (T.end - T.fadeOut)) : 1)
    }

    /// White screen, black Apple logo, exploit logs at the top, and the Tux eating the logo.
    private func whitePhase(t: Double, frame: Int, w: CGFloat, h: CGFloat) -> some View {
        let shown = max(0, min(Self.whiteLines.count, Int((t - T.whiteLogs) / T.whiteStep) + 1))
        let corruption = CGFloat(max(0, min(1, (t - T.corruptStart) / (T.corruptFull - T.corruptStart))))
        let logo = w * 0.2

        return ZStack {
            Color(white: 0.96)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<(t >= T.whiteLogs ? shown : 0), id: \.self) { index in
                    let line = Self.whiteLines[index]
                    Text(line)
                        .foregroundColor(line.contains("FAILED") ? Color(red: 0.75, green: 0.1, blue: 0.1) : Color(white: 0.25))
                }
            }
            .font(.system(size: w * 0.026, weight: .regular, design: .monospaced))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, max(SafeArea.insets.top, 20) + 6)
            .padding(.leading, w * 0.04)

            ZStack {
                Image(systemName: "applelogo")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.black)

                // The pixel Tux shows through the logo in growing blocks.
                PixelTux()
                    .frame(width: logo * 0.8, height: logo * 0.8 * PixelTux.aspect)
                    .offset(x: -logo * 0.08, y: logo * 0.1)
                    .mask(BlockDissolve(amount: corruption, seed: 7))
                    .mask(
                        Image(systemName: "applelogo")
                            .resizable()
                            .scaledToFit()
                    )

                // Stray corrupted pixels around the logo.
                if corruption > 0 {
                    NoiseBlocks(frame: frame, amount: corruption, dark: true)
                        .frame(width: logo * 1.5, height: logo * 1.5)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: logo, height: logo * 1.2)
            .position(x: w / 2, y: h * 0.48)
        }
    }

    /// Black screen: two Tux penguins at the top and the kernel / Android log flooding in.
    private func blackPhase(t: Double, w: CGFloat, h: CGFloat) -> some View {
        let font = w * 0.021
        let lineHeight = font * 1.28
        let tux = w * 0.075
        let top = max(SafeArea.insets.top, 20) + 4
        let rows = max(10, Int((h - top - tux - 16) / lineHeight))
        let count = Self.kernelCount(at: t)
        let first = max(0, count - rows)

        return ZStack(alignment: .topLeading) {
            Color.black

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: tux * 0.25) {
                    PixelTux().frame(width: tux, height: tux * PixelTux.aspect)
                    PixelTux().frame(width: tux, height: tux * PixelTux.aspect)
                }
                .padding(.bottom, 8)

                ForEach(first..<count, id: \.self) { index in
                    Self.kernelLines[index].text
                        .frame(height: lineHeight, alignment: .leading)
                }
            }
            .font(.system(size: font, weight: .regular, design: .monospaced))
            .lineLimit(1)
            .padding(.top, top)
            .padding(.leading, w * 0.025)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipped()
    }

    /// The green Android head glitching in: red and cyan copies snap together into green.
    private func androidPhase(t: Double, frame: Int, w: CGFloat, h: CGFloat) -> some View {
        let appear = max(0, min(1, (t - T.android) / 0.35))
        let split = (1 - appear) * w * 0.05 * (frame % 3 == 0 ? 1.6 : 1)
        let size = w * 0.36

        return ZStack {
            logoShape(size).fill(Color.red.opacity(0.7), style: FillStyle(eoFill: true)).offset(x: -split)
            logoShape(size).fill(Color.cyan.opacity(0.7), style: FillStyle(eoFill: true)).offset(x: split)
            logoShape(size).fill(Theme.androidGreen, style: FillStyle(eoFill: true)).opacity(appear)
        }
        .frame(width: size, height: size * AndroidLogoShape.aspect)
        .position(x: w / 2, y: h * 0.48)
        .opacity(appear < 1 && frame % 4 == 0 ? 0.4 : 1)
    }

    private func logoShape(_ size: CGFloat) -> some Shape {
        AndroidLogoShape()
    }

    // MARK: - Shake and glitches

    private func shakeOffset(t: Double, frame: Int, w: CGFloat) -> CGSize {
        let failAt = T.whiteLogs + Double(T.failLine) * T.whiteStep
        var amount: CGFloat = 0
        if t > failAt && t < failAt + 0.25 { amount = w * 0.018 }
        if t > T.glitch && t < T.black { amount = w * 0.025 }
        if t > T.hiccup && t < T.hiccupEnd { amount = w * 0.02 }
        guard amount > 0 else { return .zero }
        let x = CGFloat(Self.noise(frame * 3 + 1)) * 2 - 1
        let y = CGFloat(Self.noise(frame * 7 + 5)) * 2 - 1
        return CGSize(width: x * amount, height: y * amount * 0.5)
    }

    private func isGlitching(_ t: Double) -> Bool {
        (t > T.glitch && t < T.black + 0.1) || (t > T.hiccup && t < T.hiccupEnd) || (t > T.logsEnd - 0.1 && t < T.android + 0.2)
    }

    private func glitchStrength(_ t: Double) -> CGFloat {
        if t > T.glitch && t < T.black + 0.1 { return 1 }
        return 0.5
    }

    // MARK: - Timing

    private func schedule() {
        start = Date()
        guard os.forcedBoot else {
            after(1.6) { finish() }
            return
        }
        let failAt = T.whiteLogs + Double(T.failLine) * T.whiteStep
        after(T.screenOn) { Haptics.tap(.light) }
        after(failAt) {
            Haptics.tap(.heavy)
            OSLogger.shared.log("Kernel", "KTRR refused to turn off, forcing it", level: .warn)
        }
        for step in 0..<4 {
            after(T.glitch + Double(step) * 0.06) { Haptics.tap(.rigid) }
        }
        after(T.black) { OSLogger.shared.log("Kernel", "iOS killed, Linux is booting") }
        after(T.hiccup) {
            Haptics.tap(.heavy)
            OSLogger.shared.log("Kernel", "launchd came back, killed it again", level: .warn)
        }
        after(T.android) {
            Haptics.tap(.medium)
            OSLogger.shared.log("Kernel", "Android userspace is up")
        }
        after(T.end) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }

    // MARK: - Log text

    private static let whiteLines: [String] = [
        "iBoot-7459.140.15  (modemOS payload)",
        "=====================================",
        ":: checkm8: SecureROM pwned ........ ok",
        ":: pongoOS: modemOS force-installer v2",
        ":: patching AMFI ................... ok",
        ":: disabling KTRR .............. FAILED",
        ":: forcing KTRR off (retry 2/3) .... ok",
        ":: loading Image.lzma  android-16-arm64",
        ":: killing iOS ..................... ok",
        ":: jumping to Linux. bye, iOS.",
    ]

    struct KernelLine {
        let text: Text
    }

    /// How many kernel lines are on screen at time `t`: a flood, a freeze while iOS fights back, then faster.
    private static func kernelCount(at t: Double) -> Int {
        let rate = 62.0
        var shown: Double
        if t < T.hiccup {
            shown = (t - T.black) * rate
        } else if t < T.hiccupEnd {
            shown = (T.hiccup - T.black) * rate
        } else {
            shown = (T.hiccup - T.black) * rate + (t - T.hiccupEnd) * rate * 1.5
        }
        return max(1, min(kernelLines.count, Int(shown)))
    }

    private static let kernelLines: [KernelLine] = {
        let pool: [String] = [
            "Booting Linux on physical CPU 0x0000000000 [0x611f0221]",
            "Linux version 6.12.9-modemos (tux@forge) (clang 19.1.7) #1 SMP PREEMPT",
            "Machine model: Apple iPhone (forced, unsupported)",
            "OF: reserved mem: 0x0000000800000000..0x00000008003fffff (4096 KiB) nomap iboot",
            "Zone ranges: DMA [mem 0x0000000800000000-0x00000008ffffffff]",
            "apple-aic 23b100000.interrupt-controller: AIC2: 896 IRQs, 1 die",
            "apple-dart 231004000.iommu: DART [pagesize 4000, 16 streams, bypass 1]",
            "SError Interrupt on CPU0, code 0xbf000002 -- SError",
            "forcing: SError masked, retry 1/3 ... ok",
            "cpufreq: apple-soc p-cluster 3.46 GHz, e-cluster 2.02 GHz",
            "simple-framebuffer 9e0000000.framebuffer: 1170x2532 @ 32bpp",
            "Console: switching to colour frame buffer device 146x316",
            "nvme-apple 27bcc0000.nvme: RTKit: Initializing (protocol version 12)",
            "apple-sep: SEP says no. Ignoring the SEP.",
            "EXT4-fs (nvme0n1p7): mounted filesystem with ordered data mode",
            "Freeing unused kernel memory: 2048K",
            "Run /init as init process",
            "init: init first stage started!",
            "init: Loading SELinux policy",
            "SELinux: policy capability network_peer_controls=1",
            "init: starting service 'ueventd'...",
            "launchd[1]: still alive, sending SIGKILL",
            "[FAILED] Failed to unmount /System/Library (iOS won't let go)",
            "[  OK  ] Forced unmount of /System/Library",
            "[  OK  ] Started Android init second stage",
            "init: starting service 'logd'...",
            "init: starting service 'servicemanager'...",
            "binder: 412:412 ioctl c0306201 returned -22",
            "healthd: battery l=87 v=4102 t=29.0 h=2 st=3 chg=u",
            "audit: type=1400 avc: denied { read } comm=\"SpringBoard\" scontext=u:r:ios:s0",
            "SurfaceFlinger: GPU: Apple AGX (reverse engineered, good luck)",
            "init: starting service 'zygote64'...",
            "Zygote: Preloading classes...",
            "[  OK  ] Mounted /data (f2fs, forced rw)",
            "WARNING: CPU: 3 PID: 1 at drivers/soc/apple/rtkit.c:442",
            "apple-mailbox: ANE firmware missing, continuing without it",
            "wlan0: brcmfmac: firmware stolen from iOS, loaded",
            "system_server: Entered the Android system server!",
            "ActivityManager: System now ready",
            "bootanim: starting ModemOS boot animation",
        ]
        let gray = Color(red: 0.72, green: 0.74, blue: 0.8)
        var lines: [KernelLine] = []
        var clock = 0.0
        var seed = 11
        for index in 0..<260 {
            seed = seed &* 1103515245 &+ 12345
            clock += Double(abs(seed) % 9000) / 1_000_000 + 0.0006
            let message: String
            if index < pool.count {
                message = pool[index]
            } else {
                // After the scripted part, keep flooding with plausible noise.
                let base = pool[abs(seed / 7) % pool.count]
                let pid = abs(seed / 13) % 4000 + 100
                message = index % 5 == 0
                    ? "init: starting service 'vendor.hal.\(pid)'..."
                    : index % 7 == 0 ? "irq \(pid % 900): nobody cared (try booting with \"irqpoll\")" : base
            }
            let stamp = String(format: "[%5d.%06d] ", Int(clock), Int((clock - floor(clock)) * 1_000_000))
            let color: Color
            if message.contains("[  OK  ]") {
                color = Color(red: 0.35, green: 0.85, blue: 0.4)
            } else if message.contains("FAILED") || message.contains("SError") || message.contains("SIGKILL") || message.contains("nobody cared") {
                color = Color(red: 1, green: 0.35, blue: 0.3)
            } else if message.contains("SEP") || message.contains("denied") || message.contains("WARNING") || message.contains("forcing") || message.contains("missing") {
                color = Color(red: 1, green: 0.8, blue: 0.3)
            } else {
                color = gray
            }
            lines.append(KernelLine(text: Text(stamp).foregroundColor(Color(white: 0.45)) + Text(message).foregroundColor(color)))
        }
        return lines
    }()

    /// A cheap, repeatable pseudo-random number in 0...1.
    static func noise(_ n: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: n) &* 0x9E3779B97F4A7C15
        x ^= x >> 29
        x = x &* 0xBF58476D1CE4E5B9
        x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }
}

// MARK: - Pieces

/// The Linux penguin as pixel art (like the framebuffer boot logo).
struct PixelTux: View {
    static let aspect: CGFloat = CGFloat(rows.count) / CGFloat(rows[0].count)

    private static let rows: [String] = [
        "....KKKKK.....",
        "...KKKKKKK....",
        "...KWWKWWK....",
        "...KWBKBWK....",
        "...KKYYYKK....",
        "..KKYYYYYKK...",
        "..KWKYYYKWK...",
        ".KKWWWWWWWKK..",
        ".KWWWWWWWWWK..",
        "KKWWWWWWWWWKK.",
        "KKWWWWWWWWWKK.",
        "KKWWWWWWWWWKK.",
        "KKWWWWWWWWWKK.",
        ".KKWWWWWWWKK..",
        "YYYKWWWWWKYYY.",
        "YYYYKKKKKYYYYY",
        ".YYY.....YYY..",
    ]

    var body: some View {
        Canvas { context, size in
            let columns = Self.rows[0].count
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(Self.rows.count))
            for (y, row) in Self.rows.enumerated() {
                for (x, character) in row.enumerated() {
                    let color: Color
                    switch character {
                    case "K": color = Color(white: 0.08)
                    case "W": color = Color(white: 0.95)
                    case "B": color = .black
                    case "Y": color = Color(red: 0.98, green: 0.72, blue: 0.1)
                    default: continue
                    }
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

/// A mask that shows `amount` of its area in random square blocks (for the Tux eating the Apple logo).
private struct BlockDissolve: View {
    let amount: CGFloat
    let seed: Int

    var body: some View {
        Canvas { context, size in
            let grid = 10
            let cellW = size.width / CGFloat(grid)
            let cellH = size.height / CGFloat(grid)
            for y in 0..<grid {
                for x in 0..<grid where CGFloat(BootView.noise(seed * 1000 + y * grid + x)) < amount {
                    context.fill(Path(CGRect(x: CGFloat(x) * cellW, y: CGFloat(y) * cellH, width: cellW + 0.5, height: cellH + 0.5)), with: .color(.black))
                }
            }
        }
    }
}

/// Flickering corrupted pixels.
private struct NoiseBlocks: View {
    let frame: Int
    let amount: CGFloat
    let dark: Bool

    var body: some View {
        Canvas { context, size in
            let count = Int(18 * amount)
            let tick = frame / 3
            for index in 0..<count {
                let x = BootView.noise(tick * 131 + index * 7) * Double(size.width)
                let y = BootView.noise(tick * 173 + index * 11) * Double(size.height)
                let side = 2 + BootView.noise(tick * 37 + index) * 7
                let color: Color = BootView.noise(index * 29 + tick) > 0.5 ? (dark ? .black : .white) : Color(red: 0.98, green: 0.72, blue: 0.1)
                context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(color))
            }
        }
    }
}

/// Horizontal tear bands across the screen.
private struct GlitchBands: View {
    let frame: Int
    let strength: CGFloat

    var body: some View {
        Canvas { context, size in
            let tick = frame / 2
            let count = Int(10 * strength) + 2
            for index in 0..<count {
                let y = BootView.noise(tick * 97 + index * 13) * Double(size.height)
                let height = 2 + BootView.noise(tick * 53 + index) * 26 * Double(strength)
                let x = (BootView.noise(tick * 71 + index * 3) - 0.5) * Double(size.width) * 0.4
                let pick = BootView.noise(index * 17 + tick)
                let color: Color = pick < 0.33 ? .white : pick < 0.55 ? .cyan : pick < 0.75 ? .red : .black
                context.fill(
                    Path(CGRect(x: x, y: y, width: Double(size.width), height: height)),
                    with: .color(color.opacity(0.35 + 0.5 * Double(strength)))
                )
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func colorInvert(when on: Bool) -> some View {
        if on {
            colorInvert()
        } else {
            self
        }
    }
}
