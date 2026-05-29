# Bolt's Journal

## 2025-05-14 - Initial Assessment
**Learning:** The project is a macOS app using Swift and SwiftUI. The development environment is Linux, so direct execution/testing of Swift code is not possible. I must rely on static analysis and my knowledge of Swift/SwiftUI performance patterns.
**Action:** Focus on optimizations that are demonstrably beneficial based on Swift performance best practices.

## 2025-05-15 - [Optimization] Pre-sorted Result Filtering
**Learning:** In scenarios with large datasets (e.g., 50k items) that need to be returned in a specific order (e.g., by name), it is significantly faster to maintain a single pre-sorted master list and filter it by matching IDs ($O(N)$) rather than collecting matches and then sorting them ($O(M \log M)$). This is especially true when the result set ($M$) is large.
**Action:** Use `preSortedArray.filter { resultSet.contains($0.id) }` for sorted output in high-performance lookup engines.
