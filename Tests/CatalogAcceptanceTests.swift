import XCTest
@testable import IPTVPlayer

final class CatalogAcceptanceTests: XCTestCase {
    func test_liveFixtures_mapCurrentAndLegacyPayloads() throws {
        let channels = try decode([ChannelDTO].self, name: "iptv-org-channels")
        let logos = try decode([LogoDTO].self, name: "iptv-org-logos")
        let feeds = try decode([FeedDTO].self, name: "iptv-org-feeds")
        let streams = try decode([StreamDTO].self, name: "iptv-org-streams")
        let categories = try decode([CategoryDTO].self, name: "iptv-org-categories")
        let assembled = CatalogAssembler.channels(from: channels, logos: logos, feeds: feeds)
        let byID = Dictionary(uniqueKeysWithValues: assembled.map { ($0.id, $0) })

        let radio = try XCTUnwrap(byID["002RadioTV.do"])
        XCTAssertEqual(radio.logo, "https://i.imgur.com/7oNe8xj.png")
        XCTAssertEqual(radio.languages, ["spa"])
        XCTAssertFalse(radio.isNSFW)
        XCTAssertNil(radio.closed)

        let closed = try XCTUnwrap(byID["1000xHoraTV.uy"])
        XCTAssertEqual(closed.closed, "2026-06-19")
        XCTAssertEqual(closed.logo, "https://i.imgur.com/wP3bbYr.png")

        let adult = try XCTUnwrap(byID["21Sextury.us"])
        XCTAssertTrue(adult.isNSFW)

        let doc = try XCTUnwrap(byID["24Doc.ru"])
        XCTAssertEqual(doc.categories, ["documentary"])
        XCTAssertEqual(doc.altNames, ["24 Док"])
        XCTAssertEqual(doc.replacedBy, "Doctor.ru")
        XCTAssertEqual(doc.closed, "2017-07-01")

        let documentary = try XCTUnwrap(categories.map { $0.toDomain() }.first { $0.id == "documentary" })
        XCTAssertEqual(documentary.name, "Documentary")
        XCTAssertEqual(documentary.id, "documentary")

        let domainStreams = streams.compactMap { $0.toDomain() }
        let plus = try XCTUnwrap(domainStreams.first { $0.channel == "1Plus1International.ua" })
        XCTAssertNil(plus.status)
        XCTAssertEqual(plus.feed, "SD")
        XCTAssertEqual(plus.title, "1+1 International")
        XCTAssertFalse(plus.userAgent?.isEmpty ?? true)

        let monde = try XCTUnwrap(domainStreams.first { $0.channel == "2MMonde.ma" })
        XCTAssertEqual(monde.httpReferrer, "http://www.radio2m.ma/")
        XCTAssertEqual(monde.quality, "360p")

        let legacyURL = try fixtureURL("iptv-org-legacy")
        let legacy = try JSONDecoder().decode(LegacyFixture.self, from: Data(contentsOf: legacyURL))
        let legacyChannels = CatalogAssembler.channels(from: legacy.channels, logos: [], feeds: [])
        XCTAssertEqual(legacyChannels.first?.languages, ["eng"])
        XCTAssertEqual(legacyChannels.first?.logo, "https://example.com/legacy-cnn.png")
        let legacyStream = try XCTUnwrap(legacy.streams.first?.toDomain())
        XCTAssertEqual(legacyStream.httpReferrer, "https://cnn.com/watch")
        XCTAssertEqual(legacyStream.status, "active")
    }

    func test_categoryId_filtersDocumentaryNotDisplayName() async {
        let engine = ChannelFilterEngine()
        let channel = Channel(
            id: "24Doc.ru",
            name: "24 Doc",
            country: "RU",
            languages: ["rus"],
            categories: ["documentary"],
            logo: nil,
            website: nil
        )
        await engine.setup(
            channels: [channel],
            streams: [Stream(channel: channel.id, urlString: "http://example.com/a.m3u8", status: nil, timeshift: nil, httpReferrer: nil)]
        )
        let byID = await engine.filter(query: nil, category: "documentary", country: nil, language: nil)
        XCTAssertEqual(byID.map(\.id), ["24Doc.ru"])
        let byOther = await engine.filter(query: nil, category: "docs", country: nil, language: nil)
        XCTAssertTrue(byOther.isEmpty)
    }

    func test_playbackHeaders_sendSanitizedUserAgentAndReferer() {
        let stream = Stream(
            channel: "cnn",
            urlString: "https://example.com/live.m3u8",
            status: nil,
            timeshift: nil,
            httpReferrer: "https://cnn.com/watch",
            userAgent: "IPTVAgent/1"
        )
        let fields = PlaybackRequestHeaders.httpHeaderFields(for: stream)
        XCTAssertEqual(fields["Referer"], "https://cnn.com/watch")
        XCTAssertEqual(fields["User-Agent"], "IPTVAgent/1")

        let poisoned = Stream(
            channel: "cnn",
            urlString: "https://example.com/live.m3u8",
            status: nil,
            timeshift: nil,
            httpReferrer: "https://cnn.com/watch\r\nX-Injected: 1",
            userAgent: "Bad\r\nAgent"
        )
        let blocked = PlaybackRequestHeaders.httpHeaderFields(for: poisoned)
        XCTAssertNil(blocked["Referer"])
        XCTAssertNil(blocked["User-Agent"])
    }

    private func decode<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        let url = try fixtureURL(name)
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try XCTUnwrap(url)
    }
}

private struct LegacyFixture: Decodable {
    var channels: [ChannelDTO]
    var streams: [StreamDTO]
}
