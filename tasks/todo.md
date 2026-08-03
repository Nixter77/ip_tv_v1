# Task: Clean Architecture refactor

- [x] Domain: pure entities (no Decodable) + ports (Playlist, UserLibrary, StreamPlayer)
- [x] Application: CatalogLoadPolicy + LoadCatalogUseCase + CatalogErrorMapper
- [x] Data: PlaylistDTOs, IPTVRepository → PlaylistRepository, SwiftDataUserLibraryRepository
- [x] Presentation: thin AppViewModel, AppCommandCenter (typed commands)
- [x] Composition root in IPTVApp
- [x] `swift test` — 30/30

## Architecture after
```
App (composition) → Presentation (VM/Views)
                 → Application (use cases)
                 → Domain (entities, ports, FilterEngine)
                 ← Data / Playback adapters implement ports
```

Note: single SPM target (folder-level boundaries; multi-target optional follow-up).
