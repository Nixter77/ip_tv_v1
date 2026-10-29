import XCTest
@testable import IPTVPlayer

private final class ChunkedOversizeProtocol: URLProtocol {
    nonisolated(unsafe) static var finished = false
    nonisolated(unsafe) static var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasSuffix("/channels.json") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0x41, count: 20))
        client?.urlProtocol(self, didLoad: Data(repeating: 0x42, count: 20))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.stopped = true
    }
}

final class SecurityTests: XCTestCase {

    func test_maskedUrlString_masksCredentials() {
        let stream = Stream(
            channel: "test",
            urlString: "http://user:password@example.com/stream.m3u8",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let masked = stream.maskedUrlString
        XCTAssertTrue(masked.contains("****:****@example.com"))
        XCTAssertFalse(masked.contains("user"))
        XCTAssertFalse(masked.contains("password"))
    }

    func test_maskedUrlString_masksQueryParameters() {
        let stream = Stream(
            channel: "test",
            urlString: "https://example.com/play?token=secret123&key=abc",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let masked = stream.maskedUrlString
        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertTrue(masked.contains("key=****"))
        XCTAssertFalse(masked.contains("secret123"))
        XCTAssertFalse(masked.contains("abc"))
    }

    func test_maskedUrlString_handlesPlainUrl() {
        let stream = Stream(
            channel: "test",
            urlString: "https://example.com/simple.m3u8",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let masked = stream.maskedUrlString
        XCTAssertEqual(masked, "https://example.com/simple.m3u8")
    }

    func test_maskedUrlString_handlesInvalidUrl() {
        let stream = Stream(
            channel: "test",
            urlString: "invalid url",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let masked = stream.maskedUrlString
        XCTAssertEqual(masked, "invalid url")
    }

    func test_maskURLs_masksEmbeddedURLs() {
        let rawError = "Failed to load stream at http://user:pass@host.com/play?token=123 and also check https://other.com/key=456 for details"
        let masked = Stream.maskURLs(in: rawError)

        XCTAssertTrue(masked.contains("http://****:****@host.com/play?token=****"))
        XCTAssertTrue(masked.contains("https://other.com/key=****"))
        XCTAssertFalse(masked.contains("user"))
        XCTAssertFalse(masked.contains("pass"))
        XCTAssertFalse(masked.contains("123"))
        XCTAssertFalse(masked.contains("456"))
        XCTAssertTrue(masked.contains("Failed to load stream at"))
        XCTAssertTrue(masked.contains("and also check"))
    }

    func test_stream_url_usesPreEncoding_forRobustness() {
        // This test ensures we properly parse a URL that contains unencoded spaces
        let stream = Stream(
            channel: "test",
            urlString: "http://example.com/test space?q=a b#frag",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let url = stream.url
        XCTAssertNotNil(url)
        // Our robust logic MUST preserve # and ?, but encode spaces as %20
        XCTAssertEqual(url?.absoluteString, "http://example.com/test%20space?q=a%20b#frag")
        XCTAssertEqual(url?.fragment, "frag")
    }

    func test_mask_handlesUrlsWithSpaces() {
        let urlWithSpace = "http://example.com/play?token=secret password"
        let masked = Stream.mask(urlWithSpace)

        // Ensure the token value is masked even if the URL had a space (which usually breaks URLComponents)
        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertFalse(masked.contains("secret"))
        XCTAssertFalse(masked.contains("password"))
    }

    // MARK: - Stream / media URL policy

    func test_stream_url_rejectsNonHTTPSchemes() {
        XCTAssertNil(makeStream("file:///etc/passwd").url)
        XCTAssertNil(makeStream("javascript:alert(1)").url)
        XCTAssertNil(makeStream("data:text/plain,hi").url)
        XCTAssertNil(makeStream("ftp://example.com/live.m3u8").url)
    }

    func test_stream_url_allowsLANForLocalIPTV() {
        XCTAssertNotNil(makeStream("http://192.168.1.10:8080/live.m3u8").url)
        XCTAssertNotNil(makeStream("http://127.0.0.1:8888/stream").url)
    }

    func test_channel_safeLogoURL_blocksSSRFTargets() {
        XCTAssertNil(channel(logo: "file:///etc/passwd").safeLogoURL)
        XCTAssertNil(channel(logo: "http://127.0.0.1/admin").safeLogoURL)
        XCTAssertNil(channel(logo: "http://localhost/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://10.0.0.5/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://192.168.0.1/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://169.254.169.254/latest/meta-data").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::0:1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::0001]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::0:0:1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[0:0:0:0:0:0:0:0001]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::ffff:127.0.0.1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::ffff:7f00:1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::ffff:a9fe:a9fe]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[::ffff:c0a8:1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[fc00::1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://[fe80::1]/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "http://127.000.000.001/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "https://user:pass@cdn.example/logo.png").safeLogoURL)
        XCTAssertNil(channel(logo: "https://example.com/logo.png\r\nX-Injected: 1").safeLogoURL)
        XCTAssertNil(channel(logo: "https://example.com/logo.png%0d%0aX-Injected:%201").safeLogoURL)
        XCTAssertNotNil(channel(logo: "https://cdn.example.com/logo.png").safeLogoURL)
    }

    func test_remoteURLPolicy_blocksDecimalLoopback() {
        XCTAssertTrue(RemoteURLPolicy.isRestrictedHost("2130706433"))
        XCTAssertTrue(RemoteURLPolicy.isRestrictedHost("127.1"))
        XCTAssertFalse(RemoteURLPolicy.isRestrictedHost("cdn.example.com"))
        XCTAssertFalse(RemoteURLPolicy.shouldFollowRedirect(
            to: URL(string: "http://127.0.0.1/secret")!,
            kind: .remoteAsset
        ))
        XCTAssertTrue(RemoteURLPolicy.shouldFollowRedirect(
            to: URL(string: "https://cdn.example.com/logo.png")!,
            kind: .remoteAsset
        ))
    }

    func test_safeHTTPClient_rejectsBlockedURLWithoutFetch() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let client = SafeHTTPClient(configuration: config)
        URLProtocolMock.mockData.removeAll()

        do {
            _ = try await client.data(
                for: URL(string: "http://127.0.0.1/logo.png")!,
                maxBytes: 1024,
                kind: .remoteAsset
            )
            XCTFail("loopback logo must be blocked")
        } catch let error as SafeHTTPError {
            XCTAssertEqual(error, .blockedURL)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func test_safeHTTPClient_rejectsOversizedBody() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let client = SafeHTTPClient(configuration: config)
        let url = URL(string: "https://cdn.example.com/logo.png")!
        let oversized = Data(repeating: 0xFF, count: 8_192)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        URLProtocolMock.mockData[url] = (oversized, response, nil)

        do {
            _ = try await client.data(for: url, maxBytes: 1_024, kind: .remoteAsset)
            XCTFail("oversized body must be rejected")
        } catch let error as SafeHTTPError {
            if case .tooLarge(let seen) = error {
                XCTAssertGreaterThan(seen, 1_024)
            } else {
                XCTFail("expected tooLarge, got \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
        URLProtocolMock.mockData.removeAll()
    }

    func test_sanitizedHTTPHeaderValue_rejectsCTL() {
        XCTAssertNil(RemoteURLPolicy.sanitizedHTTPHeaderValue("abc\r\nAuthorization: Bearer x"))
        XCTAssertNil(RemoteURLPolicy.sanitizedHTTPHeaderValue("abc\nX-Injected: 1"))
        XCTAssertNil(RemoteURLPolicy.sanitizedHTTPHeaderValue("abc\0tail"))
        XCTAssertEqual(RemoteURLPolicy.sanitizedHTTPHeaderValue("  \"abc123\"  "), "\"abc123\"")
        XCTAssertNil(RemoteURLPolicy.sanitizedHTTPHeaderValue("   "))
    }

    func test_repository_dropsPoisonedETagOnRefresh() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iptv-etag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let cache = PlaylistDiskCache(directory: cacheDir, ttl: 6 * 3600)
        let repo = IPTVRepository(session: session, diskCache: cache, maxAttempts: 1)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        let json = Data(#"[{"id":"cnn.us","name":"CNN"}]"#.utf8)
        URLProtocolMock.mockData[url] = (
            json,
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "ETag": "\"abc\"\r\nAuthorization: Bearer stolen",
                    "Last-Modified": "Wed, 01 Jan 2020 00:00:00 GMT\r\nX-Injected: 1"
                ]
            )!,
            nil
        )
        _ = try await repo.fetchChannels(options: .forceNetwork)

        URLProtocolMock.lastRequest = nil
        URLProtocolMock.mockData[url] = (
            json,
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"ok\""])!,
            nil
        )
        _ = try await repo.fetchChannels(options: .forceNetwork)

        XCTAssertNil(URLProtocolMock.lastRequest?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(URLProtocolMock.lastRequest?.value(forHTTPHeaderField: "If-Modified-Since"))
        URLProtocolMock.mockData.removeAll()
        URLProtocolMock.lastRequest = nil
    }

    func test_repository_forwardsSanitizedETag() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iptv-etag-ok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let cache = PlaylistDiskCache(directory: cacheDir, ttl: 6 * 3600)
        let repo = IPTVRepository(session: session, diskCache: cache, maxAttempts: 1)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        let json = Data(#"[{"id":"cnn.us","name":"CNN"}]"#.utf8)
        URLProtocolMock.mockData[url] = (
            json,
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"abc123\""])!,
            nil
        )
        _ = try await repo.fetchChannels(options: .forceNetwork)

        URLProtocolMock.lastRequest = nil
        _ = try await repo.fetchChannels(options: .forceNetwork)
        XCTAssertEqual(URLProtocolMock.lastRequest?.value(forHTTPHeaderField: "If-None-Match"), "\"abc123\"")
        URLProtocolMock.mockData.removeAll()
        URLProtocolMock.lastRequest = nil
    }

    func test_repository_rejectsOversizedPlaylistPayload() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let repo = IPTVRepository(session: session, diskCache: nil, maxAttempts: 1, maxResponseBytes: 32)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        let body = Data(repeating: 0x41, count: 64)
        URLProtocolMock.mockData[url] = (
            body,
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            nil
        )

        do {
            _ = try await repo.fetchChannels()
            XCTFail("oversized playlist must throw")
        } catch let error as PlaylistFetchError {
            if case .payloadTooLarge(_, let count) = error {
                XCTAssertEqual(count, 64)
            } else {
                XCTFail("expected payloadTooLarge, got \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
        URLProtocolMock.mockData.removeAll()
    }

    func test_repository_abortsOversizeBodyWithoutContentLength() async {
        ChunkedOversizeProtocol.finished = false
        ChunkedOversizeProtocol.stopped = false
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChunkedOversizeProtocol.self, URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let repo = IPTVRepository(session: session, diskCache: nil, maxAttempts: 3, maxResponseBytes: 32)
        for name in ["logos", "feeds"] {
            let extra = URL(string: "https://iptv-org.github.io/api/\(name).json")!
            URLProtocolMock.mockData[extra] = (
                Data("[]".utf8),
                HTTPURLResponse(url: extra, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                nil
            )
        }

        do {
            _ = try await repo.fetchChannels(options: .forceNetwork)
            XCTFail("oversize body without Content-Length must abort")
        } catch let error as PlaylistFetchError {
            if case .payloadTooLarge(_, let count) = error {
                XCTAssertEqual(count, 40)
            } else {
                XCTFail("expected payloadTooLarge, got \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(ChunkedOversizeProtocol.stopped)
        XCTAssertFalse(ChunkedOversizeProtocol.finished)
    }

    func test_repository_rejectsBodyLargerThanDeclaredContentLength() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let repo = IPTVRepository(session: session, diskCache: nil, maxAttempts: 1, maxResponseBytes: 32)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        URLProtocolMock.mockData[url] = (
            Data(repeating: 0x41, count: 64),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "8"])!,
            nil
        )
        do {
            _ = try await repo.fetchChannels(options: .forceNetwork)
            XCTFail("lying Content-Length must still abort")
        } catch let error as PlaylistFetchError {
            if case .payloadTooLarge(_, let count) = error {
                XCTAssertEqual(count, 64)
            } else {
                XCTFail("expected payloadTooLarge, got \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
        URLProtocolMock.mockData.removeAll()
    }

    func test_repository_rejectsHTMLBeforeDecodeAndCache() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iptv-html-\(UUID().uuidString)", isDirectory: true)
        let cache = PlaylistDiskCache(directory: cacheDir, ttl: 6 * 3600)
        let repo = IPTVRepository(session: session, diskCache: cache, maxAttempts: 3)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        let body = Data(#"[{"id":"html.us","name":"Should Not Decode"}]"#.utf8)
        URLProtocolMock.mockData[url] = (
            body,
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!,
            nil
        )
        do {
            _ = try await repo.fetchChannels(options: .forceNetwork)
            XCTFail("text/html must not decode")
        } catch let error as PlaylistFetchError {
            if case .unacceptableContent = error {
            } else {
                XCTFail("expected unacceptableContent, got \(error)")
            }
        }
        let cached = cacheDir.appendingPathComponent("channels.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cached.path))
        URLProtocolMock.mockData.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func test_repository_doesNotRetryTooLarge() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let repo = IPTVRepository(session: session, diskCache: nil, maxAttempts: 3, maxResponseBytes: 32)
        let url = URL(string: "https://iptv-org.github.io/api/channels.json")!
        URLProtocolMock.resetStartCounts()
        URLProtocolMock.mockData[url] = (
            Data(repeating: 0x41, count: 64),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            nil
        )
        do {
            _ = try await repo.fetchChannels(options: .forceNetwork)
            XCTFail("expected tooLarge")
        } catch is PlaylistFetchError {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(URLProtocolMock.startCount(for: url), 1)
        URLProtocolMock.mockData.removeAll()
        URLProtocolMock.resetStartCounts()
    }

    func test_playbackClock_nanDoesNotTrap() {
        XCTAssertEqual(PlaybackClock.format(.nan), "0:00")
        XCTAssertEqual(PlaybackClock.format(.infinity), "0:00")
        XCTAssertEqual(PlaybackClock.format(-3), "0:00")
        XCTAssertEqual(PlaybackClock.format(65), "1:05")
    }

    private func makeStream(_ url: String) -> IPTVPlayer.Stream {
        IPTVPlayer.Stream(channel: "test", urlString: url, status: nil, timeshift: nil, httpReferrer: nil)
    }

    private func channel(logo: String) -> Channel {
        Channel(
            id: "t",
            name: "T",
            country: nil,
            languages: [],
            categories: [],
            logo: logo,
            website: nil
        )
    }
}
