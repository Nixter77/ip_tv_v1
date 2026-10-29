#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(AppKit)
// Sources/Presentation/HUDAutoHide.swift
import SwiftUI
import AppKit

// MARK: - Auto-Hide Modifier

/// Отслеживает движение мыши внутри окна плеера и прячет только панель HUD.
/// Системный курсор не трогаем: `NSCursor.hide()` гасит указатель на всё приложение,
/// а список каналов живёт в том же `NSWindow`, куда `mouseMoved` часто не доходит.
struct AutoHideHUDModifier: ViewModifier {
    let hideDelay: TimeInterval
    @Binding var isVisible: Bool

    @StateObject private var mouse = HUDWindowMouseMonitor()
    @State private var hideTimer: Timer?

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isVisible)
            .background(WindowAccessor { window in
                mouse.attach(to: window, onMoved: scheduleShow)
            })
            .onAppear { scheduleShow() }
            .onDisappear {
                hideTimer?.invalidate()
                mouse.stop()
            }
    }

    private func scheduleShow() {
        hideTimer?.invalidate()
        if !isVisible {
            withAnimation(.easeInOut(duration: 0.25)) { isVisible = true }
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { _ in
            MainActor.assumeIsolated {
                scheduleHide()
            }
        }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.25)) { isVisible = false }
    }
}

/// One monitor per HUD instance so main + detached windows do not clobber each other.
private final class HUDWindowMouseMonitor: ObservableObject {
    private var monitor: Any?
    private weak var window: NSWindow?
    private var onMoved: (() -> Void)?

    func attach(to window: NSWindow, onMoved: @escaping () -> Void) {
        self.window = window
        self.onMoved = onMoved
        MainActor.assumeIsolated {
            window.acceptsMouseMovedEvents = true
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let tracked = self.window, event.window == tracked else {
                return event
            }
            self.onMoved?()
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onMoved = nil
        window = nil
    }

    deinit { stop() }
}

extension View {
    func autoHideHUD(isVisible: Binding<Bool>, hideDelay: TimeInterval = 3.0) -> some View {
        modifier(AutoHideHUDModifier(hideDelay: hideDelay, isVisible: isVisible))
    }
}

#endif
