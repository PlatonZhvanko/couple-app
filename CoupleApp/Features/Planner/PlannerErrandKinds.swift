import Foundation
import SwiftData

/// Тип регулярного дела (например «Тренировка»). Разовые дела типов не имеют.
@Model
final class PlannerErrandKind: SyncableModel {
    struct Payload: Codable {
        var name: String
    }

    static let recordKind = "planner.errandKind"

    var syncID: UUID = UUID()
    var name: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(name: String) {
        self.syncID = Self.makeID(name: name)
        self.name = name
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(name: name) }

    func apply(_ payload: Payload) {
        name = payload.name
    }

    static func makeID(name: String) -> UUID {
        PlannerDeterministicID.make("errandkind|\(name.lowercased())")
    }
}

enum PlannerErrandKindStore {
    /// Находит тип по названию или заводит новый (в том числе оживляет удалённый).
    @MainActor
    static func ensure(_ context: ModelContext, name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let id = PlannerErrandKind.makeID(name: clean)
        let found = try? context.fetch(FetchDescriptor<PlannerErrandKind>(predicate: #Predicate { $0.syncID == id }))
        if let existing = found?.first {
            guard existing.deletedAt != nil else { return }
            existing.deletedAt = nil
            existing.markChanged()
        } else {
            let item = PlannerErrandKind(name: clean)
            context.insert(item)
            item.markChanged()
        }
        try? context.save()
    }
}
