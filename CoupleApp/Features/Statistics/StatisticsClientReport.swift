import SwiftData
import SwiftUI

/// Отчёт по одному клиенту: посещения, отмены, долги, заработано, абонементы.
/// Открывается из карточки клиента.
struct StatisticsClientReportView: View {
    let clientID: UUID
    let name: String

    @Environment(\.modelContext) private var context
    @State private var snapshot = StatisticsSnapshot()
    @State private var period = StatisticsPeriod(preset: .year)

    private var visits: [StatisticsVisit] {
        snapshot.visits
            .filter { $0.clientID == clientID && period.contains($0.day) && $0.start <= .now }
            .sorted { $0.start > $1.start }
    }
    private var attended: [StatisticsVisit] { visits.filter { $0.method != .unpaid } }
    private var cancelled: [StatisticsVisit] { visits.filter { $0.method == .unpaid } }
    private var debts: [StatisticsVisit] { visits.filter(\.isDebt) }
    private var cash: [PlannerPayment] {
        snapshot.cashPayments.filter { $0.clientID == clientID && period.contains($0.day) }.sorted { $0.day > $1.day }
    }
    private var subs: [PlannerSubscription] {
        snapshot.subscriptions.filter { $0.clientID == clientID }.sorted { $0.soldAt > $1.soldAt }
    }
    private var soldInPeriod: [PlannerSubscription] { subs.filter { period.contains($0.soldAt) } }

    private func money(_ value: Double) -> String { PlannerPricing.format(value) }

    private func visitRow(_ visit: StatisticsVisit) -> some View {
        StatisticsDetailRow(
            title: visit.eventTitle,
            caption: "\(StatisticsFormat.day(visit.start)) · \(visit.method.title)",
            value: money(visit.amount)
        )
    }

    var body: some View {
        List {
            Section {
                Picker("Период", selection: $period.preset) {
                    ForEach([StatisticsPeriod.Preset.month, .lastMonth, .year]) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("💰 Итоги") {
                StatisticsLine(title: "🎾 Посещения", value: "\(attended.count)") {
                    if attended.isEmpty { Text("Нет занятий").foregroundStyle(.secondary) }
                    ForEach(attended) { visitRow($0) }
                }
                StatisticsLine(title: "❌ Отмены", value: "\(cancelled.count)") {
                    if cancelled.isEmpty { Text("Отмен нет").foregroundStyle(.secondary) }
                    ForEach(cancelled) { visitRow($0) }
                }
                StatisticsLine(title: "📋 Долги", value: money(debts.reduce(0) { $0 + $1.amount })) {
                    if debts.isEmpty { Text("Долгов нет 🎉").foregroundStyle(.secondary) }
                    ForEach(debts) { visitRow($0) }
                }
                StatisticsLine(
                    title: "💵 Заработано",
                    value: money(cash.reduce(0) { $0 + $1.amount } + soldInPeriod.reduce(0) { $0 + $1.amount })
                ) {
                    ForEach(cash) { payment in
                        StatisticsDetailRow(
                            title: snapshot.eventTitles[payment.eventID] ?? "Занятие",
                            caption: "\(StatisticsFormat.day(payment.day)) · \(payment.methodValue.title)",
                            value: money(payment.amount)
                        )
                    }
                    ForEach(soldInPeriod) { sub in
                        StatisticsDetailRow(
                            title: "📜 \(sub.kindName.isEmpty ? "Абонемент" : sub.kindName)",
                            caption: StatisticsFormat.day(sub.soldAt),
                            value: money(sub.amount)
                        )
                    }
                }
            }

            Section("📜 Абонементы") {
                if subs.isEmpty { Text("Абонементов не было").foregroundStyle(.secondary) }
                ForEach(subs) { sub in
                    StatisticsDetailRow(
                        title: sub.kindName.isEmpty ? "Абонемент" : sub.kindName,
                        caption: "продан \(StatisticsFormat.day(sub.soldAt)), до \(StatisticsFormat.day(sub.expiresAt)), остаток \(money(snapshot.left(sub)))",
                        value: money(sub.amount)
                    )
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: period.preset) {
            snapshot = StatisticsSnapshot.load(context, from: period.interval.start, until: period.interval.end)
        }
        .environment(\.locale, PlannerCalendar.locale)
    }
}
