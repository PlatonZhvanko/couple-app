import Foundation
import SwiftData

/// Пример синхронизируемой модели: общие заметки.
/// Используется на экране «Проверка синхронизации» в настройках
/// и служит образцом для моделей разделов.
@Model
final class ExampleNote: SyncableModel {
    struct Payload: Codable {
        var text: String
        var author: String
        var createdAt: Date
    }

    static let recordKind = "core.example_note"

    var syncID: UUID = UUID()
    var text: String = ""
    var author: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(text: String, author: String) {
        self.text = text
        self.author = author
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(text: text, author: author, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        text = payload.text
        author = payload.author
        createdAt = payload.createdAt
    }
}
