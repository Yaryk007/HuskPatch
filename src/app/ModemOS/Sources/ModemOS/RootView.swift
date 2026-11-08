import SwiftUI

/// Boot -> setup (first launch, or "Run setup again") -> home.
/// The home screen is always underneath; the setup overlay and the boot logo sit on top of it.
struct RootView: View {
    @ObservedObject private var os = OSSettings.shared
    /// The boot sequence is off unless it is turned on in the Lab.
    @State private var booting = OSSettings.shared.forcedBoot
    @State private var locked = OSSettings.shared.lockScreen && OSSettings.shared.setupDone
    @State private var shortBoot = OSSettings.shared.bootAnimation && !OSSettings.shared.forcedBoot && OSSettings.shared.setupDone

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HomeScreen(revealed: !booting && os.setupDone)

            if !booting && !os.setupDone {
                SetupOverlay(onFinished: {
                    os.setupDone = true
                })
                .transition(.opacity)
            }

            if locked && !booting && os.setupDone {
                LockScreen(unlocked: { locked = false })
            }

            if shortBoot && !booting {
                ModemBootView(finished: {
                    shortBoot = false
                    if !locked { NotificationCenter.default.post(name: .modemOSUnlocked, object: nil) }
                })
            }

            if booting {
                BootView(onFinished: {
                    OSLogger.shared.log("Kernel", "Boot finished")
                    withAnimation(.easeInOut(duration: 0.5)) {
                        booting = false
                    }
                })
                .transition(.opacity)
            }
        }
        .environmentObject(os)
        .expressiveColors(os.palette.expressive)
        .tint(os.palette.primary)
        .toggleStyle(OSToggleStyle())
        .preferredColorScheme(os.theme.colorScheme)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }
}
