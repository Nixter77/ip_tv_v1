# Fix Plan: macOS 15 Compatibility and Protocol Existential Warnings

## Scope
Address compiler error and warnings in IPTVPlayer:
1. Fix `windowBackgroundDragBehavior` compilation error on macOS versions prior to 15.0.
2. Fix `PlayerStateManagerProtocol` warnings in `AppViewModel.swift` by using the `any` keyword.
3. Validate compilation to ensure all issues are resolved.

## Checklist
- [x] Create detailed implementation plan and obtain user approval.
- [x] Modify `App/IPTVApp.swift` to conditionally apply `.windowBackgroundDragBehavior(.disabled)` using `#available(macOS 15.0, *)`.
- [x] Modify `Sources/Presentation/AppViewModel.swift` to prefix `PlayerStateManagerProtocol` usage with `any`.
- [x] Run build command (`swift build`) to verify that the project compiles cleanly without errors or warnings.
- [x] Document final results in this todo file and walkthrough.

## Review Results
- Discovered that SwiftUI `SceneBuilder` in Swift 5.9 does not support limited availability branching (`if #available(macOS 15.0, *)`) inside the scene block.
- Implemented an elegant and robust fallback using an AppKit-bridge view accessor: `WindowAccessor` (NSViewRepresentable). It retrieves the `NSWindow` and sets `isMovableByWindowBackground = false`, completely bypassing the `SceneBuilder` limitations while remaining fully compatible with macOS 14.0+.
- Prefixed `PlayerStateManagerProtocol`, `IPTVRepositoryProtocol`, and `ChannelFilterEngineProtocol` with `any` in `AppViewModel.swift` properties and initializer.
- Verified build and tests successfully: `swift build` and `swift test` compiled cleanly and all 27 unit tests passed with 0 failures.
