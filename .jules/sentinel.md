## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Enhanced URL Masking and DoS Prevention]
**Vulnerability:** Hybrid URL structures (using both path segments and query parameters for tokens) and malformed URLs bypassed existing masking logic. Additionally, extremely long search queries posed a DoS risk during tokenization.
**Learning:** Security logic must be "fail-secure" and handle edge cases like mixed token locations and parsing failures. In Swift, complex regex patterns with backslashes (like ) are more reliably handled using raw string literals (\#"..."\#).
**Prevention:** Implement unconditional masking for all URL components that look like key-value pairs, regardless of whether they appear in the path or query. Use fail-secure regex fallbacks for malformed URLs and enforce length limits on user input before processing.

## 2024-05-30 - [Enhanced URL Masking and DoS Prevention]
**Vulnerability:** Hybrid URL structures (using both path segments and query parameters for tokens) and malformed URLs bypassed existing masking logic. Additionally, extremely long search queries posed a DoS risk during tokenization.
**Learning:** Security logic must be "fail-secure" and handle edge cases like mixed token locations and parsing failures. In Swift, complex regex patterns with backslashes (like \s) are more reliably handled using raw string literals.
**Prevention:** Implement unconditional masking for all URL components that look like key-value pairs, regardless of whether they appear in the path or query. Use fail-secure regex fallbacks for malformed URLs and enforce length limits on user input before processing.
