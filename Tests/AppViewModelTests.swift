#if canImport(Combine) && canImport(SwiftData) && canImport(AVFoundation)
// Tests/AppViewModelTests.swift
import XCTest
import Combine
@testable import IPTVPlayer

@MainActor
final class AppViewModelTests: XCTestCase {
    nonisolated(unsafe) private var session: URLSession?
    nonisolated(unsafe) private var repository: IPTVRepository?
    nonisolated(unsafe) private var filterEngine: ChannelFilterEngine?
    nonisolated(unsafe) private var playerManager: PlayerStateManager?
    nonisolated(unsafe) private var viewModel: AppViewModel?
    nonisolated(unsafe) private var clock: ManualSuspendingClock?

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]

        let newSession = URLSession(configuration: config)
        let newRepository = IPTVRepository(session: newSession, diskCache: nil)
        let newFilterEngine = ChannelFilterEngine()
        let newClock = ManualSuspendingClock()
        let built = MainActor.assumeIsolated {
            let newPlayerManager = PlayerStateManager()
            let viewModel = AppViewModel(
                repository: newRepository,
                filterEngine: newFilterEngine,
                playerManager: newPlayerManager,
                clock: newClock
            )
            viewModel.searchQuery = ""
            viewModel.selectedTab = .all
            return (newPlayerManager, viewModel)
        }

        session = newSession
        repository = newRepository
        filterEngine = newFilterEngine
        playerManager = built.0
        clock = newClock
        viewModel = built.1

        URLProtocolMock.mockData.removeAll()
        UserDefaults.standard.removeObject(forKey: "lastSearchQuery")
        UserDefaults.standard.removeObject(forKey: "lastSelectedTab")
    }

    override func tearDown() {
        viewModel = nil
        clock = nil
        playerManager = nil
        filterEngine = nil
        repository = nil
        session = nil
        URLProtocolMock.mockData.removeAll()
        UserDefaults.standard.removeObject(forKey: "lastSearchQuery")
        UserDefaults.standard.removeObject(forKey: "lastSelectedTab")
        super.tearDown()
    }

    private func makeMockJSONData() {
        let channelsJSON = """
        [
            {"id": "cnn", "name": "CNN", "country": "US", "languages": ["eng"], "categories": ["news"]}
        ]
        """
        let streamsJSON = """
        [
            {"channel": "cnn", "url": "http://cnn.com/live.m3u8", "status": "active"}
        ]
        """
        let categoriesJSON = """
        [
            {"name": "News"}
        ]
        """
        let countriesJSON = """
        [
            {"code": "US", "name": "United States", "languages": ["eng"], "flag": "🇺🇸"}
        ]
        """
        let languagesJSON = """
        [
            {"code": "eng", "name": "English"}
        ]
        """
        
        URLProtocolMock.mockData[URL(string: "https://iptv-org.github.io/api/channels.json")!] = (Data(channelsJSON.utf8), HTTPURLResponse(url: URL(string: "https://...")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        URLProtocolMock.mockData[URL(string: "https://iptv-org.github.io/api/streams.json")!] = (Data(streamsJSON.utf8), HTTPURLResponse(url: URL(string: "https://...")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        URLProtocolMock.mockData[URL(string: "https://iptv-org.github.io/api/categories.json")!] = (Data(categoriesJSON.utf8), HTTPURLResponse(url: URL(string: "https://...")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        URLProtocolMock.mockData[URL(string: "https://iptv-org.github.io/api/countries.json")!] = (Data(countriesJSON.utf8), HTTPURLResponse(url: URL(string: "https://...")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        URLProtocolMock.mockData[URL(string: "https://iptv-org.github.io/api/languages.json")!] = (Data(languagesJSON.utf8), HTTPURLResponse(url: URL(string: "https://...")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
    }

    /// Тест: Успешная загрузка всех данных из репозитория
    func test_loadDataSuccess() async throws {
        makeMockJSONData()
        
        let vm = try XCTUnwrap(viewModel)
        let engine = try XCTUnwrap(filterEngine)

        XCTAssertEqual(vm.loadingState, .loading)
        
        await vm.loadData()
        
        XCTAssertEqual(vm.loadingState, .ready)
        XCTAssertEqual(vm.categories.count, 1)
        XCTAssertEqual(vm.countries.count, 1)
        XCTAssertEqual(vm.languages.count, 1)
        
        let channels = await engine.filter(query: nil, category: nil, country: nil, language: nil)
        XCTAssertEqual(channels.count, 1)
    }

    /// Тест: Изменение поискового запроса обновляет список каналов
    func test_filterTriggersOnSearchQueryChange() async throws {
        makeMockJSONData()
        let vm = try XCTUnwrap(viewModel)
        await vm.loadData()
        
        // Изначально канал "CNN" должен находиться в списке
        XCTAssertEqual(vm.filteredChannels.count, 1)
        
        // Меняем строку поиска на несуществующую
        vm.searchQuery = "nonexistent"
        await flushDebounce(try XCTUnwrap(clock))
        XCTAssertEqual(vm.filteredChannels.count, 0)
    }

    func test_searchQuery_isCapped() {
        guard let vm = viewModel else {
            XCTFail("viewModel missing")
            return
        }
        vm.searchQuery = String(repeating: "a", count: RemoteURLPolicy.maxSearchQueryLength + 80)
        XCTAssertEqual(vm.searchQuery.count, RemoteURLPolicy.maxSearchQueryLength)
    }

    /// Тест: Метод play(channel:) корректно запускает воспроизведение в PlayerStateManager
    func test_playChannel() async throws {
        makeMockJSONData()
        let vm = try XCTUnwrap(viewModel)
        let player = try XCTUnwrap(playerManager)
        let engine = try XCTUnwrap(filterEngine)

        await vm.loadData()
        
        guard let channel = vm.filteredChannels.first else {
            XCTFail("No channels found")
            return
        }
        
        XCTAssertEqual(player.state, .idle)
        
        await vm.play(channel: channel)
        
        let streams = await engine.streams(for: channel.id)
        XCTAssertEqual(player.state, .loading(stream: streams.first!))
    }

    func test_favoriteName_usesCatalogNameWhenFilteredOut() async throws {
        makeMockJSONData()
        let library = NameRecordingLibrary()
        let clock = ManualSuspendingClock()
        let vm = AppViewModel(
            repository: try XCTUnwrap(repository),
            filterEngine: try XCTUnwrap(filterEngine),
            playerManager: PlayerStateManager(),
            userLibrary: library,
            libraryAvailable: true,
            clock: clock
        )
        await vm.loadData()
        vm.searchQuery = "zzzz-not-a-channel"
        await flushDebounce(clock)
        XCTAssertTrue(vm.filteredChannels.isEmpty)
        vm.toggleFavorite(channelId: "cnn")
        await vm.flushLibraryWrites()
        XCTAssertEqual(library.recorded.first?.name, "CNN")
    }

    func test_reselectPlayingChannel_startsAnotherAttempt() async throws {
        makeMockJSONData()
        let vm = try XCTUnwrap(viewModel)
        await vm.loadData()
        let channel = try XCTUnwrap(vm.filteredChannels.first)
        await vm.play(channel: channel)
        let firstItem = vm.playerManager.avPlayer.currentItem
        XCTAssertNotNil(firstItem)
        await vm.selectChannel(channel)
        XCTAssertFalse(firstItem === vm.playerManager.avPlayer.currentItem)
    }
}

@MainActor
private final class NameRecordingLibrary: UserLibraryRepository {
    struct Record {
        var id: String
        var name: String
        var isFavorite: Bool
    }
    var recorded: [Record] = []

    func load() async throws -> UserLibraryState { UserLibraryState() }

    func setFavorite(id: String, name: String, isFavorite: Bool) async throws {
        recorded.append(Record(id: id, name: name, isFavorite: isFavorite))
    }

    func recordView(id: String, name: String) async throws {}
}

private func flushDebounce(_ clock: ManualSuspendingClock) async {
    for _ in 0..<4 {
        let baseline = clock.pendingCount
        for _ in 0..<40 {
            if clock.pendingCount > baseline { break }
            await Task.yield()
        }
        await clock.advance(by: .milliseconds(300))
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

#endif
