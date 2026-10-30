#if canImport(SwiftUI) && canImport(AVFoundation)
// Sources/Presentation/QuickTimeVideoContainer.swift
import SwiftUI
import AVFoundation

// MARK: - QuickTimeVideoContainer

/// Безрамочный контейнер: видео-холст + авто-скрывающийся HUD поверх.
/// Observe PlayerStateManager so HUD glyph tracks published `isPaused` (A3 / S1).
public struct QuickTimeVideoContainer: View {
    @ObservedObject var playerManager: PlayerStateManager

    let channelName: String?
    let isFavorite: Bool

    var onTogglePlayPause: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onDetachPlayer: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var onRetry: (() -> Void)?
    var preferredBitrate: Binding<Double>?

    @State private var hudVisible: Bool = true

    public init(
        playerManager: PlayerStateManager,
        channelName: String? = nil,
        isFavorite: Bool = false,
        onTogglePlayPause: (() -> Void)? = nil,
        onToggleFullscreen: (() -> Void)? = nil,
        onDetachPlayer: (() -> Void)? = nil,
        onToggleFavorite: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        preferredBitrate: Binding<Double>? = nil
    ) {
        self.playerManager = playerManager
        self.channelName = channelName
        self.isFavorite = isFavorite
        self.onTogglePlayPause = onTogglePlayPause
        self.onToggleFullscreen = onToggleFullscreen
        self.onDetachPlayer = onDetachPlayer
        self.onToggleFavorite = onToggleFavorite
        self.onRetry = onRetry
        self.preferredBitrate = preferredBitrate
    }

    public var body: some View {
        ZStack {
            VideoPlayerView(player: playerManager.avPlayer)

            PlayerHUDOverlay(state: playerManager.state, onRetry: onRetry)

            if case .playing = playerManager.state {
                QuickTimeHUDPanel(
                    player: playerManager.avPlayer,
                    channelName: channelName,
                    isFavorite: isFavorite,
                    isPaused: playerManager.isPaused,
                    onTogglePlayPause: onTogglePlayPause,
                    onToggleFullscreen: onToggleFullscreen,
                    onDetachPlayer: onDetachPlayer,
                    onToggleFavorite: onToggleFavorite,
                    preferredBitrate: preferredBitrate
                )
                .id(playerManager.isPaused) // rebuild glyph when published pause flips
                .autoHideHUD(isVisible: $hudVisible)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

#endif
