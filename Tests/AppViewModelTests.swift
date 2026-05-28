// Tests/AppViewModelTests.swift
import XCTest
import Combine
@testable import IPTVPlayer

@MainActor
final class AppViewModelTests: XCTestCase {
    private var session: URLSession!
    private var repository: IPTVRepository!
    private var filterEngine: ChannelFilterEngine!
    private var playerManager: PlayerStateManager!
    private var viewModel: AppViewModel!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        session = URLSession(configuration: config)
        repository = IPTVRepository(session: session)
        
        filterEngine = ChannelFilterEngine()
        playerManager = PlayerStateManager()
        
        viewModel = AppViewModel(
            repository: repository,
            filterEngine: filterEngine,
            playerManager: playerManager
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
        
        XCTAssertEqual(viewModel.loadingState, .loading)
        
        await viewModel.loadData()
        
        XCTAssertEqual(viewModel.loadingState, .ready)
        XCTAssertEqual(viewModel.categories.count, 1)
        XCTAssertEqual(viewModel.countries.count, 1)
        XCTAssertEqual(viewModel.languages.count, 1)
        
        let channels = await filterEngine.filter(query: nil, category: nil, country: nil, language: nil)
        XCTAssertEqual(channels.count, 1)
    }

    /// Тест: Изменение поискового запроса обновляет список каналов
    func test_filterTriggersOnSearchQueryChange() async throws {
        makeMockJSONData()
        await viewModel.loadData()
        
        // Изначально канал "CNN" должен находиться в списке
        XCTAssertEqual(viewModel.filteredChannels.count, 1)
        
        // Меняем строку поиска на несуществующую
        viewModel.searchQuery = "nonexistent"
        
        // Ждем небольшое время для прогона асинхронного обновления (Combine/State)
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertEqual(viewModel.filteredChannels.count, 0)
    }

    /// Тест: Метод play(channel:) корректно запускает воспроизведение в PlayerStateManager
    func test_playChannel() async throws {
        makeMockJSONData()
        await viewModel.loadData()
        
        guard let channel = viewModel.filteredChannels.first else {
            XCTFail("No channels found")
            return
        }
        
        XCTAssertEqual(playerManager.state, .idle)
        
        await viewModel.play(channel: channel)
        
        let streams = await filterEngine.streams(for: channel.id)
        XCTAssertEqual(playerManager.state, .loading(stream: streams.first!))
    }
}
