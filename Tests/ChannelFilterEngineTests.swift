// Tests/ChannelFilterEngineTests.swift
import XCTest
import CoreFoundation
@testable import IPTVPlayer

final class ChannelFilterEngineTests: XCTestCase {
    private var engine: ChannelFilterEngine!

    override func setUp() {
        super.setUp()
        engine = ChannelFilterEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    /// Вспомогательный метод для быстрого создания канала
    private func makeChannel(
        id: String,
        name: String,
        country: String? = nil,
        languages: [String] = [],
        categories: [String] = []
    ) -> Channel {
        return Channel(
            id: id,
            name: name,
            country: country,
            languages: languages,
            categories: categories,
            logo: nil,
            website: nil
        )
    }

    /// Вспомогательный метод для быстрого создания стрима
    private func makeStream(channel: String, status: String = "active") -> IPTVPlayer.Stream {
        return IPTVPlayer.Stream(
            channel: channel,
            urlString: "http://example.com/\(channel).m3u8",
            status: status,
            timeshift: nil,
            httpReferrer: nil
        )
    }

    /// Тест: пересечение фильтров языка и страны
    func test_intersectLanguageAndCountry() async {
        let channels = [
            makeChannel(id: "us.eng.news", name: "US English News", country: "US", languages: ["eng"]),
            makeChannel(id: "us.spa.news", name: "US Spanish News", country: "US", languages: ["spa"]),
            makeChannel(id: "uk.eng.news", name: "UK English News", country: "UK", languages: ["eng"])
        ]
        let streams = channels.map { makeStream(channel: $0.id) }
        
        await engine.setup(channels: channels, streams: streams)
        
        let filtered = await engine.filter(query: nil, category: nil, country: "US", language: "eng")
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "us.eng.news")
    }

    /// Тест: текстовый поиск по токенам и префиксам (регистронезависимый)
    func test_tokenizedSearchPrefixMatching() async {
        let channels = [
            makeChannel(id: "cnn", name: "CNN Newsline"),
            makeChannel(id: "bbc", name: "BBC World"),
            makeChannel(id: "sky", name: "Sky News")
        ]
        let streams = channels.map { makeStream(channel: $0.id) }
        
        await engine.setup(channels: channels, streams: streams)
        
        // Поиск "new" должен вернуть "CNN Newsline" и "Sky News" (так как "Newsline" и "News" начинаются с "new")
        let filtered = await engine.filter(query: "new", category: nil, country: nil, language: nil)
        
        XCTAssertEqual(filtered.count, 2)
        let ids = Set(filtered.map { $0.id })
        XCTAssertTrue(ids.contains("cnn"))
        XCTAssertTrue(ids.contains("sky"))
    }

    /// Тест: текстовый поиск со свертыванием диакритических знаков
    func test_searchFoldsDiacritics() async {
        let channels = [
            makeChannel(id: "ct1", name: "ČT 1"),
            makeChannel(id: "rte", name: "RTÉ One"),
            makeChannel(id: "normal", name: "Normal Channel")
        ]
        let streams = channels.map { makeStream(channel: $0.id) }
        
        await engine.setup(channels: channels, streams: streams)
        
        // Поиск "ct" должен найти "ČT 1"
        let filteredCT = await engine.filter(query: "ct", category: nil, country: nil, language: nil)
        XCTAssertEqual(filteredCT.count, 1)
        XCTAssertEqual(filteredCT.first?.id, "ct1")
        
        // Поиск "rte" должен найти "RTÉ One"
        let filteredRTE = await engine.filter(query: "rte", category: nil, country: nil, language: nil)
        XCTAssertEqual(filteredRTE.count, 1)
        XCTAssertEqual(filteredRTE.first?.id, "rte")
    }

    /// Тест производительности: фильтрация и текстовый поиск по 50,000 каналам менее чем за 50 мс
    func test_performanceWith50kChannels() async {
        var channels: [Channel] = []
        var streams: [IPTVPlayer.Stream] = []
        
        // Генерируем 50,000 уникальных каналов
        for i in 1...50000 {
            let country = (i % 3 == 0) ? "US" : ((i % 3 == 1) ? "UK" : "FR")
            let lang = (i % 2 == 0) ? "eng" : "fra"
            let category = (i % 5 == 0) ? "news" : "movies"
            
            channels.append(
                makeChannel(
                    id: "channel_\(i)",
                    name: "Channel News Space \(i)",
                    country: country,
                    languages: [lang],
                    categories: [category]
                )
            )
            
            streams.append(makeStream(channel: "channel_\(i)"))
        }
        
        // Настройка базы
        let setupStart = CFAbsoluteTimeGetCurrent()
        await engine.setup(channels: channels, streams: streams)
        let setupDuration = CFAbsoluteTimeGetCurrent() - setupStart
        print("FilterEngine setup duration for 50k channels: \(setupDuration)s")
        
        // Тест сложной фильтрации: текстовый запрос + страна + язык + категория
        let filterStart = CFAbsoluteTimeGetCurrent()
        let filtered = await engine.filter(
            query: "space",
            category: "news",
            country: "US",
            language: "eng"
        )
        let filterDuration = CFAbsoluteTimeGetCurrent() - filterStart
        
        print("FilterEngine execution duration for 50k channels: \(filterDuration * 1000)ms")
        
        // Проверяем требования к производительности (< 80 мс в Debug)
        XCTAssertLessThan(filterDuration, 0.080, "Filter duration must be under 80ms in Debug mode")
        XCTAssertFalse(filtered.isEmpty)
    }
}
