// Sources/Application/AppLog.swift
import Foundation
import os

/// Category loggers. Stream URLs go through `safe` so raw addresses are not emitted.
public enum AppLog {
    public static let network = Logger(subsystem: "com.iptvplayer", category: "network")
    public static let playback = Logger(subsystem: "com.iptvplayer", category: "playback")
    public static let catalog = Logger(subsystem: "com.iptvplayer", category: "catalog")
    public static let persistence = Logger(subsystem: "com.iptvplayer", category: "persistence")

    public static func safe(_ text: String) -> String {
        Stream.maskURLs(in: text)
    }
}
