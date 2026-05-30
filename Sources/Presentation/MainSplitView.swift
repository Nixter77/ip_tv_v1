#if canImport(SwiftUI) && canImport(AVFoundation)
// Sources/Presentation/MainSplitView.swift
import SwiftUI
import AVFoundation

/// Основной трехпанельный макет приложения IPTVPlayer
public struct MainSplitView: View {
    @StateObject private var viewModel: AppViewModel
    
    // FocusState для быстрого фокуса на поиске по ⌘F
    @FocusState private var isSearchFocused: Bool
    
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    // Выбранный в списке канал
    @State private var selectedChannel: Channel?
    
    // Монитор клавиатурных событий для отслеживания клавиши Esc
    @State private var escapeMonitor: Any? = nil
    
    /// Инициализатор с инжекцией ViewModel
    public init(viewModel: AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        NavigationSplitView {
            // Панель 1: Sidebar
            sidebarView
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } content: {
            // Панель 2: Список каналов
            channelListView
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 450)
        } detail: {
            // Панель 3: Плеер и детали
            playerDetailView
        }
        .task {
            // Загружаем плейлист при старте
            await viewModel.loadData()
        }
        // Глобальные клавиатурные шорткаты
        .background(
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                Task {
                    await viewModel.reloadPlaylist()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .onKeyPress(.space) {
            if isSearchFocused {
                return .ignored
            }
            togglePlayPause()
            return .handled
        }
        .onAppear {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Клавиша Esc
                    if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                        window.toggleFullScreen(nil)
                        return nil // Событие обработано
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
    }
    
    // MARK: - 1. Sidebar View
    private var sidebarView: some View {
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
        .safeAreaInset(edge: .bottom) {
            // Кнопка перезагрузки внизу сайдбара
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
    
    // MARK: - 2. Channel List View
    private var channelListView: some View {
        VStack(spacing: 0) {
            // Кастомная строка поиска с Rich Aesthetics
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Поиск канала... (⌘F)", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
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
            .padding([.horizontal, .bottom])
            .padding(.top, 40) // Отступ сверху для компенсации скрытого TitleBar macOS drag-зоны!
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            
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
        .onChange(of: selectedChannel) { _, newChannel in
            if let channel = newChannel {
                Task {
                    await viewModel.play(channel: channel)
                }
            }
        }
    }
    
    // MARK: - 3. Player Detail View
    private var playerDetailView: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            
            if let channel = viewModel.playerManager.currentChannel {
                VStack(spacing: 0) {
                    // Видео-плеер
                    if viewModel.isPlayerDetached {
                        ZStack {
                            Color.black.ignoresSafeArea()
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
                        }
                    } else {
                        ZStack {
                            VideoPlayerView(player: viewModel.playerManager.avPlayer)
                                .ignoresSafeArea()
                            
                            // Кастомный HUD оверлей при загрузке или ошибке
                            PlayerHUDOverlay(state: viewModel.playerManager.state, onRetry: {
                                Task {
                                    await viewModel.play(channel: channel)
                                }
                            })
                        }
                    }
                    
                    // Панель информации о канале
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            HStack(spacing: 12) {
                                if let country = channel.country {
                                    Text("🌐 Страна: \(country)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                if !channel.categories.isEmpty {
                                    Text("🏷️ \(channel.categories.joined(separator: ", "))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Регулятор битрейта (выбор качества)
                        Picker("Качество", selection: Binding(
                            get: { viewModel.playerManager.preferredBitrate },
                            set: { viewModel.playerManager.preferredBitrate = $0 }
                        )) {
                            Text("Авто").tag(Double(0))
                            Text("1080p (6 Mbps)").tag(Double(6_000_000))
                            Text("720p (3 Mbps)").tag(Double(3_000_000))
                            Text("480p (1.5 Mbps)").tag(Double(1_500_000))
                            Text("360p (800 Kbps)").tag(Double(800_000))
                            Text("240p (400 Kbps)").tag(Double(400_000))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .padding(.trailing, 8)
                        
                        // Кнопка отсоединения плеера в отдельное окно
                        if !viewModel.isPlayerDetached {
                            Button(action: {
                                viewModel.isPlayerDetached = true
                                openWindow(id: "detached-player")
                            }) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .help("Смотреть в отдельном окне")
                            .accessibilityLabel("Смотреть в отдельном окне")
                        }
                        
                        // Кнопка переключения полноэкранного режима
                        Button(action: {
                            if let window = NSApp.keyWindow {
                                window.toggleFullScreen(nil)
                            }
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        .help("Во весь экран")
                        .accessibilityLabel("Во весь экран")
                        
                        Button(action: {
                            viewModel.toggleFavorite(channelId: channel.id)
                        }) {
                            Image(systemName: viewModel.favoriteIds.contains(channel.id) ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundColor(viewModel.favoriteIds.contains(channel.id) ? .pink : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.favoriteIds.contains(channel.id) ? "Удалить из избранного" : "Добавить в избранное")
                        .accessibilityLabel(viewModel.favoriteIds.contains(channel.id) ? "Удалить из избранного" : "Добавить в избранное")
                        .padding()
                    }
                    .padding()
                    .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
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
    
    private func togglePlayPause() {
        let player = viewModel.playerManager.avPlayer
        if player.rate > 0 {
            player.pause()
        } else if player.currentItem != nil {
            player.play()
        }
    }
}

// MARK: - Строка Списка Каналов (ChannelRowView)
struct ChannelRowView: View {
    let channel: Channel
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Логотип с AsyncImage и кастомным Gradient Placeholder
            AsyncImage(url: channel.logo.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .cornerRadius(6)
                default:
                    // Красивый градиентный плейсхолдер с первой буквой канала
                    ZStack {
                        LinearGradient(
                            colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(String(channel.name.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                }
            }
            
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
                    if !channel.languages.isEmpty {
                        Text(channel.languages.joined(separator: ", ").uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Кнопка избранного, появляется при hover или если уже в избранном
            if isHovered || isFavorite {
                Button(action: onFavoriteToggle) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .pink : .secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .help(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
                .accessibilityLabel(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
            }
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
    }
}

// MARK: - Вспомогательная вьюха для размытия (VisualEffectView)
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
