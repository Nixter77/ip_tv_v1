# Code Review 4 — IPTVPlayer (macOS)

**Reviewed tree:** `3b040bd087e6fec082b037f9d685f814ffee8904` (`main`, same as `origin/main`).
**Stack:** Swift 6.0 SPM, `.swiftLanguageMode(.v6)`, SwiftUI + AppKit, AVFoundation, SwiftData. One library target `IPTVPlayer`.
**Scope:** Read-only pass over the current workspace. No `Sources/` or `Tests/` edits. Nothing committed or pushed.

Review 3's C5 is re-judged from the streaming client that ships now. It is closed. The non-canonical forms in review 3's C6 table are closed too. A different numeric-literal bypass is open, and four behavior bugs from the playback UI are open. Deferred work (phase 4 F1–F11, phase 5, the 400-row window, the DNS-rebinding pin, copy-stream-URL, a `RemoteURLPolicy` API rewrite, the multi-target split, app icon, About, grid mode) is not filed only because it is absent.

---

## 1. Executive summary

Phases 0–3 at `3b040bd` hold. Playlist bytes are capped while they arrive. HTML is rejected before a catalog cache write. `tooLarge` and cancellation are not retried. Decode runs before `cache.save`. Current and legacy iptv-org fixtures map. Category filters use the category id. NSFW and non-null `closed` stay hidden until enabled. The HUD glyph reads published `isPaused`. Favorite names come from the full catalog. Channel order uses `localizedStandardCompare`. Reselect retries. Fullscreen targets the surface window, not `NSApp.keyWindow`. Catalog, library, and playback publish separately, and playback time ticks do not invalidate the channel list. Presentation files stay at or under 250 lines. `swift test`, `swift build --product IPTVPlayerApp`, and `DESIGN.md` lint were re-run for this review and passed.

Six issues are open. One is a residual SSRF: hex and octal dword literals that `inet_pton` rejects are still treated as public hosts, and `SafeHTTPClient` will follow a redirect onto them. Four are behavior bugs: the process-global cursor hide, an Escape monitor that ignores which window received the key, a first click that can start playback twice, and a time-control callback that can publish a stale pause bit. One is low: a cancelled catalog setup still indexes every stream.

| Severity | Count | Theme |
|---|---|---|
| High | 1 | Numeric literals that `getaddrinfo` maps to loopback pass `isRestrictedHost`; redirects follow them |
| Medium | 4 | Process-global `NSCursor.hide`; Escape is not scoped to the event window; first click can `play` twice; stale time-control hop |
| Low | 1 | Cancelled catalog setup still indexes every stream |

---

## 2. Open findings

### F1 — Hex and octal dword literals bypass `isRestrictedHost`, and redirects follow them

**Severity:** High
**File:** `Sources/Domain/RemoteURLPolicy.swift` (`isRestrictedHost`, `parseIPv4`), `Sources/Data/SafeHTTPClient.swift` (`willPerformHTTPRedirection`)
**Behavior:** `isRestrictedHost` returns false when both `inet_pton` and `parseIPv4` reject the host. `shouldFollowRedirect` is only `validatedURL != nil`, and `willPerformHTTPRedirection` follows that URL. The hosts below are in that gap, and `getaddrinfo` maps each of them to `127.0.0.1`, so a playlist or logo redirect to one of them is fetched.

Review 3's C6 strings (`::0:1`, `::ffff:7f00:1`, `127.000.000.001`, and the rest of that table) are now blocked by `inet_pton` and covered by `test_channel_safeLogoURL_blocksSSRFTargets`. This is a different hole.

`isRestrictedHost` accepts an address only when `inet_pton` or the decimal `parseIPv4` parser recognizes it. On this Mac, `URL(string:)` keeps the following hosts, `inet_pton` returns 0 for them, and `parseIPv4` returns nil (hex tokens are not decimal; `UInt32("017700000001")` does not fit). `isRestrictedHost` therefore returns false, and `validatedURL` / `shouldFollowRedirect` allow them:

| Host | `getaddrinfo(AI_NUMERICHOST)` |
|---|---|
| `0x7f.0.0.1` | `127.0.0.1` |
| `0x7f.0.0.0x1` | `127.0.0.1` |
| `0x7f.1` | `127.0.0.1` |
| `127.0.0.0x1` | `127.0.0.1` |
| `0x7f000001` | `127.0.0.1` |
| `017700000001` | `127.0.0.1` |

`connect("0x7f.0.0.1", port 1)` returns `ECONNREFUSED` (errno 61), the same result as `connect("127.0.0.1", port 1)`. The address is loopback, not an unroutable name.

`SafeHTTPClient` follows a redirect when `shouldFollowRedirect` is true. That function is only `validatedURL != nil`. It does not call `resolvesOnlyToPublicAddresses`. Playlist fetch uses this client with `kind: .remoteAsset` (`IPTVRepository.dataWithRetry`). A redirect from `iptv-org` (or from a logo CDN whose name already passed the DNS check) to `http://0x7f.0.0.1/...` is fetched.

A direct logo URL in that form is in better shape. `isLiteralIPAddress` is false for these hosts, so `ChannelLogoView` still runs the DNS fail-closed check, and a `getaddrinfo` result of `127.0.0.1` is rejected by `isRestrictedSockaddr`. The bug is the redirect path, which never takes that check.

`::ffff:0:127.0.0.1` is also not classified as IPv4-mapped (the `ff` bytes sit at positions 8–9, and the mapped-address check looks at bytes 10–11). A connect to port 1 on that name timed out (errno 60) instead of refusing, so this review does not claim it reaches loopback.

### F2 — Escape leaves fullscreen even when the key belongs to another window

**Severity:** Medium
**File:** `Sources/Presentation/PlayerSurface.swift` (`FullscreenEscapeModifier.install`)
**Behavior:** The local `.keyDown` monitor toggles `window` on key code 53 whenever that window's style mask contains `.fullScreen`. The handler never compares `event.window` with `window`, so Escape delivered to another window exits this surface's fullscreen.

Each `PlayerSurface` installs its own monitor. While the detached player is fullscreen, Escape typed in the main window is swallowed and exits the detached fullscreen. The button path (`hostWindow?.toggleFullScreen(nil)`) and this monitor both target the surface window. `NSApp.keyWindow` is not used. The event is still not tied to the window that received it.

### F3 — The click that selects a row can start playback twice

**Severity:** Medium
**File:** `Sources/Presentation/ChannelListColumn.swift` (row `TapGesture`), `Sources/Presentation/MainSplitView.swift` (`onChange(of: selectedChannel)`), `Sources/Presentation/AppViewModel.swift` (`selectChannel`)
**Behavior:** One row click has two `selectChannel` call sites on the same `selectedChannel` binding. `List(selection: $selectedChannel)` writes that binding. `MainSplitView.onChange(of: selectedChannel)` calls `selectChannel` for every non-nil change. The row `TapGesture` also calls `selectChannel` when `selectedChannel?.id == channel.id`. `selectChannel` calls `playback.retry()` when `playback.currentChannelID == channel.id`, and otherwise `play`. `PlaybackController.retry` calls `PlayerStateManager.retry`, which calls `play` and reaches `avPlayer.replaceCurrentItem(with:)`. A call that observes a matching `currentChannelID` starts another playback attempt for the channel the selection binding already names.

### F4 — A queued time-control status can publish the wrong `isPaused`

**Severity:** Medium
**File:** `Sources/Data/Playback/AVStreamPlayer.swift` (`setupTimeControlObservation`, `handleTimeControlStatus`, `playCurrentStream`)
**Behavior:** `playCurrentStream` installs the time-control observer with `[.new, .initial]` before `avPlayer.play()`, while the player is still paused, then sets `isPaused = false`. The observer copies `timeControlStatus` and applies it later in `Task { @MainActor }`. `handleTimeControlStatus` assigns `isPaused = true` for `.paused` and has no item or generation token. A `.paused` sample taken before `play()` can land after `isPaused = false`, so the HUD shows the play glyph for a stream that was just started. `handleItemStatus` drops events whose `ObjectIdentifier` is stale. A callback already queued from the previous item can also set `isPaused` after `stop()` or the next `play()`.

The glyph reads `player.isPaused`. It does not read `AVPlayer.rate`. The published bit is what goes stale.

### F5 — `NSCursor.hide()` is still process-global

**Severity:** Medium
**File:** `Sources/Presentation/HUDAutoHide.swift` (`scheduleHide`, `HUDWindowMouseMonitor.attach`)
**Behavior:** `scheduleHide` calls process-global `NSCursor.hide()`. The local monitor handles `mouseMoved`, `mouseEntered`, and mouse-down only when `event.window == tracked`. It has no `mouseExited` and no resign-key handler, so motion in the channel list, the search field, or another window does not unhide. `onDisappear` unhides, and that does not run when the pointer only leaves the video surface. The cursor stays hidden for the rest of the app until the pointer re-enters that window.

### F6 — A cancelled catalog setup still indexes every stream

**Severity:** Low
**File:** `Sources/Domain/FilterEngine.swift` (`setup`)
**Behavior:** The stream loop that fills `newActiveStreams` has no `Task.isCancelled` check, so a cancelled `setup` still indexes every stream. The channel loop checks every 2000 rows and returns before the index swap. `LoadCatalogUseCase` checks cancellation again before the store publishes, so the UI usually keeps the previous list. The CPU cost of the stream pass remains.

---

## 3. Closed / do-not-regress

Verdicts are against the tree at `3b040bd`. "Still holds" means the current code matches the invariant. A reopened row would quote the contradicting code; none of the review 3 closed rows are reopened.

### Review 3, "What is closed"

| ID | Verdict | Where |
|---|---|---|
| C1 (tested cases) | Still holds | `Channel.safeLogoURL` is `validatedURL(kind: .remoteAsset)`. `SafeHTTPClient` caps the body and refuses a restricted redirect. Hostnames still go through `resolvesOnlyToPublicAddresses` in `ChannelLogoView` before the fetch. The image is stored in `URLCache` only after `downsample` returns a thumbnail. The forms in `test_channel_safeLogoURL_blocksSSRFTargets` stay blocked. F1 is a new literal class, not a failure of those cases. |
| C2 | Still holds | `IPTVRepository.decodeArray` constructs `let decoder = JSONDecoder()` per call. No shared decoder. |
| C3 (post-download) | Still holds | `PlaylistFetchError.payloadTooLarge(endpoint:byteCount:)` and `rejectIfTooLarge` remain. `maxResponseBytes` is still injectable and defaults to `RemoteURLPolicy.maxPlaylistBytes` (64 MB). This check is defense in depth after the streaming cap. It does not replace C5, and C5 is now closed separately. |
| C4 | Still holds | `IPTVRepository` sets `If-None-Match` and `If-Modified-Since` from `sanitizedHTTPHeaderValue` (lines 440–444). `PlaylistDiskCache.save` sanitizes the same two fields again (lines 158–159). Playlist conditional headers are those two fields. Playback `Referer` is `PlaybackRequestHeaders` in `AVStreamPlayer.swift` (lines 12–14): `sanitizedHTTPHeaderValue`, then `validatedURL(kind: .remoteAsset)`. `StreamDTO` sanitizes the referrer at decode (`PlaylistDTOs.swift` line 85). |
| H1 | Still holds | `loadCacheSnapshot` and `decodeArrayOffMain` hop through `Task.detached`. |
| H2 (partial) | Still holds | `ChannelListColumn` windows `Layout.listPage` (400) and appends «Загрузить ещё…». The full filtered array is still what the store publishes. That remainder is the deferred window, not a new defect. |
| Q2 | Still holds | Streams, logos, Referer, and redirects still enter through `RemoteURLPolicy`. F1 is a hole inside `isRestrictedHost`, not a second policy type. |
| Q4 | Still holds | `HUDWindowMouseMonitor` is one object per HUD modifier. There is no `Coordinator.shared`. F5 is the cursor API, not a shared monitor. |
| Bounds | Still holds | Search is cut to `maxSearchQueryLength` (200) in `CatalogStore` (lines 115–116). SwiftData `sanitizeID` / `sanitizeName` cut to `maxPersistedIDLength` (128) and `maxPersistedNameLength` (200). `App/IPTVApp.swift` sets `URLCache` to 16 MB / 48 MB. History trim uses `LibraryPolicy.historyLimit` (50) inside `LibraryStore.recordView` (lines 45–51) and inside `SwiftDataUserLibraryRepository.recordView`, which calls `pruneHistory()`. |

**Do not regress, still holds**

- `SafeDecodable` is the fallback in `decodeArray`. `cache.save` runs only after `decodeArrayOffMain` returns, on the 200 path and on the 304 refresh path.
- `dataWithRetry` rethrows `CancellationError` and maps `URLError.cancelled` to `CancellationError` with no further attempt. `CatalogStore.performLoad` and `backgroundRevalidate` catch `CancellationError` and do not set `loadingState` to `.error` or a status banner. `CatalogErrorMapper` still has a cancel string, and the load path does not use it.
- `AppLog.safe` is `Stream.maskURLs`. Playback failures log `AppLog.safe`. This pass did not find a log site that interpolates a raw stream URL.
- `ChannelFilterEngine.setup` still builds the token index, `sortedTokens` / `tokenSets`, and the adaptive `materialize` split.
- `RemoteURLPolicy`'s existing public surface (`validatedURL(from:kind:)`, `sanitizedHTTPHeaderValue`, `shouldFollowRedirect`, the byte and length constants) is intact. `sanitizedUserAgent` was added beside it.
- H3 still holds. `Stream.url` is `validatedURL(kind: .mediaStream)`, so LAN and `http` remain allowed for playback. There is no copy-stream-URL control.

### Phase 0–3 claims from `3b040bd`

| Claim | Verdict | Where |
|---|---|---|
| Byte cap during transfer when Content-Length is missing or smaller than the body | Still holds. C5 is closed. | `SafeHTTPClient.urlSession(_:dataTask:didReceive:)` cancels when `expectedContentLength > maxBytes` before `.allow`. `didReceive data` adds `buffer.count + data.count` and, when that exceeds `maxBytes`, drops the buffer, cancels, and finishes `.tooLarge(bytesSeen:)`. A missing length is `expectedContentLength <= 0`, so only the running count applies. A length under the cap does not disable the running count. `IPTVRepository.dataWithRetry` calls `http.data(for:maxBytes:kind:)` with `maxResponseBytes`. |
| HTML rejected before a catalog cache write | Still holds. Review 3 M1 is closed. | `isHTML` runs inside `dataWithRetry` and throws `PlaylistFetchError.unacceptableContent` before the method returns. `fetchAndDecodeSafeArray` saves only after a successful decode of a returned body. An HTML error can still fall through to an already stored cache, the same way other fetch errors do. The HTML body is not written. |
| `tooLarge` and cancellation are not retried | Still holds | `SafeHTTPError.tooLarge` becomes `PlaylistFetchError.payloadTooLarge` and is rethrown. `CancellationError` and `URLError.cancelled` are rethrown. Neither branch sleeps or continues the attempt loop. |
| Decode before cache save | Still holds | 200 and 304-refresh both `decodeArrayOffMain` and only then `cache.save`. |
| Current iptv-org payload and legacy fixtures both map | Still holds | `ChannelDTO` decodes `is_nsfw` as `Bool?`, `closed` as `String?`, and optional `alt_names` / `network` / `replaced_by`, with no inline `logo` or `languages` required. `StreamDTO` prefers `referrer` and falls back to `http_referrer`, and keeps `user_agent`, `quality`, `feed`, and `title`. `toDomain()` drops only an empty channel or url. `CatalogAssembler` uses inline languages when present, otherwise feeds, and an inline logo when it validates, otherwise `logos`. `Tests/CatalogAcceptanceTests.swift` and `Tests/Fixtures/` cover both shapes. This review did not re-fetch the live API. |
| Category filter uses the category id | Still holds | The index key is `category.lowercased()`. `filter` looks up `category.lowercased()`. `CategoryDTO.toDomain()` keeps a non-empty trimmed `id`. Sidebar selection is `SidebarTab.category(category.id)`. An id of `docs` does not match a channel tagged `documentary`. |
| NSFW and non-null `closed` stay hidden until enabled | Still holds | `isListed` drops `isNSFW` unless `includeNSFW`, and drops `closed != nil` unless `includeClosed`. Defaults are false. `publishFilter` calls `setVisibility` from `showNSFW` / `showClosed`. `groupCounts` uses `isListed`, so the sidebar does not list an empty group. |
| HUD pause glyph follows published `isPaused` | Still holds for the read path. F4 is the stale write. | `PlayerSurface` passes `player.isPaused`. `togglePause` switches on `timeControlStatus` and assigns `isPaused`. No view reads `AVPlayer.rate` for the glyph. |
| Favorite toggle stores the catalog name | Still holds | `namesByID` is built from `LoadCatalogResult.channels`, not from the filtered page. `toggleFavorite(channelId:)` uses `catalog.name(for:)`. The «Канал» string remains only when that id is absent from the catalog. |
| Channel order uses `localizedStandardCompare` | Still holds | `ChannelFilterEngine.localizedNameOrder` and the category / country / language sorts in `LoadCatalogUseCase`. |
| Reselecting the playing channel retries | Still holds | `AppViewModel.selectChannel` calls `playback.retry()` when `currentChannelID` matches. `retry()` calls `play`, which replaces the item. F3 is the second `selectChannel` path on that same selection, not a missing retry. |
| Fullscreen uses the surface window | Still holds | `PlayerSurface` calls `hostWindow?.toggleFullScreen(nil)`. The Escape monitor toggles the window passed into `FullscreenEscapeModifier`. `NSApp.keyWindow` does not appear in `Sources/`. F2 is the missing `event.window` check. |
| Catalog, library, and playback are separate | Still holds | `AppViewModel` forwards `objectWillChange` from `CatalogStore`, `LibraryStore`, and `PlaybackController` only. `PlaybackController` does not sink `PlayerStateManager`. Periodic time updates `HUDTimeModel` inside the HUD. A time tick does not publish the channel list. |
| Swift 6 strict concurrency | Still holds | `Package.swift` is `swift-tools-version: 6.0` with `.swiftLanguageMode(.v6)` on `IPTVPlayer`, `IPTVPlayerTests`, and `IPTVPlayerApp`. The fresh build and test logs contain no `warning:` lines. |
| No file under `Sources/Presentation` exceeds 250 lines | Still holds | 26 Swift files, 2129 lines. Largest are `QuickTimeHUDPanel.swift` (223) and `CatalogStore.swift` (219). |
| Tests do not call `Task.sleep` | Still holds | `Task.sleep` in product code is only `ContinuousSuspendingClock`. `Tests/` has none. Debounce and playback waits use `ManualSuspendingClock`. |
| `DESIGN.md` lint is clean and presentation colors and spacing come from tokens | Still holds | Lint summary is `errors: 0`, `warnings: 0`, `infos: 1`. The info is the token census. The log has no WCAG contrast finding. `Sources/Presentation` uses `Spacing`, `Radius`, `Layout`, and `Palette`. `Color(red:)` appears only in `Design/Tokens.swift`. No `scaleEffect`. `@FocusState` for search stays in `ChannelListColumn`. The window uses `.windowToolbarStyle(.unified)` and `.windowStyle(.automatic)`. `VideoPlayerView.hitTest` returns nil over the traffic-light rect. `StatusBannerView` switches icon, tint, and wash on `StatusSeverity` info / warning / error. |
| Logos or feeds failing does not fail the catalog | Still holds | `fetchSupplemental` returns `[]` on a non-cancellation error and rethrows `CancellationError`. |
| Missing stream `status` is kept; explicit `"error"` is not indexed | Still holds | `StreamDTO.toDomain()` keeps a nil status. `setup` skips `stream.status == "error"` only. A channel with no remaining stream is left out of the index. |
| Playback sends sanitized User-Agent and Referer | Still holds | `PlaybackRequestHeaders.httpHeaderFields` sets `Referer` from a sanitized value that also passes `validatedURL(kind: .remoteAsset)`, and `User-Agent` from `sanitizedUserAgent` (control characters stripped, then 512 characters). |
| Domain does not import AVFoundation | Still holds | `import AVFoundation` is in `Sources/Data/Playback/AVStreamPlayer.swift`, two presentation files, and `Tests/PlayerStateManagerTests.swift`. `Sources/Domain` has none. `PlayerStateManager` lives in `Sources/Data/Playback/`. Review 3 Q1 is closed. |

### Re-judged items that were open in review 3

| ID | Verdict |
|---|---|
| C5 | Closed. See the byte-cap row above. The old `URLSession.data(for:)` then `data.count` path is gone. |
| C6 table | Closed for every host in review 3's table. `inet_pton` plus `isRestrictedIPv6Address` covers compressed and mapped IPv6, and the decimal parser still covers `2130706433` and `127.1`. F1 is the residual the table did not list. |
| M1 HTML | Closed. See the HTML row above. |
| Q1 Domain AVFoundation | Closed. See the Domain row above. |
| M2 DNS-rebinding pin | Not re-filed. The check-then-connect gap on hostnames is the deferred pin. F1 is a numeric literal, not that pin. |
| M3 cursor | Reopened as F5. The code still calls `NSCursor.hide()` and ignores events from other windows. |
| M4 setup cancellation | Narrowed, not closed. The channel loop samples cancellation. F6 is the stream loop that still does not. |
| H2 full-array publish | Not re-filed. The 400-row window is the accepted partial mitigation. |

---

## 4. Suggested next patch

This review does not apply the patch.

1. **F1.** Inside `isRestrictedHost`, treat a host as numeric when `getaddrinfo` with `AI_NUMERICHOST` succeeds, and run the existing `isRestrictedIPv4` / `isRestrictedIPv6Address` checks on that sockaddr. That covers `0x7f.0.0.1`, `0x7f000001`, and `017700000001` without a new string table. Call the same check from `shouldFollowRedirect` (it already calls `validatedURL`). Add `SecurityTests` rows for those hosts and for a redirect from `https://cdn.example/logo` to `http://0x7f.0.0.1/`. Do not rename `validatedURL(from:kind:)` or `sanitizedHTTPHeaderValue`. Leave the DNS-rebinding pin for a later change.
2. **F2.** In the Escape monitor, return the event unless `event.window === window`.
3. **F3.** Keep a single `selectChannel` for one click. The tap should run only when the row was selected before that click.
4. **F4.** Stamp a playback generation when the time-control observer is installed, and ignore a hopped status whose generation is no longer current. Set `isPaused = false` in the same turn as `play()`, after any initial `.paused` sample has been discarded.
5. **F5.** Unhide on `mouseExited` and when the window resigns key. Hide only while the pointer is over the video surface.
6. **F6.** Sample `Task.isCancelled` in the stream loop on the same stride as the channel loop.

Not in this patch: phase 4 F1–F11, phase 5, Instruments work on the 400-row window, copy-stream-URL, a public-API rewrite, the multi-target split, app icon, About, grid mode.

---

## 5. Verification

- Reviewed HEAD: `3b040bd087e6fec082b037f9d685f814ffee8904`. That is the expected shipped tip. `git status` at the start was `main...origin/main` with only `M .gitignore` (the unstaged line adds `tasks/improvement-plan.md`). That file was not staged, reverted, or committed. No commit and no push.
- Read: `SafeHTTPClient`, `IPTVRepository`, `RemoteURLPolicy`, `FilterEngine`, `PlaylistDTOs`, `LoadCatalogUseCase`, `AVStreamPlayer`, `CatalogStore`, `CatalogStore+Loading`, `AppViewModel`, `ChannelListColumn`, `MainSplitView`, `PlayerSurface`, `HUDAutoHide`, `ChannelLogoView`, `SidebarColumn`, `StatusBannerView`, `PlaybackController`, `IPTVApp`, `Package.swift`, `SecurityTests` (C6 table), and the review 3 closed section.
- Host probe, not a unit test: `getaddrinfo(AI_NUMERICHOST)` maps the F1 hosts to `127.0.0.1`. `connect` to port 1 on `0x7f.0.0.1` and on `127.0.0.1` both return errno 61. `connect` to `[::ffff:0:127.0.0.1]` port 1 returns errno 60. `URL(string:)` preserves those hosts.
- `swift test`: exit 0. Log line `Executed 76 tests, with 0 failures (0 unexpected)`. No `warning:` lines. Log: scratch `swift-test.log`.
- `swift build --product IPTVPlayerApp`: exit 0. Log line `Build of product 'IPTVPlayerApp' complete! (0.35s)`. No `warning:` lines. Log: scratch `swift-build.log`.
- `npx --yes @google/design.md lint DESIGN.md`: exit 0. Summary `errors: 0`, `warnings: 0`, `infos: 1`. No contrast finding. Log: scratch `design-lint.log`.
- Line count of `Sources/Presentation/**/*.swift`: 26 files, 2129 lines, maximum 223 (`QuickTimeHUDPanel.swift`). Next is `CatalogStore.swift` at 219. `Tests/` has no `Task.sleep`. `Sources/Domain` has no `import AVFoundation`. Fullscreen calls are `PlayerSurface.swift` lines 26 and 61.
- GUI `swift run` was not run.
