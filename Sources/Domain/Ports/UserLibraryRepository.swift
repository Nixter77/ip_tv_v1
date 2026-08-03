// Sources/Domain/Ports/UserLibraryRepository.swift
import Foundation

/// Состояние избранного и истории
public struct UserLibraryState: Sendable, Equatable {
    public var favoriteIds: Set<String>
    public var historyIds: [String]

    public init(favoriteIds: Set<String> = [], historyIds: [String] = []) {
        self.favoriteIds = favoriteIds
        self.historyIds = historyIds
    }
}

/// Порт: пользовательская библиотека (избранное / история). Реализация — Data/SwiftData.
@MainActor
public protocol UserLibraryRepository: AnyObject {
    func load() async throws -> UserLibraryState
    func setFavorite(id: String, name: String, isFavorite: Bool) async throws
    func recordView(id: String, name: String) async throws
}

/// No-op library when persistence is unavailable (tests / failed ModelContainer).
@MainActor
public final class InMemoryUserLibraryRepository: UserLibraryRepository {
    public init() {}

    public func load() async throws -> UserLibraryState {
        UserLibraryState()
    }

    public func setFavorite(id: String, name: String, isFavorite: Bool) async throws {}

    public func recordView(id: String, name: String) async throws {}
}
