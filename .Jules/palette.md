## 2026-05-28 - [Enhancing macOS Accessibility and Empty States]
**Learning:** In high-density macOS applications like IPTV players, icon-only buttons require explicit ARIA labels (accessibilityLabel in SwiftUI) for screen readers. Additionally, empty states for search results should provide immediate actionable feedback, like a "Clear Search" button, to improve the user flow.
**Action:** Always add `.accessibilityLabel` to icon-only buttons and provide a CTA in empty search results.

## 2026-05-29 - [Context-Aware Empty States and Recovery Actions]
**Learning:** Generic "no results" messages are frustrating. Differentiating empty states based on context (e.g., Favorites vs. Search) and providing an immediate "escape hatch" (e.g., "Go to All Channels") significantly reduces user friction in navigation-heavy apps.
**Action:** Implement context-specific empty states with relevant icons and helpful call-to-action buttons.
