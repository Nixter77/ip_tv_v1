#if canImport(SwiftUI) && canImport(SwiftData)
// App/IPTVApp.swift — composition root
import SwiftUI
import SwiftData
import IPTVPlayer

@main
struct IPTVApp: App {
    @StateObject private var viewModel: AppViewModel
    @StateObject private var commands: AppCommandCenter
    
    init() {
        // URLCache только для логотипов (API-плейлист — отдельный PlaylistDiskCache).
        // Logo bodies are capped at 512 KB; 16/48 MB is enough for visible rows.
        let memoryCapacity = 16 * 1024 * 1024
        let diskCapacity = 48 * 1024 * 1024
        let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: nil)
        URLCache.shared = cache
        
        // Composition root: Data + Domain adapters → Presentation
        let repository = IPTVRepository()
        let filterEngine = ChannelFilterEngine()
        let playerManager = PlayerStateManager()
        let commandCenter = AppCommandCenter()
        
        var modelContainer: ModelContainer? = nil
        var persistenceWarning: String? = nil
        do {
            modelContainer = try ModelContainer(for: PersistedChannel.self)
        } catch {
            AppLog.persistence.error("SwiftData container failed: \(error.localizedDescription, privacy: .public)")
            persistenceWarning = "Избранное и история недоступны (ошибка хранилища)"
        }
        
        _commands = StateObject(wrappedValue: commandCenter)
        _viewModel = StateObject(wrappedValue: AppViewModel(
            repository: repository,
            filterEngine: filterEngine,
            playerManager: playerManager,
            modelContainer: modelContainer,
            persistenceUnavailableMessage: persistenceWarning
        ))
    }
    
    var body: some Scene {
        WindowGroup {
            MainSplitView(viewModel: viewModel, commands: commands)
                .frame(minWidth: 900, minHeight: 600)
                .navigationTitle("IPTV Player Pro")
                .background(WindowAccessor { window in
                    window.isMovableByWindowBackground = false
                })
        }
        .windowToolbarStyle(.unified)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Поиск канала") {
                    commands.requestFocusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Обновить плейлист") {
                    commands.requestReload()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        
        Window("Проигрыватель", id: "detached-player") {
            DetachedPlayerView(viewModel: viewModel)
        }
    }
}

#endif
