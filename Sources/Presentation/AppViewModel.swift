// Sources/Presentation/AppViewModel.swift
import Foundation
import SwiftUI
import Combine
import SwiftData

/// Состояния загрузки данных приложения
public enum AppLoadingState: Equatable {
    case loading
    case ready
    case error(String)
}

/// Выбор вкладки в Sidebar (Codable для сохранения между сессиями)
public enum SidebarTab: Codable, Hashable, Sendable, Equatable {
    case all
    case category(String)
    case country(String)
    case language(String)
    case favorites
    case history
}

/// Главная ViewModel приложения IPTV с поддержкой SwiftData персистентности и настроек сессии
@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var loadingState: AppLoadingState = .loading
    @Published public var searchQuery: String = "" {
        didSet { saveSettings() }
    }
    @Published public var selectedTab: SidebarTab = .all {
        didSet { saveSettings() }
    }
    @Published public private(set) var filteredChannels: [Channel] = []
    
    @Published public private(set) var categories: [Category] = []
    @Published public private(set) var countries: [Country] = []
    @Published public private(set) var languages: [Language] = []
    
    // Списки для Избранного и Истории
    @Published public private(set) var favoriteIds: Set<String> = []
    @Published public private(set) var historyIds: [String] = []
    @Published public var isPlayerDetached: Bool = false
    
    public let repository: IPTVRepositoryProtocol
    public let filterEngine: ChannelFilterEngineProtocol
    public let playerManager: PlayerStateManagerProtocol
    
    // SwiftData
    private let modelContainer: ModelContainer?
    private var modelContext: ModelContext? {
        modelContainer?.mainContext
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Инициализатор AppViewModel
    /// - Parameters:
    ///   - repository: Репозиторий
    ///   - filterEngine: Движок фильтрации
    ///   - playerManager: Менеджер воспроизведения
    ///   - modelContainer: SwiftData контейнер (опциональный для гибкости и тестирования)
    public init(
        repository: IPTVRepositoryProtocol,
        filterEngine: ChannelFilterEngineProtocol,
        playerManager: PlayerStateManagerProtocol,
        modelContainer: ModelContainer? = nil
    ) {
        self.repository = repository
        self.filterEngine = filterEngine
        self.playerManager = playerManager
        self.modelContainer = modelContainer
        
        restoreSettings()
        restorePersistedData()
        setupBindings()
    }
    
    /// Настройка Combine-биндингов для автоматического обновления фильтрации
    private func setupBindings() {
        Publishers.CombineLatest3($searchQuery, $selectedTab, $favoriteIds)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                Task {
                    await self?.updateFilteredChannels()
                }
            }
            .store(in: &cancellables)
            
        playerManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    /// Загрузить данные из репозитория и проинициализировать движок фильтрации
    public func loadData() async {
        self.loadingState = .loading
        do {
            let (channels, streams, cats, ctrs, langs) = try await Task.detached(priority: .userInitiated) {
                async let channelsFetch = self.repository.fetchChannels()
                async let streamsFetch = self.repository.fetchStreams()
                async let catsFetch = self.repository.fetchCategories()
                async let ctrsFetch = self.repository.fetchCountries()
                async let langsFetch = self.repository.fetchLanguages()
                
                return try await (channelsFetch, streamsFetch, catsFetch, ctrsFetch, langsFetch)
            }.value
            
            await filterEngine.setup(channels: channels, streams: streams)
            
            self.categories = cats.sorted { $0.name < $1.name }
            self.countries = ctrs.sorted { $0.name < $1.name }
            self.languages = langs.sorted { $0.name < $1.name }
            
            await updateFilteredChannels()
            
            self.loadingState = .ready
        } catch {
            let errorMsg = Stream.maskURLs(in: error.localizedDescription)
            self.loadingState = .error("Ошибка загрузки плейлиста: \(errorMsg)")
        }
    }
    
    /// Перезагрузить плейлист из сети
    public func reloadPlaylist() async {
        await loadData()
    }
    
    /// Обновление списка отфильтрованных каналов через FilterEngine
    private func updateFilteredChannels() async {
        var categoryFilter: String?
        var countryFilter: String?
        var languageFilter: String?
        
        switch selectedTab {
        case .all:
            break
        case .category(let name):
            categoryFilter = name
        case .country(let code):
            countryFilter = code
        case .language(let code):
            languageFilter = code
        case .favorites:
            let allChannels = await filterEngine.filter(query: searchQuery, category: nil, country: nil, language: nil)
            self.filteredChannels = allChannels.filter { favoriteIds.contains($0.id) }
            return
        case .history:
            let allChannels = await filterEngine.filter(query: searchQuery, category: nil, country: nil, language: nil)
            let channelMap = Dictionary(uniqueKeysWithValues: allChannels.map { ($0.id, $0) })
            self.filteredChannels = historyIds.compactMap { channelMap[$0] }
            return
        }
        
        self.filteredChannels = await filterEngine.filter(
            query: searchQuery,
            category: categoryFilter,
            country: countryFilter,
            language: languageFilter
        )
    }
    
    /// Начать воспроизведение выбранного канала
    public func play(channel: Channel) async {
        addToHistory(channel: channel)
        
        let streams = await filterEngine.streams(for: channel.id)
        await playerManager.play(channel: channel, streams: streams)
    }
    
    /// Переключение флага избранного канала с персистентным сохранением
    public func toggleFavorite(channelId: String) {
        if favoriteIds.contains(channelId) {
            favoriteIds.remove(channelId)
            updatePersistedFavorite(channelId: channelId, name: "", isFavorite: false)
        } else {
            favoriteIds.insert(channelId)
            let channelName = filteredChannels.first(where: { $0.id == channelId })?.name ?? "Канал"
            updatePersistedFavorite(channelId: channelId, name: channelName, isFavorite: true)
        }
    }
    
    // MARK: - SwiftData Логика персистентности

    /// Восстановление избранного и истории из SwiftData БД
    private func restorePersistedData() {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<PersistedChannel>()
            let items = try context.fetch(descriptor)
            
            // Восстанавливаем Избранное
            let favorites = items.compactMap { $0.isFavorite ? $0.id : nil }
            self.favoriteIds = Set(favorites)
            
            // Восстанавливаем Историю (сортируем по дате просмотра от свежих к старым)
            let history = items.compactMap { $0.lastViewedAt != nil ? $0 : nil }
                .sorted { ($0.lastViewedAt ?? Date.distantPast) > ($1.lastViewedAt ?? Date.distantPast) }
                .map { $0.id }
            
            // Ограничиваем историю 50 элементами по ТЗ
            self.historyIds = Array(history.prefix(50))
        } catch {
            print("Не удалось прочитать данные из SwiftData: \(error)")
        }
    }

    /// Сохранение или удаление избранного статуса в SwiftData
    private func updatePersistedFavorite(channelId: String, name: String, isFavorite: Bool) {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<PersistedChannel>(predicate: #Predicate { $0.id == channelId })
            let items = try context.fetch(descriptor)
            
            if let existing = items.first {
                existing.isFavorite = isFavorite
                // Если больше не в избранном и никогда не просматривался, удаляем запись целиком
                if !isFavorite && existing.lastViewedAt == nil {
                    context.delete(existing)
                }
            } else if isFavorite {
                let newPersisted = PersistedChannel(id: channelId, name: name, isFavorite: true)
                context.insert(newPersisted)
            }
            try context.save()
        } catch {
            print("Ошибка при записи избранного в SwiftData: \(error)")
        }
    }

    /// Добавление просмотра канала в историю в памяти и SwiftData
    private func addToHistory(channel: Channel) {
        let channelId = channel.id
        
        // 1. Обновляем в памяти
        if let index = historyIds.firstIndex(of: channelId) {
            historyIds.remove(at: index)
        }
        historyIds.insert(channelId, at: 0)
        if historyIds.count > 50 {
            historyIds.removeLast()
        }
        
        // 2. Обновляем в SwiftData
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<PersistedChannel>(predicate: #Predicate { $0.id == channelId })
            let items = try context.fetch(descriptor)
            
            if let existing = items.first {
                existing.lastViewedAt = Date()
            } else {
                let newPersisted = PersistedChannel(id: channelId, name: channel.name, isFavorite: false, lastViewedAt: Date())
                context.insert(newPersisted)
            }
            try context.save()
        } catch {
            print("Ошибка при записи истории в SwiftData: \(error)")
        }
    }
    
    // MARK: - UserDefaults Логика настроек сессии

    /// Сохранение выбранных фильтров в UserDefaults
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(selectedTab) {
            UserDefaults.standard.set(encoded, forKey: "lastSelectedTab")
        }
        UserDefaults.standard.set(searchQuery, forKey: "lastSearchQuery")
    }
    
    /// Восстановление фильтров из UserDefaults при старте
    private func restoreSettings() {
        if let data = UserDefaults.standard.data(forKey: "lastSelectedTab"),
           let decoded = try? JSONDecoder().decode(SidebarTab.self, from: data) {
            self.selectedTab = decoded
        }
        if let query = UserDefaults.standard.string(forKey: "lastSearchQuery") {
            self.searchQuery = query
        }
    }
}
