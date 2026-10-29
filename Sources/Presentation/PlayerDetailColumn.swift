#if canImport(SwiftUI)
// Sources/Presentation/PlayerDetailColumn.swift
import SwiftUI

struct PlayerDetailColumn: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playerManager: PlayerStateManager
    let openWindow: OpenWindowAction
    let dismissWindow: DismissWindowAction

    var body: some View {
        ZStack {
            Palette.video
            if let channel = playerManager.currentChannel {
                if viewModel.isPlayerDetached {
                    detachedPlaceholder
                } else {
                    PlayerSurface(
                        player: playerManager,
                        channelName: channel.name,
                        isFavorite: viewModel.favoriteIds.contains(channel.id),
                        onDetach: {
                            viewModel.isPlayerDetached = true
                            openWindow(id: "detached-player")
                        },
                        onFavorite: { viewModel.toggleFavorite(channel) },
                        onRetry: { Task { await viewModel.retryPlayback() } }
                    )
                }
            } else {
                placeholder("tv.music.note", "Выберите телеканал для трансляции")
            }
        }
    }

    private var detachedPlaceholder: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "tv.and.mediabox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Трансляция перенесена в отдельное окно")
                .font(.title3)
                .foregroundStyle(Palette.hudInk)
            Button("Вернуть в главное окно") {
                viewModel.isPlayerDetached = false
                dismissWindow(id: "detached-player")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func placeholder(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
