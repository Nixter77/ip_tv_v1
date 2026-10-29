#if canImport(SwiftUI)
// Sources/Presentation/StatusBannerView.swift
import SwiftUI

struct StatusBannerView: View {
    let message: String
    let severity: StatusSeverity
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.m)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Скрыть")
            .accessibilityLabel("Скрыть уведомление")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(wash)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch severity {
        case .info: return Palette.info
        case .warning: return Palette.warning
        case .error: return Palette.error
        }
    }

    private var wash: Color {
        switch severity {
        case .info: return Palette.infoWash
        case .warning: return Palette.warningWash
        case .error: return Palette.errorWash
        }
    }
}
#endif
