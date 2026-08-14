# Code Review 2/3 — IPTVPlayer (macOS)

**Stack:** Swift 5.9 SPM, SwiftUI + AppKit, AVFoundation, SwiftData. Folder-level Clean Architecture.

**Scope:** Review **and fix** remaining OWASP / performance / SOLID issues from fire 1. `swift test --disable-swift-testing` → **61 tests, 0 failures**.

---

## 1. Executive Summary

Fire 1 treated the iptv-org catalog as untrusted input and listed four critical holes: logo SSRF/DoS, a shared `JSONDecoder`, unbounded playlist bodies, and ETag header replay. Those are closed in shipped code, with tests.

A single `RemoteURLPolicy` now owns scheme / host / header rules. Logos and Referer go through `.remoteAsset` (public http(s), no userinfo, no RFC1918/loopback, including dword `2130706433` and `127.1`). Playback stays `.mediaStream` so LAN IPTV still works. `SafeHTTPClient` cancels oversize logo bodies and refuses redirects onto restricted hosts. Playlist decode uses a **per-call** `JSONDecoder` off the MainActor, and cache validators are stripped of CTL before persist and before `If-None-Match`.

| Severity | Remaining | Theme |
|---|---|---|
| Critical | 1 | Playlist `URLSession.data` still materializes the full body *before* the 64 MB check |
| High | 2 | `@Published` still holds the entire catalog; AVFoundation still lives in Domain |
| Medium | 2 | Playlist Content-Type not checked; DNS-rebinding TOCTOU on logo hostnames |

---

## 2. Remaining Critical Issues

### C5 — Playlist fetch downloads first, then checks size (OWASP A04)

`IPTVRepository.dataWithRetry` still uses `session.data(for:)`. `rejectIfTooLarge` runs **after** Foundation has the entire body in `Data`. A hijacked CDN or MITM that returns `Content-Length: 2GB` (or streams without a length) can still OOM the process. Logos already abort incrementally in `SafeHTTPClient.didReceive`.

**Fire 3:** reuse `SafeHTTPClient` (or a byte-capped delegate) for playlist endpoints; fail on `expectedContentLength > maxResponseBytes` before appending.

### H2 (still open) — full catalog published into `@Published filteredChannels`

The list now windows 400 rows and grows on “Загрузить ещё…”. That stops 20k `ChannelLogoView.task`s from being created at once. `AppViewModel` still assigns the complete `[Channel]` on the main actor, so empty-search “All channels” can hitch. Do not rewrite `FilterEngine` without Instruments numbers; consider publishing a slice from the VM if traces show the copy as the hotspot.

### Q1 (still open) — `PlayerStateManager` in Domain

Still imports AVFoundation. Port (`StreamPlayer`) is already in `Domain/Ports`. Move the adapter to `Sources/Data/Playback/` in fire 3.

---

## 3. Code Quality Notes

**What is now DRY (keep it that way)**

- `RemoteURLPolicy.validatedURL(from:kind:)` is the only scheme/host gate. `Channel.safeLogoURL`, `Stream.url`, Referer, and `SafeHTTPClient` redirects all call it.
- `sanitizedHTTPHeaderValue` is used for ETag / Last-Modified (save + request) and Referer.
- `PlaylistDiskCache.save` sanitizes validators so a poisoned on-disk `.meta.json` from an older build is dropped on the next write.

**Still messy**

- `AppViewModel` still owns UserDefaults, library rollback, catalog load serialization, and filter mapping. Fine as a facade; next feature should not grow it.
- `SafeHTTPClient` is a hand-rolled `URLSessionDataDelegate` with an `NSLock` map of continuations. Correct for the tests we have; a future leak of `finish` vs `.cancelled` will double-resume. Keep the tests.
- HUD no longer uses `Coordinator.shared`. Each `autoHideHUD` owns a window-filtered local monitor and uses `WindowAccessor` (duplicate `HostingWindowAccessor` removed).

**Do not “improve” away**

- `SafeDecodable` + decode-before-`cache.save`
- `CancellationError` never retried / never painted as a load error
- Stream URL masking in HUD / `CatalogErrorMapper`
- FilterEngine inverted index + adaptive materialize

---

## 4. What this fire fixed

| ID | Change |
|---|---|
| C1 | `RemoteURLPolicy` + `Channel.safeLogoURL`; `SafeHTTPClient` size/redirect guard; DNS fail-closed before network (cache hit skips DNS); logo cache only after ImageIO downsample |
| C2 | Per-call `JSONDecoder` (no shared instance) |
| C3 | `PlaylistFetchError.payloadTooLarge`; injectable `maxResponseBytes` (default 64 MB) |
| C4 | CTL-stripped ETag / Last-Modified on disk and on `If-None-Match` / `If-Modified-Since` |
| H1 | Cache I/O + JSON decode via `Task.detached` so Swift 5.9 does not decode 50k rows on MainActor |
| H2 (partial) | Channel list windows 400 rows |
| Q2 | One URL/header policy type |
| Q4 | Per-window HUD mouse monitor |
| Bounds | Search query cap (200); persisted id/name cap (128/200); URLCache 16/48 MB |

**Tests added/extended:** logo SSRF matrix, decimal/abbrev loopback, SafeHTTPClient block/oversize, playlist oversize, ETag drop vs forward, header CTL, search/id truncation.

**Verification:** `swift test --disable-swift-testing` → 61 passed, 0 failed.

---

## Notes for fire 3

1. Cap playlist download *while* reading (C5).
2. Move `PlayerStateManager` out of Domain (Q1).
3. Optional: reject `text/html` playlist Content-Type (captive portal) without caching.
4. Measure H2 with a 50k fixture before changing FilterEngine.
