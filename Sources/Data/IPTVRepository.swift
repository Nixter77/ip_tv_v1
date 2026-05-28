// Sources/Data/IPTVRepository.swift
import Foundation

/// Протокол репозитория для загрузки сырых данных из сети
public protocol IPTVRepositoryProtocol: Sendable {
    /// Получить все доступные каналы
    func fetchChannels() async throws -> [Channel]
    
    /// Получить все стриминговые потоки
    func fetchStreams() async throws -> [Stream]
    
    /// Получить категории каналов
    func fetchCategories() async throws -> [Category]
    
    /// Получить страны вещания
    func fetchCountries() async throws -> [Country]
    
    /// Получить языки вещания
    func fetchLanguages() async throws -> [Language]
}

/// Вспомогательная структура для безопасного декодирования элементов массива.
/// Предотвращает падение декодирования всего массива при наличии одного поврежденного элемента.
private struct SafeDecodable<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            self.value = try container.decode(Element.self)
        } catch {
            // Мягко подавляем ошибку декодирования отдельного элемента
            self.value = nil
        }
    }
}

/// Реализация IPTVRepository с использованием URLSession и Safe JSON парсинга.
public final class IPTVRepository: IPTVRepositoryProtocol {
    private let session: URLSession

    /// Инициализатор репозитория
    /// - Parameter session: URLSession для выполнения запросов
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Вспомогательный метод для загрузки и безопасного декодирования данных
    private func fetchAndDecodeSafeArray<T: Decodable>(from urlString: String) async throws -> [T] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Используем SafeDecodable для фильтрации битых записей без сбоя всего массива
        let safeElements = try JSONDecoder().decode([SafeDecodable<T>].self, from: data)
        return safeElements.compactMap { $0.value }
    }

    /// Получить все доступные каналы
    public func fetchChannels() async throws -> [Channel] {
        return try await fetchAndDecodeSafeArray(from: "https://iptv-org.github.io/api/channels.json")
    }

    /// Получить все стриминговые потоки
    public func fetchStreams() async throws -> [Stream] {
        return try await fetchAndDecodeSafeArray(from: "https://iptv-org.github.io/api/streams.json")
    }

    /// Получить категории каналов
    public func fetchCategories() async throws -> [Category] {
        return try await fetchAndDecodeSafeArray(from: "https://iptv-org.github.io/api/categories.json")
    }

    /// Получить страны вещания
    public func fetchCountries() async throws -> [Country] {
        return try await fetchAndDecodeSafeArray(from: "https://iptv-org.github.io/api/countries.json")
    }

    /// Получить языки вещания
    public func fetchLanguages() async throws -> [Language] {
        return try await fetchAndDecodeSafeArray(from: "https://iptv-org.github.io/api/languages.json")
    }
}
