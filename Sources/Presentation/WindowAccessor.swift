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
        let view = WindowTrackingView()
        view.onWindow = callback
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowTrackingView)?.onWindow = callback
    }
}

/// AC-6b: reports the window when the view is actually attached. The old
/// makeNSView + async read often ran before attachment, so callers got nil.
final class WindowTrackingView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let cb = onWindow
        DispatchQueue.main.async { cb?(window) }
    }
}
#endif
