#if canImport(AVFoundation) && canImport(Combine)
// Tests/PlayerStateManagerTests.swift
import XCTest
import AVFoundation
@testable import IPTVPlayer

@MainActor
final class PlayerStateManagerTests: XCTestCase {
    private var manager: PlayerStateManager!

    override func setUp() {
        super.setUp()
        // Используем маленький таймаут 0.2 секунды для мгновенного выполнения тестов
        manager = PlayerStateManager(timeoutInterval: 0.2)
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    private func makeChannel(id: String, name: String) -> Channel {
        return Channel(
            id: id,
            name: name,
            country: nil,
            languages: [],
            categories: [],
            logo: nil,
            website: nil
        )
    }

    private func makeStream(channel: String, urlString: String) -> IPTVPlayer.Stream {
        return IPTVPlayer.Stream(
            channel: channel,
            urlString: urlString,
            status: "active",
            timeshift: nil,
            httpReferrer: nil
        )
    }

    /// Тест: поток не отвечает и отваливается по таймауту
    func test_streamPlaybackTimeout() async {
        let channel = makeChannel(id: "timeout-channel", name: "Timeout Channel")
        // Используем несуществующий IP-адрес, чтобы запрос гарантированно завис
        let stream = makeStream(channel: "timeout-channel", urlString: "http://10.255.255.1/stream.m3u8")
        
        await manager.play(channel: channel, streams: [stream])
        
        // В момент запуска состояние должно быть loading
        let stateAfterPlay = manager.state
        XCTAssertEqual(stateAfterPlay, .loading(stream: stream))
        
        // Ждем 0.3 секунды (больше таймаута 0.2с)
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Состояние должно перейти в failed из-за таймаута
        let stateAfterTimeout = manager.state
        if case .failed(let failedStream, let error) = stateAfterTimeout {
            XCTAssertEqual(failedStream, stream)
            XCTAssertTrue(error.lowercased().contains("timeout") || error.lowercased().contains("таймаут"))
        } else {
            XCTFail("Expected .failed state after timeout, but got: \(stateAfterTimeout)")
        }
    }

    /// Тест: автоматический переход на следующий поток, если первый мертв
    func test_automaticFallbackToNextStream() async {
        // Создаем локальный менеджер с увеличенным таймаутом 1.0 секунда для предотвращения временных гонок
        let localManager = PlayerStateManager(timeoutInterval: 1.0)
        let channel = makeChannel(id: "fallback-channel", name: "Fallback Channel")
        // Первый поток мертв (мгновенно падает из-за некорректной схемы), второй поток зависает (таймаут)
        let stream1 = makeStream(channel: "fallback-channel", urlString: "invalid_url_scheme://live")
        let stream2 = makeStream(channel: "fallback-channel", urlString: "http://10.255.255.1/stream.m3u8")
        
        await localManager.play(channel: channel, streams: [stream1, stream2])
        
        // Ждем 0.1 секунды, чтобы первый поток успел упасть, и менеджер переключился на второй
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Должен произойти авто-переход на stream2, состояние должно быть .loading(stream2)
        let currentState = localManager.state
        XCTAssertEqual(currentState, .loading(stream: stream2))
    }

    /// Тест: предотвращение бесконечного цикла, если все потоки канала мертвы
    func test_circularFallbackPrevention() async {
        let channel = makeChannel(id: "all-dead-channel", name: "All Dead Channel")
        let stream1 = makeStream(channel: "all-dead-channel", urlString: "invalid_url_scheme1://live")
        let stream2 = makeStream(channel: "all-dead-channel", urlString: "invalid_url_scheme2://live")
        
        await manager.play(channel: channel, streams: [stream1, stream2])
        
        // Ждем 0.2 секунды, чтобы оба потока успели упасть
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Менеджер должен остановиться в состоянии failed для последнего потока
        let finalState = manager.state
        if case .failed(let failedStream, _) = finalState {
            XCTAssertEqual(failedStream, stream2)
        } else {
            XCTFail("Expected .failed for stream2, but got: \(finalState)")
        }
    }

    /// Тест: быстрое переключение каналов (zapping) отменяет предыдущую загрузку
    func test_rapidChannelZappingCancellation() async {
        let channelA = makeChannel(id: "channel-a", name: "Channel A")
        let streamA = makeStream(channel: "channel-a", urlString: "http://10.255.255.1/streamA.m3u8")
        
        let channelB = makeChannel(id: "channel-b", name: "Channel B")
        let streamB = makeStream(channel: "channel-b", urlString: "http://10.255.255.1/streamB.m3u8")
        
        // Запускаем канал А
        await manager.play(channel: channelA, streams: [streamA])
        XCTAssertEqual(manager.state, .loading(stream: streamA))
        XCTAssertEqual(manager.currentChannel?.id, "channel-a")
        
        // Мгновенно переключаем на канал Б
        await manager.play(channel: channelB, streams: [streamB])
        XCTAssertEqual(manager.state, .loading(stream: streamB))
        XCTAssertEqual(manager.currentChannel?.id, "channel-b")
        
        // Ждем 0.3 секунды (больше таймаута)
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Таймаут должен сработать только для канала Б (так как загрузка канала А была отменена)
        let finalState = manager.state
        if case .failed(let failedStream, _) = finalState {
            XCTAssertEqual(failedStream, streamB)
        } else {
            XCTFail("Expected failed state for streamB, but got: \(finalState)")
        }
    }

    /// Тест: остановка воспроизведения освобождает ресурсы
    func test_playerReleasesResourcesOnStop() async {
        let channel = makeChannel(id: "stop-channel", name: "Stop Channel")
        let stream = makeStream(channel: "stop-channel", urlString: "http://10.255.255.1/stream.m3u8")
        
        await manager.play(channel: channel, streams: [stream])
        XCTAssertEqual(manager.state, .loading(stream: stream))
        
        // Останавливаем плеер
        manager.stop()
        
        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.currentChannel)
        XCTAssertNil(manager.avPlayer.currentItem)
    }

    /// Тест: Регулирование битрейта трансляции применяется к текущему AVPlayerItem
    func test_preferredBitratePropagation() async {
        let channel = makeChannel(id: "bitrate-channel", name: "Bitrate Channel")
        let stream = makeStream(channel: "bitrate-channel", urlString: "http://example.com/live.m3u8")
        
        // По умолчанию битрейт должен быть 0 (авто)
        XCTAssertEqual(manager.preferredBitrate, 0)
        
        await manager.play(channel: channel, streams: [stream])
        
        // Меняем битрейт на 1.5 Mbps (480p)
        manager.preferredBitrate = 1_500_000
        
        XCTAssertEqual(manager.avPlayer.currentItem?.preferredPeakBitRate, 1_500_000)
    }
}

#endif
