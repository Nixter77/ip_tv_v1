#if canImport(SwiftUI) && canImport(AppKit) && canImport(ImageIO)
// Sources/Presentation/ChannelLogoView.swift
import SwiftUI
import AppKit
import ImageIO

/// Загрузка логотипа с даунсэмплингом через ImageIO (без полной декодировки исходника в RAM).
struct ChannelLogoView: View {
    let url: URL?
    let name: String
    var maxPixelSize: CGFloat = Layout.logoPixel

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Layout.logo, height: Layout.logo)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                    .accessibilityLabel("Логотип канала \(name)")
            } else {
                ZStack {
                    Palette.logoFallback(for: name)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(Palette.hudInk)
                        .fontWeight(.bold)
                }
                .frame(width: Layout.logo, height: Layout.logo)
                .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                .accessibilityLabel("Логотип \(name) отсутствует")
            }
        }
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        guard let url,
              RemoteURLPolicy.validatedURL(from: url.absoluteString, kind: .remoteAsset) != nil else {
            return
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        let maxBytes = RemoteURLPolicy.maxLogoBytes

        // Cached bytes are already local — skip DNS so offline placeholders still resolve.
        if let cached = URLCache.shared.cachedResponse(for: request),
           cached.data.count <= maxBytes,
           let downsampled = Self.downsample(data: cached.data, maxPixelSize: maxPixelSize) {
            image = downsampled
            return
        }

        if let host = url.host, !RemoteURLPolicy.isLiteralIPAddress(host) {
            let publicDNS = await RemoteURLPolicy.resolvesOnlyToPublicAddresses(host: host)
            guard publicDNS else { return }
        }

        do {
            let (data, response) = try await SafeHTTPClient.shared.data(
                for: url,
                maxBytes: maxBytes,
                kind: .remoteAsset
            )
            guard data.count <= maxBytes else { return }
            guard let downsampled = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                return
            }
            image = downsampled
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                URLCache.shared.storeCachedResponse(
                    CachedURLResponse(response: response, data: data),
                    for: request
                )
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
