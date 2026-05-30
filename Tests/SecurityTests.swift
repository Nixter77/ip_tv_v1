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

    func test_stream_url_usesURLComponents_forParsing() {
        // This test ensures we properly parse a URL that contains a space and fragment using the URLComponents logic
        let stream = Stream(
            channel: "test",
            urlString: "http://example.com/test space?q=a b#frag",
            status: nil,
            timeshift: nil,
            httpReferrer: nil
        )

        let url = stream.url
        XCTAssertNotNil(url)
        // If it was just using .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) on the whole string,
        // it would incorrectly encode `#frag` as `%23frag`. We want to make sure it doesn't do that.
        XCTAssertEqual(url?.absoluteString, "http://example.com/test%20space?q=a%20b#frag")
    }
}
