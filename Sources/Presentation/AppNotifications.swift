#if canImport(Foundation)
// Sources/Presentation/AppNotifications.swift
// Deprecated: prefer AppCommandCenter. Kept for any external callers.
import Foundation

@available(*, deprecated, message: "Use AppCommandCenter instead of NotificationCenter")
public enum AppNotifications {
    public static let focusChannelSearch = Notification.Name("com.iptvplayer.focusChannelSearch")
    public static let reloadPlaylist = Notification.Name("com.iptvplayer.reloadPlaylist")
}
#endif
