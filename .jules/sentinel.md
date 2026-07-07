## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Defense-in-Depth URL Masking]
**Vulnerability:** Masking logic relied primarily on structured `URLComponents` parsing, which fails to redact sensitive tokens embedded in paths or using non-standard delimiters (e.g., `|`, `;`). Additionally, URL detection in unstructured text often captured trailing punctuation, leading to potential metadata leakage.
**Learning:** IPTV providers use highly non-standard URL formats. A single parsing pass is insufficient. Pre-compiled regexes for both boundary detection and parameter redaction provide a necessary second layer of defense.
**Prevention:** Use a multi-pass masking strategy: first attempt structured parsing for standard components, then apply a robust regex pass to catch any remaining `key=value` patterns across all common delimiters (`?&/|;#`). Ensure URL detection regexes exclude common trailing punctuation characters.
