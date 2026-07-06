# Bolt's Journal

## 2025-05-14 - Initial Assessment
**Learning:** The project is a macOS app using Swift and SwiftUI. The development environment is Linux, so direct execution/testing of Swift code is not possible. I must rely on static analysis and my knowledge of Swift/SwiftUI performance patterns.
**Action:** Focus on optimizations that are demonstrably beneficial based on Swift performance best practices.

## 2025-05-15 - [Optimization] Pre-sorted Result Filtering
**Learning:** In scenarios with large datasets (e.g., 50k items) that need to be returned in a specific order (e.g., by name), it is significantly faster to maintain a single pre-sorted master list and filter it by matching IDs ($O(N)$) rather than collecting matches and then sorting them ($O(M \log M)$). This is especially true when the result set ($M$) is large.
**Action:** Use `preSortedArray.filter { resultSet.contains($0.id) }` for sorted output in high-performance lookup engines.

## 2026-05-30 - [Optimization] Indexed Access over Dictionary Lookup
**Learning:** Even with O(1) average time complexity, dictionary lookups in Swift have measurable hashing overhead. For high-frequency loops (e.g., iterating over thousands of search tokens), mirroring dictionary values in a parallel array and using direct indexed access ((1)$ constant time) is significantly faster.
**Action:** Use a parallel array (e.g., `tokenSets: [Set<String>]`) that maps 1:1 to a sorted keys array (`sortedTokens: [String]`) to eliminate lookup overhead in tight loops.

## 2024-05-31 - [Optimization] Debounced Search and Granular Persistence
**Learning:** In SwiftUI ViewModels using Combine, chaining multiple state properties into a single pipeline can cause explosive redundant work. Debouncing and duplicate removal are essential for search inputs. Furthermore, coupling simple state persistence (strings) with complex state persistence (JSON) in a single method creates unnecessary encoding overhead.
**Action:** Always debounce search inputs and use granular persistence methods to avoid expensive encoding for simple property changes.

## 2024-06-01 - [Optimization] Adaptive Return Path Heuristic
**Learning:** For a dataset of 50k items, the optimal strategy for returning sorted results depends on the result set size. For small results (M < 1000), fetching from a dictionary and sorting is faster due to the overhead of iterating over a 50k item array. For larger sets, iterating over the pre-sorted master list remains faster as it avoids the $O(M \log M)$ sort cost.
**Action:** Implement a heuristic threshold (e.g., 1000 items) to switch between dictionary-lookup + sort and pre-sorted filtering.

## 2024-06-01 - [Optimization] Task Management in ViewModels
**Learning:** High-frequency UI updates (like typing in a search bar) can trigger multiple concurrent async operations. Without explicit Task cancellation, older results can arrive after newer ones, causing flickering and redundant processing. Storing a reference to the active `Task` and calling `cancel()` before starting a new one is essential for UI stability and performance.
**Action:** Manage async work with a private `Task` property in ViewModels and use `Task.isCancelled` checks.
