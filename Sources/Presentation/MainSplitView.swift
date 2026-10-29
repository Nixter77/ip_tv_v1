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

    public init(viewModel: AppViewModel, commands: AppCommandCenter) {
        self.viewModel = viewModel
        self.commands = commands
    }

    public var body: some View {
        VStack(spacing: Spacing.xxs) {
            if let banner = viewModel.statusBanner {
                StatusBannerView(message: banner, severity: viewModel.statusSeverity) {
                    viewModel.dismissStatusBanner()
                }
            }
            if viewModel.isRefreshing {
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
            NavigationSplitView {
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
        .onKeyPress(.space) {
            if isSearchFieldActive { return .ignored }
            viewModel.togglePause()
            return .handled
        }
        .onChange(of: selectedChannel) { _, channel in
            guard let channel else { return }
            Task { await viewModel.selectChannel(channel) }
        }
    }
}
#endif
