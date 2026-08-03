#if canImport(SwiftUI) && canImport(AVFoundation)
// Sources/Presentation/MainSplitView.swift
import SwiftUI
import AVFoundation
import AppKit

/// Основной трехпанельный макет приложения IPTVPlayer.
/// Важно: playerManager наблюдается только в `PlayerDetailColumn`, а не здесь —
/// иначе каждый tick буферизации пересобирал бы List каналов.
public struct MainSplitView: View {
    /// Owned by `IPTVApp` as `@StateObject` — here only observe (do not re-wrap as StateObject).
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var commands: AppCommandCenter
    
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var selectedChannel: Channel?
    @State private var escapeMonitor: Any? = nil
    /// True while the channel search field is first responder (space = type, not pause).
    @State private var isSearchFieldActive = false
    
    public init(viewModel: AppViewModel, commands: AppCommandCenter) {
        self.viewModel = viewModel
        self.commands = commands
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let banner = viewModel.statusBanner {
                StatusBannerView(message: banner) {
                    viewModel.dismissStatusBanner()
                }
            }
            if viewModel.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Обновление плейлиста…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
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
        .task {
            await viewModel.loadData()
        }
        .onChange(of: commands.reloadGeneration) { _, _ in
            Task {
                await viewModel.reloadPlaylist()
            }
        }
        .onChange(of: commands.focusSearchGeneration) { _, _ in
            // ChannelListColumn observes the same command center
        }
        .onKeyPress(.space) {
            if isSearchFieldActive {
                return .ignored
            }
            togglePlayPause()
            return .handled
        }
        .onAppear {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                        window.toggleFullScreen(nil)
                        return nil
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
        }
        .onChange(of: selectedChannel) { _, newChannel in
            if let channel = newChannel {
                Task {
                    await viewModel.play(channel: channel)
                }
            }
        }
    }
    
    private func togglePlayPause() {
        let player = viewModel.playerManager.avPlayer
        if player.rate > 0 {
            player.pause()
        } else if player.currentItem != nil {
            player.play()
        }
    }
}

// MARK: - Sidebar (AppViewModel only)

private struct SidebarColumn: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedTab },
            set: { tab in
                if let newTab = tab {
                    viewModel.selectedTab = newTab
                }
            }
        )) {
            Section("Библиотека") {
                NavigationLink(value: SidebarTab.all) {
                    Label("Все каналы", systemImage: "tv")
                }
                NavigationLink(value: SidebarTab.favorites) {
                    Label("Избранное", systemImage: "heart.fill")
                        .foregroundColor(.pink)
                }
                NavigationLink(value: SidebarTab.history) {
                    Label("История", systemImage: "clock.arrow.circlepath")
                }
            }
            
            if !viewModel.categories.isEmpty {
                Section("Категории") {
                    ForEach(viewModel.categories) { category in
                        NavigationLink(value: SidebarTab.category(category.name)) {
                            Label(category.name.capitalized, systemImage: "folder")
                        }
                    }
                }
            }
            
            if !viewModel.countries.isEmpty {
                Section("Страны") {
                    ForEach(viewModel.countries) { country in
                        NavigationLink(value: SidebarTab.country(country.code)) {
                            HStack {
                                Text(country.flag ?? "🌐")
                                Text(country.name)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            
            if !viewModel.languages.isEmpty {
                Section("Языки") {
                    ForEach(viewModel.languages) { language in
                        NavigationLink(value: SidebarTab.language(language.code)) {
                            Label(language.name, systemImage: "character.bubble")
                        }
                    }
                }
            }
        }
        .listStyle(SidebarListStyle())
        .padding(.top, 40)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: {
                    Task {
                        await viewModel.reloadPlaylist()
                    }
                }) {
                    Label("Обновить плейлист", systemImage: "arrow.clockwise")
                        .font(.callout)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Обновить плейлист (⌘R)")
                
                Spacer()
            }
            .padding()
            .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow).opacity(0.8))
        }
    }
}

// MARK: - Channel list (owns FocusState locally — never pass FocusState.Binding across views)

private struct ChannelListColumn: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var commands: AppCommandCenter
    @Binding var selectedChannel: Channel?
    @Binding var isSearchFieldActive: Bool

    /// Must live in the same view as `.focused` — crossing view boundaries breaks macOS focus.
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding([.horizontal, .bottom])
                .padding(.top, 40)
            
            if viewModel.loadingState == .loading {
                Spacer()
                ProgressView("Загрузка каналов...")
                Spacer()
            } else if case .error(let errorMsg) = viewModel.loadingState {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button("Попробовать снова") {
                        Task {
                            await viewModel.reloadPlaylist()
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                Spacer()
            } else if viewModel.filteredChannels.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                List(viewModel.filteredChannels, id: \.id, selection: $selectedChannel) { channel in
                    ChannelRowView(
                        channel: channel,
                        isFavorite: viewModel.favoriteIds.contains(channel.id),
                        onFavoriteToggle: {
                            viewModel.toggleFavorite(channelId: channel.id)
                        }
                    )
                    .tag(channel)
                }
                .listStyle(PlainListStyle())
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            isSearchFieldActive = focused
        }
        .onChange(of: commands.focusSearchGeneration) { _, _ in
            focusSearchField()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Поиск канала... (⌘F)", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    // Keep focus after submit so continued typing works
                    isSearchFocused = true
                }
            if !viewModel.searchQuery.isEmpty {
                Button(action: { viewModel.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        // Prefer this field when the content column becomes focused (macOS focus engine)
        .focusSection()
    }

    private func focusSearchField() {
        // Bring the app window forward when shortcut fired while another app had focus
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
        // Defer one run-loop turn so key window is established before FocusState applies
        DispatchQueue.main.async {
            isSearchFocused = true
            isSearchFieldActive = true
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            if viewModel.selectedTab == .favorites {
                Image(systemName: "heart")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("В избранном пусто")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Button("Перейти ко всем каналам") {
                    viewModel.selectedTab = .all
                }
                .buttonStyle(.bordered)
            } else if viewModel.selectedTab == .history {
                Image(systemName: "clock")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("История пуста")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Button("Перейти ко всем каналам") {
                    viewModel.selectedTab = .all
                }
                .buttonStyle(.bordered)
            } else if !viewModel.searchQuery.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("Ничего не найдено")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Button("Очистить поиск") {
                    viewModel.searchQuery = ""
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("Каналы не найдены")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Player detail (observes PlayerStateManager in isolation)

private struct PlayerDetailColumn: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playerManager: PlayerStateManager
    let openWindow: OpenWindowAction
    let dismissWindow: DismissWindowAction

    var body: some View {
        ZStack {
            Color.black

            if let channel = playerManager.currentChannel {
                if viewModel.isPlayerDetached {
                    VStack(spacing: 16) {
                        Image(systemName: "tv.and.mediabox")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("Трансляция перенесена в отдельное окно")
                            .font(.title3)
                            .foregroundColor(.white)
                        Button("Вернуть в главное окно") {
                            viewModel.isPlayerDetached = false
                            dismissWindow(id: "detached-player")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    QuickTimeVideoContainer(
                        player: playerManager.avPlayer,
                        playerState: playerManager.state,
                        channelName: channel.name,
                        isFavorite: viewModel.favoriteIds.contains(channel.id),
                        onToggleFullscreen: {
                            if let window = NSApp.keyWindow {
                                window.toggleFullScreen(nil)
                            }
                        },
                        onDetachPlayer: {
                            viewModel.isPlayerDetached = true
                            openWindow(id: "detached-player")
                        },
                        onToggleFavorite: {
                            viewModel.toggleFavorite(channelId: channel.id)
                        },
                        onRetry: {
                            Task { await viewModel.retryPlayback() }
                        },
                        preferredBitrate: Binding(
                            get: { playerManager.preferredBitrate },
                            set: { playerManager.preferredBitrate = $0 }
                        )
                    )
                    .ignoresSafeArea()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "tv.music.note")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Выберите телеканал для трансляции")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Строка Списка Каналов (предвычисленные display-поля)
struct ChannelRowView: View {
    let channel: Channel
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void

    private let logoURL: URL?
    private let languagesLabel: String
    
    @State private var isHovered = false

    init(channel: Channel, isFavorite: Bool, onFavoriteToggle: @escaping () -> Void) {
        self.channel = channel
        self.isFavorite = isFavorite
        self.onFavoriteToggle = onFavoriteToggle
        self.logoURL = channel.logo.flatMap { URL(string: $0) }
        self.languagesLabel = channel.languages.joined(separator: ", ").uppercased()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ChannelLogoView(url: logoURL, name: channel.name)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let country = channel.country {
                        Text(country)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                    if !languagesLabel.isEmpty {
                        Text(languagesLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(isFavorite ? .pink : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isFavorite ? 1 : 0)
            .help(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
            .accessibilityLabel(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .contextMenu {
            Button(action: onFavoriteToggle) {
                Label(isFavorite ? "Удалить из избранного" : "Добавить в избранное",
                      systemImage: isFavorite ? "heart.slash" : "heart")
            }

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.name, forType: .string)
            }) {
                Label("Копировать название", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Status banner (persistence / soft-reload / cooldown)

private struct StatusBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Скрыть")
            .accessibilityLabel("Скрыть уведомление")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
    }
}

// MARK: - VisualEffectView
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#endif
