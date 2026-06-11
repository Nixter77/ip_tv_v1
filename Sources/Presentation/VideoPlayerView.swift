#if canImport(SwiftUI) && canImport(AVKit)
// Sources/Presentation/VideoPlayerView.swift
import SwiftUI
import AVKit

/// Кастомный плеер без перехвата фокуса клавиатуры и без системных контролов
private class CleanAVPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }
}

/// Чистый холст видео — без floating controls, без кнопок.
/// Все управление вынесено в кастомный QuickTime-стиль HUD.
public struct VideoPlayerView: NSViewRepresentable {
    private let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeNSView(context: Context) -> AVPlayerView {
        let playerView = CleanAVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none          // Никаких системных контролов
        playerView.showsFrameSteppingButtons = false
        playerView.showsSharingServiceButton = false
        playerView.showsFullScreenToggleButton = false
        return playerView
    }

    public func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

#endif
