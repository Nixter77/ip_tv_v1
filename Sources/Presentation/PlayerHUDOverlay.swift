#if canImport(SwiftUI)
// Sources/Presentation/PlayerHUDOverlay.swift
import SwiftUI

/// HUD Оверлей поверх плеера для отображения состояний загрузки и ошибок
struct PlayerHUDOverlay: View {
    let state: PlayerState
    var onRetry: (() -> Void)? = nil

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .loading(let stream):
                ZStack {
                    Palette.video.opacity(0.6)
                    VStack(spacing: Spacing.xl) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Palette.hudInk))
                        Text("Буферизация трансляции...")
                            .foregroundStyle(Palette.hudInk)
                            .font(.headline)
                        Text(stream.maskedUrlString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.l)
                    }
                }
            case .playing:
                EmptyView()
            case .failed(let stream, let error):
                ZStack {
                    Palette.video.opacity(0.8)
                    VStack(spacing: Spacing.xl) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Palette.error)
                        Text("Ошибка воспроизведения")
                            .font(.headline)
                            .foregroundStyle(Palette.hudInk)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.l)
                        Text(stream.maskedUrlString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.l)

                        if let onRetry = onRetry {
                            Button(action: onRetry) {
                                Label("Попробовать снова", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .tint(Palette.hudInk)
                            .padding(.top, Spacing.m)
                            .help("Попробовать загрузить поток еще раз")
                            .accessibilityLabel("Попробовать снова")
                        }
                    }
                }
            }
        }
    }
}

#endif
