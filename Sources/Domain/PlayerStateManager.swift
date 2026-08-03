#if canImport(AVFoundation) && canImport(Combine)
// Sources/Domain/PlayerStateManager.swift
// Playback infrastructure adapter: Domain StreamPlayer + AVPlayer UI surface.
// PlayerState / StreamPlayer live in Domain/Ports/StreamPlayer.swift
import Foundation
import AVFoundation
import Combine

/// AVFoundation adapter + playback policy (fallback, timeout, stall, retry)
@MainActor
public final class PlayerStateManager: NSObject, StreamPlayer {
    @Published public private(set) var state: PlayerState = .idle
    @Published public private(set) var currentChannel: Channel?
    /// UI bridge — not part of StreamPlayer port
    public let avPlayer: AVPlayer = AVPlayer()
    
    @Published public var preferredBitrate: Double = 0 {
        didSet {
            let clamped = max(0, preferredBitrate)
            if clamped != preferredBitrate {
                preferredBitrate = clamped
                return
            }
            avPlayer.currentItem?.preferredPeakBitRate = clamped
        }
    }
    
    private let timeoutInterval: TimeInterval
    /// Сколько ждать в `.waitingToPlayAtSpecifiedRate` до fallback
    private let stallInterval: TimeInterval
    
    private var timeoutTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    
    private var streamsToTry: [Stream] = []
    private var currentStreamIndex: Int = 0

    public init(timeoutInterval: TimeInterval = 8.0, stallInterval: TimeInterval = 12.0) {
        self.timeoutInterval = timeoutInterval
        self.stallInterval = stallInterval
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

    /// Повтор с первого потока (кнопка «Попробовать снова»)
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
    }

    // MARK: - Internal

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
        
        var validReferrer: String?
        if let referrer = stream.httpReferrer,
           !referrer.contains("\r"),
           !referrer.contains("\n"),
           let referrerURL = URL(string: referrer),
           let scheme = referrerURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            validReferrer = referrer
        }

        let playerItem: AVPlayerItem
        if let referrer = validReferrer {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": ["Referer": referrer]]
            let customAsset = AVURLAsset(url: url, options: options)
            playerItem = AVPlayerItem(asset: customAsset)
        } else {
            playerItem = AVPlayerItem(url: url)
        }
        playerItem.preferredPeakBitRate = preferredBitrate
        avPlayer.replaceCurrentItem(with: playerItem)
        
        setupObservation(for: avPlayer.currentItem)
        setupTimeControlObservation()
        setupTimeoutTimer(for: stream)
        
        avPlayer.play()
    }

    private func setupObservation(for item: AVPlayerItem?) {
        itemStatusObservation?.invalidate()
        
        guard let item = item else { return }
        
        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] playerItem, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleItemStatusChange(playerItem)
            }
        }
    }

    private func setupTimeControlObservation() {
        timeControlObservation?.invalidate()
        timeControlObservation = avPlayer.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleTimeControlStatus(player.timeControlStatus)
            }
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            stallTask?.cancel()
            stallTask = nil
        case .waitingToPlayAtSpecifiedRate:
            // Stall only after we've reached playing/loading with an item
            guard case .playing = state else { return }
            scheduleStallWatchdog()
        case .paused:
            stallTask?.cancel()
            stallTask = nil
        @unknown default:
            break
        }
    }

    private func scheduleStallWatchdog() {
        stallTask?.cancel()
        let interval = stallInterval
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.handleStall()
        }
    }

    private func handleStall() async {
        guard case .playing(let stream) = state else { return }
        guard avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
        await handleStreamFailure(stream: stream, error: "Поток завис (нет данных \(Int(stallInterval))с)")
    }

    private func handleItemStatusChange(_ item: AVPlayerItem) {
        guard case .loading(let stream) = state,
              let currentItem = avPlayer.currentItem,
              currentItem == item else { return }
              
        switch item.status {
        case .readyToPlay:
            timeoutTask?.cancel()
            timeoutTask = nil
            self.state = .playing(stream: stream)
            
        case .failed:
            let rawError = item.error?.localizedDescription ?? "Неизвестная ошибка сети"
            let errorDescription = Stream.maskURLs(in: rawError)
            Task { @MainActor [weak self] in
                await self?.handleStreamFailure(stream: stream, error: errorDescription)
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
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
            
            if !Task.isCancelled {
                await self?.handleTimeout(for: stream)
            }
        }
    }

    private func handleTimeout(for stream: Stream) async {
        guard case .loading(let loadingStream) = state, loadingStream == stream else { return }
        let error = "Таймаут загрузки потока (\(timeoutInterval)с)"
        await handleStreamFailure(stream: stream, error: Stream.maskURLs(in: error))
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
