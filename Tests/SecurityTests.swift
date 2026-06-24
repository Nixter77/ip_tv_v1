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

    func test_maskedUrlString_masksPathTokens_withQueryParameters() {
        let stream = Stream(
            channel: "test",
            urlString: "https://example.com/auth=token123/stream.m3u8?key=abc",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let masked = stream.maskedUrlString
        XCTAssertTrue(masked.contains("auth=****"))
        XCTAssertTrue(masked.contains("key=****"))
        XCTAssertFalse(masked.contains("token123"))
        XCTAssertFalse(masked.contains("abc"))
        // Ensure structure is preserved
        XCTAssertTrue(masked.contains("/stream.m3u8?"))
    }

    func test_maskedUrlString_masksComplexDelimiters() {
        // Some providers use | or ; as delimiters
        let stream = Stream(
            channel: "test",
            urlString: "http://host.com/play;token=123|session=456#fragment=789",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let masked = stream.maskedUrlString
        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertTrue(masked.contains("session=****"))
        XCTAssertTrue(masked.contains("fragment=****"))
        XCTAssertFalse(masked.contains("123"))
        XCTAssertFalse(masked.contains("456"))
        XCTAssertFalse(masked.contains("789"))
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

    func test_maskURLs_masksEmbeddedURLs_withPunctuation() {
        let rawError = "Error at https://host.com/p?token=123, also see (https://other.com/auth=456)."
        let masked = Stream.maskURLs(in: rawError)

        XCTAssertTrue(masked.contains("https://host.com/p?token=****"))
        XCTAssertTrue(masked.contains("https://other.com/auth=****"))
        XCTAssertTrue(masked.contains("****,")) // Punctuation preserved outside URL
        XCTAssertTrue(masked.contains("****)."))
        XCTAssertFalse(masked.contains("123"))
        XCTAssertFalse(masked.contains("456"))
    }

    func test_stream_url_usesPreEncoding_forRobustness() {
        let stream = Stream(
            channel: "test",
            urlString: "http://example.com/test space?q=a b#frag",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let url = stream.url
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://example.com/test%20space?q=a%20b#frag")
        XCTAssertEqual(url?.fragment, "frag")
    }

    func test_mask_handlesUrlsWithSpaces() {
        let urlWithSpace = "http://example.com/play?token=secret password"
        let masked = Stream.mask(urlWithSpace)

        XCTAssertTrue(masked.contains("token=****"))
        XCTAssertFalse(masked.contains("secret"))
        XCTAssertFalse(masked.contains("password"))
    }
}
