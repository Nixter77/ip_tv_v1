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

    func test_mask_handlesHybridPathAndQueryTokens() {
        let hybridUrl = "https://example.com/api/key=path_secret/play?token=query_secret"
        let masked = Stream.mask(hybridUrl)

        XCTAssertTrue(masked.contains("key=****"))
        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertFalse(masked.contains("path_secret"))
        XCTAssertFalse(masked.contains("query_secret"))
    }

    func test_mask_fallbackRegex_masksMalformedUrls() {
        // A malformed URL that might fail standard parsing even after encoding attempts
        let malformedUrl = "https://example.com/path?token=secret123|other=val;sid=789"
        let masked = Stream.mask(malformedUrl)

        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertTrue(masked.contains("other=****"))
        XCTAssertTrue(masked.contains("sid=****"))
        XCTAssertFalse(masked.contains("secret123"))
        XCTAssertFalse(masked.contains("val"))
        XCTAssertFalse(masked.contains("789"))
    }

    @MainActor
    func test_appViewModel_searchQuery_lengthLimit() {
        // Verify that AppViewModel actually truncates the search query to 512 characters
        let mockRepo = IPTVRepository()
        let mockFilter = ChannelFilterEngine()
        let mockPlayer = PlayerStateManager()
        let viewModel = AppViewModel(repository: mockRepo, filterEngine: mockFilter, playerManager: mockPlayer)

        let longQuery = String(repeating: "a", count: 1000)
        viewModel.searchQuery = longQuery

        XCTAssertEqual(viewModel.searchQuery.count, 512)
        XCTAssertEqual(viewModel.searchQuery, String(longQuery.prefix(512)))
    }
}
