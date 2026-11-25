import Foundation
import SwiftData

/// Период для отчётов.
struct StatisticsPeriod: Equatable {
    enum Preset: String, CaseIterable, Identifiable {
        case today = "Сегодня"
        case week = "Неделя"
        case month = "Месяц"
        case lastMonth = "Прошлый месяц"
        case year = "Год"
        case custom = "Свой"
        var id: String { rawValue }
    }

    var preset: Preset = .month
    var customStart = Date.now
    var customEnd = Date.now

    private var cal: Calendar { PlannerCalendar.calendar }

    /// Начало (включительно) и конец (не включительно).
    var interval: (start: Date, end: Date) {
        let today = cal.startOfDay(for: .now)
        switch preset {
        case .today:
            return (today, PlannerCalendar.addDays(1, to: today))
        case .week:
            let start = PlannerCalendar.addDays(-6, to: today)
            return (start, PlannerCalendar.addDays(1, to: today))
        case .month:
            let start = PlannerCalendar.startOfMonth(today)
            return (start, cal.date(byAdding: .month, value: 1, to: start) ?? today)
        case .lastMonth:
            let thisMonth = PlannerCalendar.startOfMonth(today)
            return (cal.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth, thisMonth)
        case .year:
            let start = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
            return (start, cal.date(byAdding: .year, value: 1, to: start) ?? today)
        case .custom:
            let start = cal.startOfDay(for: min(customStart, customEnd))
            return (start, PlannerCalendar.addDays(1, to: cal.startOfDay(for: max(customStart, customEnd))))
        }
    }

    func contains(_ date: Date) -> Bool {
        let range = interval
        return date >= range.start && date < range.end
    }
}

/// Одно занятие клиента в журнале (запись + день + клиент) со своей оплатой.
struct StatisticsVisit: Identifiable {
    let id: String
    let eventTitle: String
    let day: Date
    let start: Date
    let clientID: UUID
    let category: PlannerCategory
    let method: PlannerPayMethod
    let amount: Double
    /// Занятие отменено: оплата здесь — это штраф.
    var cancelled = false

    /// Долг: явно отмечено «не оплачено» (сразу, даже если занятие сегодня позже),
    /// либо занятие уже прошло, а оплата так и не отмечена.
    var isDebt: Bool {
        guard !cancelled else { return false }
        if method == .unpaid { return true }
        return method == .none && start <= .now
    }

    /// Штраф за отмену не оплачен.
    var isUnpaidFine: Bool { cancelled && method == .unpaid }
    var isPaidFine: Bool { cancelled && (method == .cash || method == .transfer) }
}

/// Все данные для отчётов, собранные из журнала один раз.
struct StatisticsSnapshot {
    var visits: [StatisticsVisit] = []
    /// Оплаченное наличными и переводом за занятия (без штрафов).
    var cashPayments: [PlannerPayment] = []
    /// Оплаченные штрафы за отмены.
    var finePayments: [PlannerPayment] = []
    var subscriptions: [PlannerSubscription] = []
    /// Списания тренировок с абонементов.
    var charges: [PlannerPayment] = []
    var clients: [UUID: String] = [:]
    var eventTitles: [UUID: String] = [:]

    func name(_ id: UUID) -> String { clients[id] ?? "Клиент" }

    /// Сколько осталось на абонементе (оплачено минус списано за его месяц).
    func left(_ sub: PlannerSubscription) -> Double {
        let cal = PlannerCalendar.calendar
        let used = charges
            .filter { $0.clientID == sub.clientID && cal.isDate($0.day, equalTo: sub.month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        return max(0, sub.amount - used)
    }

    @MainActor
    static func load(_ context: ModelContext, from begin: Date, until end: Date) -> StatisticsSnapshot {
        let cal = PlannerCalendar.calendar
        var snap = StatisticsSnapshot()
        snap.clients = Dictionary(
            PlannerClientDirectory.all(context).map { ($0.id, $0.name) },
            uniquingKeysWith: { a, _ in a }
        )
        let events = ((try? context.fetch(FetchDescriptor<PlannerEvent>())) ?? []).filter { $0.deletedAt == nil }
        let map = PlannerPaymentStore.eventMap(events)
        snap.eventTitles = map.mapValues(\.plainTitle)
        let live = PlannerPaymentStore.allPayments(context).filter { PlannerPaymentStore.isLive($0, events: map) }
        var byKey: [String: PlannerPayment] = [:]
        for payment in live {
            byKey["\(payment.eventID.uuidString)|\(Int(cal.startOfDay(for: payment.day).timeIntervalSince1970))|\(payment.clientID.uuidString)"] = payment
        }
        let paid = live.filter { $0.methodValue == .cash || $0.methodValue == .transfer }
        snap.finePayments = paid.filter { map[$0.eventID]?.isCancelled(on: $0.day) == true }
        snap.cashPayments = paid.filter { map[$0.eventID]?.isCancelled(on: $0.day) != true }
        snap.subscriptions = PlannerPaymentStore.allSubscriptions(context)
        snap.charges = live.filter { $0.methodValue == .subscription }

        // Записи iClients, слитые с занятием планера (подтверждённый корт), не считаем второй раз.
        let aliases = (try? context.fetch(FetchDescriptor<PlannerCourtAlias>())) ?? []
        let merged = PlannerCourtMatcher(events: events, aliases: aliases).allSupersededIDs()
        for event in events where PlannerPaymentStore.isTraining(event) && !event.participantIDs.isEmpty && !merged.contains(event.syncID) {
            // Считаем только дни периода, а не всю историю повтора.
            var day = max(cal.startOfDay(for: event.start), cal.startOfDay(for: begin))
            var steps = 0
            while day < end && steps < 400 {
                if event.startsOn(day) {
                    let start = PlannerCalendar.combine(day: day, time: event.start)
                    for clientID in event.participantIDs {
                        let key = "\(event.syncID.uuidString)|\(Int(day.timeIntervalSince1970))|\(clientID.uuidString)"
                        let row = byKey[key]
                        snap.visits.append(StatisticsVisit(
                            id: key, eventTitle: event.plainTitle, day: day, start: start,
                            clientID: clientID, category: event.categoryValue,
                            method: row?.methodValue ?? .none,
                            amount: row?.amount ?? PlannerPaymentStore.price(for: event, context: context),
                            cancelled: event.isCancelled(on: day)
                        ))
                    }
                }
                if event.repeatValue == .none { break }
                day = PlannerCalendar.addDays(1, to: day)
                steps += 1
            }
        }
        return snap
    }
}
