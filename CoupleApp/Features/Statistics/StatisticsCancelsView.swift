import SwiftUI

/// Отмены: без штрафа, штрафы оплаченные и неоплаченные.
struct StatisticsCancelsView: View {
    let snapshot: StatisticsSnapshot
    let period: StatisticsPeriod

    private let all: [StatisticsVisit]

    init(snapshot: StatisticsSnapshot, period: StatisticsPeriod) {
        self.snapshot = snapshot
        self.period = period
        self.all = snapshot.visits
            .filter { period.contains($0.day) && $0.cancelled }
            .sorted { $0.start > $1.start }
    }

    private var noFine: [StatisticsVisit] { all.filter { $0.method == .none } }
    private var paidFines: [StatisticsVisit] { all.filter(\.isPaidFine) }
    private var unpaidFines: [StatisticsVisit] { all.filter(\.isUnpaidFine) }

    private func sum(_ list: [StatisticsVisit]) -> Double { list.reduce(0) { $0 + $1.amount } }

    private func row(_ visit: StatisticsVisit) -> some View {
        StatisticsDetailRow(
            title: snapshot.name(visit.clientID),
            caption: "\(StatisticsFormat.day(visit.start)) · \(visit.eventTitle)",
            value: visit.method == .none ? nil : PlannerPricing.format(visit.amount)
        )
    }

    private struct ClientFine: Identifiable {
        let id: UUID
        let name: String
        let sum: Double
    }

    private var unpaidByClient: [ClientFine] {
        Dictionary(grouping: unpaidFines, by: \.clientID)
            .map { ClientFine(id: $0.key, name: snapshot.name($0.key), sum: sum($0.value)) }
            .sorted { $0.sum > $1.sum }
    }

    var body: some View {
        List {
            Section("🚫 Отмены за период") {
                LabeledContent("Всего отмен", value: "\(all.count)").font(.headline)
                StatisticsLine(title: "🚫 Без штрафа", value: "\(noFine.count)") {
                    if noFine.isEmpty { Text("Нет").foregroundStyle(.secondary) }
                    ForEach(noFine) { row($0) }
                }
                StatisticsLine(title: "💰 Штраф оплачен", value: PlannerPricing.format(sum(paidFines))) {
                    if paidFines.isEmpty { Text("Нет").foregroundStyle(.secondary) }
                    ForEach(paidFines) { row($0) }
                }
                StatisticsLine(title: "⏳ Штраф не оплачен", value: PlannerPricing.format(sum(unpaidFines))) {
                    if unpaidFines.isEmpty { Text("Нет").foregroundStyle(.secondary) }
                    ForEach(unpaidFines) { row($0) }
                }
            }

            Section {
                if unpaidByClient.isEmpty { Text("Неоплаченных штрафов нет 🎉").foregroundStyle(.secondary) }
                ForEach(unpaidByClient) { item in
                    LabeledContent(item.name, value: PlannerPricing.format(item.sum))
                }
            } header: {
                Text("⏳ Кто должен штраф")
            } footer: {
                Text("Отмена без штрафа — когда у клиента в отменённом занятии ничего не отмечено.")
            }
        }
    }
}
