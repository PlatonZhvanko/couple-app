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
        case .profit: "Прибыль/Приход"
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
            } else if pair[1].hasPrefix("moved@"),
                      let target = pair[1].dropFirst(6).split(separator: "@").first.flatMap({ Double($0) }) {
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

    /// Статус за день у конкретного человека. «Перенесено» общее для обоих, «сделано» и
    /// «не сделано» у каждого свои.
    func status(on day: Date, for member: CoupleMember) -> PlannerErrandStatus? {
        let own = status(on: day)
        if case .moved = own { return own }
        if member == .owner { return own }
        let key = Self.statusKey(day)
        guard let part = partnerStatusRaw.split(separator: ",").first(where: { $0.hasPrefix(key + "=") }) else { return nil }
        if part.hasSuffix("=done") { return .done }
        if part.hasSuffix("=notDone") { return .notDone }
        return nil
    }

    /// Поставить статус за день от имени человека.
    func setStatus(_ status: PlannerErrandStatus?, on day: Date, for member: CoupleMember) {
        if member == .owner {
            setStatus(status, on: day)
            return
        }
        // Перенос применяется у всех сразу.
        if case .moved = status {
            setStatus(status, on: day)
            return
        }
        // Новая отметка или её снятие отменяет общий перенос этого дня.
        if case .moved = self.status(on: day) { setStatus(nil, on: day) }
        let key = Self.statusKey(day)
        var parts = partnerStatusRaw.split(separator: ",").map(String.init).filter { !$0.hasPrefix(key + "=") }
        switch status {
        case .done: parts.append("\(key)=done")
        case .notDone: parts.append("\(key)=notDone")
        default: break
        }
        partnerStatusRaw = parts.joined(separator: ",")
    }

    /// Запись, созданная переносом в новый день (если день перенесён).
    func movedCopyID(on day: Date) -> UUID? {
        let key = Self.statusKey(day)
        guard let part = statusRaw.split(separator: ",").first(where: { $0.hasPrefix(key + "=moved@") }) else { return nil }
        let items = part.split(separator: "@")
        return items.count >= 3 ? UUID(uuidString: String(items[2])) : nil
    }

    /// Отметить день перенесённым: запоминаем новую запись, чтобы удалить её при отмене переноса.
    func setMoved(to target: Date, copy: PlannerEvent, on day: Date) {
        let key = Self.statusKey(day)
        var parts = statusRaw.split(separator: ",").map(String.init).filter { !$0.hasPrefix(key + "=") }
        parts.append("\(key)=moved@\(Int(target.timeIntervalSince1970))@\(copy.syncID.uuidString)")
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
    /// Удалить тип денег: он убирается из операций и дел, где был выбран.
    @MainActor
    static func delete(_ context: ModelContext, kind: PlannerMoneyKind) {
        let old = kind.name
        let ops = (try? context.fetch(FetchDescriptor<PlannerMoneyOp>(predicate: #Predicate { $0.typeName == old }))) ?? []
        for op in ops { op.typeName = ""; op.markChanged() }
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.moneyType == old || $0.partnerMoneyType == old }))) ?? []
        for event in events {
            if event.moneyType == old { event.moneyType = "" }
            if event.partnerMoneyType == old { event.partnerMoneyType = "" }
            event.markChanged()
        }
        kind.markDeleted()
        try? context.save()
    }

    /// Переименовать тип денег: название меняется и в операциях и делах с этим типом.
    @MainActor
    static func rename(_ context: ModelContext, kind: PlannerMoneyKind, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        let old = kind.name
        guard !clean.isEmpty, clean != old else { return }
        let clash = ((try? context.fetch(FetchDescriptor<PlannerMoneyKind>())) ?? []).contains {
            $0.deletedAt == nil && $0.isProfit == kind.isProfit && $0.syncID != kind.syncID
                && $0.name.caseInsensitiveCompare(clean) == .orderedSame
        }
        guard !clash else { return }
        let ops = (try? context.fetch(FetchDescriptor<PlannerMoneyOp>(predicate: #Predicate { $0.typeName == old }))) ?? []
        for op in ops { op.typeName = clean; op.markChanged() }
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.moneyType == old || $0.partnerMoneyType == old }))) ?? []
        for event in events {
            if event.moneyType == old { event.moneyType = clean }
            if event.partnerMoneyType == old { event.partnerMoneyType = clean }
            event.markChanged()
        }
        kind.name = clean
        kind.markChanged()
        try? context.save()
    }

    /// Находит тип по названию или заводит новый (оживляет удалённый).
    @MainActor
    @discardableResult
    static func ensure(_ context: ModelContext, name: String, isProfit: Bool, emoji: String = "") -> PlannerMoneyKind? {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let id = PlannerMoneyKind.makeID(name: clean, isProfit: isProfit)
        let found = try? context.fetch(FetchDescriptor<PlannerMoneyKind>(predicate: #Predicate { $0.syncID == id }))
        let sameName = ((try? context.fetch(FetchDescriptor<PlannerMoneyKind>())) ?? [])
            .first { $0.isProfit == isProfit && $0.name.caseInsensitiveCompare(clean) == .orderedSame }
        if let existing = found?.first ?? sameName {
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
        /// 0 — вся смена, 1 — первая половина (9–15), 2 — вторая (15–21). Нет в старых записях.
        var part: Int?
    }

    static let recordKind = "planner.shift"
    static let startHour = 9
    static let endHour = 21
    /// Сколько приносит смена по умолчанию.
    static let defaultAmount: Double = 4000

    var syncID: UUID = UUID()
    var day: Date = Date.now
    var amount: Double = 4000
    /// 0 — вся смена, 1 — первая половина (9–15), 2 — вторая (15–21).
    var part: Int = 0
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

    var payload: Payload { Payload(day: day, amount: amount, part: part) }

    func apply(_ payload: Payload) {
        day = payload.day
        amount = payload.amount
        part = payload.part ?? 0
    }

    /// Часы смены: вся 9–21, первая половина 9–15, вторая 15–21.
    static func hours(part: Int) -> (start: Int, end: Int) {
        switch part {
        case 1: (startHour, 15)
        case 2: (15, endHour)
        default: (startHour, endHour)
        }
    }

    static func partTitle(_ part: Int) -> String {
        switch part {
        case 1: "Первая половина 9–15"
        case 2: "Вторая половина 15–21"
        default: "Вся смена 9–21"
        }
    }

    var title: String { part == 0 ? "Смена" : "Половина смены" }

    static func makeID(day: Date) -> UUID {
        PlannerDeterministicID.make("shift|\(Int(PlannerCalendar.calendar.startOfDay(for: day).timeIntervalSince1970))")
    }
}

enum PlannerShiftStore {
    /// Поставить смену (целую или половину) с суммой или изменить уже стоящую.
    @MainActor
    static func set(_ context: ModelContext, day: Date, part: Int, amount: Double) {
        let start = PlannerCalendar.calendar.startOfDay(for: day)
        let id = PlannerShift.makeID(day: start)
        let found = try? context.fetch(FetchDescriptor<PlannerShift>(predicate: #Predicate { $0.syncID == id }))
        if let existing = found?.first {
            existing.deletedAt = nil
            existing.part = part
            existing.amount = amount
            existing.markChanged()
        } else {
            let shift = PlannerShift(day: start, amount: amount)
            shift.part = part
            context.insert(shift)
            shift.markChanged()
        }
        try? context.save()
    }

    /// Снять смену с дня.
    @MainActor
    static func remove(_ context: ModelContext, day: Date) {
        let start = PlannerCalendar.calendar.startOfDay(for: day)
        let id = PlannerShift.makeID(day: start)
        let found = try? context.fetch(FetchDescriptor<PlannerShift>(predicate: #Predicate { $0.syncID == id }))
        if let existing = found?.first, existing.deletedAt == nil {
            existing.markDeleted()
            try? context.save()
        }
    }

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
                existing.part = 0
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
    /// Деньги Настеньки за дела: каждое занятие, которое уже прошло и не отменено.
    static func partnerEntries(events: [PlannerEvent], today: Date = .now) -> [PlannerLedgerEntry] {
        let cal = PlannerCalendar.calendar
        let last = cal.startOfDay(for: today)
        var result: [PlannerLedgerEntry] = []
        for event in events where event.deletedAt == nil {
            guard let direction = PlannerMoneyDirection(rawValue: event.partnerMoneyKindRaw), direction != .none,
                  event.partnerMoneyAmount > 0 else { continue }
            var day = cal.startOfDay(for: event.start)
            var steps = 0
            while day <= last && steps < 800 {
                if event.startsOn(day), !event.isCancelled(on: day), event.status(on: day, for: .partner) == .done {
                    result.append(PlannerLedgerEntry(
                        id: "pevent.\(event.syncID).\(Int(day.timeIntervalSince1970))", day: day,
                        title: event.plainTitle, source: .errand,
                        type: event.partnerMoneyType.isEmpty ? (direction == .profit ? "Прибыль" : "Трата") : event.partnerMoneyType,
                        amount: direction == .profit ? event.partnerMoneyAmount : -event.partnerMoneyAmount,
                        errandType: event.errandType
                    ))
                }
                if event.repeatValue == .none { break }
                day = PlannerCalendar.addDays(1, to: day)
                steps += 1
            }
        }
        return result
    }

    /// Все деньги Платони: смены, выполненные дела с суммой и разовые операции.
    static func entries(
        events: [PlannerEvent], shifts: [PlannerShift], ops: [PlannerMoneyOp]
    ) -> [PlannerLedgerEntry] {
        var result: [PlannerLedgerEntry] = []
        for shift in shifts where shift.deletedAt == nil {
            result.append(PlannerLedgerEntry(
                id: "shift.\(shift.syncID)", day: shift.day, title: shift.title,
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

    /// Только приход за день (минусы не считаем).
    static func income(on day: Date, entries: [PlannerLedgerEntry]) -> Double {
        let cal = PlannerCalendar.calendar
        return entries.filter { cal.isDate($0.day, inSameDayAs: day) && $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }

    /// Итог за один день.
    static func net(on day: Date, entries: [PlannerLedgerEntry]) -> Double {
        let cal = PlannerCalendar.calendar
        return entries.filter { cal.isDate($0.day, inSameDayAs: day) }.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Перенос дела

enum PlannerErrandCarry {
    /// «Перенос»: старый день остаётся белым с пометкой «перенесено», на новом дне появляется
    /// новая запись. В отличие от «Переместить», это идёт в статистику.
    @MainActor
    static func carry(_ event: PlannerEvent, day: Date, to newStart: Date, context: ModelContext) {
        revoke(event, day: day, context: context)
        let cal = PlannerCalendar.calendar
        let duration = max(0, event.end.timeIntervalSince(event.start))
        let start = event.isAllDay ? cal.startOfDay(for: newStart) : newStart
        let copy = PlannerEvent()
        copy.title = event.title
        copy.notes = event.notes
        copy.isAllDay = event.isAllDay
        copy.start = start
        copy.end = event.isAllDay ? start : start.addingTimeInterval(duration)
        copy.scope = event.scope
        copy.isPrivate = event.isPrivate
        copy.colorHex = event.colorHex
        copy.category = event.category
        copy.repeatRule = PlannerRepeat.none.rawValue
        copy.reminderMinutes = event.reminderMinutes
        copy.createdBy = event.createdBy
        copy.moneyKindRaw = event.moneyKindRaw
        copy.moneyAmount = event.moneyAmount
        copy.moneyType = event.moneyType
        copy.errandType = event.errandType
        context.insert(copy)
        copy.markChanged()
        event.setMoved(to: start, copy: copy, on: day)
        event.markChanged()
        try? context.save()
    }

    /// Перенос отменили (поставили другой статус или сняли): новая запись в новом дне удаляется.
    @MainActor
    static func revoke(_ event: PlannerEvent, day: Date, context: ModelContext) {
        guard let copyID = event.movedCopyID(on: day) else { return }
        let found = try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.syncID == copyID }))
        if let copy = found?.first, copy.deletedAt == nil {
            copy.markDeleted()
            PlannerPaymentStore.purge(context, eventID: copy.syncID)
        }
        try? context.save()
    }
}
