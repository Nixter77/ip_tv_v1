## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Unified Regex-First Masking for Robustness]
**Vulnerability:** Path-based tokens were skipped if query parameters existed, and malformed URLs could bypass standard URL parsing, leading to credential/token leakage.
**Learning:** Depending solely on `URLComponents` or manual path splitting is fragile. A regex-first approach that targets known sensitive patterns (credentials and key=value pairs) ensures protection even when parsing fails or URL structures are hybrid.
**Prevention:** Use a robust regex that respects common IPTV delimiters (?, &, /, |, ;, space, #) to mask values before attempting more granular parsing, ensuring a consistent security posture.
