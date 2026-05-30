# Fix Plan: macOS 15 Compatibility and Protocol Existential Warnings

## Scope
Address compiler error and warnings in IPTVPlayer:
1. Fix `windowBackgroundDragBehavior` compilation error on macOS versions prior to 15.0.
2. Fix `PlayerStateManagerProtocol` warnings in `AppViewModel.swift` by using the `any` keyword.
3. Validate compilation to ensure all issues are resolved.

## Checklist
- [ ] Create detailed implementation plan and obtain user approval.
- [ ] Modify `App/IPTVApp.swift` to conditionally apply `.windowBackgroundDragBehavior(.disabled)` using `#available(macOS 15.0, *)`.
- [ ] Modify `Sources/Presentation/AppViewModel.swift` to prefix `PlayerStateManagerProtocol` usage with `any`.
- [ ] Run build command (`swift build`) to verify that the project compiles cleanly without errors or warnings.
- [ ] Document final results in this todo file and walkthrough.
