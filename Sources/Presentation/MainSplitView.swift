#if canImport(SwiftUI) && canImport(AppKit)
// Sources/Presentation/MainSplitView.swift
import SwiftUI
import AppKit

public struct MainSplitView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var commands: AppCommandCenter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedChannel: Channel?
    @State private var isSearchFieldActive = false
    // S4/AC-6: content-only fullscreen — hide sidebar/list/toolbar while host window is FS.
    @State private var hostWindow: NSWindow?
    @State private var isFullScreen = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var savedVisibility: NavigationSplitViewVisibility = .all

    public init(viewModel: AppViewModel, commands: AppCommandCenter) {
        self.viewModel = viewModel
        self.commands = commands
    }

    public var body: some View {
        VStack(spacing: Spacing.xxs) {
            if !isFullScreen, let banner = viewModel.statusBanner {
                StatusBannerView(message: banner, severity: viewModel.statusSeverity) {
                    viewModel.dismissStatusBanner()
                }
            }
            if !isFullScreen && viewModel.isRefreshing {
                HStack(spacing: Spacing.m) {
                    ProgressView().controlSize(.small)
                    Text("Обновление плейлиста…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
            }
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarColumn(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            } content: {
                ChannelListColumn(
                    viewModel: viewModel,
                    commands: commands,
                    selectedChannel: $selectedChannel,
                    isSearchFieldActive: $isSearchFieldActive
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 450)
            } detail: {
                PlayerDetailColumn(
                    viewModel: viewModel,
                    playerManager: viewModel.playerManager,
                    openWindow: openWindow,
                    dismissWindow: dismissWindow
                )
            }
        }
        .toolbar(isFullScreen ? .hidden : .automatic, for: .windowToolbar)
        .background(WindowAccessor { hostWindow = $0 })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { note in
            guard let w = note.object as? NSWindow, w === hostWindow else { return }
            savedVisibility = columnVisibility
            isFullScreen = true
            columnVisibility = .detailOnly
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { note in
            guard let w = note.object as? NSWindow, w === hostWindow else { return }
            isFullScreen = false
            columnVisibility = savedVisibility == .detailOnly ? .all : savedVisibility
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.reloadPlaylist() }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .help("Обновить плейлист (⌘R)")
            }
        }
        .task { await viewModel.loadData() }
        .onChange(of: commands.reloadGeneration) { _, _ in
            Task { await viewModel.reloadPlaylist() }
        }
        .onChange(of: commands.pauseGeneration) { _, _ in
            // Menu "Пауза / Play" (no shortcut; Space handled by SpaceKeyMonitor).
            viewModel.togglePause()
        }
        .modifier(SpaceKeyMonitor(isActive: { viewModel.nowPlayingTitle != nil }) {
            viewModel.togglePause()
        })
        .onChange(of: selectedChannel?.id) { _, newID in
            guard let newID, let channel = selectedChannel, channel.id == newID else { return }
            Task { await viewModel.selectChannel(channel) }
            // S1e: user started playback in this window — make sure it is key so
            // SpaceKeyMonitor receives Space (user-initiated, not background stealing).
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }),
               !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

/// S1d: AppKit-level Space routing. SwiftUI .onKeyPress and a modifier-less menu
/// key equivalent both lose to the real first responder (NSTableView of the List,
/// focused HUD buttons), so Space never reached togglePause. A local keyDown monitor
/// sees the event before any responder; it passes through only when an editable
/// text view (search field editor) is first responder.
struct SpaceKeyMonitor: ViewModifier {
    let isActive: @MainActor () -> Bool
    let action: @MainActor () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.keyCode == 49 else { return event }
                    let keyWindowResponder = event.window?.firstResponder
                    let editingText = (keyWindowResponder as? NSTextView)?.isEditable ?? false
                    let mods = event.modifierFlags.intersection([.command, .control, .option, .function])
                    let isRepeat = event.isARepeat
                    let consumed = MainActor.assumeIsolated {
                        SpaceKeyMonitor.shouldConsume(
                            isRepeat: isRepeat, hasModifiers: !mods.isEmpty,
                            editingText: editingText, isActive: isActive, action: action)
                    }
                    return consumed ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    @MainActor
    static func shouldConsume(isRepeat: Bool, hasModifiers: Bool, editingText: Bool,
                              isActive: () -> Bool, action: () -> Void) -> Bool {
        guard !isRepeat, !hasModifiers, !editingText, isActive() else { return false }
        action()
        return true
    }
}
#endif
