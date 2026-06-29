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

    func test_maskURLs_handlesTrailingPunctuation() {
        let text = "Check this URL: https://example.com/play?token=secret, and this one (https://other.com/key=123); or [https://third.com/auth=abc]."
        let masked = Stream.maskURLs(in: text)

        XCTAssertTrue(masked.contains("https://example.com/play?token=****,"))
        XCTAssertTrue(masked.contains("(https://other.com/key=****);"))
        XCTAssertTrue(masked.contains("[https://third.com/auth=****]."))
        XCTAssertFalse(masked.contains("secret"))
        XCTAssertFalse(masked.contains("123"))
        XCTAssertFalse(masked.contains("abc"))
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

    func test_mask_masksPathAndQueryTogether() {
        let complexUrl = "https://provider.com/auth=abc123/stream.m3u8?token=xyz789"
        let masked = Stream.mask(complexUrl)

        XCTAssertEqual(masked, "https://provider.com/auth=****/stream.m3u8?token=****")
        XCTAssertFalse(masked.contains("abc123"))
        XCTAssertFalse(masked.contains("xyz789"))
    }

    func test_mask_handlesNonStandardDelimiters() {
        let pipedUrl = "http://server.net/play|user=joe|pass=123;token=999"
        let masked = Stream.mask(pipedUrl)

        XCTAssertTrue(masked.contains("user=****"))
        XCTAssertTrue(masked.contains("pass=****"))
        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertFalse(masked.contains("joe"))
        XCTAssertFalse(masked.contains("123"))
        XCTAssertFalse(masked.contains("999"))
    }
}
