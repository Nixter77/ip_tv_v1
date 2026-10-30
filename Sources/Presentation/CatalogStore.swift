#if canImport(Combine)
// Sources/Presentation/CatalogStore.swift
import Foundation
import Combine

@MainActor
public final class CatalogStore: ObservableObject {
    @Published public internal(set) var loadingState: AppLoadingState = .loading
    @Published public var searchQuery: String = "" {
        didSet { searchQueryDidChange(from: oldValue) }
    }
    @Published public var selectedTab: SidebarTab = .all {
        didSet {
            guard selectedTab != oldValue else { return }
            saveTab()
            scheduleFilter(debounced: false)
        }
    }
    @Published public var showNSFW: Bool {
        didSet { persistFlag("showNSFWChannels", showNSFW) }
    }
    @Published public var showClosed: Bool {
        didSet { persistFlag("showClosedChannels", showClosed) }
    }
    @Published public private(set) var filteredChannels: [Channel] = []
    @Published public internal(set) var categories: [Category] = []
    @Published public internal(set) var countries: [Country] = []
    @Published public internal(set) var languages: [Language] = []
    @Published public private(set) var categoryCounts: [String: Int] = [:]
    @Published public private(set) var countryCounts: [String: Int] = [:]
    @Published public private(set) var languageCounts: [String: Int] = [:]
    @Published public internal(set) var isRefreshing = false
    @Published public internal(set) var statusBanner: String?
    @Published public internal(set) var statusSeverity: StatusSeverity = .info

    public let filterEngine: any ChannelFilterEngineProtocol
    let loadCatalog: LoadCatalogUseCase
    let clock: any SuspendingClock
    var namesByID: [String: String] = [:]
    private var favoriteIds: Set<String> = []
    private var historyIds: [String] = []
    private var filterTask: Task<Void, Never>?
    var revalidateTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var lastReloadAt: Date?
    private let reloadCooldown: TimeInterval = 5

    public init(
        repository: any PlaylistRepository,
        filterEngine: any ChannelFilterEngineProtocol,
        clock: any SuspendingClock = ContinuousSuspendingClock(),
        persistenceUnavailableMessage: String? = nil
    ) {
        self.filterEngine = filterEngine
        self.loadCatalog = LoadCatalogUseCase(repository: repository, filterEngine: filterEngine)
        self.clock = clock
        self.showNSFW = UserDefaults.standard.bool(forKey: "showNSFWChannels")
        self.showClosed = UserDefaults.standard.bool(forKey: "showClosedChannels")
        if let persistenceUnavailableMessage {
            statusBanner = persistenceUnavailableMessage
            statusSeverity = .warning
        }
        restoreSettings()
    }

    public func name(for channelID: String) -> String? {
        namesByID[channelID]
    }

    public func streams(for channelID: String) async -> [Stream] {
        await filterEngine.streams(for: channelID)
    }

    public func applyLibrary(favoriteIds: Set<String>, historyIds: [String]) {
        self.favoriteIds = favoriteIds
        self.historyIds = historyIds
        if selectedTab == .favorites || selectedTab == .history {
            scheduleFilter(debounced: false)
        }
    }

    public func dismissStatus() {
        statusBanner = nil
    }

    public func loadData(soft: Bool = false) async {
        revalidateTask?.cancel()
        revalidateTask = nil
        loadTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad(soft: soft)
        }
        loadTask = task
        await task.value
    }

    public func reloadPlaylist() async {
        if let last = lastReloadAt, Date().timeIntervalSince(last) < reloadCooldown {
            let wait = Int(ceil(reloadCooldown - Date().timeIntervalSince(last)))
            statusBanner = "Подождите \(wait) с перед повторным обновлением"
            statusSeverity = .info
            return
        }
        lastReloadAt = Date()
        await loadData(soft: hasCatalog)
    }

    var hasCatalog: Bool {
        if case .ready = loadingState { return true }
        return false
    }

    private func searchQueryDidChange(from oldValue: String) {
        if searchQuery.count > RemoteURLPolicy.maxSearchQueryLength {
            searchQuery = String(searchQuery.prefix(RemoteURLPolicy.maxSearchQueryLength))
            return
        }
        guard searchQuery != oldValue else { return }
        UserDefaults.standard.set(searchQuery, forKey: "lastSearchQuery")
        scheduleFilter(debounced: true)
    }

    private func scheduleFilter(debounced: Bool) {
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            if debounced {
                try? await self?.clock.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await self?.publishFilter()
        }
    }

    func publishFilter() async {
        await filterEngine.setVisibility(includeNSFW: showNSFW, includeClosed: showClosed)
        var categoryFilter: String?
        var countryFilter: String?
        var languageFilter: String?
        var restrictedTo: Set<String>?
        switch selectedTab {
        case .all:
            break
        case .category(let id):
            categoryFilter = id
        case .country(let code):
            countryFilter = code
        case .language(let code):
            languageFilter = code
        case .favorites:
            restrictedTo = favoriteIds
            if favoriteIds.isEmpty {
                guard !Task.isCancelled else { return }
                filteredChannels = []
                await publishCounts()
                return
            }
        case .history:
            if searchQuery.isEmpty {
                let ordered = await filterEngine.channels(preservingOrder: historyIds)
                guard !Task.isCancelled else { return }
                filteredChannels = ordered
                await publishCounts()
                return
            }
            let matched = await filterEngine.filter(
                query: searchQuery,
                category: nil,
                country: nil,
                language: nil,
                restrictedTo: Set(historyIds)
            )
            guard !Task.isCancelled else { return }
            let map = Dictionary(matched.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            filteredChannels = historyIds.compactMap { map[$0] }
            await publishCounts()
            return
        }
        // AC-4: Favorites tab always lists every saved favorite. A lingering search
        // query (from the All tab) used to hide older favorites, so they looked wiped.
        let effectiveQuery = selectedTab == .favorites ? "" : searchQuery
        let result = await filterEngine.filter(
            query: effectiveQuery,
            category: categoryFilter,
            country: countryFilter,
            language: languageFilter,
            restrictedTo: restrictedTo
        )
        guard !Task.isCancelled else { return }
        filteredChannels = result
        await publishCounts()
    }

    private func publishCounts() async {
        let counts = await filterEngine.groupCounts()
        categoryCounts = counts.categories
        countryCounts = counts.countries
        languageCounts = counts.languages
    }

    private func persistFlag(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        scheduleFilter(debounced: false)
    }

    private func saveTab() {
        if let encoded = try? JSONEncoder().encode(selectedTab) {
            UserDefaults.standard.set(encoded, forKey: "lastSelectedTab")
        }
    }

    private func restoreSettings() {
        if let data = UserDefaults.standard.data(forKey: "lastSelectedTab"),
           let decoded = try? JSONDecoder().decode(SidebarTab.self, from: data) {
            selectedTab = decoded
        }
        if let query = UserDefaults.standard.string(forKey: "lastSearchQuery") {
            searchQuery = query
        }
    }
}
#endif
