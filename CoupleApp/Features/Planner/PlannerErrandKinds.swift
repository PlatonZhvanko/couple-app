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
        /// Эмодзи типа. Нет в старых записях.
        var emoji: String?
        /// Цвет типа (hex), нет в старых записях.
        var color: String?
        /// Деньги типа: «profit» / «expense», нет — ничего.
        var money: String?
    }

    static let recordKind = "planner.errandKind"

    var syncID: UUID = UUID()
    var name: String = ""
    /// Чей тип: `CoupleMember.rawValue`. Пусто у старых типов (они Настенькины).
    var ownerRaw: String = ""
    /// Эмодзи типа; пусто — чемодан по умолчанию.
    var emoji: String = ""
    /// Свой цвет типа (hex); пусто — обычный цвет дела.
    var colorHex: String = ""
    /// Деньги типа по умолчанию: пусто — ничего, «profit» или «expense».
    var moneyKindRaw: String = ""
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

    var payload: Payload { Payload(name: name, owner: ownerRaw.isEmpty ? nil : ownerRaw, emoji: emoji.isEmpty ? nil : emoji, color: colorHex.isEmpty ? nil : colorHex, money: moneyKindRaw.isEmpty ? nil : moneyKindRaw) }

    func apply(_ payload: Payload) {
        name = payload.name
        ownerRaw = payload.owner ?? ""
        emoji = payload.emoji ?? ""
        colorHex = payload.color ?? ""
        moneyKindRaw = payload.money ?? ""
    }

    /// Чей это тип. Старые типы без хозяина считаем Настенькиными.
    var moneyDirection: PlannerMoneyDirection { PlannerMoneyDirection(rawValue: moneyKindRaw) ?? .none }

    var displayEmoji: String { emoji.isEmpty ? "💼" : emoji }

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
    /// Переименовать тип: название меняется и в самих делах этого типа.
    @MainActor
    static func rename(_ context: ModelContext, kind: PlannerErrandKind, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        let old = kind.name
        guard !clean.isEmpty, clean != old else { return }
        let clash = ((try? context.fetch(FetchDescriptor<PlannerErrandKind>())) ?? []).contains {
            $0.deletedAt == nil && $0.member == kind.member && $0.syncID != kind.syncID
                && $0.name.caseInsensitiveCompare(clean) == .orderedSame
        }
        guard !clash else { return }
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.errandType == old }))) ?? []
        for event in events {
            event.errandType = clean
            event.markChanged()
        }
        // Тип денег с тем же названием (создан вместе с типом дела) переименовываем следом.
        if kind.moneyDirection != .none {
            let isProfit = kind.moneyDirection == .profit
            let twin = ((try? context.fetch(FetchDescriptor<PlannerMoneyKind>())) ?? []).first {
                $0.deletedAt == nil && $0.isProfit == isProfit && $0.name == old
            }
            if let twin { PlannerMoneyKindStore.rename(context, kind: twin, to: clean) }
        }
        kind.name = clean
        kind.markChanged()
        try? context.save()
    }

    /// Удалить тип: он убирается из всех дел (регулярному делу придётся назначить тип заново).
    @MainActor
    static func delete(_ context: ModelContext, kind: PlannerErrandKind) {
        let old = kind.name
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.errandType == old }))) ?? []
        for event in events {
            event.errandType = ""
            if event.moneyType == old { event.moneyType = "" }
            event.markChanged()
        }
        // Парный тип денег, созданный вместе с типом дела, удаляется вместе с ним.
        if kind.moneyDirection != .none {
            let isProfit = kind.moneyDirection == .profit
            let twins = ((try? context.fetch(FetchDescriptor<PlannerMoneyKind>())) ?? []).filter {
                $0.deletedAt == nil && $0.isProfit == isProfit && $0.name == old
            }
            for twin in twins { PlannerMoneyKindStore.delete(context, kind: twin) }
        }
        kind.markDeleted()
        try? context.save()
    }

    /// Деньги типа дела: прибыль или трата. Тип сам появляется в типах прибыли/трат.
    @MainActor
    static func setMoney(_ context: ModelContext, kind: PlannerErrandKind, direction: PlannerMoneyDirection) {
        kind.moneyKindRaw = direction.rawValue
        kind.markChanged()
        if direction != .none {
            PlannerMoneyKindStore.ensure(context, name: kind.name, isProfit: direction == .profit, emoji: kind.emoji)
        }
        try? context.save()
    }

    /// Находит тип по названию у этого человека или заводит новый (оживляет удалённый).
    @MainActor
    static func ensure(_ context: ModelContext, name: String, owner: CoupleMember, emoji: String = "", money: PlannerMoneyDirection? = nil) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let id = PlannerErrandKind.makeID(name: clean, owner: owner)
        let found = try? context.fetch(FetchDescriptor<PlannerErrandKind>(predicate: #Predicate { $0.syncID == id }))
        // Тип могли переименовать: id остался старый, ищем ещё и по названию.
        let sameName = ((try? context.fetch(FetchDescriptor<PlannerErrandKind>())) ?? [])
            .first { $0.member == owner && $0.name.caseInsensitiveCompare(clean) == .orderedSame }
        if let existing = found?.first ?? sameName {
            guard existing.deletedAt != nil else { return }
            existing.deletedAt = nil
            if !emoji.isEmpty { existing.emoji = emoji }
            if let money { existing.moneyKindRaw = money.rawValue }
            existing.markChanged()
        } else {
            let item = PlannerErrandKind(name: clean, owner: owner)
            item.emoji = emoji
            if let money { item.moneyKindRaw = money.rawValue }
            context.insert(item)
            item.markChanged()
        }
        try? context.save()
    }

    /// Тип совместного дела записывается обоим.
    @MainActor
    static func ensureForBoth(_ context: ModelContext, name: String, emoji: String = "") {
        for member in CoupleMember.allCases { ensure(context, name: name, owner: member, emoji: emoji) }
    }
}
