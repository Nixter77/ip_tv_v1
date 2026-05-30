# Code Review and Fix Plan

## Scope
Perform a full local code review of the Swift IPTV app, identify concrete correctness/security/build-quality issues, fix the highest-impact problems with minimal code changes, and verify with tests.

## Checklist
- [x] Inspect package structure, existing task notes, and current git state.
- [x] Run the existing test suite to establish a baseline.
- [x] Review domain/data/presentation code for correctness, security, concurrency, persistence, and test gaps.
- [x] Implement focused fixes for verified issues only.
- [x] Run formatting/build/tests or the closest available verification commands.
- [x] Review the final diff for elegance/minimality and document results.
- [x] Commit changes and open a PR.

## Review Results
- Baseline `swift test` failed before tests could run because Linux Swift lacks Apple-only modules such as SwiftData, SwiftUI, Combine, AVFoundation, and AVKit.
- The package always declared the graphical executable target, so non-macOS builds attempted to link an empty conditionally compiled app target and failed.
- Several source and test files imported Apple-only modules unconditionally; guarded those files so portable domain/repository/security tests can run in this environment without changing macOS behavior.
- `IPTVRepository` and repository tests needed `FoundationNetworking` on Linux for URLSession, URLProtocol, URLResponse, and HTTPURLResponse.
- `Stream.maskURLs(in:)` used `NSDataDetector`, which is unavailable in Linux Foundation; replaced it with a portable regex-based URL scanner.
- `Stream.mask(_:)` treated non-URL text as a path and percent-escaped it, which leaked into UI/tests as `invalid%20url`; it now only URL-masks strings with an actual scheme.
- Some provider/error URLs carry token-looking `key=value` data in path segments instead of query parameters; those values are now masked as well.
- `AppViewModel.loadData()` used `Task.detached` while capturing the main-actor view model; replaced it with direct `async let` fetches, preserving concurrency without leaving actor isolation unnecessarily.
- Verification after fixes: `swift test` passes 17 portable tests in this Linux environment; Apple-framework tests remain available behind import guards on macOS.
