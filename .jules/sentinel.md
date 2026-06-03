## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Incomplete Masking of Hybrid IPTV URLs]
**Vulnerability:** Hybrid IPTV URLs containing sensitive tokens in both path segments (e.g., `key=val/`) and query strings (e.g., `?token=abc`) were only partially masked. The masking logic skipped path segments if any query parameters were present.
**Learning:** IPTV providers often use non-standard URL structures where authentication data is split between path segments and query items. Security logic must be comprehensive and apply all masking rules independently of each other.
**Prevention:** Remove conditional branching that makes masking rules mutually exclusive. Every sensitive component (credentials, path tokens, query values, and fragments) should be checked and redacted individually to ensure defense-in-depth.
