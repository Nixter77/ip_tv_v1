#if canImport(SwiftUI) && canImport(AVFoundation)
// Sources/Presentation/QuickTimeVideoContainer.swift
import SwiftUI
import AVFoundation

// MARK: - QuickTimeVideoContainer

/// Безрамочный контейнер: видео-холст + авто-скрывающийся HUD поверх.
public struct QuickTimeVideoContainer: View {
    let player: AVPlayer
    let playerState: PlayerState
    let channelName: String?
    let isFavorite: Bool
    let isPaused: Bool

    var onTogglePlayPause: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onDetachPlayer: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var onRetry: (() -> Void)?
    var preferredBitrate: Binding<Double>?

    @State private var hudVisible: Bool = true

    public init(
        player: AVPlayer,
        playerState: PlayerState,
        channelName: String? = nil,
        isFavorite: Bool = false,
        isPaused: Bool = true,
        onTogglePlayPause: (() -> Void)? = nil,
        onToggleFullscreen: (() -> Void)? = nil,
        onDetachPlayer: (() -> Void)? = nil,
        onToggleFavorite: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        preferredBitrate: Binding<Double>? = nil
    ) {
        self.player = player
        self.playerState = playerState
        self.channelName = channelName
        self.isFavorite = isFavorite
        self.isPaused = isPaused
        self.onTogglePlayPause = onTogglePlayPause
        self.onToggleFullscreen = onToggleFullscreen
        self.onDetachPlayer = onDetachPlayer
        self.onToggleFavorite = onToggleFavorite
        self.onRetry = onRetry
        self.preferredBitrate = preferredBitrate
    }

    public var body: some View {
        ZStack {
            VideoPlayerView(player: player)

            // Буферизация / ошибки (+ retry)
            PlayerHUDOverlay(state: playerState, onRetry: onRetry)

            // QuickTime HUD при воспроизведении
            if case .playing = playerState {
                QuickTimeHUDPanel(
                    player: player,
                    channelName: channelName,
                    isFavorite: isFavorite,
                    isPaused: isPaused,
                    onTogglePlayPause: onTogglePlayPause,
                    onToggleFullscreen: onToggleFullscreen,
                    onDetachPlayer: onDetachPlayer,
                    onToggleFavorite: onToggleFavorite,
                    preferredBitrate: preferredBitrate
                )
                .autoHideHUD(isVisible: $hudVisible)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

#endif
