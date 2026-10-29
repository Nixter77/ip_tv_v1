#if canImport(AVFoundation) && canImport(Combine)
// Sources/Data/Playback/AVStreamPlayer.swift
// AVFoundation adapter for the Domain StreamPlayer port.
import Foundation
import AVFoundation
import Combine

public enum PlaybackRequestHeaders {
    /// Sanitized Referer and User-Agent for `AVURLAssetHTTPHeaderFieldsKey`.
    public static func httpHeaderFields(for stream: Stream) -> [String: String] {
        var fields: [String: String] = [:]
        // Never forward catalog Referer/UA to a loopback / LAN target.
        if let host = stream.url?.host, RemoteURLPolicy.isRestrictedHost(host) { return fields }
        if let referrer = RemoteURLPolicy.sanitizedHTTPHeaderValue(stream.httpReferrer),
           let referrerURL = RemoteURLPolicy.validatedURL(from: referrer, kind: .remoteAsset) {
            fields["Referer"] = referrerURL.absoluteString
        }
        if let agent = RemoteURLPolicy.sanitizedUserAgent(stream.userAgent) {
            fields["User-Agent"] = agent
        }
        return fields
    }
}

/// AVFoundation adapter + playback policy (fallback, timeout, stall, retry)
@MainActor
public final class PlayerStateManager: NSObject, StreamPlayer {
    @Published public private(set) var state: PlayerState = .idle
    @Published public private(set) var currentChannel: Channel?
    /// Published from time-control observation so SwiftUI does not read `AVPlayer.rate`.
    @Published public private(set) var isPaused: Bool = true
    /// UI bridge — not part of StreamPlayer port
    public let avPlayer: AVPlayer = AVPlayer()

    @Published public var preferredBitrate: Double = 0 {
        didSet {
            let clamped: Double
            if preferredBitrate.isFinite {
                clamped = max(0, preferredBitrate)
            } else {
                clamped = 0
            }
            if clamped != preferredBitrate {
                preferredBitrate = clamped
                return
            }
            avPlayer.currentItem?.preferredPeakBitRate = clamped
        }
    }

    private let timeoutInterval: TimeInterval
    private let stallInterval: TimeInterval
    private let clock: any SuspendingClock

    private var timeoutTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    private var streamsToTry: [Stream] = []
    private var currentStreamIndex: Int = 0

    public init(
        timeoutInterval: TimeInterval = 8.0,
        stallInterval: TimeInterval = 12.0,
        clock: any SuspendingClock = ContinuousSuspendingClock()
    ) {
        self.timeoutInterval = timeoutInterval
        self.stallInterval = stallInterval
        self.clock = clock
        super.init()
    }

    deinit {
        let observation = itemStatusObservation
        let timeControl = timeControlObservation
        let task = timeoutTask
        let stall = stallTask
        let player = avPlayer

        DispatchQueue.main.async {
            observation?.invalidate()
            timeControl?.invalidate()
            task?.cancel()
            stall?.cancel()
            player.replaceCurrentItem(with: nil)
        }
    }

    public func play(channel: Channel, streams: [Stream]) async {
        resetCurrentPlayback()

        self.currentChannel = channel
        self.streamsToTry = streams
        self.currentStreamIndex = 0

        guard !streams.isEmpty else {
            let dummyStream = Stream(channel: channel.id, urlString: "", status: "error", timeshift: nil, httpReferrer: nil)
            self.state = .failed(stream: dummyStream, error: "Нет доступных потоков")
            return
        }

        await playCurrentStream()
    }

    public func retry() async {
        guard let channel = currentChannel, !streamsToTry.isEmpty else { return }
        await play(channel: channel, streams: streamsToTry)
    }

    public func stop() {
        resetCurrentPlayback()
        self.state = .idle
        self.currentChannel = nil
        self.streamsToTry = []
        self.currentStreamIndex = 0
        self.isPaused = true
    }

    public func togglePause() {
        switch avPlayer.timeControlStatus {
        case .paused:
            guard avPlayer.currentItem != nil else { return }
            avPlayer.play()
            isPaused = false
        case .playing, .waitingToPlayAtSpecifiedRate:
            avPlayer.pause()
            isPaused = true
        @unknown default:
            avPlayer.pause()
            isPaused = true
        }
    }

    private func resetCurrentPlayback() {
        timeoutTask?.cancel()
        timeoutTask = nil
        stallTask?.cancel()
        stallTask = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil

        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        isPaused = true
    }

    private func playCurrentStream() async {
        guard currentStreamIndex < streamsToTry.count else {
            if let lastStream = streamsToTry.last {
                self.state = .failed(stream: lastStream, error: "Все потоки недоступны")
            }
            return
        }

        let stream = streamsToTry[currentStreamIndex]
        self.state = .loading(stream: stream)

        guard let url = stream.url else {
            await handleStreamFailure(stream: stream, error: "Некорректная ссылка на поток")
            return
        }

        let headers = PlaybackRequestHeaders.httpHeaderFields(for: stream)
        let playerItem: AVPlayerItem
        if headers.isEmpty {
            playerItem = AVPlayerItem(url: url)
        } else {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            let customAsset = AVURLAsset(url: url, options: options)
            playerItem = AVPlayerItem(asset: customAsset)
        }
        playerItem.preferredPeakBitRate = preferredBitrate
        avPlayer.replaceCurrentItem(with: playerItem)

        setupObservation(for: avPlayer.currentItem)
        setupTimeControlObservation()
        setupTimeoutTimer(for: stream)

        avPlayer.play()
        isPaused = false
    }

    private func setupObservation(for item: AVPlayerItem?) {
        itemStatusObservation?.invalidate()
        guard let item else { return }
        let itemID = ObjectIdentifier(item)

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] playerItem, _ in
            let status = playerItem.status
            let failedText = playerItem.error.map { AppLog.safe($0.localizedDescription) }
            Task { @MainActor in
                self?.handleItemStatus(status, errorText: failedText, itemID: itemID)
            }
        }
    }

    private func setupTimeControlObservation() {
        timeControlObservation?.invalidate()
        timeControlObservation = avPlayer.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.handleTimeControlStatus(status)
            }
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isPaused = false
            stallTask?.cancel()
            stallTask = nil
        case .waitingToPlayAtSpecifiedRate:
            isPaused = false
            guard case .playing = state else { return }
            scheduleStallWatchdog()
        case .paused:
            isPaused = true
            stallTask?.cancel()
            stallTask = nil
        @unknown default:
            break
        }
    }

    private func scheduleStallWatchdog() {
        stallTask?.cancel()
        let interval = stallInterval
        let clock = clock
        stallTask = Task { [weak self] in
            do {
                try await clock.sleep(for: .milliseconds(Int((interval * 1000).rounded())))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleStall()
        }
    }

    private func handleStall() async {
        guard case .playing(let stream) = state else { return }
        guard avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
        await handleStreamFailure(stream: stream, error: "Поток завис (нет данных \(Int(stallInterval))с)")
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, errorText: String?, itemID: ObjectIdentifier) {
        guard case .loading(let stream) = state,
              let currentItem = avPlayer.currentItem,
              ObjectIdentifier(currentItem) == itemID else { return }

        switch status {
        case .readyToPlay:
            timeoutTask?.cancel()
            timeoutTask = nil
            self.state = .playing(stream: stream)
        case .failed:
            let errorDescription = errorText ?? "Неизвестная ошибка сети"
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard case .loading(let current) = self.state, current == stream,
                      let item = self.avPlayer.currentItem, ObjectIdentifier(item) == itemID else { return }
                await self.handleStreamFailure(stream: stream, error: errorDescription)
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func setupTimeoutTimer(for stream: Stream) {
        timeoutTask?.cancel()
        let timeoutSec = timeoutInterval
        let clock = clock
        timeoutTask = Task { [weak self] in
            do {
                try await clock.sleep(for: .milliseconds(Int((timeoutSec * 1000).rounded())))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleTimeout(for: stream)
        }
    }

    private func handleTimeout(for stream: Stream) async {
        guard case .loading(let loadingStream) = state, loadingStream == stream else { return }
        let error = "Таймаут загрузки потока (\(timeoutInterval)с)"
        await handleStreamFailure(stream: stream, error: AppLog.safe(error))
    }

    private func handleStreamFailure(stream: Stream, error: String) async {
        resetCurrentPlayback()
        currentStreamIndex += 1

        if currentStreamIndex < streamsToTry.count {
            await playCurrentStream()
        } else {
            self.state = .failed(stream: stream, error: error)
        }
    }
}

#endif
