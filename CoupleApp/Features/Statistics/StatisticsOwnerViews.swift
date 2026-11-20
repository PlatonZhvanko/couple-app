import SwiftUI

/// Подразделы финансов Платони.
enum StatisticsOwnerSection: String, CaseIterable, Identifiable {
    case money = "💰 Деньги"
    case types = "🏷 Типы"
    case errands = "🧳 Дела"
    var id: String { rawValue }
}

/// Деньги Платони: смены, дела и разовые операции, прибыль и траты с детализацией.
struct StatisticsOwnerMoneyView: View {
    let entries: [PlannerLedgerEntry]
    let period: StatisticsPeriod

    private var rows: [PlannerLedgerEntry] { entries.filter { period.contains($0.day) } }

    private func sum(_ list: [PlannerLedgerEntry]) -> Double { list.reduce(0) { $0 + $1.amount } }

    private func details(_ list: [PlannerLedgerEntry]) -> some View {
        ForEach(list.sorted { $0.day > $1.day }) { item in
            StatisticsDetailRow(
                title: item.title,
                caption: "\(StatisticsFormat.day(item.day)) · \(item.type)",
                value: (item.amount >= 0 ? "+" : "−") + PlannerPricing.format(abs(item.amount))
            )
        }
    }

    var body: some View {
        let profit = rows.filter { $0.amount > 0 }
        let expense = rows.filter { $0.amount < 0 }
        List {
            Section("Итого") {
                StatisticsLine(title: "Прибыль", value: PlannerPricing.format(sum(profit))) { details(profit) }
                StatisticsLine(title: "Траты", value: PlannerPricing.format(abs(sum(expense)))) { details(expense) }
                StatisticsLine(title: "Чистыми", value: PlannerPricing.format(sum(rows)), bold: true) { details(rows) }
            }
            Section("Откуда деньги") {
                ForEach([PlannerLedgerEntry.Source.shift, .errand, .operation], id: \.rawValue) { source in
                    let list = rows.filter { $0.source == source }
                    StatisticsLine(title: source.rawValue, value: PlannerPricing.format(sum(list))) { details(list) }
                }
            }
            if !expense.isEmpty {
                Section("Траты подробно") {
                    details(expense)
                }
            }
        }
    }
}

/// Статистика по созданным типам: у каждого типа своя прибыль или трата.
struct StatisticsOwnerTypesView: View {
    let entries: [PlannerLedgerEntry]
    let period: StatisticsPeriod

    var body: some View {
        let rows = entries.filter { period.contains($0.day) }
        let groups = Dictionary(grouping: rows, by: \.type)
            .map { (name: $0.key, list: $0.value, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { abs($0.total) > abs($1.total) }
        List {
            if groups.isEmpty {
                Text("За период денег нет").foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.name) { group in
                StatisticsLine(
                    title: group.name,
                    value: (group.total >= 0 ? "+" : "−") + PlannerPricing.format(abs(group.total))
                ) {
                    ForEach(group.list.sorted { $0.day > $1.day }) { item in
                        StatisticsDetailRow(
                            title: item.title,
                            caption: "\(StatisticsFormat.day(item.day)) · \(item.source.rawValue)",
                            value: (item.amount >= 0 ? "+" : "−") + PlannerPricing.format(abs(item.amount))
                        )
                    }
                }
            }
        }
    }
}

/// Дела: сколько сделано, не сделано и перенесено.
struct StatisticsOwnerErrandsView: View {
    let events: [PlannerEvent]
    let period: StatisticsPeriod

    private struct Mark: Identifiable {
        let id: String
        let title: String
        let day: Date
        let status: PlannerErrandStatus
    }

    private var marks: [Mark] {
        var result: [Mark] = []
        for event in events where event.deletedAt == nil {
            for (day, status) in event.statuses where period.contains(day) {
                result.append(Mark(id: "\(event.syncID)-\(day.timeIntervalSince1970)", title: event.plainTitle, day: day, status: status))
            }
        }
        return result.sorted { $0.day > $1.day }
    }

    private func list(_ marks: [Mark]) -> some View {
        ForEach(marks) { item in
            StatisticsDetailRow(title: item.title, caption: StatisticsFormat.day(item.day), value: item.status.emoji)
        }
    }

    var body: some View {
        let all = marks
        let done = all.filter { $0.status == .done }
        let notDone = all.filter { $0.status == .notDone }
        let moved = all.filter { if case .moved = $0.status { true } else { false } }
        let finished = done.count + notDone.count
        List {
            Section("Итоги") {
                StatisticsLine(title: "✅ Сделано", value: "\(done.count)") { list(done) }
                StatisticsLine(title: "❌ Не сделано", value: "\(notDone.count)") { list(notDone) }
                StatisticsLine(title: "↪️ Перенесено", value: "\(moved.count)") { list(moved) }
                if finished > 0 {
                    LabeledContent("Доля выполненных", value: "\(Int((Double(done.count) / Double(finished) * 100).rounded()))%")
                }
            }
            if all.isEmpty {
                Text("За период статусов нет. Отмечай дела в записи: «Сделано», «Не сделано», «Перенесено».")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
