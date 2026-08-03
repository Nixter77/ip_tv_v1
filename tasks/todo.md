# Task: Clean Architecture refactor

- [x] Domain: pure entities (no Decodable) + ports (Playlist, UserLibrary, StreamPlayer)
- [x] Application: CatalogLoadPolicy + LoadCatalogUseCase + CatalogErrorMapper
- [x] Data: PlaylistDTOs, IPTVRepository → PlaylistRepository, SwiftDataUserLibraryRepository
- [x] Presentation: thin AppViewModel, AppCommandCenter (typed commands)
- [x] Composition root in IPTVApp
- [x] `swift test` — 30/30 (baseline); 48/48 after SRE resilience work

## Architecture after
```
App (composition) → Presentation (VM/Views)
                 → Application (use cases)
                 → Domain (entities, ports, FilterEngine)
                 ← Data / Playback adapters implement ports
```

Note: single SPM target (folder-level boundaries; multi-target optional follow-up).

---

# SRE Error-Handling & Resilience Review

**Date:** 2026-08-04  
**Scope:** Production call paths — fetch/cache/decode, LoadCatalogUseCase, AppViewModel load/reload/library, PlayerStateManager, composition root, ChannelLogoView.  
**Method:** Checklist from objective (uncaught exceptions, null safety, boundaries, network resilience, graceful degradation, error messages, idempotency, resource cleanup).  
**Status:** All 🔴 and 🟡 findings fixed in shipped code; 🟢 documented optional. `swift test` 48/48.

## Summary of shipped fixes

| # | Risk | Area | Fix |
|---|------|------|-----|
| F1 | 🔴 | `PlayerStateManager.preferredBitrate` | Clamp non-finite values to 0 (NaN/Inf no longer infinite didSet) |
| F2 | 🟡 | `IPTVRepository` cache write order | Decode-before-save so corrupt HTTP 200 cannot poison good cache |
| F3 | 🟡 | `IPTVRepository.dataWithRetry` | Never retry `CancellationError`; `Task.checkCancellation` per attempt |
| F4 | 🟡 | `LoadCatalogUseCase` meta soft-fail | Rethrow `CancellationError` instead of soft-fallback |
| F5 | 🟡 | `AppViewModel.loadData` | Ignore cancellation as user error; serialize loads via cancellable `loadTask` |
| F6 | 🟡 | `AppViewModel.persistFavorite` | Rollback optimistic `favoriteIds` on persist failure |

Tests: `Tests/ResilienceTests.swift` drives real `CatalogErrorMapper`, `IPTVRepository`, `LoadCatalogUseCase`, `PlayerStateManager`, `AppViewModel` + failing library stub.

---

## 1. Uncaught Exceptions

### F1 — preferredBitrate NaN/Inf infinite didSet (FIXED)
- **Risk Level**: 🔴 Production Crash
- **Failure Scenario**: UI slider / binding sets `preferredBitrate = .nan` (or `.infinity`). `max(0, nan)` is `nan`; `nan != nan` is true → recursive didSet → stack overflow at 3 AM when a control glitches.
- **Current Behavior (before)**: Unbounded recursion → process crash.
- **Expected Behavior**: Non-finite values clamp to `0` (auto bitrate); finite negatives clamp to `0`.
- **Fix**:
```swift
let clamped: Double
if preferredBitrate.isFinite {
    clamped = max(0, preferredBitrate)
} else {
    clamped = 0
}
```
- **Status**: ✅ Fixed in `PlayerStateManager.swift`; covered by `test_preferredBitrate_nanDoesNotCrash`.

### Finding — generic catch blocks that are intentional
- **Risk Level**: 🟢 Minor
- **Failure Scenario**: Meta endpoints fail; soft-fail catches any non-cancellation error.
- **Current Behavior**: Soft-fail with `metaWarnings` (correct product behavior).
- **Expected Behavior**: Same; cancellation must not soft-fail (see F4).
- **Fix**: already correct for non-cancel errors; F4 adds cancel rethrow.

### Finding — IPTVApp SwiftData init
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: ModelContainer fails on disk corruption.
- **Current Behavior**: Catch → in-memory library + user banner.
- **Expected Behavior**: App still launches without favorites persistence.
- **Fix**: already correct in `IPTVApp.swift`.

---

## 2. Null / Undefined Safety

### Finding — optional DTO fields
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: JSON missing `languages` / `categories` / `logo`.
- **Current Behavior**: Defaults to `[]` / `nil` via DTO `toDomain()`.
- **Expected Behavior**: No crash; empty filters.
- **Fix**: already correct (`PlaylistDTOs.swift`).

### Finding — SafeDecodable skips bad array elements
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: One bad stream object in large array.
- **Current Behavior**: Item skipped; rest decode; high skip ratio logged in DEBUG.
- **Expected Behavior**: Partial catalog, not total failure.
- **Fix**: already correct.

### Finding — stream URL nil
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Empty or non-http URL string.
- **Current Behavior**: `handleStreamFailure` → next stream / failed state.
- **Expected Behavior**: No AVPlayer crash on nil URL.
- **Fix**: already correct.

---

## 3. Boundary Conditions

### Finding — empty streams list
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Channel has zero active streams.
- **Current Behavior**: `.failed(..., "Нет доступных потоков")`.
- **Expected Behavior**: User-visible failure, not hang.
- **Fix**: already correct; test `test_emptyStreams_failsWithUserSafeMessage`.

### Finding — empty large payload treated as anomaly
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: HTTP 200 with `[]` padded to >256 bytes for channels/streams.
- **Current Behavior**: `PlaylistFetchError.emptyPayload`.
- **Expected Behavior**: Typed error, not silent empty UI.
- **Fix**: already correct; test `test_emptyLargePayload_throwsEmptyPayload`.

### Finding — negative preferredBitrate
- **Risk Level**: 🟢 Minor
- **Failure Scenario**: Caller sets `-1`.
- **Current Behavior**: Clamped to `0` (with F1 finite check).
- **Expected Behavior**: Non-negative peak bitrate.
- **Fix**: covered by F1 clamp.

### Finding — history length > 50
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: User watches >50 channels.
- **Current Behavior**: `removeLast` trims to 50.
- **Expected Behavior**: Bounded memory.
- **Fix**: already correct.

---

## 4. Network Resilience

### Finding — timeouts configured
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Hang on dead host.
- **Current Behavior**: Session request 30s / resource 120s; per-request 30s; player stream timeout default 8s + stall 12s.
- **Expected Behavior**: Bounded wait.
- **Fix**: already correct (`makeDefaultSession`, `PlayerStateManager`).

### Finding — retry with exponential backoff
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Transient 503 / timeout.
- **Current Behavior**: Up to `maxAttempts` (3) with backoff 0.2s→2s + jitter; retriable HTTP 408/429/5xx and selected URLError codes.
- **Expected Behavior**: Transient blips recover without user action.
- **Fix**: already correct.

### F3 — CancellationError was retried (FIXED)
- **Risk Level**: 🟡 Silent Failure (wasted work / delayed cancel; wrong error surfaces)
- **Failure Scenario**: User triggers reload while previous fetch in flight; task cancelled; generic `catch` treated cancel as retriable → up to N more attempts.
- **Current Behavior (before)**: Cancellation retried; cancel may surface as load error.
- **Expected Behavior**: Cancel propagates immediately; no retry.
- **Fix**:
```swift
try Task.checkCancellation()
// ...
} catch is CancellationError {
    throw CancellationError()
}
```
- **Status**: ✅ Fixed in `IPTVRepository.dataWithRetry` and outer fetch catch.

### Finding — no full circuit breaker
- **Risk Level**: 🟢 Minor
- **Failure Scenario**: API down for hours; every reload still hammers with 3 attempts.
- **Current Behavior**: Per-call retry only; soft reload cooldown 5s.
- **Expected Behavior**: Acceptable for desktop client; full CB out of scope (Non-goals).
- **Fix**: deferred (Non-goals); cooldown + backoff sufficient.

---

## 5. Graceful Degradation

### Finding — stale cache on network fail
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Offline after earlier successful cache.
- **Current Behavior**: Serve stale JSON after network/HTTP failure.
- **Expected Behavior**: App usable offline with last catalog.
- **Fix**: already correct; test `test_networkFailure_fallsBackToStaleCache`.

### F2 — corrupt 200 poisoned good cache (FIXED)
- **Risk Level**: 🟡 Silent Failure
- **Failure Scenario**: CDN returns HTTP 200 with garbage body; code saved body then decoded; on decode fail outer catch re-read the just-written garbage and wiped remaining good cache path / lost prior good snapshot for subsequent recovery.
- **Current Behavior (before)**: `cache.save` before `decodeArray` on 200 and 304-refetch paths.
- **Expected Behavior**: Only validated payloads written to disk; prior good cache remains for stale fallback.
- **Fix**: Decode first, then `cache.save`.
- **Status**: ✅ Fixed; test `test_corruptNetworkBody_doesNotPoisonGoodDiskCache`.

### Finding — meta soft-fail
- **Risk Level**: 🟢 Minor (already correct + F4)
- **Failure Scenario**: categories/countries/languages endpoint down; channels+streams OK.
- **Current Behavior**: Fallback lists + banner warning.
- **Expected Behavior**: Catalog still loads.
- **Fix**: already correct; test `test_metaSoftFail_usesFallbackAndWarnings`.

### Finding — background revalidate errors swallowed
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: SWR revalidate fails after cache-first ready.
- **Current Behavior**: Keep current catalog silently.
- **Expected Behavior**: No error flash for background work.
- **Fix**: already correct.

### Finding — SwiftData unavailable
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Container init fails.
- **Current Behavior**: `InMemoryUserLibraryRepository` + banner.
- **Expected Behavior**: Session continues without durable library.
- **Fix**: already correct.

### Finding — logo fetch fails
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Logo CDN down.
- **Current Behavior**: Placeholder gradient; catch empty.
- **Expected Behavior**: List still usable.
- **Fix**: already correct (`ChannelLogoView`).

---

## 6. Error Messages

### Finding — typed PlaylistFetchError.userMessage
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: HTTP 429/5xx/decode failures.
- **Current Behavior**: Short Russian user strings; no stack traces; endpoint details only in `errorDescription` / DEBUG.
- **Expected Behavior**: Safe UI copy.
- **Fix**: already correct; tests in `CatalogErrorMapperTests`.

### Finding — CatalogErrorMapper masks URLs
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Underlying error embeds stream URL with token.
- **Current Behavior**: `Stream.maskURLs` before display.
- **Expected Behavior**: No credentials/tokens in UI.
- **Fix**: already correct; `test_userMessage_masksEmbeddedStreamURL`.

### Finding — player failure strings masked
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: AVPlayer error includes URL.
- **Current Behavior**: `Stream.maskURLs(in: rawError)`.
- **Expected Behavior**: HUD shows sanitized text.
- **Fix**: already correct.

### F5 — cancellation painted as load error (FIXED)
- **Risk Level**: 🟡 Silent Failure (misleading UX / false error state)
- **Failure Scenario**: Concurrent `loadData` cancels prior task; prior catch maps error to `.error("…")` or banner.
- **Current Behavior (before)**: Cancellation → user-facing load error.
- **Expected Behavior**: Cancel is silent; superseding load owns UI.
- **Fix**: `catch is CancellationError` no-ops; `loadTask` cancels prior work including revalidate.
- **Status**: ✅ Fixed in `AppViewModel`.

---

## 7. Idempotency

### Finding — playlist GET retries
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Retry after 503.
- **Current Behavior**: Idempotent GET; safe.
- **Expected Behavior**: No duplicate side effects.
- **Fix**: already correct.

### Finding — setFavorite / recordView
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Double-tap favorite or replay channel.
- **Current Behavior**: Upsert by unique id; history reorders.
- **Expected Behavior**: Idempotent durable state.
- **Fix**: already correct.

### F6 — optimistic favorite without rollback (FIXED)
- **Risk Level**: 🟡 Silent Failure
- **Failure Scenario**: Disk full / SwiftData save throws after UI star toggled.
- **Current Behavior (before)**: Banner shown but `favoriteIds` kept wrong until restart.
- **Expected Behavior**: UI rolls back to last durable state; banner explains failure.
- **Fix**:
```swift
} catch {
    if isFavorite { self.favoriteIds.remove(id) }
    else { self.favoriteIds.insert(id) }
    self.statusBanner = "Не удалось сохранить избранное"
}
```
- **Status**: ✅ Fixed; test `test_favoritePersistFailure_rollsBackOptimisticUI`.

### Finding — history persist failure keeps session order
- **Risk Level**: 🟢 Minor (accepted)
- **Failure Scenario**: `recordView` throws after in-memory reorder.
- **Current Behavior**: Banner; session history kept (play already happened).
- **Expected Behavior**: User still sees session history; warned about persistence.
- **Fix**: intentional; test `test_historyPersistFailure_surfacesBanner`.

---

## 8. Resource Cleanup

### Finding — player timers/observations
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Channel zap / stop / deinit.
- **Current Behavior**: `resetCurrentPlayback` cancels timeout/stall tasks, invalidates KVO, clears item; deinit hops to main for cleanup.
- **Expected Behavior**: No orphan observers / zombie timers firing into freed self (`[weak self]`).
- **Fix**: already correct.

### Finding — filter / revalidate / load tasks
- **Risk Level**: 🟢 Minor (improved by F5)
- **Failure Scenario**: Rapid search + reload.
- **Current Behavior**: Prior filter/revalidate/load tasks cancelled.
- **Expected Behavior**: No race overwrite of published state.
- **Fix**: load serialization added in F5.

### Finding — URLSession
- **Risk Level**: 🟢 Minor (already correct)
- **Failure Scenario**: Repository lifetime ends mid-fetch.
- **Current Behavior**: Injected session; cancellation via Task; disk writes atomic.
- **Expected Behavior**: No leaked handles in app process model.
- **Fix**: already correct.

---

## Checklist coverage matrix

| Checklist item | Covered by findings |
|----------------|---------------------|
| 1. Uncaught exceptions | F1, intentional soft-fail, SwiftData fallback |
| 2. Null/undefined safety | DTO optionals, SafeDecodable, nil stream URL |
| 3. Boundary conditions | empty streams, empty large payload, bitrate clamp, history cap |
| 4. Network resilience | timeouts, retry+backoff, F3 cancel, no full CB (deferred) |
| 5. Graceful degradation | stale cache, F2 decode-before-save, meta soft-fail, logos, persistence fallback |
| 6. Error messages | userMessage, URL mask, F5 cancel silence |
| 7. Idempotency | GET retry, library upsert, F6 favorite rollback |
| 8. Resource cleanup | player reset/deinit, task cancellation |

## Open 🔴 count: 0  
## Open 🟡 count: 0  

## Deferred (Non-goals)
- Full circuit-breaker framework — not required; per-request retry + 5s reload cooldown + stale cache cover desktop client failure modes.
- Multi-source failover UI / offline product mode.
- Exhaustive DTO fuzzing beyond crash/silent-wrong paths.

## Verification
- `swift test` → **48 tests, 0 failures** (includes `ResilienceTests.swift`).
- Production files touched: `IPTVRepository.swift`, `LoadCatalogUseCase.swift`, `PlayerStateManager.swift`, `AppViewModel.swift`.
- Review artifact: this section in `tasks/todo.md`.
