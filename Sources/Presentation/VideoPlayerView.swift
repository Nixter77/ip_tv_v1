// Sources/Presentation/VideoPlayerView.swift
import SwiftUI
import AVKit

/// Кастомный плеер, который не перехватывает фокус клавиатуры у SwiftUI элементов
private class NonFocusableAVPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool {
        return false
    }
}

/// Обертка над нативным системным AVPlayerView для macOS Sonoma
public struct VideoPlayerView: NSViewRepresentable {
    private let player: AVPlayer
    
    /// Инициализатор VideoPlayerView
    /// - Parameter player: Экземпляр AVPlayer для воспроизведения
    public init(player: AVPlayer) {
        self.player = player
    }
    
    public func makeNSView(context: Context) -> AVPlayerView {
        let playerView = NonFocusableAVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .floating // Стильные парящие элементы управления macOS
        playerView.showsFrameSteppingButtons = false
        playerView.showsSharingServiceButton = false
        playerView.showsFullScreenToggleButton = true // Поддержка нативного полноэкранного режима
        return playerView
    }
    
    public func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
