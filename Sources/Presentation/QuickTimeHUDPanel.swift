#if canImport(SwiftUI) && canImport(AVFoundation)
// Sources/Presentation/QuickTimeHUDPanel.swift
import SwiftUI
import AVFoundation

// MARK: - Auto-Hide Modifier

/// Отслеживает движение мыши внутри окна и управляет видимостью HUD + системного курсора.
/// HUD исчезает через `hideDelay` секунд после прекращения движения.
struct AutoHideHUDModifier: ViewModifier {
    let hideDelay: TimeInterval
    @Binding var isVisible: Bool

    @State private var trackingTag: NSView.TrackingRectTag?
    @State private var hideTimer: Timer?

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isVisible)
            .background(HostingWindowAccessor { window in
                guard let contentView = window.contentView else { return }
                if let oldTag = trackingTag {
                    contentView.removeTrackingRect(oldTag)
                }
                trackingTag = contentView.addTrackingRect(
                    contentView.bounds,
                    owner: Coordinator.shared,
                    userData: nil,
                    assumeInside: false
                )
                Coordinator.shared.onMouseMoved = { scheduleShow() }
                Coordinator.shared.onMouseExited = { scheduleHide() }
            })
            .onAppear { scheduleShow() }
            .onDisappear {
                hideTimer?.invalidate()
                Coordinator.shared.onMouseMoved = nil
                Coordinator.shared.onMouseExited = nil
            }
    }

    private func scheduleShow() {
        hideTimer?.invalidate()
        NSCursor.unhide()
        if !isVisible {
            withAnimation(.easeInOut(duration: 0.25)) { isVisible = true }
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { _ in
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.25)) { isVisible = false }
        NSCursor.hide()
    }
}

private final class Coordinator: NSObject {
    static let shared = Coordinator()
    var onMouseMoved: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override init() {
        super.init()
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .leftMouseDown, .rightMouseDown]) { event in
            self.onMouseMoved?()
            return event
        }
    }
}

extension View {
    func autoHideHUD(isVisible: Binding<Bool>, hideDelay: TimeInterval = 3.0) -> some View {
        modifier(AutoHideHUDModifier(hideDelay: hideDelay, isVisible: isVisible))
    }
}

private struct HostingWindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { callback(window) }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - QuickTime HUD Panel

/// Стеклянная плавающая панель управления в стиле QuickTime Player.
public struct QuickTimeHUDPanel: View {
    let player: AVPlayer
    let channelName: String?
    let isFavorite: Bool

    var onToggleFullscreen: (() -> Void)?
    var onDetachPlayer: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var preferredBitrate: Binding<Double>?

    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var isSeeking: Bool = false
    @State private var volume: Float = 1.0
    @State private var timeObserverToken: Any?

    public init(
        player: AVPlayer,
        channelName: String? = nil,
        isFavorite: Bool = false,
        onToggleFullscreen: (() -> Void)? = nil,
        onDetachPlayer: (() -> Void)? = nil,
        onToggleFavorite: (() -> Void)? = nil,
        preferredBitrate: Binding<Double>? = nil
    ) {
        self.player = player
        self.channelName = channelName
        self.isFavorite = isFavorite
        self.onToggleFullscreen = onToggleFullscreen
        self.onDetachPlayer = onDetachPlayer
        self.onToggleFavorite = onToggleFavorite
        self.preferredBitrate = preferredBitrate
    }

    public var body: some View {
        VStack(spacing: 10) {
            timelineView
                .padding(.horizontal, 14)

            HStack(spacing: 12) {
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(isPlaying ? "Пауза" : "Воспроизвести")
                .accessibilityLabel(isPlaying ? "Пауза" : "Воспроизвести")

                HStack(spacing: 4) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 13))
                        .frame(width: 18)
                    Slider(value: $volume, in: 0...1) { _ in
                        player.volume = volume
                    }
                    .frame(width: 80)
                    .controlSize(.mini)
                    .help("Громкость")
                    .accessibilityLabel("Громкость")
                }

                Spacer()

                if let name = channelName {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                if let bitrateBinding = preferredBitrate {
                    Picker("", selection: bitrateBinding) {
                        Text("Авто").tag(Double(0))
                        Text("1080p").tag(Double(6_000_000))
                        Text("720p").tag(Double(3_000_000))
                        Text("480p").tag(Double(1_500_000))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 64)
                    .scaleEffect(0.85)
                    .help("Выбор качества")
                    .accessibilityLabel("Выбор качества")
                }

                if let detach = onDetachPlayer {
                    Button(action: detach) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .help("Смотреть в отдельном окне")
                }

                if let fullscreen = onToggleFullscreen {
                    Button(action: fullscreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .help("Во весь экран")
                }

                if let fav = onToggleFavorite {
                    Button(action: fav) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 15))
                            .foregroundColor(isFavorite ? .pink : nil)
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .onAppear { setupTimeObserver() }
        .onDisappear { removeTimeObserver() }
    }

    // MARK: - Timeline

    private var timelineView: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isSeeking ? currentTime : currentTime },
                    set: { newValue in
                        currentTime = newValue
                        let cmTime = CMTime(seconds: newValue, preferredTimescale: 600)
                        player.seek(to: cmTime)
                    }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in isSeeking = editing }
            )
            .controlSize(.mini)
            .tint(.white)

            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(formatTime(duration - currentTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Helpers

    private var isPlaying: Bool { player.rate > 0 }

    private var volumeIcon: String {
        if volume == 0 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func togglePlayPause() {
        if player.rate > 0 {
            player.pause()
        } else if player.currentItem != nil {
            player.play()
        }
    }

    private func setupTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isSeeking else { return }
            currentTime = time.seconds
            if let item = player.currentItem,
               item.duration.seconds.isFinite && !item.duration.seconds.isNaN {
                duration = item.duration.seconds
            }
        }
        timeObserverToken = token
        volume = player.volume
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - QuickTimeVideoContainer

/// Безрамочный контейнер: видео-холст + авто-скрывающийся HUD поверх.
public struct QuickTimeVideoContainer: View {
    let player: AVPlayer
    let playerState: PlayerState
    let channelName: String?
    let isFavorite: Bool

    var onToggleFullscreen: (() -> Void)?
    var onDetachPlayer: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var preferredBitrate: Binding<Double>?

    @State private var hudVisible: Bool = true

    public init(
        player: AVPlayer,
        playerState: PlayerState,
        channelName: String? = nil,
        isFavorite: Bool = false,
        onToggleFullscreen: (() -> Void)? = nil,
        onDetachPlayer: (() -> Void)? = nil,
        onToggleFavorite: (() -> Void)? = nil,
        preferredBitrate: Binding<Double>? = nil
    ) {
        self.player = player
        self.playerState = playerState
        self.channelName = channelName
        self.isFavorite = isFavorite
        self.onToggleFullscreen = onToggleFullscreen
        self.onDetachPlayer = onDetachPlayer
        self.onToggleFavorite = onToggleFavorite
        self.preferredBitrate = preferredBitrate
    }

    public var body: some View {
        ZStack {
            VideoPlayerView(player: player)

            // Буферизация / ошибки
            PlayerHUDOverlay(state: playerState, onRetry: nil)

            // QuickTime HUD при воспроизведении
            if case .playing = playerState {
                QuickTimeHUDPanel(
                    player: player,
                    channelName: channelName,
                    isFavorite: isFavorite,
                    onToggleFullscreen: onToggleFullscreen,
                    onDetachPlayer: onDetachPlayer,
                    onToggleFavorite: onToggleFavorite,
                    preferredBitrate: preferredBitrate
                )
                .autoHideHUD(isVisible: $hudVisible)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

#endif
