#if canImport(SwiftData)
// Sources/Data/Persistence/PersistedChannel.swift
import Foundation
import SwiftData

/// Модель SwiftData для персистентного хранения избранных каналов и истории просмотров
@Model
public final class PersistedChannel {
    /// Уникальный идентификатор канала (предотвращает дублирование)
    @Attribute(.unique) public var id: String
    
    /// Название канала
    public var name: String
    
    /// Флаг нахождения в избранном
    public var isFavorite: Bool
    
    /// Время последнего просмотра (для истории)
    public var lastViewedAt: Date?
    
    /// Инициализатор модели PersistedChannel
    public init(id: String, name: String, isFavorite: Bool = false, lastViewedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
        self.lastViewedAt = lastViewedAt
    }
}

#endif
