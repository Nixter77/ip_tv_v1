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

## 2025-05-31 - [Optimization] Subset Pruning & Tail-scan Optimization
**Learning:** For Actor-based filtering, passing a restricted set of IDs (`matchingIds`) as the initial search space (Subset Pruning) significantly reduces intersection overhead. Additionally, a "tail-scan" heuristic that switches between $O(M \log M)$ sorting for small result sets (< 1000 items) and $O(N)$ master-list scanning for large ones ensures optimal performance across all query types.
**Action:** Implement `matchingIds` in filter methods and use result-count thresholds to select the most efficient sorting/filtering strategy at the end of the pipeline.
