#if canImport(SwiftData)
// Tests/SwiftDataTests.swift
import XCTest
import SwiftData
@testable import IPTVPlayer

@MainActor
final class SwiftDataTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        do {
            // Создаем изолированный In-Memory контейнер для юнит-тестирования
            let schema = Schema([PersistedChannel.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try ModelContainer(for: schema, configurations: [config])
            context = container.mainContext
        } catch {
            XCTFail("Не удалось инициализировать SwiftData контейнер: \(error)")
        }
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    /// Тест: Добавление канала в избранное и его последующее удаление в SwiftData
    func test_persistFavoriteChannel() throws {
        let channelId = "cnn"
        let channelName = "CNN News"
        
        // 1. Создаем и сохраняем объект
        let persisted = PersistedChannel(id: channelId, name: channelName, isFavorite: true)
        context.insert(persisted)
        try context.save()
        
        // 2. Делаем запрос из базы и проверяем корректность сохранения
        let descriptor = FetchDescriptor<PersistedChannel>()
        let items = try context.fetch(descriptor)
        
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, channelId)
        XCTAssertEqual(items.first?.name, channelName)
        XCTAssertEqual(items.first?.isFavorite, true)
        
        // 3. Проверяем уникальность (попытка вставить дубликат с тем же ID должна обновить существующий объект или вызвать бесконфликтное слияние)
        let duplicate = PersistedChannel(id: channelId, name: "CNN Updated", isFavorite: true)
        context.insert(duplicate)
        try context.save()
        
        let itemsAfterDup = try context.fetch(descriptor)
        XCTAssertEqual(itemsAfterDup.count, 1, "Уникальный ID должен предотвращать создание дубликатов")
        
        // 4. Удаляем объект
        if let toDelete = itemsAfterDup.first {
            context.delete(toDelete)
            try context.save()
        }
        
        let itemsAfterDelete = try context.fetch(descriptor)
        XCTAssertTrue(itemsAfterDelete.isEmpty, "Объект должен быть успешно удален из базы")
    }

    func test_recordView_prunesHistoryBeyondLimit() async throws {
        let library = SwiftDataUserLibraryRepository(modelContext: context, historyLimit: 3)
        for i in 1...5 {
            try await library.recordView(id: "ch\(i)", name: "Channel \(i)")
        }
        let items = try context.fetch(FetchDescriptor<PersistedChannel>())
        XCTAssertEqual(items.count, 3)
        let state = try await library.load()
        XCTAssertEqual(state.historyIds.count, 3)
        XCTAssertEqual(state.historyIds.first, "ch5")
        XCTAssertFalse(state.historyIds.contains("ch1"))
        XCTAssertFalse(state.historyIds.contains("ch2"))
    }

    func test_setFavorite_truncatesOversizedIdentity() async throws {
        let library = SwiftDataUserLibraryRepository(modelContext: context)
        let longID = String(repeating: "a", count: 400)
        let longName = String(repeating: "n", count: 400)
        try await library.setFavorite(id: longID, name: longName, isFavorite: true)
        let items = try context.fetch(FetchDescriptor<PersistedChannel>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id.count, RemoteURLPolicy.maxPersistedIDLength)
        XCTAssertEqual(items.first?.name.count, RemoteURLPolicy.maxPersistedNameLength)
    }
}

#endif
