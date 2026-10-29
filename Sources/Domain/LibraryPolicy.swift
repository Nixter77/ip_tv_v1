// Sources/Domain/LibraryPolicy.swift
import Foundation

/// Single history cap shared by the session list and SwiftData prune.
public enum LibraryPolicy {
    public static let historyLimit = 50
}
