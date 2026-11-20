import SwiftData
import SwiftUI

/// Настроение за период и его связь с загруженностью.
struct StatisticsMoodView: View {
    let entries: [MoodEntry]
    let workload: [Date: StatisticsWorkloadDay]
    let period: StatisticsPeriod

    private var cal: Calendar { PlannerCalendar.calendar }

    private var mine: [MoodEntry] { entries.filter { $0.deletedAt == nil && period.contains($0.createdAt) } }

    private func average(_ member: CoupleMember) -> Double? {
        MoodStats.average(mine.filter { $0.coupleMember == member })
    }

    private var dayAverages: [(day: Date, value: Double)] {
        MoodStats.byDay(mine, calendar: cal)
            .compactMap { day, list in MoodStats.average(list).map { (day, $0) } }
            .sorted { $0.day > $1.day }
    }

    /// Среднее настроение в загруженные и спокойные дни (граница — медиана часов).
    private var link: (busy: Double, calm: Double, border: Double)? {
        let pairs = dayAverages.map { ($0.value, workload[$0.day]?.hours ?? 0) }
        guard pairs.count >= 4 else { return nil }
        let sorted = pairs.map(\.1).sorted()
        let border = sorted[sorted.count / 2]
        let busy = pairs.filter { $0.1 > border }.map(\.0)
        let calm = pairs.filter { $0.1 <= border }.map(\.0)
        guard !busy.isEmpty, !calm.isEmpty else { return nil }
        return (busy.reduce(0, +) / Double(busy.count), calm.reduce(0, +) / Double(calm.count), border)
    }

    private func text(_ value: Double?) -> String {
        guard let value else { return "нет отметок" }
        return "\(MoodLevel.nearest(to: value).emoji) \(String(format: "%.1f", value))"
    }

    var body: some View {
        List {
            Section("Среднее настроение") {
                LabeledContent("Всего отметок", value: "\(mine.count)")
                LabeledContent("Платоня", value: text(average(.owner)))
                LabeledContent("Настенька", value: text(average(.partner)))
            }
            Section("Связь с загруженностью") {
                if let link {
                    LabeledContent("В загруженные дни", value: text(link.busy))
                    LabeledContent("В спокойные дни", value: text(link.calm))
                    Text(link.busy < link.calm - 0.2
                         ? "В загруженные дни настроение ниже. Стоит оставлять больше свободных окон."
                         : link.busy > link.calm + 0.2
                            ? "В загруженные дни настроение выше. Работа вас заряжает."
                            : "Загруженность почти не влияет на настроение.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Нужно хотя бы 4 дня с отметками настроения").foregroundStyle(.secondary)
                }
            }
            Section("По дням") {
                if dayAverages.isEmpty { Text("В этом периоде отметок нет").foregroundStyle(.secondary) }
                ForEach(dayAverages, id: \.day) { item in
                    let load = workload[item.day]
                    StatisticsDetailRow(
                        title: PlannerCalendar.format(item.day, "EEE, d MMM"),
                        caption: load.map { "Загрузка: \($0.count) зап., \(StatisticsWorkloadDay.hoursText($0.hours))" } ?? "Загрузка: записей не было",
                        value: text(item.value)
                    )
                }
            }
        }
    }
}
