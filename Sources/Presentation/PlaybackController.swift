#if canImport(Combine) && canImport(AVFoundation)
// Sources/Presentation/PlaybackController.swift
import Foundation
import Combine

/// Playback surface for both windows. Does not republish player time ticks.
@MainActor
public final class PlaybackController: ObservableObject {
    public let player: PlayerStateManager
    @Published public var isDetached = false
    @Published public private(set) var nowPlayingTitle: String?

    private var playerBag: AnyCancellable?

    public init(player: PlayerStateManager) {
        self.player = player
        // Forward pause/state so parents observing PlaybackController also refresh (A3).
        playerBag = player.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func play(channel: Channel, streams: [Stream]) async {
        nowPlayingTitle = channel.name
        await player.play(channel: channel, streams: streams)
    }

    public func retry() async {
        await player.retry()
    }

    public func togglePause() {
        player.togglePause()
    }

    public var currentChannelID: String? {
        player.currentChannel?.id
    }
}
#endif
