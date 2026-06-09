## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Hybrid URL Masking and DoS Protection]
**Vulnerability:** IPTV providers often mix path-based and query-based authentication; previous filters only applied path-based masking if query items were absent, potentially leaking tokens in hybrid URLs. Additionally, unbounded search inputs posed a DoS risk.
**Learning:** Security filters must apply sanitization passes (path, query, credentials, fragment) independently to prevent leakage in hybrid structures. Input length limits are essential for preventing resource exhaustion in string processing.
**Prevention:** Remove conditional guards that skip sanitization passes (e.g., query-present check before path masking) and enforce strict character limits on user-controlled inputs like search queries.
