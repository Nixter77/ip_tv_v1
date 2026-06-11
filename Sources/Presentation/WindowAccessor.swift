#if canImport(SwiftUI) && canImport(AppKit)
// Sources/Presentation/WindowAccessor.swift
import SwiftUI
import AppKit

/// Вспомогательное представление для доступа к NSWindow из SwiftUI.
public struct WindowAccessor: NSViewRepresentable {
    public var callback: (NSWindow) -> Void

    public init(callback: @escaping (NSWindow) -> Void) {
        self.callback = callback
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
