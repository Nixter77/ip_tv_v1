## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2026-07-08 - [Unified Parameter Redaction as Defense-in-Depth]
**Vulnerability:** IPTV stream URLs often embed sensitive tokens in non-standard ways (e.g., path segments or using delimiters like '|' or ';') that standard 'URLComponents' parsing or simple query-string logic might miss.
**Learning:** A "unified" regex pass using lookbehind '(?<=[?&/|;#])' provides a robust second layer of defense. It redacts 'key=value' patterns across various separators while preserving the keys, ensuring sensitive data is masked even in malformed or complex URLs.
**Prevention:** Use pre-compiled regex constants for both URL detection and parameter masking to ensure consistency, performance, and robustness against exotic URL structures and trailing punctuation in unstructured text.
