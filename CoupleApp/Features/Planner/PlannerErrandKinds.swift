import Foundation
import SwiftData

/// Тип регулярного дела (например «Тренировка»). Разовые дела типов не имеют.
/// Типы у Платони и Настеньки раздельные: у каждого свои. Общими они становятся
/// только для «Совместного дела».
@Model
final class PlannerErrandKind: SyncableModel {
    struct Payload: Codable {
        var name: String
        /// Чей тип: «owner» (Платоня) или «partner» (Настенька). Нет в старых записях:
        /// они появились у Настеньки.
        var owner: String?
    }

    static let recordKind = "planner.errandKind"

    var syncID: UUID = UUID()
    var name: String = ""
    /// Чей тип: `CoupleMember.rawValue`. Пусто у старых типов (они Настенькины).
    var ownerRaw: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(name: String, owner: CoupleMember) {
        self.syncID = Self.makeID(name: name, owner: owner)
        self.name = name
        self.ownerRaw = owner.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(name: name, owner: ownerRaw.isEmpty ? nil : ownerRaw) }

    func apply(_ payload: Payload) {
        name = payload.name
        ownerRaw = payload.owner ?? ""
    }

    /// Чей это тип. Старые типы без хозяина считаем Настенькиными.
    var member: CoupleMember { CoupleMember(rawValue: ownerRaw) ?? .partner }

    /// Идентификатор: у Настеньки прежний (чтобы старые типы не дублировались), у Платони свой.
    static func makeID(name: String, owner: CoupleMember) -> UUID {
        let key = name.lowercased()
        return PlannerDeterministicID.make(owner == .partner ? "errandkind|\(key)" : "errandkind|owner|\(key)")
    }
}

extension Sequence where Element == PlannerErrandKind {
    /// Только типы этого человека.
    func visible(to member: CoupleMember) -> [PlannerErrandKind] {
        filter { $0.member == member }
    }
}

enum PlannerErrandKindStore {
    /// Находит тип по названию у этого человека или заводит новый (оживляет удалённый).
    @MainActor
    static func ensure(_ context: ModelContext, name: String, owner: CoupleMember) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let id = PlannerErrandKind.makeID(name: clean, owner: owner)
        let found = try? context.fetch(FetchDescriptor<PlannerErrandKind>(predicate: #Predicate { $0.syncID == id }))
        if let existing = found?.first {
            guard existing.deletedAt != nil else { return }
            existing.deletedAt = nil
            existing.markChanged()
        } else {
            let item = PlannerErrandKind(name: clean, owner: owner)
            context.insert(item)
            item.markChanged()
        }
        try? context.save()
    }

    /// Тип совместного дела записывается обоим.
    @MainActor
    static func ensureForBoth(_ context: ModelContext, name: String) {
        for member in CoupleMember.allCases { ensure(context, name: name, owner: member) }
    }
}
