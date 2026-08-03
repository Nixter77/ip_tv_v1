#if canImport(SwiftUI) && canImport(AppKit) && canImport(ImageIO)
// Sources/Presentation/ChannelLogoView.swift
import SwiftUI
import AppKit
import ImageIO

/// Загрузка логотипа с даунсэмплингом через ImageIO (без полной декодировки исходника в RAM).
struct ChannelLogoView: View {
    let url: URL?
    let name: String
    var maxPixelSize: CGFloat = 88 // 44pt @2x

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .accessibilityLabel("Логотип канала \(name)")
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(String(name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                }
                .frame(width: 44, height: 44)
                .cornerRadius(6)
                .accessibilityLabel("Логотип \(name) отсутствует")
            }
        }
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        guard let url else { return }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

        if let cached = URLCache.shared.cachedResponse(for: request),
           let downsampled = Self.downsample(data: cached.data, maxPixelSize: maxPixelSize) {
            image = downsampled
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                let cached = CachedURLResponse(response: response, data: data)
                URLCache.shared.storeCachedResponse(cached, for: request)
            }
            if let downsampled = Self.downsample(data: data, maxPixelSize: maxPixelSize) {
                image = downsampled
            }
        } catch {
            // placeholder остаётся
        }
    }

    /// ImageIO thumbnail — O(target pixels), не full-res decode
    static func downsample(data: Data, maxPixelSize: CGFloat) -> NSImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

#endif
