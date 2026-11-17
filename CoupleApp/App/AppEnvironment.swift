import SwiftData

/// Собирает общие сервисы приложения в одном месте.
@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let sync: SyncCoordinator

    init(modelContainer: ModelContainer, sync: SyncCoordinator) {
        self.modelContainer = modelContainer
        self.sync = sync
    }

    static func live() -> AppEnvironment {
        let container = AppDatabase.makeContainer()
        let sync = SyncCoordinator(container: container, models: AppDatabase.allModels)
        return AppEnvironment(modelContainer: container, sync: sync)
    }
}
