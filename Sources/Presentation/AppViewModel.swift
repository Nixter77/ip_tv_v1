#if canImport(Combine) && canImport(SwiftData)
// Sources/Presentation/AppViewModel.swift
// Thin presentation state: maps Application use cases + ports → @Published UI state.
import Foundation
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

/// Главная ViewModel — presentation only (orchestration via use cases / ports)
@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var loadingState: AppLoadingState = .loading
    @Published public var searchQuery: String = ""
    @Published public var selectedTab: SidebarTab = .all
    @Published public private(set) var filteredChannels: [Channel] = []
    
    @Published public private(set) var categories: [Category] = []
    @Published public private(set) var countries: [Country] = []
    @Published public private(set) var languages: [Language] = []
    
    @Published public private(set) var favoriteIds: Set<String> = []
    @Published public private(set) var historyIds: [String] = []
    @Published public var isPlayerDetached: Bool = false

    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var statusBanner: String? = nil
    
    public let filterEngine: any ChannelFilterEngineProtocol
    /// Concrete adapter for SwiftUI @ObservedObject + avPlayer surface
    public let playerManager: PlayerStateManager

    private let loadCatalog: LoadCatalogUseCase
    private let userLibrary: any UserLibraryRepository
    private let libraryAvailable: Bool
    
    private var cancellables = Set<AnyCancellable>()
    private var filterTask: Task<Void, Never>?
    private var revalidateTask: Task<Void, Never>?
    /// Serializes catalog loads so soft reload + background revalidate cannot race UI state
    private var loadTask: Task<Void, Never>?
    private var lastReloadAt: Date?
    private let reloadCooldown: TimeInterval = 5

    private var hasCatalog: Bool {
        if case .ready = loadingState { return true }
        return false
    }
    
    public init(
        repository: any PlaylistRepository,
        filterEngine: any ChannelFilterEngineProtocol,
        playerManager: PlayerStateManager,
        userLibrary: any UserLibraryRepository,
        libraryAvailable: Bool = true,
        persistenceUnavailableMessage: String? = nil
    ) {
        self.filterEngine = filterEngine
        self.playerManager = playerManager
        self.loadCatalog = LoadCatalogUseCase(repository: repository, filterEngine: filterEngine)
        self.userLibrary = userLibrary
        self.libraryAvailable = libraryAvailable
        
        if let persistenceUnavailableMessage {
            self.statusBanner = persistenceUnavailableMessage
        }
        
        restoreSettings()
        Task { await self.restoreLibrary() }
        setupBindings()
    }

    /// Convenience for App composition + tests with optional ModelContainer
    public convenience init(
        repository: any PlaylistRepository,
        filterEngine: any ChannelFilterEngineProtocol,
        playerManager: PlayerStateManager,
        modelContainer: ModelContainer? = nil,
        persistenceUnavailableMessage: String? = nil
    ) {
        let library: any UserLibraryRepository
        let available: Bool
        if let container = modelContainer {
            library = SwiftDataUserLibraryRepository.make(modelContainer: container)
            available = true
        } else {
            library = InMemoryUserLibraryRepository()
            available = false
        }
        self.init(
            repository: repository,
            filterEngine: filterEngine,
            playerManager: playerManager,
            userLibrary: library,
            libraryAvailable: available,
            persistenceUnavailableMessage: persistenceUnavailableMessage
        )
    }
    
    private func setupBindings() {
        Publishers.CombineLatest(
            $searchQuery
                .removeDuplicates()
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main),
            $selectedTab
                .removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.saveSettings()
            self?.scheduleFilteredChannelsUpdate()
        }
        .store(in: &cancellables)

        $favoriteIds
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if case .favorites = self.selectedTab {
                    self.scheduleFilteredChannelsUpdate()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleFilteredChannelsUpdate() {
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            await self?.updateFilteredChannels()
        }
    }

    public func dismissStatusBanner() {
        statusBanner = nil
    }
    
    public func loadData(soft: Bool = false) async {
        // Cancel in-flight catalog work (including background revalidate) to avoid race overwrites
        revalidateTask?.cancel()
        revalidateTask = nil
        loadTask?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoadData(soft: soft)
        }
        loadTask = task
        await task.value
    }

    private func performLoadData(soft: Bool) async {
        let keepUI = soft && hasCatalog
        if keepUI {
            isRefreshing = true
        } else {
            loadingState = .loading
        }

        let policy: CatalogLoadPolicy = soft ? .forceNetwork : .cacheFirstThenRevalidate

        do {
            let result = try await loadCatalog.execute(
                policy: policy,
                fallbackCategories: keepUI ? categories : [],
                fallbackCountries: keepUI ? countries : [],
                fallbackLanguages: keepUI ? languages : []
            )

            guard !Task.isCancelled else {
                isRefreshing = false
                return
            }

            categories = result.categories
            countries = result.countries
            languages = result.languages
            loadingState = .ready
            await updateFilteredChannels()
            isRefreshing = false

            if !result.metaWarnings.isEmpty {
                statusBanner = "Не удалось обновить: \(result.metaWarnings.joined(separator: ", ")). Показаны предыдущие/пустые списки."
            }

            if result.shouldScheduleRevalidate {
                scheduleBackgroundRevalidate()
            }
        } catch is CancellationError {
            isRefreshing = false
            // Caller superseded this load — do not paint cancellation as a playlist error
        } catch {
            guard !Task.isCancelled else {
                isRefreshing = false
                return
            }
            isRefreshing = false
            let message = CatalogErrorMapper.userMessage(for: error)
            if keepUI {
                statusBanner = message
            } else {
                loadingState = .error(message)
            }
        }
    }

    private func scheduleBackgroundRevalidate() {
        revalidateTask?.cancel()
        revalidateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.backgroundRevalidate()
        }
    }

    private func backgroundRevalidate() async {
        do {
            let result = try await loadCatalog.execute(
                policy: .backgroundRevalidate,
                fallbackCategories: categories,
                fallbackCountries: countries,
                fallbackLanguages: languages
            )
            guard !Task.isCancelled else { return }
            categories = result.categories
            countries = result.countries
            languages = result.languages
            await updateFilteredChannels()
        } catch is CancellationError {
            // superseded
        } catch {
            // keep current catalog (soft degrade)
        }
    }
    
    public func reloadPlaylist() async {
        if let last = lastReloadAt, Date().timeIntervalSince(last) < reloadCooldown {
            let wait = Int(ceil(reloadCooldown - Date().timeIntervalSince(last)))
            statusBanner = "Подождите \(wait) с перед повторным обновлением"
            return
        }
        lastReloadAt = Date()
        await loadData(soft: hasCatalog)
    }
    
    private func updateFilteredChannels() async {
        var categoryFilter: String?
        var countryFilter: String?
        var languageFilter: String?
        var restrictedTo: Set<String>?
        
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
            restrictedTo = favoriteIds
            if favoriteIds.isEmpty {
                guard !Task.isCancelled else { return }
                self.filteredChannels = []
                return
            }
        case .history:
            let query = searchQuery
            if query.isEmpty {
                let ordered = await filterEngine.channels(preservingOrder: historyIds)
                guard !Task.isCancelled else { return }
                self.filteredChannels = ordered
                return
            }
            let historySet = Set(historyIds)
            let matched = await filterEngine.filter(
                query: query,
                category: nil,
                country: nil,
                language: nil,
                restrictedTo: historySet
            )
            guard !Task.isCancelled else { return }
            let map = Dictionary(uniqueKeysWithValues: matched.map { ($0.id, $0) })
            self.filteredChannels = historyIds.compactMap { map[$0] }
            return
        }
        
        let result = await filterEngine.filter(
            query: searchQuery,
            category: categoryFilter,
            country: countryFilter,
            language: languageFilter,
            restrictedTo: restrictedTo
        )
        guard !Task.isCancelled else { return }
        self.filteredChannels = result
    }
    
    public func play(channel: Channel) async {
        await recordHistory(channel: channel)
        let streams = await filterEngine.streams(for: channel.id)
        await playerManager.play(channel: channel, streams: streams)
    }

    public func retryPlayback() async {
        await playerManager.retry()
    }
    
    public func toggleFavorite(channelId: String) {
        if favoriteIds.contains(channelId) {
            favoriteIds.remove(channelId)
            persistFavorite(id: channelId, name: "", isFavorite: false)
        } else {
            favoriteIds.insert(channelId)
            let channelName = filteredChannels.first(where: { $0.id == channelId })?.name ?? "Канал"
            persistFavorite(id: channelId, name: channelName, isFavorite: true)
        }
    }

    // MARK: - Library port

    private func restoreLibrary() async {
        do {
            let state = try await userLibrary.load()
            favoriteIds = state.favoriteIds
            historyIds = state.historyIds
        } catch {
            statusBanner = "Не удалось прочитать избранное и историю"
        }
    }

    private func persistFavorite(id: String, name: String, isFavorite: Bool) {
        guard libraryAvailable else {
            if statusBanner == nil {
                statusBanner = "Избранное не сохраняется (хранилище недоступно)"
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.userLibrary.setFavorite(id: id, name: name, isFavorite: isFavorite)
            } catch {
                // Rollback optimistic UI so star state matches durable store
                if isFavorite {
                    self.favoriteIds.remove(id)
                } else {
                    self.favoriteIds.insert(id)
                }
                self.statusBanner = "Не удалось сохранить избранное"
            }
        }
    }

    private func recordHistory(channel: Channel) async {
        let channelId = channel.id
        if let index = historyIds.firstIndex(of: channelId) {
            historyIds.remove(at: index)
        }
        historyIds.insert(channelId, at: 0)
        if historyIds.count > 50 {
            historyIds.removeLast()
        }
        if case .history = selectedTab {
            scheduleFilteredChannelsUpdate()
        }

        guard libraryAvailable else { return }
        do {
            try await userLibrary.recordView(id: channel.id, name: channel.name)
        } catch {
            // Keep session-local history (play already happened); warn that it won't survive restart
            statusBanner = "Не удалось сохранить историю просмотров"
        }
    }

    /// Kept for tests / call sites expecting static mapper
    public static func userFacingLoadError(_ error: Error) -> String {
        CatalogErrorMapper.userMessage(for: error)
    }
    
    // MARK: - Session settings (UI concern)

    private func saveSearchQuery() {
        UserDefaults.standard.set(searchQuery, forKey: "lastSearchQuery")
    }

    private func saveSelectedTab() {
        if let encoded = try? JSONEncoder().encode(selectedTab) {
            UserDefaults.standard.set(encoded, forKey: "lastSelectedTab")
        }
    }

    private func saveSettings() {
        saveSearchQuery()
        saveSelectedTab()
    }
    
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

#endif
