#if canImport(Foundation)
// Sources/Presentation/AppState.swift
import Foundation

public enum AppLoadingState: Equatable, Sendable {
    case loading
    case ready
    case error(String)
}

public enum SidebarTab: Codable, Hashable, Sendable, Equatable {
    case all
    case category(String)
    case country(String)
    case language(String)
    case favorites
    case history
}
#endif
