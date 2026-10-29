#if canImport(Combine)
// Sources/Presentation/CatalogStore+Loading.swift
import Foundation
import Combine

extension CatalogStore {
    func performLoad(soft: Bool) async {
        let keepUI = soft && hasCatalog
        if keepUI {
            isRefreshing = true
        } else {
            loadingState = .loading
        }
        let policy: CatalogLoadPolicy = soft ? .forceNetwork : .cacheFirstThenRevalidate
        do {
            let result = try await loadCatalog.execute(
                policy: policy,
                fallbackCategories: keepUI ? categories : [],
                fallbackCountries: keepUI ? countries : [],
                fallbackLanguages: keepUI ? languages : []
            )
            guard !Task.isCancelled else {
                isRefreshing = false
                return
            }
            categories = result.categories
            countries = result.countries
            languages = result.languages
            namesByID = Dictionary(result.channels.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
            loadingState = .ready
            await publishFilter()
            isRefreshing = false
            if !result.metaWarnings.isEmpty {
                statusBanner = "Не удалось обновить: \(result.metaWarnings.joined(separator: ", ")). Показаны предыдущие/пустые списки."
                statusSeverity = .warning
            }
            if result.shouldScheduleRevalidate {
                scheduleBackgroundRevalidate()
            }
        } catch is CancellationError {
            isRefreshing = false
        } catch {
            guard !Task.isCancelled else {
                isRefreshing = false
                return
            }
            isRefreshing = false
            let message = CatalogErrorMapper.userMessage(for: error)
            if keepUI {
                statusBanner = message
                statusSeverity = .error
            } else {
                loadingState = .error(message)
            }
        }
    }

    func scheduleBackgroundRevalidate() {
        revalidateTask?.cancel()
        revalidateTask = Task { [weak self] in
            try? await self?.clock.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            await self?.backgroundRevalidate()
        }
    }

    func backgroundRevalidate() async {
        do {
            let result = try await loadCatalog.execute(
                policy: .backgroundRevalidate,
                fallbackCategories: categories,
                fallbackCountries: countries,
                fallbackLanguages: languages
            )
            guard !Task.isCancelled else { return }
            categories = result.categories
            countries = result.countries
            languages = result.languages
            namesByID = Dictionary(result.channels.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
            await publishFilter()
        } catch is CancellationError {
        } catch {
            AppLog.catalog.error("Background revalidate kept the current catalog")
        }
    }

}
#endif
