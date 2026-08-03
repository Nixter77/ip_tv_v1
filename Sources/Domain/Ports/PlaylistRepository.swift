// Sources/Domain/Ports/PlaylistRepository.swift
// Domain-facing port for remote playlist sources (implemented in Data).
import Foundation

/// Опции загрузки с источника плейлиста
public struct CatalogFetchOptions: Sendable, Equatable {
    public var forceNetwork: Bool

    public init(forceNetwork: Bool = false) {
        self.forceNetwork = forceNetwork
    }

    public static let cacheFirst = CatalogFetchOptions(forceNetwork: false)
    public static let forceNetwork = CatalogFetchOptions(forceNetwork: true)
}

/// Агрегированный снимок каталога
public struct PlaylistCatalog: Sendable, Equatable {
    public let channels: [Channel]
    public let streams: [Stream]
    public let categories: [Category]
    public let countries: [Country]
    public let languages: [Language]
    /// Имена meta-разделов, которые не удалось загрузить (soft-fail)
    public let metaWarnings: [String]

    public init(
        channels: [Channel],
        streams: [Stream],
        categories: [Category],
        countries: [Country],
        languages: [Language],
        metaWarnings: [String] = []
    ) {
        self.channels = channels
        self.streams = streams
        self.categories = categories
        self.countries = countries
        self.languages = languages
        self.metaWarnings = metaWarnings
    }
}

/// Порт: источник плейлиста (iptv-org API, M3U, …)
public protocol PlaylistRepository: Sendable {
    func fetchChannels(options: CatalogFetchOptions) async throws -> [Channel]
    func fetchStreams(options: CatalogFetchOptions) async throws -> [Stream]
    func fetchCategories(options: CatalogFetchOptions) async throws -> [Category]
    func fetchCountries(options: CatalogFetchOptions) async throws -> [Country]
    func fetchLanguages(options: CatalogFetchOptions) async throws -> [Language]
}

public extension PlaylistRepository {
    func fetchChannels(forceNetwork: Bool = false) async throws -> [Channel] {
        try await fetchChannels(options: CatalogFetchOptions(forceNetwork: forceNetwork))
    }

    func fetchStreams(forceNetwork: Bool = false) async throws -> [Stream] {
        try await fetchStreams(options: CatalogFetchOptions(forceNetwork: forceNetwork))
    }

    func fetchCategories(forceNetwork: Bool = false) async throws -> [Category] {
        try await fetchCategories(options: CatalogFetchOptions(forceNetwork: forceNetwork))
    }

    func fetchCountries(forceNetwork: Bool = false) async throws -> [Country] {
        try await fetchCountries(options: CatalogFetchOptions(forceNetwork: forceNetwork))
    }

    func fetchLanguages(forceNetwork: Bool = false) async throws -> [Language] {
        try await fetchLanguages(options: CatalogFetchOptions(forceNetwork: forceNetwork))
    }
}

/// Backward-compatible alias used by older call sites / tests
public typealias IPTVRepositoryProtocol = PlaylistRepository
