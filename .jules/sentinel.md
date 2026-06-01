## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Mixed-Format URL Masking]
**Vulnerability:** URLs containing both path-based tokens (e.g., `/auth=token/`) and standard query parameters caused path-based tokens to be skipped by the masking logic, potentially leaking credentials.
**Learning:** IPTV providers often use non-standard URL structures where sensitive tokens are embedded in path segments using `=` as a delimiter. Masking logic must evaluate path segments independently of the presence of query parameters.
**Prevention:** Ensure path-segment masking logic for "key=value" patterns is executed unconditionally for all parsed URLs, even when standard query parameters are also present.
