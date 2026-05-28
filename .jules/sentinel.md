## 2024-05-28 - [Information Leakage Prevention]
**Vulnerability:** Sensitive URL information (authentication tokens in query parameters and user credentials) was exposed in the UI during stream loading and error states.
**Learning:** IPTV streams often use sensitive tokens in URLs. Displaying the raw URL in the HUD or error messages is a security risk (e.g., shoulder surfing or screenshots).
**Prevention:** Implement a `maskedUrlString` property in the domain model that redacts credentials and query parameter values, and ensure the UI only uses this masked version for display.
