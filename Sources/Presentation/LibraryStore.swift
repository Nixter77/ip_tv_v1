#if canImport(Combine)
// Sources/Presentation/LibraryStore.swift
import Foundation
import Combine

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var favoriteIds: Set<String> = []
    @Published public private(set) var historyIds: [String] = []
    @Published public private(set) var statusBanner: String?
    @Published public private(set) var statusSeverity: StatusSeverity = .warning

    public var onChange: ((Set<String>, [String]) -> Void)?

    private let userLibrary: any UserLibraryRepository
    private let libraryAvailable: Bool
    private var favoritePersistGeneration: [String: UInt] = [:]
    private var writes: [UUID: Task<Void, Never>] = [:]

    public init(userLibrary: any UserLibraryRepository, libraryAvailable: Bool) {
        self.userLibrary = userLibrary
        self.libraryAvailable = libraryAvailable
        Task { await self.restore() }
    }

    public func dismissStatus() {
        statusBanner = nil
    }

    public func toggleFavorite(_ channel: Channel) {
        toggleFavorite(id: channel.id, name: channel.name)
    }

    public func toggleFavorite(id: String, name: String) {
        if favoriteIds.contains(id) {
            favoriteIds.remove(id)
            persistFavorite(id: id, name: name, isFavorite: false)
        } else {
            favoriteIds.insert(id)
            persistFavorite(id: id, name: name, isFavorite: true)
        }
        onChange?(favoriteIds, historyIds)
    }

    public func recordView(_ channel: Channel) async {
        if let index = historyIds.firstIndex(of: channel.id) {
            historyIds.remove(at: index)
        }
        historyIds.insert(channel.id, at: 0)
        if historyIds.count > LibraryPolicy.historyLimit {
            historyIds.removeLast(historyIds.count - LibraryPolicy.historyLimit)
        }
        onChange?(favoriteIds, historyIds)
        guard libraryAvailable else { return }
        do {
            try await userLibrary.recordView(id: channel.id, name: channel.name)
        } catch {
            statusBanner = "Не удалось сохранить историю просмотров"
            statusSeverity = .warning
        }
    }

    public func flushWrites() async {
        let pending = Array(writes.values)
        for task in pending {
            await task.value
        }
    }

    private func restore() async {
        do {
            let state = try await userLibrary.load()
            favoriteIds = state.favoriteIds
            historyIds = state.historyIds
            onChange?(favoriteIds, historyIds)
        } catch {
            statusBanner = "Не удалось прочитать избранное и историю"
            statusSeverity = .error
        }
    }

    private func persistFavorite(id: String, name: String, isFavorite: Bool) {
        guard libraryAvailable else {
            if statusBanner == nil {
                statusBanner = "Избранное не сохраняется (хранилище недоступно)"
                statusSeverity = .warning
            }
            return
        }
        favoritePersistGeneration[id, default: 0] &+= 1
        let generation = favoritePersistGeneration[id] ?? 1
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.userLibrary.setFavorite(id: id, name: name, isFavorite: isFavorite)
            } catch {
                guard self.favoritePersistGeneration[id] == generation else { return }
                if let state = try? await self.userLibrary.load() {
                    self.favoriteIds = state.favoriteIds
                } else if isFavorite {
                    self.favoriteIds.remove(id)
                } else {
                    self.favoriteIds.insert(id)
                }
                self.statusBanner = "Не удалось сохранить избранное"
                self.statusSeverity = .error
                self.onChange?(self.favoriteIds, self.historyIds)
            }
            self.writes[token] = nil
        }
        writes[token] = task
    }
}
#endif
