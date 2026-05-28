// Sources/Domain/FilterEngine.swift
import Foundation

/// Расширение для быстрого свертывания диакритических знаков и приведения к нижнему регистру
private extension String {
    func foldedForSearch() -> String {
        return self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

/// Быстрый движок фильтрации по 50k каналам (оборудован для Concurrency)
public protocol ChannelFilterEngineProtocol: Sendable {
    /// Инициализация движка набором каналов и потоков
    func setup(channels: [Channel], streams: [Stream]) async
    
    /// Фильтрация с использованием предвычисленных индексов (< 50мс)
    func filter(
        query: String?,
        category: String?,
        country: String?,
        language: String?
    ) async -> [Channel]
    
    /// Получить все доступные потоки для конкретного канала
    func streams(for channelId: String) async -> [Stream]
}

/// Высокопроизводительная реализация ChannelFilterEngine в виде Swift Actor.
/// Использует инвертированные индексы на основе словарей, множеств и двоичного поиска для мгновенного выполнения запросов.
public actor ChannelFilterEngine: ChannelFilterEngineProtocol {
    // Первичные данные
    private var channels: [String: Channel] = [:]
    private var activeStreams: [String: [Stream]] = [:] // key: channelId

    // Индексы быстрого доступа
    private var channelsByCategory: [String: Set<String>] = [:] // categoryId -> Set<channelId>
    private var channelsByCountry: [String: Set<String>] = [:]  // countryCode -> Set<channelId>
    private var channelsByLanguage: [String: Set<String>] = [:] // languageCode -> Set<channelId>
    
    // Индекс текстового поиска (токенизированные слова в нижнем регистре с вычищенной диакритикой)
    private var channelIdsByNameToken: [String: Set<String>] = [:] // token -> Set<channelId>
    
    // Отсортированный массив токенов для сверхбыстрого двоичного поиска по префиксу
    private var sortedTokens: [String] = []
    
    public init() {}

    /// Инициализация движка набором каналов и потоков и построение индексов в памяти
    /// - Parameters:
    ///   - channels: Список всех каналов
    ///   - streams: Список всех потоков
    public func setup(channels: [Channel], streams: [Stream]) async {
        self.channels.removeAll(keepingCapacity: true)
        self.activeStreams.removeAll(keepingCapacity: true)
        self.channelsByCategory.removeAll(keepingCapacity: true)
        self.channelsByCountry.removeAll(keepingCapacity: true)
        self.channelsByLanguage.removeAll(keepingCapacity: true)
        self.channelIdsByNameToken.removeAll(keepingCapacity: true)
        self.sortedTokens.removeAll(keepingCapacity: true)

        // 1. Фильтруем и индексируем рабочие потоки (исключаем status == "error")
        for stream in streams {
            guard stream.status != "error" else { continue }
            self.activeStreams[stream.channel, default: []].append(stream)
        }

        // 2. Индексируем каналы
        for channel in channels {
            // Оставляем только те каналы, у которых есть хотя бы один рабочий поток
            guard self.activeStreams[channel.id] != nil else { continue }
            
            self.channels[channel.id] = channel
            
            // Категории
            for category in channel.categories {
                self.channelsByCategory[category.lowercased(), default: []].insert(channel.id)
            }
            
            // Страна
            if let country = channel.country {
                self.channelsByCountry[country.uppercased(), default: []].insert(channel.id)
            }
            
            // Языки
            for lang in channel.languages {
                self.channelsByLanguage[lang.lowercased(), default: []].insert(channel.id)
            }
            
            // Токенизация названия для поиска (диакритика вырезается)
            let tokens = channel.name.foldedForSearch()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            for token in tokens {
                self.channelIdsByNameToken[token, default: []].insert(channel.id)
            }
        }
        
        // Сортируем токены один раз при старте для обеспечения O(log N) поиска
        self.sortedTokens = channelIdsByNameToken.keys.sorted()
    }

    /// Вспомогательный метод для двоичного поиска токенов с заданным префиксом.
    /// Работает за O(log K) вместо O(K) линейного поиска.
    private func findTokens(startingWith prefix: String) -> [String] {
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
        
        var results: [String] = []
        var index = low
        while index < sortedTokens.count {
            let token = sortedTokens[index]
            if token.hasPrefix(prefix) {
                results.append(token)
                index += 1
            } else {
                break
            }
        }
        return results
    }

    /// Фильтрация с использованием предвычисленных индексов (< 50мс)
    /// - Parameters:
    ///   - query: Текстовый поисковый запрос
    ///   - category: Выбранная категория
    ///   - country: Выбранная страна
    ///   - language: Выбранный язык
    /// - Returns: Список отфильтрованных и отсортированных каналов
    public func filter(
        query: String?,
        category: String?,
        country: String?,
        language: String?
    ) async -> [Channel] {
        var resultSet: Set<String>? = nil
        
        let intersect: (Set<String>) -> Void = { set in
            if let current = resultSet {
                resultSet = current.intersection(set)
            } else {
                resultSet = set
            }
        }
        
        // 1. Фильтр по категории
        if let category = category, !category.isEmpty {
            let catSet = channelsByCategory[category.lowercased()] ?? []
            intersect(catSet)
            if resultSet?.isEmpty == true { return [] }
        }
        
        // 2. Фильтр по стране
        if let country = country, !country.isEmpty {
            let countrySet = channelsByCountry[country.uppercased()] ?? []
            intersect(countrySet)
            if resultSet?.isEmpty == true { return [] }
        }
        
        // 3. Фильтр по языку
        if let language = language, !language.isEmpty {
            let langSet = channelsByLanguage[language.lowercased()] ?? []
            intersect(langSet)
            if resultSet?.isEmpty == true { return [] }
        }
        
        // 4. Текстовый поиск по токенам и префиксам с двоичным поиском
        if let query = query, !query.isEmpty {
            let queryTokens = query.foldedForSearch()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            
            var tokenIntersection: Set<String>? = nil
            for token in queryTokens {
                var tokenSet = Set<String>()
                
                // Используем сверхбыстрый двоичный поиск для префиксов
                let matchingTokens = findTokens(startingWith: token)
                var unionIds: [String] = []
                for matchingToken in matchingTokens {
                    if let ids = channelIdsByNameToken[matchingToken] {
                        unionIds.append(contentsOf: ids)
                    }
                }
                tokenSet = Set(unionIds)
                
                if let current = tokenIntersection {
                    tokenIntersection = current.intersection(tokenSet)
                } else {
                    tokenIntersection = tokenSet
                }
            }
            
            if let searchSet = tokenIntersection {
                intersect(searchSet)
            } else {
                return []
            }
            if resultSet?.isEmpty == true { return [] }
        }
        
        // Если никакие фильтры не применялись
        let finalIds = resultSet ?? Set(channels.keys)
        
        return finalIds.compactMap { channels[$0] }
            .sorted { $0.name < $1.name }
    }

    /// Получить все доступные потоки для конкретного канала
    /// - Parameter channelId: Идентификатор канала
    /// - Returns: Список потоков
    public func streams(for channelId: String) async -> [Stream] {
        return activeStreams[channelId] ?? []
    }
}
