// Sources/Data/IPTVRepository.swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Типизированные ошибки загрузки плейлиста (user-safe + debug context)
public enum PlaylistFetchError: Error, LocalizedError, Sendable {
    case badURL(endpoint: String)
    case httpStatus(endpoint: String, statusCode: Int)
    case emptyPayload(endpoint: String, byteCount: Int)
    case decodingFailed(endpoint: String, underlying: String)
    case noData
    case payloadTooLarge(endpoint: String, byteCount: Int)

    public var errorDescription: String? {
        switch self {
        case .badURL(let endpoint):
            return "Некорректный адрес источника (\(endpoint))"
        case .httpStatus(_, let code):
            return "Сервер плейлиста недоступен (HTTP \(code))"
        case .emptyPayload(let endpoint, _):
            return "Пустой ответ источника (\(endpoint))"
        case .decodingFailed:
            return "Не удалось разобрать данные плейлиста"
        case .noData:
            return "Нет данных плейлиста"
        case .payloadTooLarge(_, let byteCount):
            return "Ответ плейлиста слишком большой (\(byteCount) байт)"
        }
    }

    /// Короткое сообщение для UI (без внутренних деталей)
    public var userMessage: String {
        switch self {
        case .httpStatus(_, let code) where code == 429:
            return "Слишком много запросов к серверу плейлиста. Подождите и обновите снова."
        case .httpStatus(_, let code) where (500...599).contains(code):
            return "Сервер плейлиста временно недоступен (HTTP \(code))."
        case .httpStatus(_, let code):
            return "Ошибка загрузки плейлиста (HTTP \(code))."
        case .emptyPayload:
            return "Сервер вернул пустой плейлист."
        case .decodingFailed:
            return "Формат плейлиста повреждён или изменился."
        case .badURL:
            return "Внутренняя ошибка адреса плейлиста."
        case .noData:
            return "Нет данных плейлиста."
        case .payloadTooLarge:
            return "Сервер вернул слишком большой плейлист."
        }
    }
}

/// Вспомогательная структура для безопасного декодирования элементов массива.
private struct SafeDecodable<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            self.value = try container.decode(Element.self)
        } catch {
            self.value = nil
        }
    }
}

/// Метаданные дискового кэша плейлиста
private struct PlaylistCacheMeta: Codable, Sendable {
    var fetchedAt: Date
    var etag: String?
    var lastModified: String?
    var contentLength: Int
}

/// Дисковый кэш JSON API (отдельно от URLCache логотипов)
public struct PlaylistDiskCache: Sendable {
    public let directory: URL
    public let ttl: TimeInterval

    public init(directory: URL, ttl: TimeInterval = 6 * 60 * 60) {
        self.directory = directory
        self.ttl = ttl
    }

    public static var applicationDefault: PlaylistDiskCache? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("IPTVPlayer/APICache", isDirectory: true)
        return PlaylistDiskCache(directory: dir)
    }

    fileprivate func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    fileprivate func dataURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    fileprivate func metaURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).meta.json")
    }

    fileprivate func loadMeta(for key: String) -> PlaylistCacheMeta? {
        let url = metaURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlaylistCacheMeta.self, from: data)
    }

    fileprivate func loadData(for key: String) -> Data? {
        try? Data(contentsOf: dataURL(for: key))
    }

    fileprivate func isFresh(_ meta: PlaylistCacheMeta) -> Bool {
        Date().timeIntervalSince(meta.fetchedAt) < ttl
    }

    fileprivate func save(key: String, data: Data, etag: String?, lastModified: String?) throws {
        try ensureDirectory()
        try data.write(to: dataURL(for: key), options: .atomic)
        let meta = PlaylistCacheMeta(
            fetchedAt: Date(),
            etag: RemoteURLPolicy.sanitizedHTTPHeaderValue(etag),
            lastModified: RemoteURLPolicy.sanitizedHTTPHeaderValue(lastModified),
            contentLength: data.count
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: metaURL(for: key), options: .atomic)
    }

    fileprivate func remove(key: String) {
        try? FileManager.default.removeItem(at: dataURL(for: key))
        try? FileManager.default.removeItem(at: metaURL(for: key))
    }
}

/// Data adapter: iptv-org HTTP + disk cache → Domain entities (via DTOs).
public final class IPTVRepository: PlaylistRepository, @unchecked Sendable {
    private let session: URLSession
    private let diskCache: PlaylistDiskCache?
    private let maxAttempts: Int
    private let maxResponseBytes: Int
    private let cacheLock = NSLock()

    /// Сессия по умолчанию с жёсткими таймаутами (не .shared)
    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }

    private enum Endpoint: String {
        case channels
        case streams
        case categories
        case countries
        case languages

        var urlString: String {
            "https://iptv-org.github.io/api/\(rawValue).json"
        }

        var cacheKey: String { rawValue }

        /// Для channels/streams пустой массив при большом теле = аномалия
        var rejectsEmptyLargePayload: Bool {
            self == .channels || self == .streams
        }
    }

    public init(
        session: URLSession = IPTVRepository.makeDefaultSession(),
        diskCache: PlaylistDiskCache? = .applicationDefault,
        maxAttempts: Int = 3,
        maxResponseBytes: Int = RemoteURLPolicy.maxPlaylistBytes
    ) {
        self.session = session
        self.diskCache = diskCache
        self.maxAttempts = max(1, maxAttempts)
        self.maxResponseBytes = max(1, maxResponseBytes)
    }

    private func withCacheLock<T>(_ body: (PlaylistDiskCache) throws -> T) rethrows -> T? {
        guard let diskCache else { return nil }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return try body(diskCache)
    }

    private func rejectIfTooLarge(_ data: Data, endpoint: Endpoint) throws {
        if data.count > maxResponseBytes {
            throw PlaylistFetchError.payloadTooLarge(endpoint: endpoint.rawValue, byteCount: data.count)
        }
    }

    private func decodeArray<T: Decodable>(from data: Data, endpoint: Endpoint) throws -> [T] {
        try rejectIfTooLarge(data, endpoint: endpoint)
        let decoder = JSONDecoder()
        do {
            let items = try decoder.decode([T].self, from: data)
            try validatePayload(items, data: data, endpoint: endpoint)
            return items
        } catch let error as PlaylistFetchError {
            throw error
        } catch {
            do {
                let safeElements = try decoder.decode([SafeDecodable<T>].self, from: data)
                let items = safeElements.compactMap { $0.value }
                let skipped = safeElements.count - items.count
                if skipped > 0 {
                    let ratio = Double(skipped) / Double(max(safeElements.count, 1))
                    if ratio > 0.3, endpoint.rejectsEmptyLargePayload, safeElements.count >= 20 {
                        throw PlaylistFetchError.decodingFailed(
                            endpoint: endpoint.rawValue,
                            underlying: "skipped \(skipped)/\(safeElements.count) items"
                        )
                    }
                    #if DEBUG
                    if ratio > 0.3 {
                        print("Playlist \(endpoint.rawValue): skipped \(skipped)/\(safeElements.count) items (\(Int(ratio * 100))%)")
                    }
                    #endif
                }
                try validatePayload(items, data: data, endpoint: endpoint)
                return items
            } catch let error as PlaylistFetchError {
                throw error
            } catch {
                throw PlaylistFetchError.decodingFailed(
                    endpoint: endpoint.rawValue,
                    underlying: error.localizedDescription
                )
            }
        }
    }

    private func validatePayload<T>(_ items: [T], data: Data, endpoint: Endpoint) throws {
        if endpoint.rejectsEmptyLargePayload, items.isEmpty, data.count > 256 {
            throw PlaylistFetchError.emptyPayload(endpoint: endpoint.rawValue, byteCount: data.count)
        }
    }

    private func isRetriableHTTP(_ code: Int) -> Bool {
        code == 408 || code == 429 || (500...599).contains(code)
    }

    private func isRetriableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .resourceUnavailable, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    /// Retry с exponential backoff + jitter. Cancellation never retried.
    private func dataWithRetry(for request: URLRequest, endpoint: Endpoint) async throws -> (Data, URLResponse) {
        var delayNs: UInt64 = 200_000_000 // 0.2s
        var lastError: Error = PlaylistFetchError.noData

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if let lengthString = http.value(forHTTPHeaderField: "Content-Length"),
                       let length = Int(lengthString), length > maxResponseBytes {
                        throw PlaylistFetchError.payloadTooLarge(endpoint: endpoint.rawValue, byteCount: length)
                    }
                }
                try rejectIfTooLarge(data, endpoint: endpoint)
                if let http = response as? HTTPURLResponse {
                    if isRetriableHTTP(http.statusCode), attempt < maxAttempts - 1 {
                        try await Task.sleep(nanoseconds: delayNs + UInt64.random(in: 0...50_000_000))
                        delayNs = min(delayNs * 2, 2_000_000_000)
                        continue
                    }
                    if http.statusCode != 200 && http.statusCode != 304 {
                        throw PlaylistFetchError.httpStatus(endpoint: endpoint.rawValue, statusCode: http.statusCode)
                    }
                }
                return (data, response)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as PlaylistFetchError {
                throw error
            } catch let error as URLError {
                lastError = error
                if isRetriableURLError(error), attempt < maxAttempts - 1 {
                    try await Task.sleep(nanoseconds: delayNs + UInt64.random(in: 0...50_000_000))
                    delayNs = min(delayNs * 2, 2_000_000_000)
                    continue
                }
                throw error
            } catch {
                // Do not retry cancellation-like cooperative cancels mis-typed as other errors
                if error is CancellationError { throw error }
                lastError = error
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(nanoseconds: delayNs + UInt64.random(in: 0...50_000_000))
                    delayNs = min(delayNs * 2, 2_000_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    /// Disk I/O + JSON decode hop off the caller's executor (Swift 5.9 inherits MainActor).
    private func decodeArrayOffMain<T: Decodable & Sendable>(
        from data: Data,
        endpoint: Endpoint
    ) async throws -> [T] {
        try await Task.detached(priority: .userInitiated) {
            try self.decodeArray(from: data, endpoint: endpoint)
        }.value
    }

    private func loadCacheSnapshot(key: String) async -> (meta: PlaylistCacheMeta?, data: Data?) {
        await Task.detached(priority: .utility) {
            let meta = self.withCacheLock { $0.loadMeta(for: key) } ?? nil
            let data = self.withCacheLock { $0.loadData(for: key) } ?? nil
            return (meta, data)
        }.value
    }

    private func fetchAndDecodeSafeArray<T: Decodable & Sendable>(
        endpoint: Endpoint,
        forceNetwork: Bool
    ) async throws -> [T] {
        let cacheKey = endpoint.cacheKey
        let (cachedMeta, cachedData) = await loadCacheSnapshot(key: cacheKey)

        // Свежий кэш — мгновенный ответ (SWR: вызывающий может forceNetwork позже)
        if !forceNetwork, let meta = cachedMeta, let data = cachedData,
           withCacheLock({ $0.isFresh(meta) }) == true {
            do {
                return try await decodeArrayOffMain(from: data, endpoint: endpoint)
            } catch {
                // Битый fresh cache — снести и идти в сеть
                _ = withCacheLock { cache in
                    cache.remove(key: cacheKey)
                }
            }
        }

        guard let url = URL(string: endpoint.urlString) else {
            throw PlaylistFetchError.badURL(endpoint: endpoint.rawValue)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        if let etag = RemoteURLPolicy.sanitizedHTTPHeaderValue(cachedMeta?.etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = RemoteURLPolicy.sanitizedHTTPHeaderValue(cachedMeta?.lastModified) {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (data, response) = try await dataWithRetry(for: request, endpoint: endpoint)
            guard let http = response as? HTTPURLResponse else {
                throw PlaylistFetchError.httpStatus(endpoint: endpoint.rawValue, statusCode: -1)
            }

            if http.statusCode == 304, let cachedData {
                do {
                    let items: [T] = try await decodeArrayOffMain(from: cachedData, endpoint: endpoint)
                    // Refresh meta only after successful decode (avoid writing bad state)
                    _ = withCacheLock { cache in
                        try? cache.save(
                            key: cacheKey,
                            data: cachedData,
                            etag: RemoteURLPolicy.sanitizedHTTPHeaderValue(http.value(forHTTPHeaderField: "ETag")) ?? cachedMeta?.etag,
                            lastModified: RemoteURLPolicy.sanitizedHTTPHeaderValue(http.value(forHTTPHeaderField: "Last-Modified")) ?? cachedMeta?.lastModified
                        )
                    }
                    return items
                } catch {
                    _ = withCacheLock { $0.remove(key: cacheKey) }
                    // 304 без валидного тела — полный refetch без conditional headers
                    var full = URLRequest(url: url)
                    full.cachePolicy = .reloadIgnoringLocalCacheData
                    full.timeoutInterval = 30
                    let (freshData, freshResponse) = try await dataWithRetry(for: full, endpoint: endpoint)
                    guard let freshHTTP = freshResponse as? HTTPURLResponse, freshHTTP.statusCode == 200 else {
                        throw PlaylistFetchError.httpStatus(
                            endpoint: endpoint.rawValue,
                            statusCode: (freshResponse as? HTTPURLResponse)?.statusCode ?? -1
                        )
                    }
                    // Decode before save — never poison disk cache with corrupt 200 body
                    let items: [T] = try await decodeArrayOffMain(from: freshData, endpoint: endpoint)
                    _ = withCacheLock { cache in
                        try? cache.save(
                            key: cacheKey,
                            data: freshData,
                            etag: RemoteURLPolicy.sanitizedHTTPHeaderValue(freshHTTP.value(forHTTPHeaderField: "ETag")),
                            lastModified: RemoteURLPolicy.sanitizedHTTPHeaderValue(freshHTTP.value(forHTTPHeaderField: "Last-Modified"))
                        )
                    }
                    return items
                }
            }

            guard http.statusCode == 200 else {
                throw PlaylistFetchError.httpStatus(endpoint: endpoint.rawValue, statusCode: http.statusCode)
            }

            // Decode before save so a corrupt 200 cannot overwrite a still-valid stale cache
            let items: [T] = try await decodeArrayOffMain(from: data, endpoint: endpoint)
            _ = withCacheLock { cache in
                try? cache.save(
                    key: cacheKey,
                    data: data,
                    etag: RemoteURLPolicy.sanitizedHTTPHeaderValue(http.value(forHTTPHeaderField: "ETag")),
                    lastModified: RemoteURLPolicy.sanitizedHTTPHeaderValue(http.value(forHTTPHeaderField: "Last-Modified"))
                )
            }
            return items
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Сеть/HTTP fail — stale cache (в т.ч. просроченный)
            if let cachedData {
                do {
                    return try await decodeArrayOffMain(from: cachedData, endpoint: endpoint)
                } catch {
                    _ = withCacheLock { $0.remove(key: cacheKey) }
                }
            }
            throw error
        }
    }

    public func fetchChannels(options: CatalogFetchOptions) async throws -> [Channel] {
        let dtos: [ChannelDTO] = try await fetchAndDecodeSafeArray(
            endpoint: .channels,
            forceNetwork: options.forceNetwork
        )
        return dtos.map { $0.toDomain() }
    }

    public func fetchStreams(options: CatalogFetchOptions) async throws -> [Stream] {
        let dtos: [StreamDTO] = try await fetchAndDecodeSafeArray(
            endpoint: .streams,
            forceNetwork: options.forceNetwork
        )
        return dtos.map { $0.toDomain() }
    }

    public func fetchCategories(options: CatalogFetchOptions) async throws -> [Category] {
        let dtos: [CategoryDTO] = try await fetchAndDecodeSafeArray(
            endpoint: .categories,
            forceNetwork: options.forceNetwork
        )
        return dtos.map { $0.toDomain() }
    }

    public func fetchCountries(options: CatalogFetchOptions) async throws -> [Country] {
        let dtos: [CountryDTO] = try await fetchAndDecodeSafeArray(
            endpoint: .countries,
            forceNetwork: options.forceNetwork
        )
        return dtos.map { $0.toDomain() }
    }

    public func fetchLanguages(options: CatalogFetchOptions) async throws -> [Language] {
        let dtos: [LanguageDTO] = try await fetchAndDecodeSafeArray(
            endpoint: .languages,
            forceNetwork: options.forceNetwork
        )
        return dtos.map { $0.toDomain() }
    }
}
