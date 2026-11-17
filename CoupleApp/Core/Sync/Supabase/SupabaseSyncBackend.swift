import Foundation

/// Синхронизация через таблицу `records` в Supabase.
/// Схема таблицы и правила доступа: `docs/supabase-setup.sql`.
@MainActor
struct SupabaseSyncBackend: SyncBackend {
    let client: SupabaseClient

    /// Насколько «назад» перекрывать курсор, чтобы не потерять записи,
    /// сохранённые на сервере почти одновременно. Повторы безопасны.
    private let cursorOverlap: TimeInterval = 5
    private let pageSize = 500

    func push(_ records: [SyncRecord]) async throws {
        guard !records.isEmpty else { return }
        var rows: [[String: Any]] = []
        for record in records {
            var row: [String: Any] = [
                "id": record.id.uuidString.lowercased(),
                "kind": record.kind,
                "payload": try JSONSerialization.jsonObject(with: record.payload),
                "updated_at": ISODate.string(from: record.updatedAt),
            ]
            if let deletedAt = record.deletedAt {
                row["deleted_at"] = ISODate.string(from: deletedAt)
            } else {
                row["deleted_at"] = NSNull()
            }
            rows.append(row)
        }
        let body = try JSONSerialization.data(withJSONObject: rows)
        _ = try await client.rest(
            "records",
            query: "on_conflict=id",
            method: "POST",
            body: body,
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    func pull(since cursor: Date?) async throws -> (records: [SyncRecord], cursor: Date?) {
        var all: [SyncRecord] = []
        var newCursor = cursor
        var from = cursor.map { $0.addingTimeInterval(-cursorOverlap) }

        while true {
            var query = "select=id,kind,payload,updated_at,deleted_at,server_updated_at&order=server_updated_at.asc&limit=\(pageSize)"
            if let from {
                query += "&server_updated_at=gt.\(ISODate.queryValue(from))"
            }
            let data = try await client.rest("records", query: query)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }

            for row in rows {
                guard
                    let idText = row["id"] as? String, let id = UUID(uuidString: idText),
                    let kind = row["kind"] as? String,
                    let updatedText = row["updated_at"] as? String, let updatedAt = ISODate.date(from: updatedText),
                    let serverText = row["server_updated_at"] as? String, let serverAt = ISODate.date(from: serverText)
                else { continue }
                let payload = try JSONSerialization.data(withJSONObject: row["payload"] ?? [String: Any](), options: [.fragmentsAllowed])
                let deletedAt = (row["deleted_at"] as? String).flatMap(ISODate.date(from:))
                all.append(SyncRecord(id: id, kind: kind, payload: payload, updatedAt: updatedAt, deletedAt: deletedAt))
                if newCursor == nil || serverAt > newCursor! { newCursor = serverAt }
                from = serverAt
            }
            if rows.count < pageSize { break }
        }
        return (all, newCursor)
    }
}

/// Даты в формате ISO 8601, как их понимает Postgres.
enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    /// Значение для URL: «+» в часовом поясе нужно закодировать.
    static func queryValue(_ date: Date) -> String {
        string(from: date).replacingOccurrences(of: "+", with: "%2B")
    }

    /// Postgres отдаёт до 6 знаков после запятой; оставляем 3.
    static func date(from text: String) -> Date? {
        var value = text
        if let dot = value.firstIndex(of: ".") {
            let digitsStart = value.index(after: dot)
            let digitsEnd = value[digitsStart...].firstIndex { !$0.isNumber } ?? value.endIndex
            let digits = value[digitsStart..<digitsEnd]
            let kept = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            value.replaceSubrange(digitsStart..<digitsEnd, with: kept)
        }
        return withFraction.date(from: value) ?? plain.date(from: value)
    }
}
