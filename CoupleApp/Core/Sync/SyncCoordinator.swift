import Foundation
import Observation
import SwiftData

/// Управляет синхронизацией: хранит настройки, вход, статус
/// и запускает обмен данными с сервером.
///
/// Разделам приложения достаточно после изменений вызвать
/// `sync.requestSync()` (через `@Environment(SyncCoordinator.self)`).
@Observable
@MainActor
final class SyncCoordinator {
    enum Status: Equatable {
        case notConfigured
        case signedOut
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .notConfigured
    private(set) var lastSyncedAt: Date?
    private(set) var signedInEmail: String?
    private(set) var config: SupabaseConfig

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let adapters: [String: SyncAdapter]
    @ObservationIgnored private var client: SupabaseClient?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var runAgain = false

    private enum Keys {
        static let config = "sync.supabase.config"
        static let session = "sync.supabase.session"
        static let cursor = "sync.cursor"
        static let lastSynced = "sync.lastSyncedAt"
        static let knownKinds = "sync.knownKinds"
    }

    init(container: ModelContainer, models: [any PersistentModel.Type]) {
        self.container = container
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
        let kinds = adapters.keys.sorted().joined(separator: ",")
        if UserDefaults.standard.string(forKey: Keys.knownKinds) != kinds {
            UserDefaults.standard.removeObject(forKey: Keys.cursor)
            UserDefaults.standard.set(kinds, forKey: Keys.knownKinds)
        }

        let defaults = UserDefaults.standard
        config = defaults.data(forKey: Keys.config)
            .flatMap { try? JSONDecoder().decode(SupabaseConfig.self, from: $0) } ?? SupabaseConfig()
        lastSyncedAt = defaults.object(forKey: Keys.lastSynced) as? Date
        let session = KeychainStore.data(for: Keys.session)
            .flatMap { try? JSONDecoder().decode(SupabaseSession.self, from: $0) }
        rebuildClient(session: session)
    }

    // MARK: - Настройки и вход

    func updateConfig(_ newConfig: SupabaseConfig) {
        guard newConfig != config else { return }
        config = newConfig
        UserDefaults.standard.set(try? JSONEncoder().encode(newConfig), forKey: Keys.config)
        resetCursor()
        rebuildClient(session: nil)
    }

    func signIn(email: String, password: String) async {
        guard let client else { status = .notConfigured; return }
        do {
            try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            resetCursor()
            await syncNow()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        client?.signOut()
        resetCursor()
    }

    // MARK: - Синхронизация

    /// Попросить синхронизацию «когда будет удобно». Можно вызывать часто.
    func requestSync() {
        Task { await syncNow() }
    }

    func syncNow() async {
        guard let client, client.session != nil else { return }
        if isRunning { runAgain = true; return }
        isRunning = true
        defer { isRunning = false }

        repeat {
            runAgain = false
            status = .syncing
            do {
                try await performSync(backend: SupabaseSyncBackend(client: client))
                lastSyncedAt = .now
                UserDefaults.standard.set(lastSyncedAt, forKey: Keys.lastSynced)
                status = .idle
            } catch {
                status = client.session == nil ? .signedOut : .failed(error.localizedDescription)
                return
            }
        } while runAgain
    }

    private func performSync(backend: some SyncBackend) async throws {
        let context = container.mainContext

        // 1. Отправляем свои изменения.
        let pending = try adapters.values.flatMap { try $0.collectPending(context) }
        if !pending.isEmpty {
            try await backend.push(pending.map(\.record))
            pending.forEach { $0.markSynced() }
            try context.save()
        }

        // 2. Забираем изменения со второго телефона.
        let cursor = UserDefaults.standard.object(forKey: Keys.cursor) as? Date
        let result = try await backend.pull(since: cursor)
        let grouped = Dictionary(grouping: result.records, by: \.kind)
        for (kind, records) in grouped {
            // Записи неизвестного типа (из более новой версии приложения) пропускаем.
            try adapters[kind]?.applyRemote(records, context)
        }
        try context.save()
        if let newCursor = result.cursor {
            UserDefaults.standard.set(newCursor, forKey: Keys.cursor)
        }
    }

    // MARK: - Внутреннее

    private func resetCursor() {
        UserDefaults.standard.removeObject(forKey: Keys.cursor)
    }

    private func rebuildClient(session: SupabaseSession?) {
        guard config.isComplete else {
            client = nil
            signedInEmail = nil
            KeychainStore.set(nil, for: Keys.session)
            status = .notConfigured
            return
        }
        let client = SupabaseClient(config: config, session: session)
        client.onSessionChange = { [weak self] session in
            self?.handleSessionChange(session)
        }
        self.client = client
        handleSessionChange(session)
    }

    private func handleSessionChange(_ session: SupabaseSession?) {
        KeychainStore.set(session.flatMap { try? JSONEncoder().encode($0) }, for: Keys.session)
        signedInEmail = session?.email
        if session == nil {
            status = .signedOut
        } else if status == .notConfigured || status == .signedOut {
            status = .idle
        }
    }
}
