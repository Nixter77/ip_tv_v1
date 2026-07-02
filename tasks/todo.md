# Task: Fix Window Close and Zoom Buttons

- [x] Create public `WindowAccessor` in `Sources/Presentation/WindowAccessor.swift` <!-- id: 5 -->
- [x] Modify `CleanAVPlayerView` in `Sources/Presentation/VideoPlayerView.swift` to pass clicks through in traffic light region <!-- id: 6 -->
- [x] Remove hardcoded `.ignoresSafeArea()` in `Sources/Presentation/QuickTimeHUDPanel.swift` <!-- id: 7 -->
- [x] Update `Sources/Presentation/MainSplitView.swift` to apply ignoresSafeArea and add sidebar top padding <!-- id: 8 -->
- [x] Update `Sources/Presentation/DetachedPlayerView.swift` to use public `WindowAccessor` and disable ignoresSafeArea on video container <!-- id: 9 -->
- [x] Update `App/IPTVApp.swift` to use the public `WindowAccessor` and remove local declaration <!-- id: 10 -->
- [x] Verify changes manually and run unit tests <!-- id: 11 -->
- [x] Optimize Favorites and History filtering using `matchingIds` in `FilterEngine` <!-- id: 12 -->

## Review
- **Public Window Accessor**: Moved the local window accessor out of `IPTVApp.swift` to the `Presentation` module to allow shared access across modules.
- **Traffic Light Event Pass-Through**: Implemented `hitTest(_:)` in `CleanAVPlayerView` (which wraps AppKit's `AVPlayerView` inside `NSViewRepresentable`). Clicking within the top-left area `(x: 0...80, y: height-40...height)` now bypasses the player view, restoring full click responsiveness to the Close, Minimize, and Zoom window controls.
- **Sidebar Padding**: Added top padding of `40` to the sidebar List in `MainSplitView.swift` so that navigation items do not overlap the traffic light buttons.
- **Detached Window Styling**: Configured the detached player window view `DetachedPlayerView` to respect safe areas, ensuring the player does not obscure its native title bar. We also added window dragging functionality so users can drag the detached window by its background.
- **Verification**: Verified using `swift test` which passed successfully.
