## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Defense-in-Depth for Non-Standard IPTV URL Parameters]
**Vulnerability:** Sensitive tokens embedded in URL path segments or using non-standard delimiters (like `|` or `;`) were not consistently redacted by `URLComponents`-based logic, and trailing punctuation in text logs often broke URL detection.
**Learning:** IPTV providers frequently use custom URL structures that standard parsers don't fully decompose. A secondary regex-based masking pass is necessary to catch tokens across multiple delimiters and as a fail-safe.
**Prevention:** Use a restrictive regex for URL detection (`https?://[^\s,;()<>[\]{}'"]+`) to exclude punctuation, and apply a non-destructive regex mask (`(?<=[?&/|;#])([^?&/|;=\s#]+)=[^?&/|;\s#]+`) on the entire string to redact all key-value pairs regardless of their position or delimiter.
