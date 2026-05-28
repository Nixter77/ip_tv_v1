## 2026-05-28 - [Enhancing macOS Accessibility and Empty States]
**Learning:** In high-density macOS applications like IPTV players, icon-only buttons require explicit ARIA labels (accessibilityLabel in SwiftUI) for screen readers. Additionally, empty states for search results should provide immediate actionable feedback, like a "Clear Search" button, to improve the user flow.
**Action:** Always add `.accessibilityLabel` to icon-only buttons and provide a CTA in empty search results.
