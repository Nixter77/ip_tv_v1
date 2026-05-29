// Sources/Domain/PlayerStateManager.swift
import Foundation
import AVFoundation
import Combine

/// Состояния проигрывателя
public enum PlayerState: Equatable, Sendable {
    case idle
    case loading(stream: Stream)
    case playing(stream: Stream)
    case failed(stream: Stream, error: String)
}

/// Управление воспроизведением и авто-фолбэками
@MainActor
public protocol PlayerStateManagerProtocol: AnyObject, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    /// Текущее состояние плеера
    var state: PlayerState { get }
    
    /// Текущий проигрываемый канал
    var currentChannel: Channel? { get }
    
    /// Экземпляр AVPlayer для SwiftUI AVPlayerView
    var avPlayer: AVPlayer { get }
    
    /// Начать воспроизведение канала (с авто-фолбэком на резервные потоки)
    func play(channel: Channel, streams: [Stream]) async
    
    /// Остановить воспроизведение
    func stop()
    
    /// Предпочтительный максимальный битрейт в bps (0 = авто)
    var preferredBitrate: Double { get set }
}

/// Реализация PlayerStateManager с поддержкой авто-фолбэков, таймаутов и отмены при переключении
@MainActor
public final class PlayerStateManager: NSObject, PlayerStateManagerProtocol {
    @Published public private(set) var state: PlayerState = .idle
    @Published public private(set) var currentChannel: Channel?
    public let avPlayer: AVPlayer = AVPlayer()
    
    @Published public var preferredBitrate: Double = 0 {
        didSet {
            avPlayer.currentItem?.preferredPeakBitRate = preferredBitrate
        }
    }
    
    private let timeoutInterval: TimeInterval
    
    // Хранилище для отмены текущих задач
    private var timeoutTask: Task<Void, Never>?
    private var itemStatusObservation: NSKeyValueObservation?
    
    // Логика фолбэков
    private var streamsToTry: [Stream] = []
    private var currentStreamIndex: Int = 0

    /// Инициализатор PlayerStateManager
    /// - Parameter timeoutInterval: Таймаут загрузки потока в секундах (по умолчанию 8.0)
    public init(timeoutInterval: TimeInterval = 8.0) {
        self.timeoutInterval = timeoutInterval
        super.init()
    }

    deinit {
        let observation = itemStatusObservation
        let task = timeoutTask
        let player = avPlayer
        
        DispatchQueue.main.async {
            observation?.invalidate()
            task?.cancel()
            player.replaceCurrentItem(with: nil)
        }
    }

    /// Начать воспроизведение канала
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

    /// Остановить воспроизведение и высвободить все ресурсы
    public func stop() {
        resetCurrentPlayback()
        self.state = .idle
        self.currentChannel = nil
    }

    // MARK: - Внутренние методы управления воспроизведением

    private func resetCurrentPlayback() {
        timeoutTask?.cancel()
        timeoutTask = nil
        
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        
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
        
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredPeakBitRate = preferredBitrate
        
        if let referrer = stream.httpReferrer, playerItem.asset is AVURLAsset {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": ["Referer": referrer]]
            let customAsset = AVURLAsset(url: url, options: options)
            let customItem = AVPlayerItem(asset: customAsset)
            customItem.preferredPeakBitRate = preferredBitrate
            avPlayer.replaceCurrentItem(with: customItem)
        } else {
            avPlayer.replaceCurrentItem(with: playerItem)
        }
        
        setupObservation(for: avPlayer.currentItem)
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
            Task {
                await handleStreamFailure(stream: stream, error: errorDescription)
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
