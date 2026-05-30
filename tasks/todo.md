# Fix Plan: Channel Search Field Cannot Receive Focus

## Scope
Fix the channel search text field so users can click/focus it and type channel queries normally, without changing unrelated IPTV app behavior.

## Checklist
- [x] Inspect current project instructions, task notes, and relevant SwiftUI presentation files.
- [x] Identify the root cause that prevents the search field from accepting focus/input.
- [x] Implement the minimal robust fix in the channel list UI/window setup.
- [x] Update this task file with progress and review notes.
- [x] Run available build/tests or closest verification commands.
- [x] Review final diff for simplicity/elegance.
- [x] Commit the changes and open a PR.

## Review Results
- The main window uses `.windowStyle(.hiddenTitleBar)`, and the search field sits at the top of the custom content area.
- With hidden title bars on macOS, the content background can become a window-drag region. That can intercept mouse events before the custom SwiftUI search field becomes first responder, making the field appear unfocusable/untypable.
- Disabled window-background dragging for the main app window so clicks in custom content go to interactive controls like the channel search field.
- Kept the existing `TextField`/`@FocusState` implementation intact, including the ⌘F shortcut path, to avoid an unnecessary custom AppKit text-field wrapper.
- Verification: `swift test` passes 17 portable tests in this Linux environment. The macOS-only visual focus behavior cannot be exercised directly here because the container is Linux and has no AppKit window server.
