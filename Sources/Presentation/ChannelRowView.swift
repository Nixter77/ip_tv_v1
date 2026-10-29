#if canImport(SwiftUI)
// Sources/Presentation/ChannelRowView.swift
import SwiftUI
import AppKit

struct ChannelRowView: View {
    let channel: Channel
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void

    private let logoURL: URL?
    private let languagesLabel: String
    @State private var isHovered = false

    init(channel: Channel, isFavorite: Bool, onFavoriteToggle: @escaping () -> Void) {
        self.channel = channel
        self.isFavorite = isFavorite
        self.onFavoriteToggle = onFavoriteToggle
        self.logoURL = channel.safeLogoURL
        self.languagesLabel = channel.languages.joined(separator: ", ").uppercased()
    }

    var body: some View {
        HStack(spacing: Spacing.l) {
            ChannelLogoView(url: logoURL, name: channel.name)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(channel.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: Spacing.m) {
                    if let country = channel.country {
                        Text(country)
                            .font(.caption)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Palette.chip)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.s))
                    }
                    if !languagesLabel.isEmpty {
                        Text(languagesLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? Palette.favorite : Color.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isFavorite ? 1 : 0)
            .help(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
            .accessibilityLabel(isFavorite ? "Удалить из избранного" : "Добавить в избранное")
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.m)
        .background(isHovered ? Palette.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channel.name)
        .accessibilityAction(named: Text("В избранное"), onFavoriteToggle)
        .contextMenu {
            Button(action: onFavoriteToggle) {
                Label(
                    isFavorite ? "Удалить из избранного" : "Добавить в избранное",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.name, forType: .string)
            } label: {
                Label("Копировать название", systemImage: "doc.on.doc")
            }
        }
    }
}
#endif
