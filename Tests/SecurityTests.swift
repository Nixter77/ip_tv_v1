import XCTest
@testable import IPTVPlayer

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

    func test_mask_masksPathSegments_whenQueryIsPresent() {
        // Path should be masked even if query parameters are present (defense-in-depth)
        let url = "https://example.com/api/key=123/stream.m3u8?token=abc"
        let masked = Stream.mask(url)

        XCTAssertTrue(masked.contains("key=****"))
        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertFalse(masked.contains("123"))
        XCTAssertFalse(masked.contains("abc"))
    }

    func test_mask_handlesNonStandardDelimiters() {
        // Test for pipe and semicolon delimiters commonly used in IPTV URLs
        let url = "https://example.com/play|token=secret;key=abc"
        let masked = Stream.mask(url)

        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertTrue(masked.contains("key=****"))
        XCTAssertFalse(masked.contains("secret"))
        XCTAssertFalse(masked.contains("abc"))
    }

    func test_mask_masksFragments() {
        let url = "https://example.com/stream#access_token=12345"
        let masked = Stream.mask(url)

        XCTAssertTrue(masked.contains("#****") || masked.contains("access_token=****"))
        XCTAssertFalse(masked.contains("12345"))
    }

    @MainActor
    func test_searchQuery_truncation_forDoSPrevention() async {
        // AppViewModel requires SwiftData context which might be hard to mock here,
        // but we can test the synchronous truncation in the property observer.

        // Use a mock or just rely on the real one if it doesn't crash without SwiftData
        let repository = IPTVRepository()
        let filterEngine = ChannelFilterEngine()
        let playerManager = PlayerStateManager()

        let viewModel = AppViewModel(
            repository: repository,
            filterEngine: filterEngine,
            playerManager: playerManager
        )

        let longQuery = String(repeating: "a", count: 1000)
        viewModel.searchQuery = longQuery

        XCTAssertEqual(viewModel.searchQuery.count, 512)
        XCTAssertEqual(viewModel.searchQuery, String(longQuery.prefix(512)))
    }
}
