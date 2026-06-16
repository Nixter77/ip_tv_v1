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
        // Implementation now uses a single **** for the entire credential block
        XCTAssertTrue(masked.contains("://****@example.com"))
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

        XCTAssertTrue(masked.contains("http://****@host.com/play?token=****"))
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

    func test_mask_handlesHybridUrl_withPathAndQueryTokens() {
        let hybridUrl = "https://example.com/auth=token123/stream.m3u8?session=abc"
        let masked = Stream.mask(hybridUrl)

        // Path token should be masked
        XCTAssertTrue(masked.contains("auth=****"))
        XCTAssertFalse(masked.contains("token123"))

        // Query token should also be masked
        XCTAssertTrue(masked.contains("session=****"))
        XCTAssertFalse(masked.contains("abc"))
    }

    func test_mask_failSecure_masksComplexMalformedUrls() {
        // A malformed URL with pipes and spaces that URLComponents might fail on even after encoding
        let malformed = "http://user:pass@host.com/play|token=123|key=456 password"
        let masked = Stream.mask(malformed)

        XCTAssertTrue(masked.contains("http://****@host.com"))
        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertTrue(masked.contains("key=****"))
        XCTAssertFalse(masked.contains("pass"))
        XCTAssertFalse(masked.contains("123"))
        XCTAssertFalse(masked.contains("456"))
        XCTAssertFalse(masked.contains("password"))
    }
}
