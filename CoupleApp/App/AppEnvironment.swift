import SwiftData

/// Собирает общие сервисы приложения в одном месте.
@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let account: AccountStore
    let sync: SyncCoordinator

    init(modelContainer: ModelContainer, account: AccountStore, sync: SyncCoordinator) {
        self.modelContainer = modelContainer
        self.account = account
        self.sync = sync
    }

    static func live() -> AppEnvironment {
        let container = AppDatabase.makeContainer()
        let account = AccountStore()
        let sync = SyncCoordinator(container: container, models: AppDatabase.allModels, account: account)
        account.onAccountChange = { [weak sync] in sync?.accountDidChange() }
        return AppEnvironment(modelContainer: container, account: account, sync: sync)
    }
}
