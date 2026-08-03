// Sources/Application/LoadCatalogUseCase.swift
import Foundation

/// Результат загрузки каталога для Presentation
public struct LoadCatalogResult: Sendable {
    public let channels: [Channel]
    public let streams: [Stream]
    public let categories: [Category]
    public let countries: [Country]
    public let languages: [Language]
    public let metaWarnings: [String]
    public let shouldScheduleRevalidate: Bool

    public init(
        channels: [Channel],
        streams: [Stream],
        categories: [Category],
        countries: [Country],
        languages: [Language],
        metaWarnings: [String],
        shouldScheduleRevalidate: Bool
    ) {
        self.channels = channels
        self.streams = streams
        self.categories = categories
        self.countries = countries
        self.languages = languages
        self.metaWarnings = metaWarnings
        self.shouldScheduleRevalidate = shouldScheduleRevalidate
    }
}

/// Use case: загрузка + индексация каталога (application layer)
public struct LoadCatalogUseCase: Sendable {
    private let repository: any PlaylistRepository
    private let filterEngine: any ChannelFilterEngineProtocol

    public init(
        repository: any PlaylistRepository,
        filterEngine: any ChannelFilterEngineProtocol
    ) {
        self.repository = repository
        self.filterEngine = filterEngine
    }

    /// - Parameters:
    ///   - policy: стратегия сети/кэша
    ///   - fallbackCategories/countries/languages: previous UI values for soft meta-fail
    public func execute(
        policy: CatalogLoadPolicy,
        fallbackCategories: [Category] = [],
        fallbackCountries: [Country] = [],
        fallbackLanguages: [Language] = []
    ) async throws -> LoadCatalogResult {
        let options = policy.fetchOptions

        async let channelsFetch = repository.fetchChannels(options: options)
        async let streamsFetch = repository.fetchStreams(options: options)
        let channels = try await channelsFetch
        let streams = try await streamsFetch

        var metaWarnings: [String] = []

        let cats: [Category]
        do {
            cats = try await repository.fetchCategories(options: options)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            cats = fallbackCategories
            metaWarnings.append("категории")
        }

        let ctrs: [Country]
        do {
            ctrs = try await repository.fetchCountries(options: options)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ctrs = fallbackCountries
            metaWarnings.append("страны")
        }

        let langs: [Language]
        do {
            langs = try await repository.fetchLanguages(options: options)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            langs = fallbackLanguages
            metaWarnings.append("языки")
        }

        await filterEngine.setup(channels: channels, streams: streams)

        return LoadCatalogResult(
            channels: channels,
            streams: streams,
            categories: cats.sorted { $0.name < $1.name },
            countries: ctrs.sorted { $0.name < $1.name },
            languages: langs.sorted { $0.name < $1.name },
            metaWarnings: metaWarnings,
            shouldScheduleRevalidate: policy.shouldScheduleRevalidate
        )
    }
}

/// Маппинг ошибок загрузки в user-facing текст (Application)
public enum CatalogErrorMapper {
    public static func userMessage(for error: Error) -> String {
        if error is CancellationError {
            return "Загрузка плейлиста отменена."
        }
        if let playlist = error as? PlaylistFetchError {
            return playlist.userMessage
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Превышено время ожидания сервера плейлиста."
            case .notConnectedToInternet, .networkConnectionLost:
                return "Нет подключения к интернету. Проверьте сеть."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Не удалось подключиться к серверу плейлиста."
            case .cancelled:
                return "Загрузка плейлиста отменена."
            default:
                break
            }
        }
        let raw = Stream.maskURLs(in: error.localizedDescription)
        return "Ошибка загрузки плейлиста: \(raw)"
    }
}
