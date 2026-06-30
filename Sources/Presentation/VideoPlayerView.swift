#if canImport(SwiftUI) && canImport(AVKit)
// Sources/Presentation/VideoPlayerView.swift
import SwiftUI
import AVKit

/// Кастомный плеер без перехвата фокуса клавиатуры и без системных контролов
private class CleanAVPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Если клик в левом верхнем углу (зона traffic lights), игнорируем его, чтобы он прошел к кнопкам окна
        guard let window = self.window else { return super.hitTest(point) }
        
        // Переводим точку из координат супервью в координаты окна
        let localPoint = self.superview != nil ? self.convert(point, from: self.superview) : point
        let pointInWindow = self.convert(localPoint, to: nil)
        
        let windowHeight = window.contentView?.bounds.height ?? self.bounds.height
        
        // Зона кнопок управления окном (top-left corner)
        // Высота стандартного titlebar ~28-40pt, ширина под кнопки ~80pt
        let trafficLightsZone = NSRect(x: 0, y: windowHeight - 40, width: 80, height: 40)
        
        let isFullScreen = window.styleMask.contains(.fullScreen)
        
        if !isFullScreen && trafficLightsZone.contains(pointInWindow) {
            return nil // Пропускаем клик сквозь плеер
        }
        
        return super.hitTest(point)
    }
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
