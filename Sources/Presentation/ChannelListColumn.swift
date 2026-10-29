#if canImport(SwiftUI) && canImport(AppKit)
// Sources/Presentation/ChannelListColumn.swift
import SwiftUI
import AppKit

struct ChannelListColumn: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var commands: AppCommandCenter
    @Binding var selectedChannel: Channel?
    @Binding var isSearchFieldActive: Bool

    @FocusState private var isSearchFocused: Bool
    @State private var listWindow = Layout.listPage

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            searchBar
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
            content
        }
        .onChange(of: viewModel.searchQuery) { _, _ in listWindow = Layout.listPage }
        .onChange(of: viewModel.selectedTab) { _, _ in listWindow = Layout.listPage }
        .onChange(of: isSearchFocused) { _, focused in isSearchFieldActive = focused }
        .onChange(of: commands.focusSearchGeneration) { _, _ in focusSearchField() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.loadingState == .loading {
            Spacer()
            ProgressView("Загрузка каналов...")
            Spacer()
        } else if case .error(let errorMsg) = viewModel.loadingState {
            Spacer()
            VStack(spacing: Spacing.l) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(Palette.error)
                Text(errorMsg)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.l)
                Button("Попробовать снова") {
                    Task { await viewModel.reloadPlaylist() }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        } else if viewModel.filteredChannels.isEmpty {
            Spacer()
            emptyState
            Spacer()
        } else {
            channelList
        }
    }

    private var channelList: some View {
        let rows = viewModel.filteredChannels
        let visible = Array(rows.prefix(listWindow))
        return List(selection: $selectedChannel) {
            ForEach(visible, id: \.id) { channel in
                ChannelRowView(
                    channel: channel,
                    isFavorite: viewModel.favoriteIds.contains(channel.id),
                    onFavoriteToggle: { viewModel.toggleFavorite(channel) }
                )
                .tag(channel)
            }
            if listWindow < rows.count {
                Text("Загрузить ещё…")
                    .foregroundStyle(.secondary)
                    .onAppear { listWindow += Layout.listPage }
            }
        }
        .listStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск канала... (⌘F)", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = true }
            if !viewModel.searchQuery.isEmpty {
                Button { viewModel.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(Spacing.m)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .focusSection()
    }

    private func focusSearchField() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.async {
            isSearchFocused = true
            isSearchFieldActive = true
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: emptySymbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            if viewModel.selectedTab == .favorites || viewModel.selectedTab == .history {
                Button("Перейти ко всем каналам") { viewModel.selectedTab = .all }
                    .buttonStyle(.bordered)
            } else if !viewModel.searchQuery.isEmpty {
                Button("Очистить поиск") { viewModel.searchQuery = "" }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var emptySymbol: String {
        switch viewModel.selectedTab {
        case .favorites: return "heart"
        case .history: return "clock"
        default: return viewModel.searchQuery.isEmpty ? "tv" : "magnifyingglass"
        }
    }

    private var emptyTitle: String {
        switch viewModel.selectedTab {
        case .favorites: return "В избранном пусто"
        case .history: return "История пуста"
        default: return viewModel.searchQuery.isEmpty ? "Каналы не найдены" : "Ничего не найдено"
        }
    }
}
#endif
