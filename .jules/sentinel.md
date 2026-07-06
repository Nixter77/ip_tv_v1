## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Defense-in-Depth URL Masking]
**Vulnerability:** Structured URL parsing (URLComponents) can miss sensitive credentials or tokens if they are embedded in path segments, fragments, or following non-standard delimiters (like '|' or ';'), especially when standard query parameters are also present.
**Learning:** A single layer of structured parsing is insufficient for the diverse and often non-standard URL formats used by IPTV providers. Defense-in-depth using a secondary regex pass on the entire URL string ensures that any "key=value" pattern is redacted regardless of its position or the preceding delimiter.
**Prevention:** Implement a multi-stage masking pipeline: first, use structured parsing for standard components, then apply a broad but targeted regex to redact any remaining sensitive patterns in the final string representation.
