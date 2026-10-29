#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(AppKit)
// Sources/Presentation/QuickTimeHUDPanel.swift
import SwiftUI
import AVFoundation
import AppKit

// MARK: - QuickTime HUD Panel

/// Стеклянная плавающая панель управления в стиле QuickTime Player.
public struct QuickTimeHUDPanel: View {
    let player: AVPlayer
    let channelName: String?
    let isFavorite: Bool
    let isPaused: Bool

    var onTogglePlayPause: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onDetachPlayer: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var preferredBitrate: Binding<Double>?

    @StateObject private var clock = HUDTimeModel()
    @State private var volume: Float = 1.0
    @State private var timeObserverToken: Any?

    public init(
        player: AVPlayer,
        channelName: String? = nil,
        isFavorite: Bool = false,
        isPaused: Bool = true,
        onTogglePlayPause: (() -> Void)? = nil,
        onToggleFullscreen: (() -> Void)? = nil,
        onDetachPlayer: (() -> Void)? = nil,
        onToggleFavorite: (() -> Void)? = nil,
        preferredBitrate: Binding<Double>? = nil
    ) {
        self.player = player
        self.channelName = channelName
        self.isFavorite = isFavorite
        self.isPaused = isPaused
        self.onTogglePlayPause = onTogglePlayPause
        self.onToggleFullscreen = onToggleFullscreen
        self.onDetachPlayer = onDetachPlayer
        self.onToggleFavorite = onToggleFavorite
        self.preferredBitrate = preferredBitrate
    }

    public var body: some View {
        VStack(spacing: Spacing.m) {
            timelineView
                .padding(.horizontal, Spacing.l)

            HStack(spacing: Spacing.l) {
                Button(action: { onTogglePlayPause?() }) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: Layout.playControl, height: Layout.playControl)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                HStack(spacing: Spacing.xs) {
                    Image(systemName: volumeIcon)
                        .font(.caption)
                        .frame(width: Spacing.xl)
                    Slider(value: $volume, in: 0...1) { _ in
                        player.volume = volume
                    }
                    .frame(width: Layout.volumeSlider)
                    .controlSize(.mini)
                }

                Spacer()

                if let name = channelName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(Palette.hudInk.opacity(0.7))
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
                    .frame(width: Layout.bitrateMenu)
                }

                if let detach = onDetachPlayer {
                    Button(action: detach) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: Layout.hudIcon))
                    }
                    .buttonStyle(.plain)
                    .help("Смотреть в отдельном окне")
                }

                if let fullscreen = onToggleFullscreen {
                    Button(action: fullscreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: Layout.hudIcon))
                    }
                    .buttonStyle(.plain)
                    .help("Во весь экран")
                }

                if let fav = onToggleFavorite {
                    Button(action: fav) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: Layout.hudIcon))
                            .foregroundStyle(isFavorite ? Palette.favorite : Palette.hudInk)
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
                }
            }
            .padding(.horizontal, Spacing.l)
        }
        .padding(.vertical, Spacing.l)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: Radius.hud))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.hud)
                        .stroke(Palette.hudInk.opacity(0.15), lineWidth: Layout.hairline)
                )
        )
        .padding(.horizontal, Spacing.xxl)
        .padding(.bottom, Spacing.xxl)
        .onAppear { setupTimeObserver() }
        .onDisappear { removeTimeObserver() }
    }

    // MARK: - Timeline

    private var timelineView: some View {
        VStack(spacing: Spacing.xs) {
            if clock.isLiveStream {
                HStack(spacing: Spacing.s) {
                    Circle()
                        .fill(Palette.live)
                        .frame(width: Spacing.s, height: Spacing.s)
                    Text("LIVE")
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(Palette.hudInk.opacity(0.7))
                    Spacer()
                    Text(formatTime(clock.currentTime))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Palette.hudInk.opacity(0.5))
                }
            } else {
                Slider(
                    value: Binding(
                        get: { clock.currentTime },
                        set: { newValue in
                            clock.currentTime = newValue
                            let cmTime = CMTime(seconds: newValue, preferredTimescale: 600)
                            player.seek(to: cmTime)
                        }
                    ),
                    in: 0...max(clock.duration, 1),
                    onEditingChanged: { editing in clock.isSeeking = editing }
                )
                .controlSize(.mini)
                .tint(Palette.hudInk)

                HStack {
                    Text(formatTime(clock.currentTime))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Palette.hudInk.opacity(0.5))
                    Spacer()
                    Text(formatTime(clock.duration - clock.currentTime))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Palette.hudInk.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Helpers

    private var volumeIcon: String {
        if volume == 0 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func setupTimeObserver() {
        removeTimeObserver()
        // 1s base interval (was 0.5s); live streams further throttle @State writes
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        let playerRef = player
        let clock = clock
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                clock.apply(seconds: seconds, itemDuration: playerRef.currentItem?.duration.seconds)
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
        PlaybackClock.format(seconds)
    }
}

#endif
