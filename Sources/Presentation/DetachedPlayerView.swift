#if canImport(SwiftUI) && canImport(AppKit)
// Sources/Presentation/DetachedPlayerView.swift
import SwiftUI
import AppKit

public struct DetachedPlayerView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var playerManager: PlayerStateManager
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _playerManager = ObservedObject(wrappedValue: viewModel.playerManager)
    }

    public var body: some View {
        ZStack {
            Palette.video
            if let channel = playerManager.currentChannel {
                PlayerSurface(
                    player: playerManager,
                    channelName: channel.name,
                    isFavorite: viewModel.favoriteIds.contains(channel.id),
                    showsDetach: false,
                    onFavorite: { viewModel.toggleFavorite(channel) },
                    onRetry: { Task { await viewModel.retryPlayback() } }
                )
            } else {
                VStack(spacing: Spacing.xl) {
                    Image(systemName: "tv.music.note")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Нет активной трансляции")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .navigationTitle(playerManager.currentChannel?.name ?? "Проигрыватель")
        .background(WindowAccessor { window in
            window.isMovableByWindowBackground = true
        })
        .onDisappear {
            viewModel.isPlayerDetached = false
        }
    }
}
#endif
