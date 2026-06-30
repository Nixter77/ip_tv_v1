## 2026-05-28 - [Enhancing macOS Accessibility and Empty States]
**Learning:** In high-density macOS applications like IPTV players, icon-only buttons require explicit ARIA labels (accessibilityLabel in SwiftUI) for screen readers. Additionally, empty states for search results should provide immediate actionable feedback, like a "Clear Search" button, to improve the user flow.
**Action:** Always add `.accessibilityLabel` to icon-only buttons and provide a CTA in empty search results.

## 2026-05-29 - [Context-Aware Empty States and Recovery Actions]
**Learning:** Generic "no results" messages are frustrating. Differentiating empty states based on context (e.g., Favorites vs. Search) and providing an immediate "escape hatch" (e.g., "Go to All Channels") significantly reduces user friction in navigation-heavy apps.
**Action:** Implement context-specific empty states with relevant icons and helpful call-to-action buttons.

## 2026-05-30 - [Actionable Error States in Media Playback]
**Learning:** In media playback interfaces, providing an immediate "Retry" action directly within the error overlay reduces the cognitive load of navigating back to a list to restart a stream.
**Action:** Always include an `onRetry` callback in player error HUDs to allow one-click recovery from transient network failures.

## 2026-05-31 - [Native macOS Interactions and Layout Stability]
**Learning:** For macOS-native SwiftUI apps, favor `.opacity(isVisible ? 1 : 0)` over conditional rendering for interactive elements in rows to prevent layout jumps during hover and keep elements accessible. Implementing `.contextMenu` for secondary actions like "Copy Name" or "Toggle Favorite" improves desktop-native feel and discoverability.
**Action:** Use `.opacity` for stable hover buttons and provide context menus for row-based actions.
