import SwiftUI

/// Деньги: заработано, отказы, долги и список должников. Каждый пункт раскрывается.
struct StatisticsMoneyView: View {
    let snapshot: StatisticsSnapshot
    let period: StatisticsPeriod

    private func payments(_ method: PlannerPayMethod) -> [PlannerPayment] {
        snapshot.cashPayments
            .filter { $0.methodValue == method && period.contains($0.day) }
            .sorted { $0.day > $1.day }
    }
    private var cashList: [PlannerPayment] { payments(.cash) }
    private var transferList: [PlannerPayment] { payments(.transfer) }
    private var fineList: [PlannerPayment] {
        snapshot.finePayments.filter { period.contains($0.day) }.sorted { $0.day > $1.day }
    }
    private var soldList: [PlannerSubscription] {
        snapshot.subscriptions.filter { period.contains($0.soldAt) }.sorted { $0.soldAt > $1.soldAt }
    }
    private func sum(_ list: [PlannerPayment]) -> Double { list.reduce(0) { $0 + $1.amount } }
    private var sold: Double { soldList.reduce(0) { $0 + $1.amount } }

    /// Занятия периода считаются один раз при создании экрана.
    private let inPeriod: [StatisticsVisit]
    /// Прошедшие занятия без оплаты и неоплаченные штрафы.
    private let debtVisits: [StatisticsVisit]

    init(snapshot: StatisticsSnapshot, period: StatisticsPeriod) {
        self.snapshot = snapshot
        self.period = period
        self.debtVisits = snapshot.visits
            .filter { period.contains($0.day) && ($0.isDebt || $0.isUnpaidFine) }
            .sorted { $0.start > $1.start }
        self.inPeriod = snapshot.visits
            .filter { period.contains($0.day) && $0.start <= .now && !$0.cancelled }
            .sorted { $0.start > $1.start }
    }
    private var paidVisits: [StatisticsVisit] { inPeriod.filter { $0.method.isPaid } }

    private var burnedList: [(sub: PlannerSubscription, left: Double)] {
        snapshot.subscriptions
            .filter { $0.isExpired && period.contains($0.expiresAt) }
            .map { (sub: $0, left: snapshot.left($0)) }
            .filter { $0.left > 0 }
            .sorted { $0.left > $1.left }
    }
    private var burnedTotal: Double { burnedList.reduce(0) { $0 + $1.left } }

    private func visitRow(_ visit: StatisticsVisit, showClient: Bool) -> some View {
        StatisticsDetailRow(
            title: showClient ? snapshot.name(visit.clientID) : visit.eventTitle,
            caption: "\(StatisticsFormat.day(visit.start)) · \(showClient ? visit.eventTitle : visit.method.title)",
            value: PlannerPricing.format(visit.amount)
        )
    }

    private func paymentRow(_ payment: PlannerPayment) -> some View {
        StatisticsDetailRow(
            title: snapshot.name(payment.clientID),
            caption: "\(StatisticsFormat.day(payment.day)) · \(snapshot.eventTitles[payment.eventID] ?? "Занятие")",
            value: PlannerPricing.format(payment.amount)
        )
    }

    var body: some View {
        List {
            Section("💰 Заработано за период") {
                LabeledContent("Всего", value: PlannerPricing.format(sum(cashList) + sum(transferList) + sold + sum(fineList)))
                    .font(.headline)
                StatisticsLine(title: "💵 Наличные", value: PlannerPricing.format(sum(cashList))) {
                    if cashList.isEmpty { Text("Нет оплат").foregroundStyle(.secondary) }
                    ForEach(cashList) { paymentRow($0) }
                }
                StatisticsLine(title: "💳 Переводы", value: PlannerPricing.format(sum(transferList))) {
                    if transferList.isEmpty { Text("Нет оплат").foregroundStyle(.secondary) }
                    ForEach(transferList) { paymentRow($0) }
                }
                StatisticsLine(title: "⚠️ Штрафы за отмены", value: PlannerPricing.format(sum(fineList))) {
                    if fineList.isEmpty { Text("Штрафов нет").foregroundStyle(.secondary) }
                    ForEach(fineList) { paymentRow($0) }
                }
                StatisticsLine(title: "📜 Абонементы (\(soldList.count))", value: PlannerPricing.format(sold)) {
                    if soldList.isEmpty { Text("Продаж нет").foregroundStyle(.secondary) }
                    ForEach(soldList) { sub in
                        StatisticsDetailRow(
                            title: snapshot.name(sub.clientID),
                            caption: "\(StatisticsFormat.day(sub.soldAt)) · \(sub.kindName.isEmpty ? "Абонемент" : sub.kindName)",
                            value: PlannerPricing.format(sub.amount)
                        )
                    }
                }
            }

            Section("🎾 Занятия") {
                StatisticsLine(title: "Проведено", value: "\(inPeriod.count)") {
                    ForEach(inPeriod) { visitRow($0, showClient: true) }
                }
                StatisticsLine(title: "Оплачено", value: "\(paidVisits.count)") {
                    ForEach(paidVisits) { visitRow($0, showClient: true) }
                }
            }

            Section("📋 Долги") {
                StatisticsLine(
                    title: "Должны всего",
                    value: PlannerPricing.format(debtVisits.reduce(0) { $0 + $1.amount }),
                    bold: true
                ) {
                    if debtVisits.isEmpty { Text("Долгов нет 🎉").foregroundStyle(.secondary) }
                    ForEach(debtVisits) { visit in
                        StatisticsDetailRow(
                            title: snapshot.name(visit.clientID),
                            caption: "\(StatisticsFormat.day(visit.start)) · \(visit.cancelled ? "штраф за отмену" : visit.eventTitle)",
                            value: PlannerPricing.format(visit.amount)
                        )
                    }
                }
            }

            Section {
                if burnedList.isEmpty {
                    Text("Ничего не сгорело").foregroundStyle(.secondary)
                }
                ForEach(burnedList, id: \.sub.syncID) { item in
                    StatisticsLine(title: snapshot.name(item.sub.clientID), value: PlannerPricing.format(item.left)) {
                        StatisticsDetailRow(title: "Оплачено", caption: item.sub.kindName.isEmpty ? "Абонемент" : item.sub.kindName,
                                            value: PlannerPricing.format(item.sub.amount))
                        StatisticsDetailRow(title: "Использовано", value: PlannerPricing.format(item.sub.amount - item.left))
                        StatisticsDetailRow(title: "Срок вышел", value: StatisticsFormat.day(item.sub.expiresAt))
                    }
                }
                if !burnedList.isEmpty {
                    LabeledContent("Сгорело всего", value: PlannerPricing.format(burnedTotal))
                        .font(.headline)
                }
            } header: {
                Text("🔥 Не реализовано (сгорело)")
            } footer: {
                Text("Остаток на абонементе, у которого вышел срок действия в этом периоде.")
            }
        }
    }
}
