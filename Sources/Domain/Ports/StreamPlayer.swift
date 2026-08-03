// Sources/Domain/Ports/StreamPlayer.swift
// Domain playback port — no AVPlayer surface (UI binds to concrete adapter separately).
import Foundation
import Combine

/// Состояния проигрывателя (domain)
public enum PlayerState: Equatable, Sendable {
    case idle
    case loading(stream: Stream)
    case playing(stream: Stream)
    case failed(stream: Stream, error: String)
}

/// Порт управления воспроизведением (policy + fallback). UI-player surface — в Playback adapter.
@MainActor
public protocol StreamPlayer: AnyObject, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var state: PlayerState { get }
    var currentChannel: Channel? { get }
    func play(channel: Channel, streams: [Stream]) async
    func stop()
    func retry() async
    var preferredBitrate: Double { get set }
}

/// Backward-compatible name
public typealias PlayerStateManagerProtocol = StreamPlayer
