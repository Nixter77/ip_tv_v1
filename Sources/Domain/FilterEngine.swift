// Sources/Domain/FilterEngine.swift
import Foundation

/// Расширение для быстрого свертывания диакритических знаков и приведения к нижнему регистру
private extension String {
    func foldedForSearch() -> String {
        return self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

/// Быстрый движок фильтрации по 50k каналам (оборудован для Concurrency)
public protocol ChannelFilterEngineProtocol: Sendable {
    /// Инициализация движка набором каналов и потоков
    func setup(channels: [Channel], streams: [Stream], generation: UInt64) async
    
    /// Фильтрация с использованием предвычисленных индексов (< 50мс)
    /// - Parameter restrictedTo: Опциональное множество ID (избранное и т.п.) — фильтр применяется только внутри него
    func filter(
        query: String?,
        category: String?,
        country: String?,
        language: String?,
        restrictedTo: Set<String>?
    ) async -> [Channel]
    
    /// Получить все доступные потоки для конкретного канала
    func streams(for channelId: String) async -> [Stream]
    
    /// Каналы по ID с сохранением порядка (история просмотров)
    func channels(preservingOrder ids: [String]) async -> [Channel]
}

public extension ChannelFilterEngineProtocol {
    func setup(channels: [Channel], streams: [Stream]) async {
        await setup(channels: channels, streams: streams, generation: 0)
    }

    /// Удобный overload без ограничения по ID
    func filter(
        query: String?,
        category: String?,
        country: String?,
        language: String?
    ) async -> [Channel] {
        await filter(
            query: query,
            category: category,
            country: country,
            language: language,
            restrictedTo: nil
        )
    }
}

/// Высокопроизводительная реализация ChannelFilterEngine в виде Swift Actor.
/// Использует инвертированные индексы на основе словарей, множеств и двоичного поиска для мгновенного выполнения запросов.
public actor ChannelFilterEngine: ChannelFilterEngineProtocol {
    /// Кэшированный набор символов для токенизации (избегаем повторных аллокаций CharacterSet.alphanumerics.inverted)
    private static let nonAlphanumerics = CharacterSet.alphanumerics.inverted

    /// Порог: при |result| ниже — materialize через dict + sort (O(M log M)); иначе — scan sorted list (O(N))
    private static let adaptiveMaterializeThresholdRatio = 0.05
    private static let adaptiveMaterializeAbsoluteCap = 2_000

    // Первичные данные
    private var channels: [String: Channel] = [:]
    private var activeStreams: [String: [Stream]] = [:] // key: channelId

    // Индексы быстрого доступа
    private var channelsByCategory: [String: Set<String>] = [:] // categoryId -> Set<channelId>
    private var channelsByCountry: [String: Set<String>] = [:]  // countryCode -> Set<channelId>
    private var channelsByLanguage: [String: Set<String>] = [:] // languageCode -> Set<channelId>
    
    // Отсортированный массив токенов для сверхбыстрого двоичного поиска по префиксу
    private var sortedTokens: [String] = []
    
    // Кэшированные наборы ID каналов, соответствующие sortedTokens (1:1)
    private var tokenSets: [Set<String>] = []

    // Предварительно отсортированный список всех активных каналов
    private var allChannelsSorted: [Channel] = []
    /// Newer catalog loads win; stale cancelled setups do not replace the index.
    private var appliedGeneration: UInt64 = 0

    public init() {}

    /// Инициализация движка: индексы собираются в локальные структуры и атомарно подменяются в конце
    public func setup(channels: [Channel], streams: [Stream], generation: UInt64 = 0) async {
        var newChannels: [String: Channel] = [:]
        var newActiveStreams: [String: [Stream]] = [:]
        var newByCategory: [String: Set<String>] = [:]
        var newByCountry: [String: Set<String>] = [:]
        var newByLanguage: [String: Set<String>] = [:]
        var tokenIndex: [String: Set<String>] = [:]

        newChannels.reserveCapacity(channels.count)
        newActiveStreams.reserveCapacity(min(streams.count, channels.count))

        // 1. Фильтруем и индексируем рабочие потоки (исключаем status == "error")
        for stream in streams {
            guard stream.status != "error" else { continue }
            newActiveStreams[stream.channel, default: []].append(stream)
        }

        // 2. Индексируем каналы
        let nonAlphanumerics = Self.nonAlphanumerics
        for (index, channel) in channels.enumerated() {
            if index % 2000 == 0 {
                if Task.isCancelled { return }
            }
            guard newActiveStreams[channel.id] != nil else { continue }
            
            newChannels[channel.id] = channel
            
            for category in channel.categories {
                newByCategory[category.lowercased(), default: []].insert(channel.id)
            }
            
            if let country = channel.country {
                newByCountry[country.uppercased(), default: []].insert(channel.id)
            }
            
            for lang in channel.languages {
                newByLanguage[lang.lowercased(), default: []].insert(channel.id)
            }
            
            let tokens = channel.name.foldedForSearch()
                .components(separatedBy: nonAlphanumerics)
                .filter { !$0.isEmpty }
            for token in tokens {
                tokenIndex[token, default: []].insert(channel.id)
            }
        }
        
        // Сортируем токены один раз; после построения tokenSets словарь tokenIndex не храним
        let newSortedTokens = tokenIndex.keys.sorted()
        let newTokenSets = newSortedTokens.map { tokenIndex[$0] ?? [] }
        let newAllSorted = newChannels.values.sorted { $0.name < $1.name }

        if generation > 0, generation < appliedGeneration {
            return
        }

        // Атомарная подмена состояния актора
        if generation > 0 {
            appliedGeneration = generation
        }
        self.channels = newChannels
        self.activeStreams = newActiveStreams
        self.channelsByCategory = newByCategory
        self.channelsByCountry = newByCountry
        self.channelsByLanguage = newByLanguage
        self.sortedTokens = newSortedTokens
        self.tokenSets = newTokenSets
        self.allChannelsSorted = newAllSorted
    }

    /// Вспомогательный метод для двоичного поиска токенов с заданным префиксом.
    /// Работает за O(log K) вместо O(K) линейного поиска.
    private func findTokenRange(startingWith prefix: String) -> Range<Int>? {
        var low = 0
        var high = sortedTokens.count
        
        while low < high {
            let mid = (low + high) / 2
            if sortedTokens[mid] < prefix {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        let start = low
        guard start < sortedTokens.count, sortedTokens[start].hasPrefix(prefix) else {
            return nil
        }

        low = start
        high = sortedTokens.count
        while low < high {
            let mid = (low + high) / 2
            if sortedTokens[mid].hasPrefix(prefix) {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return start..<low
    }

    /// Intersect `resultSet` with `other`. Returns true when the result is empty.
    private func intersect(_ resultSet: inout Set<String>?, with other: Set<String>) -> Bool {
        if var current = resultSet {
            current.formIntersection(other)
            resultSet = current
        } else {
            resultSet = other
        }
        return resultSet?.isEmpty == true
    }

    /// Материализация множества ID в отсортированный список каналов.
    /// Малые результаты: O(M log M) через словарь; большие: O(N) scan уже отсортированного массива.
    private func materialize(_ finalIds: Set<String>) -> [Channel] {
        let n = allChannelsSorted.count
        guard !finalIds.isEmpty, n > 0 else { return [] }

        let threshold = min(
            Self.adaptiveMaterializeAbsoluteCap,
            max(1, Int(Double(n) * Self.adaptiveMaterializeThresholdRatio))
        )

        if finalIds.count <= threshold {
            var result: [Channel] = []
            result.reserveCapacity(finalIds.count)
            for id in finalIds {
                if let channel = channels[id] {
                    result.append(channel)
                }
            }
            result.sort { $0.name < $1.name }
            return result
        }

        return allChannelsSorted.filter { finalIds.contains($0.id) }
    }

    /// Собирает ID, чьи name-токены начинаются с prefix; при наличии universe — только пересечение (дешевле на коротких префиксах).
    private func channelIdsMatchingToken(_ token: String, within universe: Set<String>?) -> Set<String> {
        guard let range = findTokenRange(startingWith: token) else {
            return []
        }

        var matches = Set<String>()
        if let universe = universe {
            // Раннее пересечение: не раздуваем union на весь корпус
            for index in range {
                matches.formUnion(tokenSets[index].intersection(universe))
                if matches.count == universe.count {
                    // Все ID из universe уже покрыты — дальше union бесполезен
                    break
                }
            }
        } else {
            for index in range {
                matches.formUnion(tokenSets[index])
            }
        }
        return matches
    }

    public func filter(
        query: String?,
        category: String?,
        country: String?,
        language: String?,
        restrictedTo: Set<String>?
    ) async -> [Channel] {
        let hasFilters = !(query ?? "").isEmpty ||
                         !(category ?? "").isEmpty ||
                         !(country ?? "").isEmpty ||
                         !(language ?? "").isEmpty ||
                         restrictedTo != nil

        if !hasFilters {
            return allChannelsSorted
        }

        // Ограничение по ID (избранное и т.д.) — стартовое множество
        var resultSet: Set<String>? = restrictedTo.map { Set($0) }
        if let restricted = resultSet, restricted.isEmpty {
            return []
        }
        
        if let category = category, !category.isEmpty {
            if intersect(&resultSet, with: channelsByCategory[category.lowercased()] ?? []) { return [] }
        }
        if let country = country, !country.isEmpty {
            if intersect(&resultSet, with: channelsByCountry[country.uppercased()] ?? []) { return [] }
        }
        if let language = language, !language.isEmpty {
            if intersect(&resultSet, with: channelsByLanguage[language.lowercased()] ?? []) { return [] }
        }
        
        // 4. Текстовый поиск: пересечение токенов; universe сужает union на коротких префиксах
        if let query = query, !query.isEmpty {
            let queryTokens = query.foldedForSearch()
                .components(separatedBy: Self.nonAlphanumerics)
                .filter { !$0.isEmpty }
            
            if queryTokens.isEmpty {
                return []
            }

            var tokenIntersection: Set<String>? = nil
            for token in queryTokens {
                // Universe = уже накопленный результат фильтров + предыдущих токенов
                let universe = tokenIntersection ?? resultSet
                let matchesForToken = channelIdsMatchingToken(token, within: universe)

                if matchesForToken.isEmpty { return [] }
                if intersect(&tokenIntersection, with: matchesForToken) { return [] }
            }
            
            if let searchSet = tokenIntersection {
                if intersect(&resultSet, with: searchSet) { return [] }
            } else {
                return []
            }
        }
        
        guard let finalIds = resultSet else {
            return allChannelsSorted
        }
        
        return materialize(finalIds)
    }

    public func streams(for channelId: String) async -> [Stream] {
        return activeStreams[channelId] ?? []
    }

    public func channels(preservingOrder ids: [String]) async -> [Channel] {
        var result: [Channel] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            if let channel = channels[id] {
                result.append(channel)
            }
        }
        return result
    }
}
