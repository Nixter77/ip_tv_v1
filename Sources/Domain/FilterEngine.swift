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
    /// Кэшированный набор символов для токенизации (избегаем повторных аллокаций CharacterSet.alphanumerics.inverted)
    private static let nonAlphanumerics = CharacterSet.alphanumerics.inverted

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
    
    // Кэшированные наборы ID каналов, соответствующие sortedTokens (1:1), для исключения lookup-ов в словаре
    private var tokenSets: [Set<String>] = []

    // Предварительно отсортированный список всех активных каналов (для мгновенного возврата при отсутствии фильтров)
    private var allChannelsSorted: [Channel] = []

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
        self.tokenSets.removeAll(keepingCapacity: true)

        // 1. Фильтруем и индексируем рабочие потоки (исключаем status == "error")
        for stream in streams {
            guard stream.status != "error" else { continue }
            self.activeStreams[stream.channel, default: []].append(stream)
        }

        // 2. Индексируем каналы
        let nonAlphanumerics = Self.nonAlphanumerics
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
                .components(separatedBy: nonAlphanumerics)
                .filter { !$0.isEmpty }
            for token in tokens {
                self.channelIdsByNameToken[token, default: []].insert(channel.id)
            }
        }
        
        // Сортируем токены один раз при старте для обеспечения O(log N) поиска
        self.sortedTokens = channelIdsByNameToken.keys.sorted()

        // Кэшируем соответствующие наборы ID в массив для мгновенного доступа по индексу (O(1))
        self.tokenSets = sortedTokens.compactMap { channelIdsByNameToken[$0] }

        // Кэшируем отсортированный список всех каналов
        self.allChannelsSorted = self.channels.values.sorted { $0.name < $1.name }
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
        // Оптимизация: мгновенный возврат кэшированного списка, если фильтры не заданы
        let hasFilters = (query != nil && !query!.isEmpty) ||
                         (category != nil && !category!.isEmpty) ||
                         (country != nil && !country!.isEmpty) ||
                         (language != nil && !language!.isEmpty)

        if !hasFilters {
            return allChannelsSorted
        }

        var resultSet: Set<String>? = nil
        
        // 1. Фильтр по категории
        if let category = category, !category.isEmpty {
            resultSet = channelsByCategory[category.lowercased()] ?? []
            if resultSet?.isEmpty == true { return [] }
        }
        
        // 2. Фильтр по стране
        if let country = country, !country.isEmpty {
            let countrySet = channelsByCountry[country.uppercased()] ?? []
            if var current = resultSet {
                current.formIntersection(countrySet)
                resultSet = current
            } else {
                resultSet = countrySet
            }
            if resultSet?.isEmpty == true { return [] }
        }
        
        // 3. Фильтр по языку
        if let language = language, !language.isEmpty {
            let langSet = channelsByLanguage[language.lowercased()] ?? []
            if var current = resultSet {
                current.formIntersection(langSet)
                resultSet = current
            } else {
                resultSet = langSet
            }
            if resultSet?.isEmpty == true { return [] }
        }
        
        // 4. Текстовый поиск по токенам и префиксам с двоичным поиском
        if let query = query, !query.isEmpty {
            let queryTokens = query.foldedForSearch()
                .components(separatedBy: Self.nonAlphanumerics)
                .filter { !$0.isEmpty }
            
            var tokenIntersection: Set<String>? = nil
            for token in queryTokens {
                var matchesForToken = Set<String>()
                
                // Используем сверхбыстрый двоичный поиск для префиксов
                if let range = findTokenRange(startingWith: token) {
                    for index in range {
                        // Оптимизация: используем прямой доступ к кэшированным наборам ID по индексу (O(1))
                        // Это быстрее, чем lookup в словаре channelIdsByNameToken[sortedTokens[index]]
                        let ids = tokenSets[index]
                        matchesForToken.formUnion(ids)
                    }
                }

                // Ранний выход, если по текущему токену ничего не найдено
                if matchesForToken.isEmpty { return [] }
                
                if var current = tokenIntersection {
                    current.formIntersection(matchesForToken)
                    tokenIntersection = current
                    // Ранний выход, если пересечение стало пустым
                    if tokenIntersection?.isEmpty == true { return [] }
                } else {
                    tokenIntersection = matchesForToken
                }
            }
            
            if let searchSet = tokenIntersection {
                if var current = resultSet {
                    current.formIntersection(searchSet)
                    resultSet = current
                } else {
                    resultSet = searchSet
                }
            } else {
                return []
            }
            if resultSet?.isEmpty == true { return [] }
        }
        
        // Если никакие фильтры не применялись
        guard let finalIds = resultSet else {
            return allChannelsSorted
        }
        
        // Оптимизация: вместо compactMap + sorted (O(M log M)),
        // фильтруем уже отсортированный массив всех каналов за O(N).
        return allChannelsSorted.filter { finalIds.contains($0.id) }
    }

    /// Получить все доступные потоки для конкретного канала
    /// - Parameter channelId: Идентификатор канала
    /// - Returns: Список потоков
    public func streams(for channelId: String) async -> [Stream] {
        return activeStreams[channelId] ?? []
    }
}
