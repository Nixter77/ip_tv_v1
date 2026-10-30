#if canImport(AppKit)
// App/AppActivation.swift — S1e
import AppKit

/// `swift run` launches an unbundled executable (no Info.plist), so AppKit leaves it
/// without a regular activation policy: windows show but the app never becomes
/// active/key, and keystrokes (Space) keep going to the previously active app.
/// Force `.regular` policy and activate once at launch.
final class IPTVAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey })?
                .makeKeyAndOrderFront(nil)
        }
    }
}
#endif
