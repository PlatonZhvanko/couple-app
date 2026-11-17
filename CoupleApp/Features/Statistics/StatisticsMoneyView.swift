import SwiftUI

/// Деньги: заработано, отказы, долги и список должников.
struct StatisticsMoneyView: View {
    let snapshot: StatisticsSnapshot
    let period: StatisticsPeriod

    private var cash: Double {
        snapshot.cashPayments.filter { $0.methodValue == .cash && period.contains($0.day) }.reduce(0) { $0 + $1.amount }
    }
    private var transfer: Double {
        snapshot.cashPayments.filter { $0.methodValue == .transfer && period.contains($0.day) }.reduce(0) { $0 + $1.amount }
    }
    private var sold: Double {
        snapshot.subscriptions.filter { period.contains($0.soldAt) }.reduce(0) { $0 + $1.amount }
    }
    private var soldCount: Int { snapshot.subscriptions.filter { period.contains($0.soldAt) }.count }

    private var inPeriod: [StatisticsVisit] {
        snapshot.visits.filter { period.contains($0.day) && $0.start <= .now }
    }
    private var refused: Int { inPeriod.filter { $0.method == .unpaid }.count }
    private var paidCount: Int { inPeriod.filter { $0.method.isPaid }.count }

    private struct Debt: Identifiable {
        let id: UUID
        let name: String
        let count: Int
        let sum: Double
    }

    private var debts: [Debt] {
        let rows = inPeriod.filter(\.isDebt)
        return Dictionary(grouping: rows, by: \.clientID)
            .map { Debt(id: $0.key, name: snapshot.name($0.key), count: $0.value.count, sum: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.sum > $1.sum }
    }
    private struct Burned: Identifiable {
        let id: UUID
        let name: String
        let sum: Double
    }

    /// Срок абонемента вышел в этом периоде, а деньги не потрачены.
    private var burned: [Burned] {
        snapshot.subscriptions
            .filter { $0.isExpired && period.contains($0.expiresAt) }
            .compactMap { sub -> Burned? in
                let left = snapshot.left(sub)
                return left > 0 ? Burned(id: sub.syncID, name: snapshot.name(sub.clientID), sum: left) : nil
            }
            .sorted { $0.sum > $1.sum }
    }
    private var burnedTotal: Double { burned.reduce(0) { $0 + $1.sum } }

    private var debtTotal: Double { debts.reduce(0) { $0 + $1.sum } }

    private var debtText: String {
        var lines = ["Долги (\(PlannerCalendar.monthTitle(period.interval.start)) и период):"]
        for item in debts {
            lines.append("\(item.name) — \(PlannerPricing.format(item.sum)) (\(item.count) зан.)")
        }
        lines.append("Итого: \(PlannerPricing.format(debtTotal))")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section("Заработано за период") {
                LabeledContent("Всего", value: PlannerPricing.format(cash + transfer + sold))
                    .font(.headline)
                LabeledContent("Наличные", value: PlannerPricing.format(cash))
                LabeledContent("Переводы", value: PlannerPricing.format(transfer))
                LabeledContent("Абонементы (продано \(soldCount))", value: PlannerPricing.format(sold))
            }

            Section("Занятия") {
                LabeledContent("Проведено", value: "\(inPeriod.count)")
                LabeledContent("Оплачено", value: "\(paidCount)")
                LabeledContent("Отказались или не оплатили ❌", value: "\(refused)")
            }

            Section {
                if burned.isEmpty {
                    Text("Ничего не сгорело").foregroundStyle(.secondary)
                }
                ForEach(burned) { item in
                    LabeledContent(item.name, value: PlannerPricing.format(item.sum))
                }
                if !burned.isEmpty {
                    LabeledContent("Сгорело всего", value: PlannerPricing.format(burnedTotal))
                        .font(.headline)
                }
            } header: {
                Text("Не реализовано (сгорело)")
            } footer: {
                Text("Остаток на абонементе, у которого вышел срок действия в этом периоде.")
            }

            Section {
                if debts.isEmpty {
                    Text("Долгов нет 🎉").foregroundStyle(.secondary)
                }
                ForEach(debts) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text("Занятий без оплаты: \(item.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(PlannerPricing.format(item.sum)).font(.body.weight(.semibold))
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
                Text("Долги")
            } footer: {
                Text("Долг — прошедшее занятие, за которое нет отметки об оплате или стоит ❌.")
            }
        }
    }
}
