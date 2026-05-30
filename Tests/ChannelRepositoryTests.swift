// Tests/ChannelRepositoryTests.swift
import XCTest
@testable import IPTVPlayer

final class URLProtocolMock: URLProtocol {
    static var mockData: [URL: (Data, URLResponse, Error?)] = [:]
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        if let url = request.url, let (data, response, error) = URLProtocolMock.mockData[url] {
            if let error = error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}

final class ChannelRepositoryTests: XCTestCase {
    private var session: URLSession!
    private var repository: IPTVRepository!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        session = URLSession(configuration: config)
        repository = IPTVRepository(session: session)
        URLProtocolMock.mockData.removeAll()
    }

    override func tearDown() {
        session = nil
        repository = nil
        URLProtocolMock.mockData.removeAll()
        super.tearDown()
    }

    /// Проверяет успешное декодирование каналов при корректном JSON
    func test_validChannelDecoding() async throws {
        let jsonString = """
        [
            {
                "id": "cnn.us",
                "name": "CNN US",
                "country": "US",
                "languages": ["eng"],
                "categories": ["news"],
                "logo": "https://example.com/logo.png",
                "website": "https://cnn.com"
            }
        ]
        """
        let data = Data(jsonString.utf8)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        URLProtocolMock.mockData[url] = (data, response, nil)
        
        let channels = try await repository.fetchChannels()
        
        XCTAssertEqual(channels.count, 1)
        guard !channels.isEmpty else {
            XCTFail("Channels array is empty")
            return
        }
        XCTAssertEqual(channels.first?.id, "cnn.us")
        XCTAssertEqual(channels.first?.name, "CNN US")
        XCTAssertEqual(channels.first?.country, "US")
        XCTAssertEqual(channels.first?.languages, ["eng"])
        XCTAssertEqual(channels.first?.categories, ["news"])
        XCTAssertEqual(channels.first?.logo, "https://example.com/logo.png")
        XCTAssertEqual(channels.first?.website, "https://cnn.com")
    }

    /// Проверяет успешное декодирование канала при отсутствии необязательных полей
    func test_missingOptionalFieldsDecoding() async throws {
        let jsonString = """
        [
            {
                "id": "cnn.us",
                "name": "CNN US"
            }
        ]
        """
        let data = Data(jsonString.utf8)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        URLProtocolMock.mockData[url] = (data, response, nil)
        
        let channels = try await repository.fetchChannels()
        
        XCTAssertEqual(channels.count, 1)
        guard !channels.isEmpty else {
            XCTFail("Channels array is empty")
            return
        }
        XCTAssertEqual(channels.first?.id, "cnn.us")
        XCTAssertNil(channels.first?.country)
        XCTAssertEqual(channels.first?.languages, [])
        XCTAssertEqual(channels.first?.categories, [])
        XCTAssertNil(channels.first?.logo)
        XCTAssertNil(channels.first?.website)
    }

    /// Проверяет успешное декодирование стран при корректном JSON
    func test_validCountryDecoding() async throws {
        let jsonString = """
        [
            {
                "code": "us",
                "name": "United States",
                "languages": ["eng", "spa"],
                "flag": "🇺🇸"
            }
        ]
        """
        let data = Data(jsonString.utf8)
        let url = URL(string: "https://iptv-org.github.io/api/countries.json")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!

        URLProtocolMock.mockData[url] = (data, response, nil)

        let countries = try await repository.fetchCountries()

        XCTAssertEqual(countries.count, 1)
        guard !countries.isEmpty else {
            XCTFail("Countries array is empty")
            return
        }
        XCTAssertEqual(countries.first?.code, "us")
        XCTAssertEqual(countries.first?.name, "United States")
        XCTAssertEqual(countries.first?.languages, ["eng", "spa"])
        XCTAssertEqual(countries.first?.flag, "🇺🇸")
    }

    /// Проверяет успешное декодирование страны при отсутствии необязательных полей
    func test_missingOptionalFieldsCountryDecoding() async throws {
        let jsonString = """
        [
            {
                "code": "us",
                "name": "United States"
            }
        ]
        """
        let data = Data(jsonString.utf8)
        let url = URL(string: "https://iptv-org.github.io/api/countries.json")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!

        URLProtocolMock.mockData[url] = (data, response, nil)

        let countries = try await repository.fetchCountries()

        XCTAssertEqual(countries.count, 1)
        guard !countries.isEmpty else {
            XCTFail("Countries array is empty")
            return
        }
        XCTAssertEqual(countries.first?.code, "us")
        XCTAssertEqual(countries.first?.name, "United States")
        XCTAssertEqual(countries.first?.languages, [])
        XCTAssertNil(countries.first?.flag)
    }

    /// Проверяет, что один поврежденный элемент в массиве стримов не ломает декодирование остальных валидных стримов
    func test_corruptedStreamArrayDecoding() async throws {
        let jsonString = """
        [
            {
                "channel": "cnn.us",
                "url": "http://cnn-live.com/stream.m3u8",
                "status": "active"
            },
            {
                "channel": "broken.channel",
                "url": 12345,
                "status": "active"
            },
            {
                "channel": "fox.us",
                "url": "http://fox-live.com/stream.m3u8",
                "status": "active"
            }
        ]
        """
        let data = Data(jsonString.utf8)
        let url = URL(string: "https://iptv-org.github.io/api/streams.json")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        URLProtocolMock.mockData[url] = (data, response, nil)
        
        let streams = try await repository.fetchStreams()
        
        XCTAssertEqual(streams.count, 2)
        guard streams.count >= 2 else {
            XCTFail("Streams count is less than 2: \(streams.count)")
            return
        }
        XCTAssertEqual(streams[0].channel, "cnn.us")
        XCTAssertEqual(streams[0].urlString, "http://cnn-live.com/stream.m3u8")
        XCTAssertEqual(streams[1].channel, "fox.us")
        XCTAssertEqual(streams[1].urlString, "http://fox-live.com/stream.m3u8")
    }
}
