// Sources/Application/CatalogLoadPolicy.swift
import Foundation

/// Политика загрузки каталога (Application strategy)
public enum CatalogLoadPolicy: Sendable, Equatable {
    /// Кэш-first; вызывающий может запланировать revalidate
    case cacheFirstThenRevalidate
    /// Принудительная сеть (soft reload / explicit refresh)
    case forceNetwork
    /// Только фоновая ревалидация (ошибки глотаются на уровне use case caller)
    case backgroundRevalidate

    public var fetchOptions: CatalogFetchOptions {
        switch self {
        case .cacheFirstThenRevalidate:
            return .cacheFirst
        case .forceNetwork, .backgroundRevalidate:
            return .forceNetwork
        }
    }

    public var shouldScheduleRevalidate: Bool {
        self == .cacheFirstThenRevalidate
    }
}
