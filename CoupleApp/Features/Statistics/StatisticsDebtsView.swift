import SwiftUI

/// Долги: прошедшие занятия без оплаты и список должников для выгрузки.
struct StatisticsDebtsView: View {
    let snapshot: StatisticsSnapshot
    let period: StatisticsPeriod

    private struct Debt: Identifiable {
        let id: UUID
        let name: String
        let visits: [StatisticsVisit]
        var sum: Double { visits.reduce(0) { $0 + $1.amount } }
    }

    private let debts: [Debt]

    init(snapshot: StatisticsSnapshot, period: StatisticsPeriod) {
        self.snapshot = snapshot
        self.period = period
        let rows = snapshot.visits.filter { period.contains($0.day) && $0.isDebt }
        self.debts = Dictionary(grouping: rows, by: \.clientID)
            .map { Debt(id: $0.key, name: snapshot.name($0.key), visits: $0.value.sorted { $0.start > $1.start }) }
            .sorted { $0.sum > $1.sum }
    }

    private var total: Double { debts.reduce(0) { $0 + $1.sum } }

    private var shareText: String {
        var lines = ["Долги:"]
        for item in debts {
            lines.append("\(item.name) — \(PlannerPricing.format(item.sum)) (\(item.visits.count) зан.)")
        }
        lines.append("Итого: \(PlannerPricing.format(total))")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Должны всего", value: PlannerPricing.format(total)).font(.headline)
                LabeledContent("Должников", value: "\(debts.count)")
            }

            Section {
                if debts.isEmpty { Text("Долгов нет 🎉").foregroundStyle(.secondary) }
                ForEach(debts) { item in
                    StatisticsLine(title: item.name, value: PlannerPricing.format(item.sum)) {
                        ForEach(item.visits) { visit in
                            StatisticsDetailRow(
                                title: visit.eventTitle,
                                caption: "\(StatisticsFormat.day(visit.start)) · \(visit.method.title)",
                                value: PlannerPricing.format(visit.amount)
                            )
                        }
                    }
                }
            } header: {
                Text("📋 По клиентам")
            } footer: {
                Text("Долг — прошедшее занятие без отметки об оплате или с ❌. Отменённые занятия сюда не входят.")
            }

            if !debts.isEmpty {
                Section {
                    ShareLink(item: shareText) {
                        Label("Выгрузить список должников", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = shareText
                    } label: {
                        Label("Скопировать список", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
