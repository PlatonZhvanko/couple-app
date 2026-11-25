import Foundation
import Observation
import SwiftData

/// Управляет синхронизацией между телефонами: статус и обмен данными с сервером.
///
/// Разделам приложения достаточно после изменений вызвать
/// `sync.requestSync()` (через `@Environment(SyncCoordinator.self)`).
/// Вход в аккаунт и адрес сервера хранит `AccountStore`.
@Observable
@MainActor
final class SyncCoordinator {
    enum Status: Equatable {
        /// Вход без сервера: данные только на этом телефоне.
        case localOnly
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .localOnly
    private(set) var lastSyncedAt: Date? = nil
    /// Растёт только когда с сервера пришли новые данные: экраны обновляются по нему, а не при каждом опросе.
    private(set) var dataVersion = 0

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private let adapters: [String: SyncAdapter]
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var runAgain = false

    private enum Keys {
        static let cursor = "sync.cursor"
        static let lastSynced = "sync.lastSyncedAt"
        static let knownKinds = "sync.knownKinds"
    }

    init(container: ModelContainer, models: [any PersistentModel.Type], account: AccountStore) {
        self.container = container
        self.account = account
        var adapters: [String: SyncAdapter] = [:]
        for model in models {
            if let syncable = model as? any SyncableModel.Type {
                let adapter = SyncAdapter.make(for: syncable)
                adapters[adapter.kind] = adapter
            }
        }
        self.adapters = adapters

        // Если в новой версии приложения появились новые типы записей,
        // забираем всё заново, чтобы получить их и со старых дат.
        // Версия полей записей: при её смене тоже забираем всё заново (старые сборки пропускали новые поля).
        let kinds = adapters.keys.sorted().joined(separator: ",") + "|fields3"
        if UserDefaults.standard.string(forKey: Keys.knownKinds) != kinds {
            UserDefaults.standard.removeObject(forKey: Keys.cursor)
            UserDefaults.standard.set(kinds, forKey: Keys.knownKinds)
        }
        lastSyncedAt = UserDefaults.standard.object(forKey: Keys.lastSynced) as? Date
        refreshStatus()
    }

    /// Вызывается при входе/выходе из аккаунта.
    func accountDidChange() {
        UserDefaults.standard.removeObject(forKey: Keys.cursor)
        UserDefaults.standard.removeObject(forKey: Keys.lastSynced)
        lastSyncedAt = nil
        refreshStatus()
        requestSync()
    }

    private func refreshStatus() {
        if !account.isServerMode {
            status = .localOnly
        } else if status == .localOnly {
            status = .idle
        }
    }

    // MARK: - Синхронизация

    /// Попросить синхронизацию «когда будет удобно». Можно вызывать часто.
    func requestSync() {
        Task { await syncNow() }
    }

    func syncNow() async {
        guard account.isServerMode, let client = account.client, client.session != nil else { return }
        if isRunning { runAgain = true; return }
        isRunning = true
        defer { isRunning = false }

        repeat {
            runAgain = false
            do {
                let changed = try await performSync(backend: SupabaseSyncBackend(client: client))
                // Тихий опрос без изменений не должен перерисовывать экраны (и мешать вводу текста).
                let now = Date.now
                if changed || lastSyncedAt == nil || now.timeIntervalSince(lastSyncedAt ?? now) > 60 {
                    lastSyncedAt = now
                    UserDefaults.standard.set(now, forKey: Keys.lastSynced)
                }
                if changed { dataVersion += 1 }
                if status != .idle { status = .idle }
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        } while runAgain
    }

    private func performSync(backend: some SyncBackend) async throws -> Bool {
        let context = container.mainContext
        var problems: [String] = []

        // 1. Отправляем свои изменения. Если пачку сервер не принял, пробуем по одной записи,
        // чтобы одна «плохая» запись не мешала остальным и приёму чужих изменений.
        var pending: [PendingRecord] = []
        for adapter in adapters.values {
            do { pending += try adapter.collectPending(context) }
            catch { problems.append("\(adapter.kind): \(error.localizedDescription)") }
        }
        // «Синхронизация…» показываем, только если есть что отправлять.
        if !pending.isEmpty, status != .syncing { status = .syncing }
        let chunkSize = 100
        var index = 0
        while index < pending.count {
            let chunk = Array(pending[index ..< min(index + chunkSize, pending.count)])
            index += chunkSize
            do {
                try await backend.push(chunk.map(\.record))
                chunk.forEach { $0.markSynced() }
            } catch {
                for item in chunk {
                    do {
                        try await backend.push([item.record])
                        item.markSynced()
                    } catch {
                        problems.append("\(item.record.kind): \(error.localizedDescription)")
                    }
                }
            }
        }
        if !pending.isEmpty { try context.save() }

        // 2. Забираем изменения со второго телефона.
        let cursor = UserDefaults.standard.object(forKey: Keys.cursor) as? Date
        let result = try await backend.pull(since: cursor)
        let grouped = Dictionary(grouping: result.records, by: \.kind)
        for (kind, records) in grouped {
            // Записи неизвестного типа (из более новой версии приложения) пропускаем.
            do { try adapters[kind]?.applyRemote(records, context) }
            catch { problems.append("\(kind): \(error.localizedDescription)") }
        }
        if !result.records.isEmpty { try context.save() }
        if let newCursor = result.cursor {
            UserDefaults.standard.set(newCursor, forKey: Keys.cursor)
        }
        if let first = problems.first {
            throw SyncIssue(message: "Часть записей не прошла (\(problems.count)): \(first)")
        }
        return !pending.isEmpty || !result.records.isEmpty
    }
}

private struct SyncIssue: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
