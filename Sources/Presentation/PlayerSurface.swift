#if canImport(SwiftUI) && canImport(AppKit)
// Sources/Presentation/PlayerSurface.swift
import SwiftUI
import AppKit

struct FullscreenEscapeModifier: ViewModifier {
    let window: NSWindow?
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { install() }
            .onDisappear { remove() }
            .onChange(of: window) { _, _ in
                remove()
                install()
            }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, let window, window.styleMask.contains(.fullScreen) else {
                return event
            }
            window.toggleFullScreen(nil)
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    func fullscreenEscape(window: NSWindow?) -> some View {
        modifier(FullscreenEscapeModifier(window: window))
    }
}

struct PlayerSurface: View {
    @ObservedObject var player: PlayerStateManager
    let channelName: String
    let isFavorite: Bool
    var showsDetach: Bool = true
    var onDetach: (() -> Void)?
    let onFavorite: () -> Void
    let onRetry: () -> Void
    @State private var hostWindow: NSWindow?

    var body: some View {
        QuickTimeVideoContainer(
            player: player.avPlayer,
            playerState: player.state,
            channelName: channelName,
            isFavorite: isFavorite,
            isPaused: player.isPaused,
            onTogglePlayPause: { player.togglePause() },
            onToggleFullscreen: { hostWindow?.toggleFullScreen(nil) },
            onDetachPlayer: showsDetach ? onDetach : nil,
            onToggleFavorite: onFavorite,
            onRetry: onRetry,
            preferredBitrate: Binding(
                get: { player.preferredBitrate },
                set: { player.preferredBitrate = $0 }
            )
        )
        .background(WindowAccessor { hostWindow = $0 })
        .fullscreenEscape(window: hostWindow)
    }
}
#endif
