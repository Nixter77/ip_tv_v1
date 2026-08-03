#if canImport(SwiftUI) && canImport(AVFoundation)
// Sources/Presentation/DetachedPlayerView.swift
import SwiftUI
import AVFoundation

/// Окно видеоплеера в QuickTime-стиле для отдельного просмотра.
public struct DetachedPlayerView: View {
    @ObservedObject var viewModel: AppViewModel
    /// Изолированная подписка на плеер — не трогает list-биндинги AppViewModel
    @ObservedObject private var playerManager: PlayerStateManager
    @Environment(\.dismiss) private var dismiss

    @State private var escapeMonitor: Any? = nil

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _playerManager = ObservedObject(wrappedValue: viewModel.playerManager)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let channel = playerManager.currentChannel {
                QuickTimeVideoContainer(
                    player: playerManager.avPlayer,
                    playerState: playerManager.state,
                    channelName: channel.name,
                    isFavorite: viewModel.favoriteIds.contains(channel.id),
                    onToggleFullscreen: {
                        if let window = NSApp.keyWindow {
                            window.toggleFullScreen(nil)
                        }
                    },
                    onToggleFavorite: {
                        viewModel.toggleFavorite(channelId: channel.id)
                    },
                    onRetry: {
                        Task { await viewModel.retryPlayback() }
                    },
                    preferredBitrate: Binding(
                        get: { playerManager.preferredBitrate },
                        set: { playerManager.preferredBitrate = $0 }
                    )
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "tv.music.note")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Нет активной трансляции")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .navigationTitle(playerManager.currentChannel?.name ?? "Проигрыватель")
        .background(WindowAccessor { window in
            window.isMovableByWindowBackground = true
        })
        .onAppear {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                        window.toggleFullScreen(nil)
                        return nil
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
            viewModel.isPlayerDetached = false
        }
    }
}

#endif
