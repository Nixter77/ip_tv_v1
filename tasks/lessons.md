# Lessons Learned

## 3. macOS search focus: never pass FocusState across views; never use invisible Button for ⌘F
- **Problem**: `@FocusState` owned by parent and passed as `FocusState<Bool>.Binding` into a child broke `.focused` on the search `TextField`. Invisible `Button` + `.opacity(0)` + `.keyboardShortcut` never entered the key view loop, so ⌘F stayed in Xcode/other apps. Double-wrapping the app’s `AppViewModel` as `@StateObject` inside `MainSplitView` also risked broken identity.
- **Solution**: Own `@FocusState` in the same view as the `TextField`. Use `.commands { Button(...).keyboardShortcut("f") }` + `NotificationCenter` to focus. Parent holds ViewModel as `@ObservedObject` only. Call `NSApp.activate` + deferred `isSearchFocused = true` on shortcut.

## 2. Player ObservableObject must not rebroadcast into the channel-list ViewModel
- **Problem**: Forwarding `playerManager.objectWillChange` into `AppViewModel.objectWillChange` (or putting `@ObservedObject player` on the same view that owns the channel `List`) forces full list invalidation on every buffer/fallback state change.
- **Solution**: Never bridge player ticks into the catalog ViewModel. Split columns into child views: list/sidebar observe only `AppViewModel`; detail/detached observe `PlayerStateManager` alone. Cancel in-flight filter `Task`s; re-filter favorites only when that tab is active.

## 1. SwiftUI safe area overrides and AppKit View interactions on macOS
- **Problem**: Placing an AppKit/UIKit wrapper view (like `AVPlayerView` in `NSViewRepresentable`) using `.ignoresSafeArea()` on a window will stretch the underlying view over the title bar area. Because it's an active AppKit view, it intercepts all mouse events in that region, making the window's native controls (Close, Minimize, Zoom buttons) unresponsive.
- **Solution**: 
  1. Restrict `.ignoresSafeArea()` where possible (e.g. only apply it to background decorative colors, keeping interactive components or player views within safe areas).
  2. If the view must cover the entire window frame, implement `hitTest(_:)` in the AppKit view to return `nil` inside the traffic lights zone `(x: 0...80, y: height-40...height)`. This lets the OS handle clicks in that area, passing them directly to the traffic light controls.
  3. When using `.windowStyle(.hiddenTitleBar)`, add padding to the top of the sidebar List and other columns (at least `40` points) to prevent content items and hover actions from overlapping the traffic light buttons.
