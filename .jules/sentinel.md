## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.

## 2024-05-29 - [Robust URL Masking for Malformed Streams]
**Vulnerability:** URLs with unencoded spaces or special characters caused `URLComponents` parsing to fail, bypassing the sensitive data masking logic and leaking raw tokens in the UI.
**Learning:** IPTV stream URLs often contain "dirty" data (unencoded spaces). `URLComponents` is strict and returns `nil` if parsing fails, so masking must handle pre-encoding to ensure robustness.
**Prevention:** Always attempt to encode the URL string with a robust character set (including `#` for fragments) if initial parsing fails in masking or URL creation logic, ensuring that sensitive components can still be identified and redacted without breaking functionality.

## 2024-05-30 - [Defense-in-Depth for URL Masking and DoS]
**Vulnerability:** Information leakage through non-standard URL delimiters (e.g., `|`, `;`) and resource exhaustion through oversized search queries.
**Learning:** Standard URL parsers like `URLComponents` fail on malformed IPTV URLs, and relying on them alone is insufficient for security masking. Lookbehind regexes can provide a robust second layer of defense.
**Prevention:** Implement a "fail-secure" regex pass for URL masking that covers multiple delimiters. Cap all user-controllable input lengths (like search queries) at the model/view-model level to mitigate DoS risks.
