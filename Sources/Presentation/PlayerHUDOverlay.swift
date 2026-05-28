// Sources/Presentation/PlayerHUDOverlay.swift
import SwiftUI

/// HUD Оверлей поверх плеера для отображения состояний загрузки и ошибок
struct PlayerHUDOverlay: View {
    let state: PlayerState

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .loading(let stream):
                ZStack {
                    Color.black.opacity(0.6)
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Буферизация трансляции...")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text(stream.maskedUrlString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal)
                    }
                }
            case .playing:
                EmptyView()
            case .failed(let stream, let error):
                ZStack {
                    Color.black.opacity(0.8)
                    VStack(spacing: 16) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Ошибка воспроизведения")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Text(stream.maskedUrlString)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}
