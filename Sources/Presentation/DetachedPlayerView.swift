// Sources/Presentation/DetachedPlayerView.swift
import SwiftUI
import AVFoundation

/// Окно видеоплеера, предназначенное для отдельного (отсоединенного) просмотра
public struct DetachedPlayerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Монитор клавиатурных событий для отслеживания клавиши Esc
    @State private var escapeMonitor: Any? = nil
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.playerManager.currentChannel != nil {
                ZStack {
                    // Видео-плеер
                    VideoPlayerView(player: viewModel.playerManager.avPlayer)
                        .ignoresSafeArea()
                    
                    // HUD Оверлей загрузки или ошибок
                    PlayerHUDOverlay(state: viewModel.playerManager.state)
                    
                    // Кнопки управления в левом верхнем углу
                    VStack {
                        HStack(spacing: 12) {
                            Button(action: {
                                dismiss()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    Text("Вернуть в главное окно")
                                }
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(6)
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            
                            // Кнопка полноэкранного режима
                            Button(action: {
                                if let window = NSApp.keyWindow {
                                    window.toggleFullScreen(nil)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    Text("Во весь экран")
                                }
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(6)
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                        .padding()
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "tv.music.note")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Нет активной трансляции")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .navigationTitle(viewModel.playerManager.currentChannel?.name ?? "Проигрыватель")
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
            // Мгновенный возврат плеера в главное окно при закрытии
            viewModel.isPlayerDetached = false
        }
    }
    
}
