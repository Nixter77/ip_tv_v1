# Code Review 3/3 — IPTVPlayer (macOS)

**Stack:** Swift 5.9 SPM, SwiftUI + AppKit, AVFoundation, SwiftData. Folder-level Clean Architecture.

**Scope:** Read-only pass over remaining OWASP / performance / SOLID issues after fires 1–2. No `Sources/` or `Tests/` edits this fire. Loop ends here (`N=3`).

**Method:** Source review of production files plus a Foundation/`inet_pton` check of host forms that `SecurityTests` does not cover. `swift test` was not re-run (review-only).

---

## 1. Executive Summary

Fires 1–2 closed the original criticals (C1–C4) *for the cases they tested*: one `RemoteURLPolicy`, incremental logo caps, per-call `JSONDecoder`, post-download 64 MB playlist reject, CTL-stripped validators. That work is still in place and should stay.

Two production holes remain.

**C5** is unchanged: playlist fetch still calls `URLSession.data(for:)` and only then measures `data.count`. A hijacked `iptv-org` CDN or MITM can still force a multi-GB allocation before `payloadTooLarge`.

**C6** is a residual of C1 that fire 2’s tests do not catch. `isRestrictedIPv6` is an exact-string list (`::1`, `::`, `0:0:0:0:0:0:0:1`) plus a dotted `:ffff:` mapper. Foundation accepts, and `inet_pton` canonicalizes, compressed and hex-mapped loopback that the policy treats as public. `ChannelLogoView` also **skips DNS** for any host containing `:`, so the fail-closed resolver never sees these literals. `SafeHTTPClient` will GET them, including after a redirect from a public logo host.

| Severity | Remaining | Theme |
|---|---|---|
| Critical | 2 | Playlist body materialized before the cap (C5); non-canonical IP literals bypass logo SSRF (C6) |
| High | 2 | Full catalog still assigned to `@Published filteredChannels` (H2); AVFoundation adapter still in Domain (Q1) |
| Medium | 4 | Playlist `Content-Type`; DNS-rebinding TOCTOU; process-global `NSCursor.hide`; FilterEngine setup ignores cancel |

---

## 2. Remaining Critical Issues

### C5 — Playlist fetch downloads first, then checks size (OWASP A04)

**Status:** Open. Same root cause as review 2.

```274:282:Sources/Data/IPTVRepository.swift
    private func dataWithRetry(for request: URLRequest, endpoint: Endpoint) async throws -> (Data, URLResponse) {
        var delayNs: UInt64 = 200_000_000 // 0.2s
        var lastError: Error = PlaylistFetchError.noData

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                try rejectIfTooLarge(data, endpoint: endpoint)
```

`rejectIfTooLarge` only runs after Foundation has the entire (decompressed) body in `Data`. `expectedContentLength` is never consulted. A `Content-Length: 2GB` 200, a chunked stream with no length, or a small gzip that expands past 64 MB can OOM the process. Logos already abort in `SafeHTTPClient.urlSession(_:dataTask:didReceive:)` and on `expectedContentLength`.

`payloadTooLarge` is typed and not retried — good — but one oversize download is enough.

**Fix:** Reuse `SafeHTTPClient` (or the same delegate pattern) for playlist endpoints with `maxBytes: maxResponseBytes`. Cancel when `expectedContentLength > max` **or** `buffer.count > max`. Keep decode-before-`cache.save`. Do not retry `SafeHTTPError.tooLarge`.

---

### C6 — Logo SSRF policy matches IP *strings*, not addresses (OWASP A10 residual)

**Status:** New residual of C1. Dotted `127.0.0.1`, `localhost`, dword `2130706433`, and `127.1` are blocked. Equivalent addresses that Foundation will fetch are not.

`isRestrictedIPv6` only exact-matches three spellings, then tries `parseIPv4` on the suffix after `:ffff:` (dotted IPv4 only):

```184:197:Sources/Domain/RemoteURLPolicy.swift
    private static func isRestrictedIPv6(_ host: String) -> Bool {
        if host == "::1" || host == "::" || host == "0:0:0:0:0:0:0:1" {
            return true
        }
        if let mapped = ipv4Mapped(from: host) {
            return isRestrictedIPv4(mapped)
        }
        let head = host.split(separator: ":", omittingEmptySubsequences: false)
            .first.map(String.init)?.lowercased() ?? ""
        if head.hasPrefix("fc") || head.hasPrefix("fd") { return true }
        if head.hasPrefix("fe8") || head.hasPrefix("fe9") || head.hasPrefix("fea") || head.hasPrefix("feb") {
            return true
        }
        return false
    }
```

`ChannelLogoView` then skips the DNS fail-closed path for every literal IP (any host with `:`):

```64:67:Sources/Presentation/ChannelLogoView.swift
        if let host = url.host, !RemoteURLPolicy.isLiteralIPAddress(host) {
            let publicDNS = await RemoteURLPolicy.resolvesOnlyToPublicAddresses(host: host)
            guard publicDNS else { return }
        }
```

Foundation parses all of the following (`URL(string:)` returns a host). `inet_pton` on Darwin canonicalizes the IPv6 forms to `::1` / `::ffff:127.0.0.1` and `127.000.000.001` to `127.0.0.1`:

| Catalog `logo` / redirect target | Policy today | Actual address |
|---|---|---|
| `http://[::1]/logo.png` | blocked | loopback |
| `http://[::0:1]/logo.png` | **allowed** | `::1` |
| `http://[::0001]/logo.png` | **allowed** | `::1` |
| `http://[::0:0:1]/logo.png` | **allowed** | `::1` |
| `http://[0:0:0:0:0:0:0:0001]/logo.png` | **allowed** | `::1` |
| `http://[::ffff:127.0.0.1]/logo.png` | blocked (dotted mapped) | 127.0.0.1 |
| `http://[::ffff:7f00:1]/logo.png` | **allowed** | 127.0.0.1 |
| `http://[::ffff:a9fe:a9fe]/…` | **allowed** | 169.254.169.254 |
| `http://[::ffff:c0a8:1]/logo.png` | **allowed** | 192.168.0.1 |
| `http://127.000.000.001/logo.png` | not an IP in *this* parser | 127.0.0.1 via `inet_pton` |

Direct logo URLs use the first path. A public host that 302s to any allowed row uses the second: `shouldFollowRedirect` is only `validatedURL != nil`, so `SafeHTTPClient` will follow onto loopback/LAN.

The process is an unsandboxed SPM app. A malicious or compromised `iptv-org` `logo` field is enough.

**Fix (one function, not more allowlist strings):**

1. Strip brackets; run `inet_pton(AF_INET6)` then `inet_pton(AF_INET)` on the host.
2. If v6: treat `::1` / unspecified as restricted; if v4-mapped / translated, run the existing `isRestrictedIPv4` on the low 32 bits; keep ULA (`fc00::/7`) and link-local (`fe80::/10`).
3. If v4: existing `isRestrictedIPv4`.
4. Keep the custom dword / `127.1` parser **only** for forms `inet_pton` rejects (`2130706433`, `127.1`) — those tests must stay green.
5. Add `SecurityTests` rows for every line in the table above, plus a redirect `https://cdn.example/logo` → `http://[::ffff:7f00:1]/`.
6. Optional hardening: do not skip DNS for literals; run the same `inet_pton` + sockaddr check. That also closes the `127.000.000.001` hole without treating it as a hostname.

Do **not** rewrite `RemoteURLPolicy`’s public surface (`validatedURL(from:kind:)`, `sanitizedHTTPHeaderValue`). Extend `isRestrictedHost` in place (see `tasks/lessons.md` §4).

---

## 3. Remaining High / Medium

### H2 — `@Published filteredChannels` still holds the full catalog

**Status:** Partially mitigated, still open.

The list windows 400 rows and grows on “Загрузить ещё…”. That stops 20k `ChannelLogoView.task`s from mounting at once. `updateFilteredChannels` still does `self.filteredChannels = result` where empty search + `.all` is `allChannelsSorted` (10–20k `Channel` values) on the main actor.

Do not rewrite `FilterEngine` without Instruments. If the assign is the hitch, publish a slice from the VM (or an index + `RandomAccessCollection`) and keep the engine’s sorted array inside the actor.

### Q1 — `PlayerStateManager` still lives in Domain

**Status:** Open.

```1:11:Sources/Domain/PlayerStateManager.swift
// Sources/Domain/PlayerStateManager.swift
// Playback infrastructure adapter: Domain StreamPlayer + AVPlayer UI surface.
import Foundation
import AVFoundation
import Combine

/// AVFoundation adapter + playback policy (fallback, timeout, stall, retry)
@MainActor
public final class PlayerStateManager: NSObject, StreamPlayer {
```

`StreamPlayer` / `PlayerState` already sit in `Domain/Ports/StreamPlayer.swift`. Move the adapter to `Sources/Data/Playback/`. Next feature (AirPlay, PiP, DRM headers) will otherwise land in Domain.

### M1 — Playlist `Content-Type` still unchecked

A captive-portal or CDN 200 with `text/html` still enters `decodeArray`. Large HTML usually becomes `emptyPayload` / `decodingFailed` and then stale cache — so this is not C5 — but you still download and parse the body and may write nothing useful. Reject `text/html` (and empty/`octet-stream` only if decode fails) **before** `cache.save`. Do not cache the HTML.

### M2 — DNS-rebinding TOCTOU on logo hostnames

`ChannelLogoView` resolves the host, then `SafeHTTPClient` resolves again. A hostname that is public at check time can be loopback at connect time. Literal bypass (C6) is worse because DNS is skipped entirely. After C6, pin or re-check the connected address (or resolve once and connect to that IP with a matching `Host` header). Desktop risk is real but needs an attacker-controlled name in the catalog.

### M3 — `NSCursor.hide()` is process-global

`AutoHideHUDModifier.scheduleHide` calls `NSCursor.hide()` when the pointer is idle **inside the tracked window**. Mouse events in other windows are ignored, so the cursor stays hidden while the user is in the search field or another app window. Unhide on `mouseExited` / resign-key, or hide only while the pointer is over the video surface.

### M4 — `FilterEngine.setup` is not cancellable

The setup loop has no `Task.checkCancellation()`. A cancelled reload still builds a full inverted index, then may discard it if `generation` is stale. Fine for one load; rapid ⌘R + SWR stacks CPU/RAM. Check cancellation every N thousand rows; keep the generation fence.

---

## 4. What is closed (do not regress)

| ID | Still true in tree |
|---|---|
| C1 (tested cases) | `Channel.safeLogoURL` + `SafeHTTPClient` size/redirect; DNS fail-closed for **hostnames**; cache only after ImageIO downsample |
| C2 | Per-call `JSONDecoder`; no shared instance |
| C3 (post-download) | `PlaylistFetchError.payloadTooLarge`; injectable `maxResponseBytes` (64 MB) — does **not** replace C5 |
| C4 | ETag / Last-Modified / Referer go through `sanitizedHTTPHeaderValue` on save and on `If-None-Match` |
| H1 | Cache I/O + JSON decode in `Task.detached` |
| H2 (partial) | List window 400 + “Загрузить ещё…” |
| Q2 | Single `RemoteURLPolicy` for streams / logos / Referer / redirects |
| Q4 | Per-window HUD mouse monitor; no `Coordinator.shared` |
| Bounds | Search 200; persisted id/name 128/200; URLCache 16/48 MB; history prune on `recordView` |

**Do not “improve” away:** `SafeDecodable` + decode-before-`cache.save`; `CancellationError` never retried / never painted as a load error; stream URL masking in HUD / `CatalogErrorMapper`; FilterEngine inverted index + adaptive materialize; `RemoteURLPolicy` public API shape.

**H3 (accepted product risk):** `Stream.url` is `.mediaStream` — LAN + `http` + userinfo. AVPlayer will still follow HLS child playlists to any host; that is outside `RemoteURLPolicy`. Never log unmasked `urlString`; do not add “Copy stream URL” without a prompt.

---

## 5. Suggested next patch (priority order)

This review loop is **closed**. A later session should fix in this order, without renaming policy APIs:

1. **C6** — `inet_pton` (then existing dword/`127.1` parser) inside `isRestrictedHost`. Tests for compressed/hex-mapped loopback and a redirect onto `[::ffff:7f00:1]`.
2. **C5** — byte-capped playlist download via `SafeHTTPClient`; fail on `expectedContentLength` before append.
3. **M1** — reject `text/html` playlist responses without caching.
4. **Q1** — move `PlayerStateManager` to `Sources/Data/Playback/`.
5. **H2** — only after a 50k-fixture Instruments trace.

`tasks/todo.md` still lists Q1 and windowed list as deferred; add C5 and C6 there when work starts.

---

## Verification

- Reviewed: `RemoteURLPolicy`, `SafeHTTPClient`, `IPTVRepository`, `ChannelLogoView`, `Entities`, `AppViewModel`, `MainSplitView`, `FilterEngine`, `PlayerStateManager`, DTOs, library, HUD, `SecurityTests`.
- Confirmed with Foundation + `inet_pton` (not with `swift test`): `URL(string:)` accepts every C6 host; `inet_pton` maps `::0:1` / `::0001` → `::1` and `::ffff:7f00:1` → `::ffff:127.0.0.1`.
- `SecurityTests` covers `file:`, `127.0.0.1`, `localhost`, RFC1918, `[::1]`, userinfo, CTL, dword `2130706433`, `127.1`, SafeHTTPClient oversize, poisoned ETag. It does **not** cover C6 or C5-during-download.
