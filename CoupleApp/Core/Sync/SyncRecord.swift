import Foundation
import SwiftData

/// Одна запись в том виде, в котором она лежит на сервере.
struct SyncRecord {
    var id: UUID
    var kind: String
    /// JSON-представление `Payload` модели.
    var payload: Data
    var updatedAt: Date
    var deletedAt: Date?
}

/// Локальная запись, ожидающая отправки.
struct PendingRecord {
    let record: SyncRecord
    /// Снять флаг `needsSync`, если запись не менялась во время отправки.
    let markSynced: @MainActor () -> Void
}

/// Связывает конкретный тип модели с движком синхронизации.
/// Создаётся автоматически для каждой модели, реализующей `SyncableModel`.
struct SyncAdapter {
    let kind: String
    let collectPending: @MainActor (ModelContext) throws -> [PendingRecord]
    let applyRemote: @MainActor ([SyncRecord], ModelContext) throws -> Void

    static func make<Model: SyncableModel>(for type: Model.Type) -> SyncAdapter {
        SyncAdapter(
            kind: Model.recordKind,
            collectPending: { context in
                let items = try context.fetch(FetchDescriptor<Model>()).filter { $0.needsSync }
                return try items.map { item in
                    let record = SyncRecord(
                        id: item.syncID,
                        kind: Model.recordKind,
                        payload: try JSONEncoder.sync.encode(item.payload),
                        updatedAt: item.updatedAt,
                        deletedAt: item.deletedAt
                    )
                    let sentVersion = item.updatedAt
                    return PendingRecord(record: record) {
                        if item.updatedAt == sentVersion { item.needsSync = false }
                    }
                }
            },
            applyRemote: { records, context in
                guard !records.isEmpty else { return }
                var existing: [UUID: Model] = [:]
                for item in try context.fetch(FetchDescriptor<Model>()) {
                    existing[item.syncID] = item
                }
                for record in records {
                    let payload = try JSONDecoder.sync.decode(Model.Payload.self, from: record.payload)
                    if let local = existing[record.id] {
                        // Побеждает последнее изменение.
                        guard record.updatedAt > local.updatedAt else { continue }
                        local.apply(payload)
                        local.updatedAt = record.updatedAt
                        local.deletedAt = record.deletedAt
                        local.needsSync = false
                    } else {
                        let item = Model(syncID: record.id, payload: payload)
                        item.updatedAt = record.updatedAt
                        item.deletedAt = record.deletedAt
                        item.needsSync = false
                        context.insert(item)
                        existing[record.id] = item
                    }
                }
            }
        )
    }
}

extension JSONEncoder {
    static let sync: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let sync: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
