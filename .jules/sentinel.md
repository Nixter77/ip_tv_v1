## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2026-07-01 - [Enhanced Regex-Based URL Masking]
**Vulnerability:** Existing URL masking relied on strict `URLComponents` parsing, which frequently failed on IPTV URLs containing unencoded spaces or non-standard delimiters (e.g., `|`, `;`), causing sensitive tokens to leak in the UI and logs.
**Learning:** `URLComponents` is insufficient for the "dirty" URLs common in IPTV playlists. A secondary, robust regex-based pass is required to catch sensitive parameters regardless of the delimiter used or the overall URL validity.
**Prevention:** Implement a defense-in-depth masking strategy using pre-compiled regexes with lookbehind assertions to redact any `key=value` pair across standard and non-standard delimiters, ensuring consistent protection even when structured parsing fails.
