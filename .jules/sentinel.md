## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Hybrid URL Masking and DoS Prevention]
**Vulnerability:** 1. Hybrid URLs containing sensitive tokens in both path segments and query parameters were only partially masked (path segments were skipped if query items were present). 2. Lack of input length limits on search queries posed a potential DoS risk during high-frequency filtering operations.
**Learning:** Security filters must apply sanitization passes independently for all URL components (path, query, credentials) to ensure complete redaction in complex, non-standard URL structures often used by IPTV providers. Additionally, UI inputs that trigger heavy computation (like filtering) must be bounded to prevent resource exhaustion.
**Prevention:** Remove conditional logic that prevents one masking pass if another succeeds. Implement strict character limits on all user-facing search fields that trigger expensive filtering logic.
