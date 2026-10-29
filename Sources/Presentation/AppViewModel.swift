#if canImport(Combine) && canImport(SwiftData)
// Sources/Presentation/AppViewModel.swift
import Foundation
import Combine
import SwiftData

@MainActor
public final class AppViewModel: ObservableObject {
    public let catalog: CatalogStore
    public let library: LibraryStore
    public let playback: PlaybackController

    private var cancellables = Set<AnyCancellable>()

    public init(
        repository: any PlaylistRepository,
        filterEngine: any ChannelFilterEngineProtocol,
        playerManager: PlayerStateManager,
        userLibrary: any UserLibraryRepository,
        libraryAvailable: Bool = true,
        persistenceUnavailableMessage: String? = nil,
        clock: any SuspendingClock = ContinuousSuspendingClock()
    ) {
        catalog = CatalogStore(
            repository: repository,
            filterEngine: filterEngine,
            clock: clock,
            persistenceUnavailableMessage: persistenceUnavailableMessage
        )
        library = LibraryStore(userLibrary: userLibrary, libraryAvailable: libraryAvailable)
        playback = PlaybackController(player: playerManager)
        catalog.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        library.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        playback.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        library.onChange = { [weak self] favorites, history in
            self?.catalog.applyLibrary(favoriteIds: favorites, historyIds: history)
        }
    }

    public convenience init(
        repository: any PlaylistRepository,
        filterEngine: any ChannelFilterEngineProtocol,
        playerManager: PlayerStateManager,
        modelContainer: ModelContainer? = nil,
        persistenceUnavailableMessage: String? = nil,
        clock: any SuspendingClock = ContinuousSuspendingClock()
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
            persistenceUnavailableMessage: persistenceUnavailableMessage,
            clock: clock
        )
    }

    public var loadingState: AppLoadingState { catalog.loadingState }
    public var searchQuery: String {
        get { catalog.searchQuery }
        set { catalog.searchQuery = newValue }
    }
    public var selectedTab: SidebarTab {
        get { catalog.selectedTab }
        set { catalog.selectedTab = newValue }
    }
    public var filteredChannels: [Channel] { catalog.filteredChannels }
    public var categories: [Category] { catalog.categories }
    public var countries: [Country] { catalog.countries }
    public var languages: [Language] { catalog.languages }
    public var favoriteIds: Set<String> { library.favoriteIds }
    public var historyIds: [String] { library.historyIds }
    public var isRefreshing: Bool { catalog.isRefreshing }
    public var isPlayerDetached: Bool {
        get { playback.isDetached }
        set { playback.isDetached = newValue }
    }
    public var statusBanner: String? { library.statusBanner ?? catalog.statusBanner }
    public var statusSeverity: StatusSeverity {
        if library.statusBanner != nil { return library.statusSeverity }
        return catalog.statusSeverity
    }
    public var playerManager: PlayerStateManager { playback.player }
    public var filterEngine: any ChannelFilterEngineProtocol { catalog.filterEngine }
    public var nowPlayingTitle: String? { playback.nowPlayingTitle }
    public var showNSFW: Bool {
        get { catalog.showNSFW }
        set { catalog.showNSFW = newValue }
    }
    public var showClosed: Bool {
        get { catalog.showClosed }
        set { catalog.showClosed = newValue }
    }

    public func dismissStatusBanner() {
        library.dismissStatus()
        catalog.dismissStatus()
    }

    public func loadData(soft: Bool = false) async {
        await catalog.loadData(soft: soft)
    }

    public func reloadPlaylist() async {
        await catalog.reloadPlaylist()
    }

    public func play(channel: Channel) async {
        await library.recordView(channel)
        let streams = await catalog.streams(for: channel.id)
        await playback.play(channel: channel, streams: streams)
    }

    public func selectChannel(_ channel: Channel) async {
        if playback.currentChannelID == channel.id {
            await playback.retry()
        } else {
            await play(channel: channel)
        }
    }

    public func retryPlayback() async {
        await playback.retry()
    }

    public func togglePause() {
        playback.togglePause()
    }

    public func toggleFavorite(_ channel: Channel) {
        library.toggleFavorite(channel)
    }

    public func toggleFavorite(channelId: String) {
        let name = catalog.name(for: channelId) ?? "Канал"
        library.toggleFavorite(id: channelId, name: name)
    }

    public func flushLibraryWrites() async {
        await library.flushWrites()
    }

    public static func userFacingLoadError(_ error: Error) -> String {
        CatalogErrorMapper.userMessage(for: error)
    }
}
#endif
