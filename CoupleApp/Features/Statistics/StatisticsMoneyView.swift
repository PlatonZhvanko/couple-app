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
    private var soldList: [PlannerSubscription] {
        snapshot.subscriptions.filter { period.contains($0.soldAt) }.sorted { $0.soldAt > $1.soldAt }
    }
    private func sum(_ list: [PlannerPayment]) -> Double { list.reduce(0) { $0 + $1.amount } }
    private var sold: Double { soldList.reduce(0) { $0 + $1.amount } }

    /// Занятия периода считаются один раз при создании экрана.
    private let inPeriod: [StatisticsVisit]

    init(snapshot: StatisticsSnapshot, period: StatisticsPeriod) {
        self.snapshot = snapshot
        self.period = period
        self.inPeriod = snapshot.visits
            .filter { period.contains($0.day) && $0.start <= .now }
            .sorted { $0.start > $1.start }
    }
    private var paidVisits: [StatisticsVisit] { inPeriod.filter { $0.method.isPaid } }
    private var refusedVisits: [StatisticsVisit] { inPeriod.filter { $0.method == .unpaid } }

    private struct Debt: Identifiable {
        let id: UUID
        let name: String
        let visits: [StatisticsVisit]
        var sum: Double { visits.reduce(0) { $0 + $1.amount } }
    }

    private var debts: [Debt] {
        Dictionary(grouping: inPeriod.filter(\.isDebt), by: \.clientID)
            .map { Debt(id: $0.key, name: snapshot.name($0.key), visits: $0.value) }
            .sorted { $0.sum > $1.sum }
    }
    private var debtTotal: Double { debts.reduce(0) { $0 + $1.sum } }

    private var burnedList: [(sub: PlannerSubscription, left: Double)] {
        snapshot.subscriptions
            .filter { $0.isExpired && period.contains($0.expiresAt) }
            .map { (sub: $0, left: snapshot.left($0)) }
            .filter { $0.left > 0 }
            .sorted { $0.left > $1.left }
    }
    private var burnedTotal: Double { burnedList.reduce(0) { $0 + $1.left } }

    private var debtText: String {
        var lines = ["Долги:"]
        for item in debts {
            lines.append("\(item.name) — \(PlannerPricing.format(item.sum)) (\(item.visits.count) зан.)")
        }
        lines.append("Итого: \(PlannerPricing.format(debtTotal))")
        return lines.joined(separator: "\n")
    }

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
                LabeledContent("Всего", value: PlannerPricing.format(sum(cashList) + sum(transferList) + sold))
                    .font(.headline)
                StatisticsLine(title: "💵 Наличные", value: PlannerPricing.format(sum(cashList))) {
                    if cashList.isEmpty { Text("Нет оплат").foregroundStyle(.secondary) }
                    ForEach(cashList) { paymentRow($0) }
                }
                StatisticsLine(title: "💳 Переводы", value: PlannerPricing.format(sum(transferList))) {
                    if transferList.isEmpty { Text("Нет оплат").foregroundStyle(.secondary) }
                    ForEach(transferList) { paymentRow($0) }
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
                StatisticsLine(title: "Отказались или не оплатили ❌", value: "\(refusedVisits.count)") {
                    ForEach(refusedVisits) { visitRow($0, showClient: true) }
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

            Section {
                if debts.isEmpty {
                    Text("Долгов нет 🎉").foregroundStyle(.secondary)
                }
                ForEach(debts) { item in
                    StatisticsLine(title: item.name, value: PlannerPricing.format(item.sum)) {
                        ForEach(item.visits) { visitRow($0, showClient: false) }
                    }
                }
                if !debts.isEmpty {
                    LabeledContent("Сумма долгов", value: PlannerPricing.format(debtTotal))
                        .font(.headline)
                    ShareLink(item: debtText) {
                        Label("Выгрузить список должников", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = debtText
                    } label: {
                        Label("Скопировать список", systemImage: "doc.on.doc")
                    }
                }
            } header: {
                Text("📋 Долги")
            } footer: {
                Text("Долг — прошедшее занятие, за которое нет отметки об оплате или стоит ❌.")
            }
        }
    }
}
