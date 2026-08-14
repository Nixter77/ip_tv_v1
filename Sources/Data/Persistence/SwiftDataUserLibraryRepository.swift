#if canImport(SwiftData)
// Sources/Data/Persistence/SwiftDataUserLibraryRepository.swift
import Foundation
import SwiftData

/// Data adapter: SwiftData → UserLibraryRepository port
@MainActor
public final class SwiftDataUserLibraryRepository: UserLibraryRepository {
    private let modelContext: ModelContext
    private let historyLimit: Int

    public init(modelContext: ModelContext, historyLimit: Int = 50) {
        self.modelContext = modelContext
        self.historyLimit = historyLimit
    }

    public static func make(modelContainer: ModelContainer?, historyLimit: Int = 50) -> any UserLibraryRepository {
        guard let context = modelContainer?.mainContext else {
            return InMemoryUserLibraryRepository()
        }
        return SwiftDataUserLibraryRepository(modelContext: context, historyLimit: historyLimit)
    }

    public func load() async throws -> UserLibraryState {
        let descriptor = FetchDescriptor<PersistedChannel>()
        let items = try modelContext.fetch(descriptor)

        let favorites = Set(items.compactMap { $0.isFavorite ? $0.id : nil })
        let history = items.compactMap { $0.lastViewedAt != nil ? $0 : nil }
            .sorted { ($0.lastViewedAt ?? Date.distantPast) > ($1.lastViewedAt ?? Date.distantPast) }
            .map(\.id)
        return UserLibraryState(
            favoriteIds: favorites,
            historyIds: Array(history.prefix(historyLimit))
        )
    }

    public func setFavorite(id: String, name: String, isFavorite: Bool) async throws {
        let id = Self.sanitizeID(id)
        guard !id.isEmpty else { return }
        let name = Self.sanitizeName(name)
        let descriptor = FetchDescriptor<PersistedChannel>(predicate: #Predicate { $0.id == id })
        let items = try modelContext.fetch(descriptor)

        if let existing = items.first {
            existing.isFavorite = isFavorite
            if !existing.name.isEmpty || !name.isEmpty {
                existing.name = name.isEmpty ? existing.name : name
            }
            if !isFavorite && existing.lastViewedAt == nil {
                modelContext.delete(existing)
            }
        } else if isFavorite {
            modelContext.insert(PersistedChannel(id: id, name: name, isFavorite: true))
        }
        try modelContext.save()
    }

    public func recordView(id: String, name: String) async throws {
        let id = Self.sanitizeID(id)
        guard !id.isEmpty else { return }
        let name = Self.sanitizeName(name)
        let descriptor = FetchDescriptor<PersistedChannel>(predicate: #Predicate { $0.id == id })
        let items = try modelContext.fetch(descriptor)

        if let existing = items.first {
            existing.lastViewedAt = Date()
            if !name.isEmpty {
                existing.name = name
            }
        } else {
            modelContext.insert(
                PersistedChannel(id: id, name: name, isFavorite: false, lastViewedAt: Date())
            )
        }
        try pruneHistory()
        try modelContext.save()
    }

    private func pruneHistory() throws {
        let descriptor = FetchDescriptor<PersistedChannel>()
        let items = try modelContext.fetch(descriptor)
        let history = items.filter { $0.lastViewedAt != nil }
            .sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }
        guard history.count > historyLimit else { return }
        for extra in history.dropFirst(historyLimit) {
            extra.lastViewedAt = nil
            if !extra.isFavorite {
                modelContext.delete(extra)
            }
        }
    }

    private static func sanitizeID(_ id: String) -> String {
        String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(RemoteURLPolicy.maxPersistedIDLength))
    }

    private static func sanitizeName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(RemoteURLPolicy.maxPersistedNameLength))
    }
}
#endif
