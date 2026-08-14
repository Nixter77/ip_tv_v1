# Code Review 1/3 — IPTVPlayer (macOS)

**Stack detected:** Swift 5.9 SPM package, SwiftUI + AppKit, AVFoundation/AVKit, SwiftData, Combine. Folder-level Clean Architecture (`App` composition → `Presentation` → `Application` → `Domain` ← `Data`). Single `IPTVPlayer` library target + `IPTVPlayerApp` executable.

**Scope:** OWASP Top 10, hot-path performance, SOLID/DRY. Reviewed production sources under `Sources/` and `App/`, plus `Tests/SecurityTests.swift` and the SRE notes in `tasks/todo.md`.

**Audience:** mid-level developer who will own the next hardening pass.

---

## 1. Executive Summary

This is a well-structured desktop IPTV client. Prior SRE work (retry/cancel, decode-before-cache, bitrate clamp, favorite rollback, URL masking in errors) is real and shows up in the code. FilterEngine-as-actor, SWR disk cache, and isolating `PlayerStateManager` from the channel `List` are the right instincts.

The remaining risk is **trust of the remote catalog**. Almost every byte that is not your own code arrives from `iptv-org.github.io` (community JSON). Stream URLs are already restricted to `http`/`https` and Referer is sanitized. **Logo URLs and playlist HTTP metadata are not.** Combined with a **shared, non-thread-safe `JSONDecoder`** used from concurrent `async let` fetches, that is enough to crash, hang, or make the process open attacker-chosen URLs.

Treat the catalog as **untrusted input** the same way you would treat a web form. Validate at the boundary (DTO → domain), not at the last call site that happens to remember.

| Severity | Count | Theme |
|---|---|---|
| Critical | 4 | Untrusted logo fetch (SSRF/DoS), `JSONDecoder` data race, unbounded playlist body, ETag header replay |
| High (perf / design) | 4 | Main-thread cache decode, 20k-row `List`, 100 MB logo `URLCache`, AVFoundation in Domain |
| Medium | 4 | HUD singleton, duplicated window accessors, fat VM leftovers, missing payload Content-Type |

---

## 2. Critical Issues (Security / Performance)

### C1 — Untrusted logo URLs fetched with no scheme, host, or size policy (OWASP A10 SSRF, A05 Misconfiguration, A04 Insecure Design)

**Why this is a production bug, not a theory.** `iptv-org` is a public, PR-driven dataset. A malicious or compromised `logo` field becomes a URL your process will GET.

`ChannelRowView` accepts any parseable URL:

```450:456:Sources/Presentation/MainSplitView.swift
        self.logoURL = channel.logo.flatMap { URL(string: $0) }
        self.languagesLabel = channel.languages.joined(separator: ", ").uppercased()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ChannelLogoView(url: logoURL, name: channel.name)
```

`ChannelLogoView` then downloads it on `URLSession.shared` and caches **any 2xx body**, with no byte cap:

```46:66:Sources/Presentation/ChannelLogoView.swift
    private func loadImage() async {
        image = nil
        guard let url else { return }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        // ...
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                let cached = CachedURLResponse(response: response, data: data)
                URLCache.shared.storeCachedResponse(cached, for: request)
            }
```

Contrast with `Stream.url` in the same codebase, which already rejects non-`http(s)`:

```56:68:Sources/Domain/Entities.swift
    public var url: URL? {
        if let url = URL(string: urlString),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        // ...
    }
```

**What an attacker can do**

| Payload in `channels[].logo` | Effect |
|---|---|
| `file:///etc/passwd` or `file:///Users/…` | `URLSession` will read a local file (this SPM app has no sandbox entitlements). ImageIO then parses the bytes. |
| `http://127.0.0.1:PORT/…` or link-local | SSRF against services on the user’s LAN (routers, dev servers, cloud-metadata analogues). |
| `https://evil.example/10gb.bin` | Full body is loaded into `Data` **before** ImageIO downsample. One visible row can OOM the app. |
| Valid-looking 200 with a 40 MB PNG | Same: downsample is O(target pixels) only *after* the download. |

`URLCache.shared` is also configured in `App/IPTVApp.swift` at **100 MB memory / 300 MB disk**. You store the *original* logo bytes, then display an 88 px thumbnail. That is both a DoS amplifier and a waste of RAM.

**Fix (minimum bar)**

1. Reuse one allowlist: scheme ∈ {`https` (prefer), `http`}, reject `file`, `data`, custom schemes.
2. Reject loopback / link-local / unique-local hosts for logos (users did not ask to probe their LAN).
3. Cap download at ~512 KB–2 MB (`URLSession` bytes limit, or abort if `Content-Length` / `data.count` exceeds).
4. Do not `storeCachedResponse` unless ImageIO actually produced a thumbnail.
5. Prefer the existing `IPTVRepository.makeDefaultSession()` (timeouts, connection cap) over `.shared`.

This is the same lesson as “never `eval` user input”: the catalog is user input written by strangers.

---

### C2 — Shared `JSONDecoder` used concurrently (`async let` channels + streams)

`JSONDecoder` is **not thread-safe**. Apple’s docs and every TSAN run will tell you that. The repository holds one instance and marks the class `@unchecked Sendable`:

```136:141:Sources/Data/IPTVRepository.swift
public final class IPTVRepository: PlaylistRepository, @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let diskCache: PlaylistDiskCache?
    private let maxAttempts: Int
```

The use case always fetches both endpoints in parallel:

```57:60:Sources/Application/LoadCatalogUseCase.swift
        async let channelsFetch = repository.fetchChannels(options: options)
        async let streamsFetch = repository.fetchStreams(options: options)
        let channels = try await channelsFetch
        let streams = try await streamsFetch
```

Both call `decodeArray`, which uses `self.decoder`. On a cache miss (or two large 200s), you decode **two multi‑MB JSON arrays at the same time on one decoder**. That is undefined behavior: torn internal state, rare crashes, or silently wrong catalogs.

`@unchecked Sendable` is a promise you made to the compiler. You are currently breaking it.

**Fix:** construct a `JSONDecoder()` inside `decodeArray` (decoders are cheap compared to 20 MB of JSON), or isolate the repository as an `actor`. Do not share a decoder across tasks.

---

### C3 — Unbounded playlist HTTP body → memory DoS (OWASP A04 / A05)

`dataWithRetry` returns whatever `URLSession` downloaded. There is no `Content-Length` check and no post-download cap:

```244:255:Sources/Data/IPTVRepository.swift
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if isRetriableHTTP(http.statusCode), attempt < maxAttempts - 1 {
                        // ...
                    }
                    if http.statusCode != 200 && http.statusCode != 304 {
                        throw PlaylistFetchError.httpStatus(endpoint: endpoint.rawValue, statusCode: http.statusCode)
                    }
                }
                return (data, response)
```

You already treat “empty but large” as an anomaly (`rejectsEmptyLargePayload` + 256 byte threshold). You do **not** treat “non-empty and huge” as an anomaly. A 200 from a hijacked CDN, a broken proxy, or a future API change can hand you 1–2 GB. `JSONDecoder` will try to allocate graphs of tens of thousands of objects on top of that `Data`.

iptv-org `channels.json` / `streams.json` today are on the order of tens of MB. A hard cap of **64 MB per endpoint** (or whatever you measure + 2× headroom) is a product decision, not a guess. Reject with a typed `PlaylistFetchError` and keep the last good cache (you already have that path).

---

### C4 — Conditional-request headers replay unsanitized `ETag` / `Last-Modified` (OWASP A03 Injection)

You already learned this lesson for `http_referrer` (CR/LF rejected, scheme checked) in `PlayerStateManager.playCurrentStream()`. The playlist client does not apply the same rule:

```309:314:Sources/Data/IPTVRepository.swift
        if let etag = cachedMeta?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cachedMeta?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
```

Those strings come from a previous `HTTPURLResponse` and are persisted to disk (`PlaylistCacheMeta`). A single poisoned response (compromised host, captive portal, local MITM on first launch) writes:

```
ETag: "abc"\r\nAuthorization: Bearer stolen
```

`URLRequest.setValue(_:forHTTPHeaderField:)` is not a security boundary. Foundation has historically been inconsistent about stripping CTL characters. You persist the value and send it on every subsequent refresh.

**Fix:** reject any header value containing CR, LF, NUL, or other CTL (`U+0000…001F`, `U+007F`) before `save` **and** before `setValue`. If invalid, drop the validator and do a full GET. Same helper should sanitize Referer (DRY).

---

### Related high (not counted in `critical_count`, but do not ignore)

**H1 — Fresh disk cache can decode on the MainActor (Swift 5.9).** `AppViewModel` is `@MainActor` and calls `LoadCatalogUseCase.execute`. In Swift 5.9 (this package’s tools version), a non-isolated async function **starts on the caller’s executor**. The cache-hit path in `fetchAndDecodeSafeArray` is fully synchronous (`Data(contentsOf:)` + `JSONDecoder`) until the first `await`. First launch after a good cache = hitch of hundreds of ms to seconds while 50k channels + streams decode on the UI thread. Wrap decode + file I/O in `Task.detached` (or make `IPTVRepository` an actor) and hop back with the arrays.

**H2 — “All channels” publishes the entire catalog into a SwiftUI `List`.** Empty search + `.all` returns `allChannelsSorted` (easily 10–20k `Channel` values). Each row builds a `ChannelLogoView` whose `.task` will fire as the user scrolls. That is the correct lazy behavior — but the `@Published` assignment still copies a huge array and invalidates the column. Consider a windowed / paged materialize (first 500 + “load more”), or keep the engine’s sorted list and only publish a slice.

**H3 — Stream playback is intentional open-proxy behavior.** `Stream.url` allowing `http` + userinfo (`user:pass@host`) means AVPlayer will send credentials in cleartext and follow HLS child playlists to any host. That is the product, but it is still A08 (integrity of the catalog). Document it; never log `urlString` unmasked (you already mask in HUD — good); do not add “Copy stream URL” without a confirmation.

---

## 3. Code Quality Improvements (SOLID / DRY)

These will not page you at 3 AM, but they will make C1–C4 cheaper to fix and harder to regress.

### Q1 — `PlayerStateManager` lives in Domain but *is* the AVFoundation adapter (DIP / layering)

The file even says so:

```1:11:Sources/Domain/PlayerStateManager.swift
// Sources/Domain/PlayerStateManager.swift
// Playback infrastructure adapter: Domain StreamPlayer + AVPlayer UI surface.
```

Domain should not import AVFoundation. You already have the port (`StreamPlayer`) and a comment that the UI binds to a concrete adapter. Move the class to `Sources/Data/Playback/` (or `Infrastructure/`). Keep `PlayerState` + `StreamPlayer` in Domain. Tests that need `AVPlayer` stay on the adapter; domain tests can use a fake.

This is not pedantry: once AVPlayer is “domain,” the next feature (AirPlay, PiP, DRM headers) will also land in Domain and the port becomes decoration.

### Q2 — URL policy is implemented three times (DRY)

| Site | What it checks |
|---|---|
| `Stream.url` | `http` / `https` only |
| `PlayerStateManager` Referer | `http`/`https` + no CR/LF |
| `ChannelRowView` / `ChannelLogoView` | **nothing** |

Extract one `RemoteHTTPURL` (or `func URL.validatedForUntrustedRemote`) used by stream play, logo fetch, and Referer. Security rules that exist in only one call site *will* be skipped in the next one. C1 is exactly that.

### Q3 — `AppViewModel` is thinner than it was, still not a single responsibility

It still: restores `UserDefaults`, owns library optimistic updates, serializes catalog loads, maps sidebar → filter, and drives playback. That is acceptable as a facade **if** UserDefaults and library rollback move behind small types (`SessionSettingsStore`, `FavoriteController`). The next person who adds “watch later” will otherwise grow this file again.

### Q4 — HUD `Coordinator.shared` is a process-wide singleton

```63:75:Sources/Presentation/QuickTimeHUDPanel.swift
private final class Coordinator: NSObject {
    static let shared = Coordinator()
    var onMouseMoved: (() -> Void)?
    // ...
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, ...]) { ... }
```

Main window + detached player both install `autoHideHUD`. The second overwrites `onMouseMoved`. Mouse in one window animates the other HUD; `onDisappear` of either clears the shared callbacks. Own a coordinator per view, or use `NSTrackingArea` on the representable.

Same file reimplements `HostingWindowAccessor` next to `Sources/Presentation/WindowAccessor.swift`. Delete the private copy.

### Q5 — What is already good (do not “improve” these away)

- `SafeDecodable` so one bad stream object does not kill the catalog.
- Decode-then-`cache.save` (SRE F2) — keep this order when you add the size cap.
- `CancellationError` never retried (F3) and not painted as a user error (F5).
- `Stream.mask` / `maskURLs` and `CatalogErrorMapper` — HUD shows `maskedUrlString`. Keep tests in `SecurityTests.swift`; add cases for logos and ETags next.
- FilterEngine inverted index + adaptive materialize — this is the right performance work. Do not replace it with `channels.filter { $0.name.contains }`.

---

## 4. Refactored Code Example

**File:** `Sources/Presentation/ChannelLogoView.swift` (+ one line in `ChannelRowView`).  
**Goal:** close C1 with the same discipline `Stream.url` already uses. Mid-level takeaway: *validate untrusted URLs at the fetch boundary, fail closed, never cache garbage.*

```swift
// Sources/Presentation/ChannelLogoView.swift
#if canImport(SwiftUI) && canImport(AppKit) && canImport(ImageIO)
import SwiftUI
import AppKit
import ImageIO

struct ChannelLogoView: View {
    let url: URL?
    let name: String
    var maxPixelSize: CGFloat = 88

    @State private var image: NSImage?

    /// Community catalog is untrusted input. Logos are decoration — never worth SSRF or an OOM.
    static func acceptedLogoURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        guard !url.isFileURL else { return nil }
        if let host = url.host?.lowercased(),
           host == "localhost"
            || host.hasPrefix("127.")
            || host == "::1"
            || host.hasPrefix("169.254.")
            || host.hasPrefix("10.")
            || host.hasPrefix("192.168.") {
            return nil
        }
        return url
    }

    private static let maxLogoBytes = 512 * 1024

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .accessibilityLabel("Логотип канала \(name)")
            } else {
                placeholder
            }
        }
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(name.prefix(1)).uppercased())
                .font(.headline)
                .foregroundColor(.white)
                .fontWeight(.bold)
        }
        .frame(width: 44, height: 44)
        .cornerRadius(6)
        .accessibilityLabel("Логотип \(name) отсутствует")
    }

    private func loadImage() async {
        image = nil
        guard let url else { return }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("bytes=0-\(Self.maxLogoBytes - 1)", forHTTPHeaderField: "Range")

        if let cached = URLCache.shared.cachedResponse(for: request),
           cached.data.count <= Self.maxLogoBytes,
           let downsampled = Self.downsample(data: cached.data, maxPixelSize: maxPixelSize) {
            image = downsampled
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= Self.maxLogoBytes else { return }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }
            guard let downsampled = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                return
            }
            // Cache only what we could actually render — not an unbounded 2xx body.
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            image = downsampled
        } catch {
            // placeholder stays
        }
    }

    static func downsample(data: Data, maxPixelSize: CGFloat) -> NSImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif
```

**Call site** (`ChannelRowView.init` in `Sources/Presentation/MainSplitView.swift`):

```swift
// before — any scheme, including file://
self.logoURL = channel.logo.flatMap { URL(string: $0) }

// after — same policy as Stream.url, plus LAN deny
self.logoURL = ChannelLogoView.acceptedLogoURL(channel.logo)
```

**Follow-up in the same spirit for C2/C3/C4** (`IPTVRepository.decodeArray` / `dataWithRetry`):

```swift
private static let maxPlaylistBytes = 64 * 1024 * 1024

private func decodeArray<T: Decodable>(from data: Data, endpoint: Endpoint) throws -> [T] {
    let decoder = JSONDecoder() // per-call: JSONDecoder is not thread-safe
    // ... existing SafeDecodable fallback, using `decoder`, not `self.decoder`
}

private static func httpHeaderToken(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    if raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
        return nil
    }
    return raw
}

// after session.data:
if data.count > Self.maxPlaylistBytes {
    throw PlaylistFetchError.emptyPayload(endpoint: endpoint.rawValue, byteCount: data.count)
}
```

Add tests next to `SecurityTests.swift`:

- `file:///tmp/x` and `http://127.0.0.1/logo` → `acceptedLogoURL` is `nil`.
- ETag containing `\r\n` is dropped (no `If-None-Match`).
- Two concurrent `fetchChannels` + `fetchStreams` under TSan (or a stub decoder counter) do not share one decoder.

---

## Review notes for the next fires

Fire 2 should measure H1 (MainActor cache decode) and H2 (List size) with Instruments / a 50k fixture — do not “fix” FilterEngine until you have numbers. Fire 3 should move `PlayerStateManager` out of Domain and collapse the three URL policies into one type.

**Verification not run this fire:** `swift test` was not executed (review-only). Findings are from source, not from a failing test.
