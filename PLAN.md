# PLAN.md — ФАЗА 2: DEFINE (ОБНОВЛЕННЫЙ)

Этот документ содержит полную матрицу тест-кейсов для верификации IPTV-приложения по методологии TDD, а также план архитектурной реализации.

---

## 1. Матрица тест-кейсов (TDD Test Matrix)

| Модуль | Тест-кейс | Входные данные | Ожидаемый результат |
|---|---|---|---|
| **JSONParser** | `test_validChannelDecoding` | JSON-объект канала со всеми заполненными полями | Успешно декодированный `Channel` с корректными полями |
| **JSONParser** | `test_missingOptionalFieldsDecoding` | JSON-объект канала, где отсутствуют `country`, `logo`, `website` | Успешно декодированный `Channel` с `nil` в этих полях (без падения парсинга) |
| **JSONParser** | `test_corruptedStreamArrayDecoding` | Массив стримов, где один стрим поврежден (битый JSON), а остальные валидны | Валидные стримы декодированы, битый стрим пропущен (база не ломается целиком) |
| **FilterEngine** | `test_intersectLanguageAndCountry` | Фильтр `language = "eng"`, `country = "US"` | Возвращаются только каналы, удовлетворяющие обоим критериям одновременно |
| **FilterEngine** | `test_tokenizedSearchPrefixMatching` | Поисковый запрос "new" для каналов "CNN News" и "Newsline" | Оба канала находятся по префиксу токена, регистронезависимо |
| **FilterEngine** | `test_searchFoldsDiacritics` | Поисковый запрос "ct" для канала "ČT 1" | Канал находится благодаря свертыванию диакритических знаков |
| **FilterEngine** | `test_performanceWith50kChannels` | Искусственно сгенерированная база из 50,000 каналов и 70,000 потоков | Время фильтрации и текстового поиска составляет менее 50 мс |
| **PlayerStateManager** | `test_streamPlaybackTimeout` | Поток, не отдающий видеоданные (эмуляция задержки 8 секунд) | Состояние переходит в `.failed` по таймауту ровно через 8 секунд |
| **PlayerStateManager** | `test_automaticFallbackToNextStream` | Канал с 2 потоками: 1-й мертв (дает ошибку), 2-й рабочий | Плеер автоматически переключается на 2-й поток и переходит в `.playing` |
| **PlayerStateManager** | `test_circularFallbackPrevention` | Канал с 2 потоками, оба из которых мертвы | После неудачной попытки проиграть все потоки плеер останавливается в состоянии `.failed`, не уходя в бесконечный цикл |
| **PlayerStateManager** | `test_rapidChannelZappingCancellation` | Быстрый выбор канала Б во время загрузки канала А | Загрузка канала А немедленно отменяется, ресурсы освобождаются, начинает играть канал Б |
| **PlayerStateManager** | `test_playerReleasesResourcesOnStop` | Вызов `stop()` во время воспроизведения | Все ссылки на `AVPlayerItem`, KVO-наблюдатели обнуляются, фоновые таймеры отменяются |
| **SwiftData** | `test_persistFavoriteChannel` | Добавление канала в избранное и последующее удаление в in-memory БД | Канал сохраняется в SwiftData хранилище и удаляется из него без влияния на дисковый кэш |

---

## 2. Архитектурный план реализации (По модулям)

### Модуль 3.1: Data Layer (JSONParser)
- **Цель:** Написать `IPTVRepository` и парсеры, способные быстро обрабатывать большие объемы данных из сети и локального кэша.
- **Тесты:** `ChannelRepositoryTests.swift` в `IPTVPlayerTests/`.
- **Продакшн код:** `Sources/Data/IPTVRepository.swift`.

### Модуль 3.2: Domain Layer (FilterEngine)
- **Цель:** Реализовать `ChannelFilterEngine` как `actor` для безопасной и сверхбыстрой фильтрации 50k+ каналов.
- **Тесты:** `ChannelFilterEngineTests.swift` в `IPTVPlayerTests/`.
- **Продакшн код:** `Sources/Domain/FilterEngine.swift`.

### Модуль 3.3: Domain Layer (PlayerStateManager)
- **Цель:** Реализовать управление `AVPlayer` с таймаутами через `async/await` и авто-фолбэком.
- **Тесты:** `PlayerStateManagerTests.swift` в `IPTVPlayerTests/`.
- **Продакшн код:** `Sources/Domain/PlayerStateManager.swift`.

### Модуль 3.4: Presentation Layer (SwiftUI Views)
- **Цель:** Построить современный, красивый трехпанельный интерфейс macOS (Sidebar + List + Detail).
- **Клавиатурные шорткаты:**
  - `Space` — пауза/воспроизведение.
  - `⌘F` — фокус на строку поиска.
  - `⌘R` — перезагрузка плейлиста.
- **Продакшн код:** Views и ViewModels в `Sources/Presentation/`.

### Модуль 3.5: Persistence (SwiftData)
- **Цель:** Реализовать хранение избранного, истории просмотров (до 50 последних каналов) и кэширование фильтров.
- **Продакшн код:** `Sources/Data/Persistence/`.

---
