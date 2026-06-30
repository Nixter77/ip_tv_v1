# Lessons Learned

## 1. SwiftUI safe area overrides and AppKit View interactions on macOS
- **Problem**: Placing an AppKit/UIKit wrapper view (like `AVPlayerView` in `NSViewRepresentable`) using `.ignoresSafeArea()` on a window will stretch the underlying view over the title bar area. Because it's an active AppKit view, it intercepts all mouse events in that region, making the window's native controls (Close, Minimize, Zoom buttons) unresponsive.
- **Solution**: 
  1. Restrict `.ignoresSafeArea()` where possible (e.g. only apply it to background decorative colors, keeping interactive components or player views within safe areas).
  2. If the view must cover the entire window frame, implement `hitTest(_:)` in the AppKit view to return `nil` inside the traffic lights zone `(x: 0...80, y: height-40...height)`. This lets the OS handle clicks in that area, passing them directly to the traffic light controls.
  3. When using `.windowStyle(.hiddenTitleBar)`, add padding to the top of the sidebar List and other columns (at least `40` points) to prevent content items and hover actions from overlapping the traffic light buttons.
