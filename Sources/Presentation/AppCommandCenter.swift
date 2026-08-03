#if canImport(Combine)
// Sources/Presentation/AppCommandCenter.swift
// Typed app commands — replaces NotificationCenter bus for menu shortcuts.
import Foundation
import Combine

@MainActor
public final class AppCommandCenter: ObservableObject {
    /// Bumps when ⌘F / menu requests focus on channel search
    @Published public private(set) var focusSearchGeneration: UInt = 0
    /// Bumps when ⌘R / menu requests playlist reload
    @Published public private(set) var reloadGeneration: UInt = 0

    public init() {}

    public func requestFocusSearch() {
        focusSearchGeneration &+= 1
    }

    public func requestReload() {
        reloadGeneration &+= 1
    }
}
#endif
