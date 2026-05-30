#if canImport(SwiftUI) && canImport(SwiftData)
// App/IPTVApp.swift
import SwiftUI
import SwiftData
import IPTVPlayer

@main
struct IPTVApp: App {
    @StateObject private var viewModel: AppViewModel
    
    init() {
        // Настройка дискового кэша для AsyncImage на 100 МБ согласно ТЗ
        let memoryCapacity = 50 * 1024 * 1024 // 50 MB
        let diskCapacity = 100 * 1024 * 1024 // 100 MB
        let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: nil)
        URLCache.shared = cache
        
        // Внедрение зависимостей
        let repository = IPTVRepository()
        let filterEngine = ChannelFilterEngine()
        let playerManager = PlayerStateManager()
        
        // Настройка SwiftData контейнера для избранного и истории
        var modelContainer: ModelContainer? = nil
        do {
            modelContainer = try ModelContainer(for: PersistedChannel.self)
        } catch {
            print("Не удалось инициализировать SwiftData контейнер: \(error.localizedDescription)")
        }
        
        _viewModel = StateObject(wrappedValue: AppViewModel(
            repository: repository,
            filterEngine: filterEngine,
            playerManager: playerManager,
            modelContainer: modelContainer
        ))
    }
    
    var body: some Scene {
        WindowGroup {
            MainSplitView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .navigationTitle("IPTV Player Pro")
                .background(WindowAccessor { window in
                    window.isMovableByWindowBackground = false
                })
        }
        .windowStyle(.hiddenTitleBar) // Скрываем верхнюю плашку для максимального погружения
        
        Window("Проигрыватель", id: "detached-player") {
            DetachedPlayerView(viewModel: viewModel)
        }
    }
}

#if os(macOS)
struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#endif
