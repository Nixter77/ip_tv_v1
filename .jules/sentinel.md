## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Defense-in-depth URL Masking]
**Vulnerability:** Sensitive tokens hidden in path segments or separated by non-standard delimiters (like `|` or `;`) could bypass `URLComponents`-based masking, especially when standard query parameters were also present.
**Learning:** `URLComponents` is excellent for standard URLs but lacks visibility into custom path-based key-value patterns or non-standard delimiters. A multi-layered approach using both structured parsing and a final regex-based "safety net" is necessary for robust redaction.
**Prevention:** Use a lookbehind-based regex `(?<=[?&/|;#])([^?&/|;=\s#]+)=[^?&/|;\s#]+` as a secondary pass to catch sensitive patterns across all URL components and delimiters while preserving the keys.
