## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Synchronous Input Hardening]
**Vulnerability:** Asynchronous truncation of the search query in a Combine pipeline allowed oversized strings to trigger expensive filtering and state updates before truncation occurred, creating a DoS risk.
**Learning:** Security-critical input validation and normalization must happen synchronously (e.g., in a property's `didSet` observer) to protect the application state before any reactive observers are notified.
**Prevention:** Always enforce input length limits and basic sanitization synchronously at the point of ingestion.

## 2024-05-30 - [Defense-in-Depth URL Masking]
**Vulnerability:** IPTV stream URLs frequently contain non-standard structures (unencoded spaces, tokens in path segments, or complex fragments) that bypass traditional URL parsers or simple regex filters.
**Learning:** Robust masking requires a multi-layered approach: use structured parsing for credentials, then apply a comprehensive regex-based redaction pass for all key-value pairs across the entire string (query, path, fragments).
**Prevention:** Combine `URLComponents` with robust regex patterns like `(?<=[?&/|;#])([^?&/|;=\s#]+)=[^?&/|;#]+` to ensure full coverage of sensitive tokens in diverse URL formats.
