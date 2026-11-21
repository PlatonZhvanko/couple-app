import CryptoKit
import Foundation
import SwiftData
import SwiftUI

// MARK: - Статусы дел (профиль Платони)

/// Что стало с делом в конкретный день.
enum PlannerErrandStatus: Equatable {
    case done
    case notDone
    /// Перенесено на другое время.
    case moved(Date)

    var emoji: String {
        switch self {
        case .done: "✅"
        case .notDone: "❌"
        case .moved: "↪️"
        }
    }
}

/// Деньги записи: прибыль или трата.
enum PlannerMoneyDirection: String, CaseIterable, Identifiable {
    case none = ""
    case profit
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Ничего"
        case .profit: "Прибыль"
        case .expense: "Трата"
        }
    }
}

extension PlannerEvent {
    private static func statusKey(_ day: Date) -> String {
        String(Int(PlannerCalendar.calendar.startOfDay(for: day).timeIntervalSince1970))
    }

    /// Все отметки: день (начало суток) → статус.
    var statuses: [Date: PlannerErrandStatus] {
        var result: [Date: PlannerErrandStatus] = [:]
        for part in statusRaw.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, let stamp = Double(pair[0]) else { continue }
            let day = Date(timeIntervalSince1970: stamp)
            if pair[1] == "done" {
                result[day] = .done
            } else if pair[1] == "notDone" {
                result[day] = .notDone
            } else if pair[1].hasPrefix("moved@"), let target = Double(pair[1].dropFirst(6)) {
                result[day] = .moved(Date(timeIntervalSince1970: target))
            }
        }
        return result
    }

    func status(on day: Date) -> PlannerErrandStatus? {
        statuses[PlannerCalendar.calendar.startOfDay(for: day)]
    }

    /// Поставить статус за день; `nil` снимает отметку.
    func setStatus(_ status: PlannerErrandStatus?, on day: Date) {
        let key = Self.statusKey(day)
        var parts = statusRaw.split(separator: ",").map(String.init).filter { !$0.hasPrefix(key + "=") }
        switch status {
        case .done: parts.append("\(key)=done")
        case .notDone: parts.append("\(key)=notDone")
        case .moved(let target): parts.append("\(key)=moved@\(Int(target.timeIntervalSince1970))")
        case nil: break
        }
        statusRaw = parts.joined(separator: ",")
    }

    var moneyDirection: PlannerMoneyDirection {
        PlannerMoneyDirection(rawValue: moneyKindRaw) ?? .none
    }

    /// Сумма со знаком: прибыль плюс, трата минус.
    var signedMoney: Double {
        switch moneyDirection {
        case .none: 0
        case .profit: moneyAmount
        case .expense: -moneyAmount
        }
    }
}

// MARK: - Тип денег

/// Тип прихода или траты («Продажа», «Бензин»): настраивается в настройках, по нему своя статистика.
@Model
final class PlannerMoneyKind: SyncableModel {
    struct Payload: Codable {
        var name: String
        var isProfit: Bool
        var emoji: String
    }

    static let recordKind = "planner.moneyKind"

    var syncID: UUID = UUID()
    var name: String = ""
    var isProfit: Bool = true
    var emoji: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(name: String, isProfit: Bool, emoji: String = "") {
        self.syncID = Self.makeID(name: name, isProfit: isProfit)
        self.name = name
        self.isProfit = isProfit
        self.emoji = emoji
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(name: name, isProfit: isProfit, emoji: emoji) }

    func apply(_ payload: Payload) {
        name = payload.name
        isProfit = payload.isProfit
        emoji = payload.emoji
    }

    static func makeID(name: String, isProfit: Bool) -> UUID {
        PlannerDeterministicID.make("moneykind|\(isProfit ? "p" : "e")|\(name.lowercased())")
    }

    var title: String { emoji.isEmpty ? name : "\(emoji) \(name)" }
}

enum PlannerMoneyKindStore {
    /// Находит тип по названию или заводит новый (оживляет удалённый).
    @MainActor
    @discardableResult
    static func ensure(_ context: ModelContext, name: String, isProfit: Bool, emoji: String = "") -> PlannerMoneyKind? {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let id = PlannerMoneyKind.makeID(name: clean, isProfit: isProfit)
        let found = try? context.fetch(FetchDescriptor<PlannerMoneyKind>(predicate: #Predicate { $0.syncID == id }))
        if let existing = found?.first {
            if existing.deletedAt != nil {
                existing.deletedAt = nil
                existing.emoji = emoji
                existing.markChanged()
                try? context.save()
            }
            return existing
        }
        let item = PlannerMoneyKind(name: clean, isProfit: isProfit, emoji: emoji)
        context.insert(item)
        item.markChanged()
        try? context.save()
        return item
    }
}

// MARK: - Приход или трата (кнопка «доллар»)

/// Разовая операция: продажа, приход денег или трата.
@Model
final class PlannerMoneyOp: SyncableModel {
    struct Payload: Codable {
        var date: Date
        var amount: Double
        var isProfit: Bool
        var typeName: String
        var note: String
    }

    static let recordKind = "planner.moneyOp"

    var syncID: UUID = UUID()
    var date: Date = Date.now
    var amount: Double = 0
    var isProfit: Bool = true
    var typeName: String = ""
    var note: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(date: Date, amount: Double, isProfit: Bool, typeName: String, note: String) {
        self.date = date
        self.amount = amount
        self.isProfit = isProfit
        self.typeName = typeName
        self.note = note
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(date: date, amount: amount, isProfit: isProfit, typeName: typeName, note: note)
    }

    func apply(_ payload: Payload) {
        date = payload.date
        amount = payload.amount
        isProfit = payload.isProfit
        typeName = payload.typeName
        note = payload.note
    }

    var signed: Double { isProfit ? amount : -amount }
}

// MARK: - Смена

/// Рабочая смена на день (9:00–21:00). Один день — одна смена на обоих телефонах.
@Model
final class PlannerShift: SyncableModel {
    struct Payload: Codable {
        var day: Date
        var amount: Double
    }

    static let recordKind = "planner.shift"
    static let startHour = 9
    static let endHour = 21
    /// Сколько приносит смена по умолчанию.
    static let defaultAmount: Double = 4000

    var syncID: UUID = UUID()
    var day: Date = Date.now
    var amount: Double = 4000
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(day: Date, amount: Double) {
        let start = PlannerCalendar.calendar.startOfDay(for: day)
        self.syncID = Self.makeID(day: start)
        self.day = start
        self.amount = amount
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(day: day, amount: amount) }

    func apply(_ payload: Payload) {
        day = payload.day
        amount = payload.amount
    }

    static func makeID(day: Date) -> UUID {
        PlannerDeterministicID.make("shift|\(Int(PlannerCalendar.calendar.startOfDay(for: day).timeIntervalSince1970))")
    }
}

enum PlannerShiftStore {
    /// Поставить или снять смену на день.
    @MainActor
    static func toggle(_ context: ModelContext, day: Date, amount: Double) {
        let start = PlannerCalendar.calendar.startOfDay(for: day)
        let id = PlannerShift.makeID(day: start)
        let found = try? context.fetch(FetchDescriptor<PlannerShift>(predicate: #Predicate { $0.syncID == id }))
        if let existing = found?.first {
            if existing.deletedAt == nil {
                existing.markDeleted()
            } else {
                existing.deletedAt = nil
                existing.amount = amount
                existing.markChanged()
            }
        } else {
            let shift = PlannerShift(day: start, amount: amount)
            context.insert(shift)
            shift.markChanged()
        }
        try? context.save()
    }
}

// MARK: - Деньги за период

/// Одна строка прибыли или траты для статистики.
struct PlannerLedgerEntry: Identifiable {
    enum Source: String { case shift = "Смены", errand = "Дела", operation = "Операции" }

    let id: String
    let day: Date
    let title: String
    let source: Source
    /// Название типа денег или источника, если типа нет.
    let type: String
    /// Прибыль со знаком плюс, трата со знаком минус.
    let amount: Double
    /// Тип дела (для дел): пусто — разовое.
    var errandType: String = ""
}

enum PlannerLedger {
    /// Все деньги Платони: смены, выполненные дела с суммой и разовые операции.
    static func entries(
        events: [PlannerEvent], shifts: [PlannerShift], ops: [PlannerMoneyOp]
    ) -> [PlannerLedgerEntry] {
        var result: [PlannerLedgerEntry] = []
        for shift in shifts where shift.deletedAt == nil {
            result.append(PlannerLedgerEntry(
                id: "shift.\(shift.syncID)", day: shift.day, title: "Смена",
                source: .shift, type: "Смена", amount: shift.amount
            ))
        }
        for event in events where event.deletedAt == nil && event.moneyDirection != .none && event.moneyAmount > 0 {
            for (day, status) in event.statuses where status == .done {
                result.append(PlannerLedgerEntry(
                    id: "event.\(event.syncID).\(Int(day.timeIntervalSince1970))", day: day,
                    title: event.plainTitle, source: .errand,
                    type: event.moneyType.isEmpty ? "Без типа" : event.moneyType, amount: event.signedMoney,
                    errandType: event.errandType
                ))
            }
        }
        for op in ops where op.deletedAt == nil {
            result.append(PlannerLedgerEntry(
                id: "op.\(op.syncID)", day: PlannerCalendar.calendar.startOfDay(for: op.date),
                title: op.note.isEmpty ? (op.typeName.isEmpty ? "Операция" : op.typeName) : op.note,
                source: .operation, type: op.typeName.isEmpty ? "Без типа" : op.typeName, amount: op.signed
            ))
        }
        return result
    }

    /// Итог за один день.
    static func net(on day: Date, entries: [PlannerLedgerEntry]) -> Double {
        let cal = PlannerCalendar.calendar
        return entries.filter { cal.isDate($0.day, inSameDayAs: day) }.reduce(0) { $0 + $1.amount }
    }
}
