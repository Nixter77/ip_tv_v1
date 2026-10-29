#if canImport(SwiftUI)
// Sources/Presentation/SidebarColumn.swift
import SwiftUI

struct SidebarColumn: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedTab },
            set: { tab in
                if let tab { viewModel.selectedTab = tab }
            }
        )) {
            Section("Библиотека") {
                if let title = viewModel.nowPlayingTitle {
                    Label(title, systemImage: "dot.radiowaves.left.and.right")
                }
                NavigationLink(value: SidebarTab.all) {
                    Label("Все каналы", systemImage: "tv")
                }
                NavigationLink(value: SidebarTab.favorites) {
                    Label("Избранное", systemImage: "heart.fill")
                        .foregroundStyle(Palette.favorite)
                }
                NavigationLink(value: SidebarTab.history) {
                    Label("История", systemImage: "clock.arrow.circlepath")
                }
            }
            countSection("Категории", systemImage: "folder") { category in
                (SidebarTab.category(category.id), category.name.capitalized, viewModel.catalog.categoryCounts[category.id.lowercased(), default: 0])
            } rows: {
                viewModel.categories
            }
            countrySection
            languageSection
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var countrySection: some View {
        Section("Страны") {
            ForEach(viewModel.countries.filter { viewModel.catalog.countryCounts[$0.code.uppercased(), default: 0] > 0 }) { country in
                NavigationLink(value: SidebarTab.country(country.code)) {
                    HStack(spacing: Spacing.m) {
                        Text(country.flag ?? "🌐")
                        Text(country.name).lineLimit(1)
                        Spacer()
                        Text("\(viewModel.catalog.countryCounts[country.code.uppercased(), default: 0])")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var languageSection: some View {
        Section("Языки") {
            ForEach(viewModel.languages.filter { viewModel.catalog.languageCounts[$0.code.lowercased(), default: 0] > 0 }) { language in
                NavigationLink(value: SidebarTab.language(language.code)) {
                    HStack {
                        Text(language.name).lineLimit(1)
                        Spacer()
                        Text("\(viewModel.catalog.languageCounts[language.code.lowercased(), default: 0])")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Toggle("Каналы 18+", isOn: Binding(
                get: { viewModel.showNSFW },
                set: { viewModel.showNSFW = $0 }
            ))
            Toggle("Закрытые каналы", isOn: Binding(
                get: { viewModel.showClosed },
                set: { viewModel.showClosed = $0 }
            ))
            Button {
                Task { await viewModel.reloadPlaylist() }
            } label: {
                Label("Обновить плейлист", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Обновить плейлист (⌘R)")
        }
        .font(.callout)
        .padding(Spacing.l)
    }

    @ViewBuilder
    private func countSection<Row: RandomAccessCollection>(
        _ title: String,
        systemImage: String,
        label: @escaping (Row.Element) -> (SidebarTab, String, Int),
        rows: () -> Row
    ) -> some View where Row.Element: Identifiable {
        let visible = rows().filter { label($0).2 > 0 }
        if !visible.isEmpty {
            Section(title) {
                ForEach(visible) { row in
                    let item = label(row)
                    NavigationLink(value: item.0) {
                        HStack {
                            Label(item.1, systemImage: systemImage)
                            Spacer()
                            Text("\(item.2)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
#endif
