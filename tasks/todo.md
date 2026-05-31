# Task: AppViewModel Performance Optimization

- [ ] Add 300ms debounce to `$searchQuery` in `Sources/Presentation/AppViewModel.swift` <!-- id: 0 -->
- [ ] Add `.removeDuplicates()` to `$searchQuery`, `$selectedTab`, and `$favoriteIds` in `Sources/Presentation/AppViewModel.swift` <!-- id: 1 -->
- [ ] Refactor `saveSettings` into `saveSearchQuery` and `saveSelectedTab` and update `didSet` observers <!-- id: 2 -->
- [ ] Verify changes via `read_file` <!-- id: 3 -->
- [ ] Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done. <!-- id: 4 -->
