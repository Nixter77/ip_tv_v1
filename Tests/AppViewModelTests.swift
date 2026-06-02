#if canImport(Combine) && canImport(SwiftData) && canImport(AVFoundation)
// Tests/AppViewModelTests.swift
import XCTest
import Combine
@testable import IPTVPlayer

@MainActor
final class AppViewModelTests: XCTestCase {
    private var session: URLSession?
    private var repository: IPTVRepository?
    private var filterEngine: ChannelFilterEngine?
    private var playerManager: PlayerStateManager?
    private var viewModel: AppViewModel?

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        
        let newSession = URLSession(configuration: config)
        let newRepository = IPTVRepository(session: newSession)
        let newFilterEngine = ChannelFilterEngine()
        let newPlayerManager = PlayerStateManager()

        session = newSession
        repository = newRepository
        filterEngine = newFilterEngine
        playerManager = newPlayerManager
        
        viewModel = AppViewModel(
            repository: newRepository,
            filterEngine: newFilterEngine,
            playerManager: newPlayerManager
        )
        
        URLProtocolMock.mockData.removeAll()
    }

    override func tearDown() {
        viewModel = nil
        playerManager = nil
        filterEngine = nil
        repository = nil
        session = nil
        URLProtocolMock.mockData.removeAll()
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
        
        // Ждем небольшое время для прогона асинхронного обновления (Combine/State)
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertEqual(vm.filteredChannels.count, 0)
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

    func test_searchQueryLengthLimit() throws {
        let vm = try XCTUnwrap(viewModel)

        let longQuery = String(repeating: "a", count: 1000)
        vm.searchQuery = longQuery

        XCTAssertEqual(vm.searchQuery.count, 512)
        XCTAssertEqual(vm.searchQuery, String(repeating: "a", count: 512))
    }
}

#endif
