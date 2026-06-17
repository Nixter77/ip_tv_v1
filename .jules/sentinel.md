## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2026-06-17 - [Defense-in-Depth URL Masking & DoS Protection]
**Vulnerability:** URL token leakage due to non-standard delimiters (e.g., `;`, `|`) bypassing standard `URLComponents` parsing, and potential resource exhaustion (DoS) via unrestricted search query length.
**Learning:** IPTV ecosystems often use non-standard URL structures that break standard library parsers. Relying solely on `URLComponents` for masking is a "fail-open" risk. Additionally, even small UI inputs can be vectors for DoS if not capped before processing.
**Prevention:** Use a regex-first masking approach with lookbehind logic to redact `key=value` pairs regardless of delimiters or URL validity. Implement hard character limits (e.g., 512 chars) on all user-facing search inputs at the ViewModel level.
