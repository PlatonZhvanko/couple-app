import CryptoKit
import Foundation
import SwiftData

// MARK: - Способ оплаты

enum PlannerPayMethod: String, CaseIterable, Identifiable {
    /// Ещё не отмечено.
    case none
    case cash
    case transfer
    case subscription
    /// Не оплатили (крестик).
    case unpaid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Не отмечено"
        case .cash: "Наличные"
        case .transfer: "Перевод"
        case .subscription: "Абонемент"
        case .unpaid: "Не оплатили"
        }
    }

    var shortTitle: String {
        switch self {
        case .none: ""
        case .cash: "нал"
        case .transfer: "перевод"
        case .subscription: "абонемент"
        case .unpaid: "не оплатил"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "circle"
        case .cash: "banknote.fill"
        case .transfer: "creditcard.fill"
        case .subscription: "ticket.fill"
        case .unpaid: "xmark.circle.fill"
        }
    }

    /// Смайлик способа: банкнота, карта, свиток абонемента, крестик.
    var emoji: String {
        switch self {
        case .none: "⚪️"
        case .cash: "💵"
        case .transfer: "💳"
        case .subscription: "📜"
        case .unpaid: "❌"
        }
    }

    /// Короткая подпись для кнопок выбора.
    var chipTitle: String {
        switch self {
        case .none: "Сбросить"
        case .cash: "Наличные"
        case .transfer: "Перевод"
        case .subscription: "Абонемент"
        case .unpaid: "Не оплатил"
        }
    }

    var isPaid: Bool { self == .cash || self == .transfer || self == .subscription }
}

/// Цены по умолчанию (всегда можно поправить вручную в самой записи).
enum PlannerPricing {
    static let personal: Double = 2000
    /// Группа и школа: с каждого клиента.
    static let group: Double = 750
    /// Сколько списывается с абонемента за одну тренировку.
    static let subscriptionCharge: Double = 500
    /// Сумма нового абонемента по умолчанию.
    static let subscriptionDefault: Double = 4000

    static func price(for category: PlannerCategory) -> Double {
        category == .personal ? personal : group
    }

    static func format(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.005 { return "\(Int(rounded)) ₽" }
        return String(format: "%.2f ₽", value)
    }
}

/// Значок оплаты записи в журнале.
enum PlannerPayBadge {
    case none
    /// Все оплатили (банкнота).
    case paid
    /// Оплатили не все (доллар).
    case partial
    /// Не оплатили (крестик).
    case unpaid
    /// Ничего не отмечено (вопросик).
    case unknown
    /// Отменено без штрафа.
    case cancelled
    /// Штраф не оплачен.
    case fineUnpaid
    /// Штраф оплачен.
    case finePaid
    /// Дело сделано / не сделано / перенесено (профиль Платони).
    case errandDone, errandNotDone, errandMoved

    var symbol: String? {
        switch self {
        case .none: nil
        case .paid: "💵"
        case .partial: "💲"
        case .unpaid: "❌"
        case .unknown: "❓"
        case .cancelled: "🚫"
        case .fineUnpaid: "⏳"
        case .finePaid: "💰"
        case .errandDone: "✅"
        case .errandNotDone: "❌"
        case .errandMoved: "↪️"
        }
    }
}

// MARK: - Оплата одного клиента за одну тренировку

/// Оплата клиента за конкретную тренировку (запись + день + клиент).
/// Идентификатор считается из этих трёх значений, поэтому на двух телефонах
/// одна и та же оплата не дублируется.
@Model
final class PlannerPayment: SyncableModel {
    struct Payload: Codable {
        var eventID: UUID
        var day: Date
        var clientID: UUID
        var method: String
        var amount: Double
    }

    static let recordKind = "planner.payment"

    var syncID: UUID = UUID()
    var eventID: UUID = UUID()
    var day: Date = Date.now
    var clientID: UUID = UUID()
    var method: String = PlannerPayMethod.none.rawValue
    var amount: Double = 0
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(eventID: UUID, day: Date, clientID: UUID, method: PlannerPayMethod, amount: Double) {
        self.syncID = Self.makeID(eventID: eventID, day: day, clientID: clientID)
        self.eventID = eventID
        self.day = PlannerCalendar.calendar.startOfDay(for: day)
        self.clientID = clientID
        self.method = method.rawValue
        self.amount = amount
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(eventID: eventID, day: day, clientID: clientID, method: method, amount: amount)
    }

    func apply(_ payload: Payload) {
        eventID = payload.eventID
        day = payload.day
        clientID = payload.clientID
        method = payload.method
        amount = payload.amount
    }

    var methodValue: PlannerPayMethod { PlannerPayMethod(rawValue: method) ?? .none }

    static func makeID(eventID: UUID, day: Date, clientID: UUID) -> UUID {
        let parts = PlannerCalendar.calendar.dateComponents([.year, .month, .day], from: day)
        let key = "pay|\(eventID.uuidString)|\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)|\(clientID.uuidString)"
        return PlannerDeterministicID.make(key)
    }
}

// MARK: - Абонемент клиента на месяц

/// Абонемент: клиент заранее оплатил сумму на месяц, с неё списываются тренировки.
@Model
final class PlannerSubscription: SyncableModel {
    struct Payload: Codable {
        var clientID: UUID
        var month: Date
        var amount: Double
        var kindName: String? = nil
        var soldAt: Date? = nil
        var expiresAt: Date? = nil
        var charge: Double? = nil
    }

    static let recordKind = "planner.subscription"

    var syncID: UUID = UUID()
    var clientID: UUID = UUID()
    /// Первый день месяца.
    var month: Date = Date.now
    var amount: Double = 0
    /// Название вида абонемента, по которому он продан.
    var kindName: String = ""
    /// Когда продан (деньги за абонемент считаются в этот день).
    var soldAt: Date = Date.now
    /// До какого дня действует; потом неиспользованный остаток «сгорает».
    var expiresAt: Date = Date.distantFuture
    /// Сколько списывается за одно занятие.
    var charge: Double = PlannerPricing.subscriptionCharge
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(clientID: UUID, month: Date, amount: Double) {
        self.syncID = Self.makeID(clientID: clientID, month: month)
        self.clientID = clientID
        self.month = PlannerCalendar.startOfMonth(month)
        self.amount = amount
        self.expiresAt = Self.endOfMonth(month)
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(clientID: clientID, month: month, amount: amount, kindName: kindName, soldAt: soldAt, expiresAt: expiresAt, charge: charge) }

    func apply(_ payload: Payload) {
        clientID = payload.clientID
        month = payload.month
        amount = payload.amount
        kindName = payload.kindName ?? ""
        soldAt = payload.soldAt ?? Date.now
        expiresAt = payload.expiresAt ?? Self.endOfMonth(payload.month)
        charge = payload.charge ?? PlannerPricing.subscriptionCharge
    }

    static func endOfMonth(_ month: Date) -> Date {
        let cal = PlannerCalendar.calendar
        let start = PlannerCalendar.startOfMonth(month)
        let next = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return next.addingTimeInterval(-1)
    }

    /// Действует ли абонемент в этот день.
    func covers(_ day: Date) -> Bool {
        PlannerCalendar.calendar.isDate(month, equalTo: day, toGranularity: .month)
            && PlannerCalendar.calendar.startOfDay(for: day) <= expiresAt
    }

    /// Срок вышел.
    var isExpired: Bool { expiresAt < .now }

    static func makeID(clientID: UUID, month: Date) -> UUID {
        let parts = PlannerCalendar.calendar.dateComponents([.year, .month], from: month)
        return PlannerDeterministicID.make("sub|\(clientID.uuidString)|\(parts.year ?? 0)-\(parts.month ?? 0)")
    }
}

enum PlannerDeterministicID {
    /// Одинаковая строка всегда даёт одинаковый UUID (на обоих телефонах).
    static func make(_ key: String) -> UUID {
        let hash = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        var b = hash
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

// MARK: - Операции

@MainActor
enum PlannerPaymentStore {
    private static var cal: Calendar { PlannerCalendar.calendar }

    static func isTraining(_ event: PlannerEvent) -> Bool {
        [.personal, .group, .school].contains(event.categoryValue)
    }

    static func allPayments(_ context: ModelContext) -> [PlannerPayment] {
        (try? context.fetch(FetchDescriptor<PlannerPayment>())) ?? []
    }

    /// Оплаты, у которых запись ещё есть в журнале (и день не снят из повтора).
    /// Если запись удалили, её деньги за этот день не считаются.
    static func isLive(_ payment: PlannerPayment, events: [UUID: PlannerEvent]) -> Bool {
        guard payment.deletedAt == nil, let event = events[payment.eventID], event.deletedAt == nil else { return false }
        return !event.skippedDays.contains { cal.isDate($0, inSameDayAs: payment.day) }
    }

    static func eventMap(_ events: [PlannerEvent]) -> [UUID: PlannerEvent] {
        Dictionary(events.map { ($0.syncID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Живые оплаты наличными и переводом (списания с абонемента — не деньги, они уже учтены при продаже).
    static func cashPayments(_ context: ModelContext) -> [PlannerPayment] {
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>())) ?? []
        let map = eventMap(events)
        return allPayments(context).filter {
            ($0.methodValue == .cash || $0.methodValue == .transfer) && isLive($0, events: map)
        }
    }

    static func allSubscriptions(_ context: ModelContext) -> [PlannerSubscription] {
        ((try? context.fetch(FetchDescriptor<PlannerSubscription>())) ?? []).filter { $0.deletedAt == nil }
    }

    /// Пометить оплаты записи удалёнными (весь повтор или один день).
    static func purge(_ context: ModelContext, eventID: UUID, day: Date? = nil) {
        for item in allPayments(context) where item.eventID == eventID && item.deletedAt == nil {
            if let day, !cal.isDate(item.day, inSameDayAs: day) { continue }
            item.markDeleted()
        }
        try? context.save()
    }

    /// Цена занятия: у группы — своя (из настроек групп), иначе по умолчанию.
    static func price(for event: PlannerEvent, context: ModelContext) -> Double {
        guard event.categoryValue == .group || event.categoryValue == .school else {
            return PlannerPricing.price(for: event.categoryValue)
        }
        let id = PlannerGroupKind.makeID(name: event.title)
        let found = try? context.fetch(FetchDescriptor<PlannerGroupKind>(predicate: #Predicate { $0.syncID == id }))
        if let kind = found?.first, kind.deletedAt == nil { return kind.price }
        return PlannerPricing.group
    }

    /// Сколько спишется с абонемента клиента за занятие в этот день.
    static func subscriptionCharge(_ context: ModelContext, clientID: UUID, day: Date) -> Double {
        allSubscriptions(context).first { $0.clientID == clientID && $0.covers(day) }?.charge
            ?? PlannerPricing.subscriptionCharge
    }

    static func payment(_ context: ModelContext, eventID: UUID, day: Date, clientID: UUID) -> PlannerPayment? {
        let id = PlannerPayment.makeID(eventID: eventID, day: day, clientID: clientID)
        let found = try? context.fetch(FetchDescriptor<PlannerPayment>(predicate: #Predicate { $0.syncID == id }))
        return found?.first
    }

    /// Поставить способ оплаты и/или сумму. Создаёт запись, если её ещё нет.
    @discardableResult
    static func set(
        _ context: ModelContext,
        event: PlannerEvent,
        day: Date,
        clientID: UUID,
        method: PlannerPayMethod? = nil,
        amount: Double? = nil
    ) -> PlannerPayment {
        let price = Self.price(for: event, context: context)
        let item: PlannerPayment
        if let existing = payment(context, eventID: event.syncID, day: day, clientID: clientID) {
            item = existing
            if item.deletedAt != nil {
                item.deletedAt = nil
                item.method = PlannerPayMethod.none.rawValue
                item.amount = price
            }
        } else {
            item = PlannerPayment(eventID: event.syncID, day: day, clientID: clientID, method: .none, amount: price)
            context.insert(item)
        }
        if let method {
            let old = item.methodValue
            item.method = method.rawValue
            if amount == nil {
                if method == .subscription {
                    item.amount = Self.subscriptionCharge(context, clientID: clientID, day: day)
                } else if old == .subscription {
                    item.amount = price
                }
            }
        }
        if let amount { item.amount = max(0, amount) }
        item.markChanged()
        try? context.save()
        return item
    }

    /// Значок оплаты записи за конкретный день.
    static func badge(for event: PlannerEvent, day: Date, payments: [PlannerPayment]) -> PlannerPayBadge {
        guard isTraining(event) else { return .none }
        let rows = payments.filter {
            $0.eventID == event.syncID && $0.deletedAt == nil && cal.isDate($0.day, inSameDayAs: day)
        }
        if event.isCancelled(on: day) {
            // Отмена: штраф не оплачен, оплачен, или просто отмена.
            if rows.contains(where: { $0.methodValue == .unpaid }) { return .fineUnpaid }
            if rows.contains(where: { $0.methodValue == .cash || $0.methodValue == .transfer }) { return .finePaid }
            return .cancelled
        }
        guard !event.participantIDs.isEmpty else { return .none }
        let ids = event.participantIDs
        let paid = ids.filter { id in rows.contains { $0.clientID == id && $0.methodValue.isPaid } }.count
        let unpaid = ids.filter { id in rows.contains { $0.clientID == id && $0.methodValue == .unpaid } }.count
        if paid == ids.count { return .paid }
        if paid > 0 { return .partial }
        if unpaid > 0 { return .unpaid }
        return .unknown
    }

    // MARK: Абонементы

    static func subscription(_ context: ModelContext, clientID: UUID, month: Date) -> PlannerSubscription? {
        let id = PlannerSubscription.makeID(clientID: clientID, month: month)
        let found = try? context.fetch(FetchDescriptor<PlannerSubscription>(predicate: #Predicate { $0.syncID == id }))
        guard let item = found?.first, item.deletedAt == nil else { return nil }
        return item
    }

    /// Остаток на абонементе: оплаченная сумма минус списания за месяц.
    static func balance(_ context: ModelContext, of subscription: PlannerSubscription) -> Double {
        let start = PlannerCalendar.startOfMonth(subscription.month)
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        let subscriptionMethod = PlannerPayMethod.subscription.rawValue
        let clientID = subscription.clientID
        let rows = allPayments(context).filter {
            $0.deletedAt == nil && $0.clientID == clientID && $0.method == subscriptionMethod
                && $0.day >= start && $0.day < end
        }
        return subscription.amount - rows.reduce(0) { $0 + $1.amount }
    }

    /// Оформить (или изменить) абонемент клиента на месяц и сразу списать им тренировки месяца.
    static func saveSubscription(_ context: ModelContext, clientID: UUID, month: Date, amount: Double, kindName: String? = nil, validDays: Int? = nil, charge: Double? = nil) {
        let monthStart = PlannerCalendar.startOfMonth(month)
        let id = PlannerSubscription.makeID(clientID: clientID, month: monthStart)
        let found = try? context.fetch(FetchDescriptor<PlannerSubscription>(predicate: #Predicate { $0.syncID == id }))
        let item: PlannerSubscription
        if let existing = found?.first {
            item = existing
            item.deletedAt = nil
            item.amount = amount
            if let kindName { item.kindName = kindName }
        } else {
            item = PlannerSubscription(clientID: clientID, month: monthStart, amount: amount)
            item.kindName = kindName ?? ""
            context.insert(item)
        }
        if let charge { item.charge = max(0, charge) }
        if let validDays {
            item.soldAt = .now
            item.expiresAt = cal.startOfDay(for: .now).addingTimeInterval(Double(max(1, validDays)) * 86400 - 1)
        }
        item.markChanged()
        try? context.save()

        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let count = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: monthStart) }
        autoCharge(context, events: events, days: days)
    }

    /// Тренировки клиентов с абонементом сразу списываются с него (без галочек).
    /// Уже отмеченное вручную не трогаем.
    static func autoCharge(_ context: ModelContext, events: [PlannerEvent], days: [Date]) {
        let subs = ((try? context.fetch(FetchDescriptor<PlannerSubscription>())) ?? []).filter { $0.deletedAt == nil }
        guard !subs.isEmpty else { return }
        // Абонемент действует только на группы и школу.
        for event in events where isTraining(event) && event.categoryValue != .personal && !event.participantIDs.isEmpty {
            for day in days where event.startsOn(day) && !event.isCancelled(on: day) {
                for clientID in event.participantIDs {
                    let hasSubscription = subs.contains {
                        $0.clientID == clientID && $0.covers(day)
                            && PlannerSubscriptionTypeStore.applies($0, to: event, context: context)
                    }
                    guard hasSubscription,
                          payment(context, eventID: event.syncID, day: day, clientID: clientID) == nil
                    else { continue }
                    set(context, event: event, day: day, clientID: clientID, method: .subscription)
                }
            }
        }
    }
}

// MARK: - Перенос записи

@MainActor
enum PlannerMover {
    /// Перенести один раз события (`occurrenceStart`) на новое время.
    /// Повторяющееся событие не ломается: этот раз выделяется в отдельную запись.
    static func move(
        _ event: PlannerEvent,
        occurrenceStart: Date,
        to newStart: Date,
        context: ModelContext
    ) {
        let cal = PlannerCalendar.calendar
        let oldDay = cal.startOfDay(for: occurrenceStart)
        let newStartValue = event.isAllDay ? cal.startOfDay(for: newStart) : newStart
        let newDay = cal.startOfDay(for: newStart)
        let duration = event.end.timeIntervalSince(event.start)

        let target: PlannerEvent
        if event.repeatValue == .none {
            target = event
        } else {
            event.skippedDays.append(oldDay)
            event.markChanged()
            let clone = PlannerEvent()
            clone.title = event.title
            clone.notes = event.notes
            clone.isAllDay = event.isAllDay
            clone.scope = event.scope
            clone.isPrivate = event.isPrivate
            clone.colorHex = event.colorHex
            clone.category = event.category
            clone.repeatRule = PlannerRepeat.none.rawValue
            clone.reminderMinutes = event.reminderMinutes
            clone.createdBy = event.createdBy
            clone.createdAt = event.createdAt
            clone.participantIDs = event.participantIDs
            context.insert(clone)
            target = clone
        }
        target.start = newStartValue
        target.end = newStartValue.addingTimeInterval(duration)
        target.markChanged()

        // Оплаты едут вместе с записью.
        let rows = PlannerPaymentStore.allPayments(context).filter {
            $0.eventID == event.syncID && $0.deletedAt == nil && cal.isDate($0.day, inSameDayAs: oldDay)
        }
        if target.syncID != event.syncID || newDay != oldDay {
            for row in rows {
                let method = row.methodValue
                let amount = row.amount
                let clientID = row.clientID
                row.markDeleted()
                PlannerPaymentStore.set(context, event: target, day: newDay, clientID: clientID, method: method, amount: amount)
            }
        }
        try? context.save()
    }
}

// MARK: - Виды групп

/// Название группы («Олимпик Взрослые»), которое можно быстро выбрать при создании записи.
@Model
final class PlannerGroupKind: SyncableModel {
    struct Payload: Codable {
        var name: String
        var category: String
        /// Постоянные клиенты группы. Нет в старых записях.
        var memberIDs: [UUID]?
        var price: Double?
    }

    static let recordKind = "planner.group_kind"

    var syncID: UUID = UUID()
    var name: String = ""
    /// `group` или `school`.
    var category: String = PlannerCategory.group.rawValue
    /// Постоянные клиенты группы: подставляются при создании записи.
    var memberIDs: [UUID] = []
    /// Цена с клиента по умолчанию.
    var price: Double = PlannerPricing.group
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(name: String, category: PlannerCategory) {
        self.syncID = Self.makeID(name: name)
        self.name = name
        self.category = category.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(name: name, category: category, memberIDs: memberIDs, price: price) }

    func apply(_ payload: Payload) {
        name = payload.name
        category = payload.category
        memberIDs = payload.memberIDs ?? []
        price = payload.price ?? PlannerPricing.group
    }

    var categoryValue: PlannerCategory { category == PlannerCategory.school.rawValue ? .school : .group }

    /// Одинаковое название даёт одинаковый id, поэтому на двух телефонах не двоится.
    static func makeID(name: String) -> UUID {
        PlannerDeterministicID.make("gk|" + name.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

@MainActor
enum PlannerGroupKindStore {
    /// Добавить вид группы, если такого ещё нет (или вернуть существующий по названию).
    @discardableResult
    static func ensure(_ context: ModelContext, name: String, category: PlannerCategory) -> PlannerGroupKind {
        let clean = name.trimmingCharacters(in: .whitespaces)
        let all = (try? context.fetch(FetchDescriptor<PlannerGroupKind>())) ?? []
        let item: PlannerGroupKind
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            item = existing
            if item.deletedAt != nil || item.category != category.rawValue {
                item.deletedAt = nil
                item.category = category.rawValue
                item.markChanged()
            }
        } else {
            item = PlannerGroupKind(name: clean, category: category)
            item.markChanged()
            context.insert(item)
        }
        try? context.save()
        return item
    }
}


// MARK: - Виды абонементов

/// Готовый вид абонемента (например «Абонемент Ноябрь», 5000 ₽) для быстрой продажи.
@Model
final class PlannerSubscriptionType: SyncableModel {
    struct Payload: Codable {
        var name: String
        var price: Double
        var validDays: Int? = nil
        var charge: Double? = nil
        /// На какие группы действует (названия); нет или пусто: на все.
        var groups: [String]? = nil
    }

    static let recordKind = "planner.subscriptionType"

    var syncID: UUID = UUID()
    var name: String = ""
    var price: Double = 0
    /// Срок действия в днях.
    var validDays: Int = 30
    /// Сколько списывается за одно занятие.
    var charge: Double = PlannerPricing.subscriptionCharge
    /// Названия групп, на которые действует абонемент, по одному в строке. Пусто: на все.
    var groupsRaw: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    var groupNames: [String] {
        get { groupsRaw.split(separator: "\n").map(String.init) }
        set { groupsRaw = newValue.joined(separator: "\n") }
    }

    init(name: String, price: Double) {
        self.syncID = Self.makeID(name: name)
        self.name = name
        self.price = price
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(name: name, price: price, validDays: validDays, charge: charge, groups: groupNames.isEmpty ? nil : groupNames) }

    func apply(_ payload: Payload) {
        name = payload.name
        price = payload.price
        validDays = payload.validDays ?? 30
        groupsRaw = (payload.groups ?? []).joined(separator: "\n")
        charge = payload.charge ?? PlannerPricing.subscriptionCharge
    }

    static func makeID(name: String) -> UUID {
        PlannerDeterministicID.make("subtype|\(name.lowercased())")
    }
}

enum PlannerSubscriptionTypeStore {
    /// Действует ли проданный абонемент на это занятие: если у вида указаны группы,
    /// то только на них, если пусто, то на все.
    @MainActor
    static func applies(_ sub: PlannerSubscription, to event: PlannerEvent, context: ModelContext) -> Bool {
        guard !sub.kindName.isEmpty else { return true }
        let kind = sub.kindName
        let type = try? context.fetch(FetchDescriptor<PlannerSubscriptionType>(
            predicate: #Predicate { $0.deletedAt == nil && $0.name == kind }
        )).first
        guard let groups = type?.groupNames, !groups.isEmpty else { return true }
        return groups.contains { $0.caseInsensitiveCompare(event.title) == .orderedSame }
    }

    /// Удалить одну продажу абонемента вместе со списаниями с неё.
    @MainActor
    static func deleteSale(_ context: ModelContext, sub: PlannerSubscription) {
        let cal = PlannerCalendar.calendar
        for charge in PlannerPaymentStore.allPayments(context) where charge.deletedAt == nil
            && charge.methodValue == .subscription && charge.clientID == sub.clientID
            && cal.isDate(charge.day, equalTo: sub.month, toGranularity: .month) {
            charge.markDeleted()
        }
        sub.markDeleted()
        try? context.save()
    }

    /// Удалить вид вместе с проданными по нему абонементами и их списаниями.
    @MainActor
    static func delete(_ context: ModelContext, type: PlannerSubscriptionType) {
        let name = type.name
        let subs = ((try? context.fetch(FetchDescriptor<PlannerSubscription>())) ?? [])
            .filter { $0.deletedAt == nil && $0.kindName == name }
        let cal = PlannerCalendar.calendar
        let charges = PlannerPaymentStore.allPayments(context).filter {
            $0.deletedAt == nil && $0.methodValue == .subscription
        }
        for sub in subs {
            for charge in charges where charge.clientID == sub.clientID
                && cal.isDate(charge.day, equalTo: sub.month, toGranularity: .month) {
                charge.markDeleted()
            }
            sub.markDeleted()
        }
        type.markDeleted()
        try? context.save()
    }

    /// Создаёт «Абонемент Ноябрь» 5000 ₽, если видов ещё нет.
    @MainActor
    static func ensureDefault(_ context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<PlannerSubscriptionType>())) ?? []
        guard all.isEmpty else { return }
        let item = PlannerSubscriptionType(name: "Абонемент Ноябрь", price: 5000)
        context.insert(item)
        item.markChanged()
        try? context.save()
    }
}
