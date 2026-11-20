import SwiftData
import SwiftUI

/// Загруженность одного дня: сколько занятий и часов в журнале.
struct StatisticsWorkloadDay: Identifiable {
    let day: Date
    var id: Date { day }
    var count = 0
    var minutes = 0
    var cancelled = 0
    /// Занятые отрезки (минуты от начала суток) для поиска свободных окон.
    var spans: [(Int, Int)] = []
    var hours: Double { Double(minutes) / 60 }
}

enum StatisticsWorkload {
    /// Загруженность по дням периода (по всем записям журнала, кроме «на весь день»).
    @MainActor
    static func load(_ context: ModelContext, from begin: Date, until end: Date) -> [Date: StatisticsWorkloadDay] {
        let cal = PlannerCalendar.calendar
        let events = ((try? context.fetch(FetchDescriptor<PlannerEvent>())) ?? []).filter { $0.deletedAt == nil && !$0.isAllDay }
        var result: [Date: StatisticsWorkloadDay] = [:]
        for event in events {
            var day = max(cal.startOfDay(for: event.start), cal.startOfDay(for: begin))
            var steps = 0
            let length = max(0, Int(event.end.timeIntervalSince(event.start) / 60))
            while day < end && steps < 400 {
                if event.startsOn(day) {
                    var item = result[day] ?? StatisticsWorkloadDay(day: day)
                    if event.isCancelled(on: day) {
                        item.cancelled += 1
                    } else {
                        item.count += 1
                        item.minutes += length
                        let from = cal.component(.hour, from: event.start) * 60 + cal.component(.minute, from: event.start)
                        item.spans.append((from, min(from + length, 24 * 60)))
                    }
                    result[day] = item
                }
                if event.repeatValue == .none { break }
                day = PlannerCalendar.addDays(1, to: day)
                steps += 1
            }
        }
        return result
    }

    /// Свободные окна в рабочее время (8:00–22:00) не короче часа.
    static func freeWindows(_ item: StatisticsWorkloadDay) -> [(Int, Int)] {
        var cursor = 8 * 60
        var out: [(Int, Int)] = []
        for span in item.spans.sorted(by: { $0.0 < $1.0 }) {
            if span.0 - cursor >= 60 { out.append((cursor, span.0)) }
            cursor = max(cursor, span.1)
        }
        if 22 * 60 - cursor >= 60 { out.append((cursor, 22 * 60)) }
        return out
    }

    static func clock(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

    static func hoursText(_ hours: Double) -> String {
        let value = (hours * 10).rounded() / 10
        return value == value.rounded() ? "\(Int(value)) ч" : String(format: "%.1f ч", value)
    }
}

/// Загруженность: часы, занятия, отмены и свободные окна по дням и неделям.
struct StatisticsWorkloadView: View {
    let days: [Date: StatisticsWorkloadDay]
    let period: StatisticsPeriod

    private var cal: Calendar { PlannerCalendar.calendar }
    private var rows: [StatisticsWorkloadDay] {
        days.values.filter { period.contains($0.day) }.sorted { $0.day < $1.day }
    }

    private struct Week: Identifiable {
        let start: Date
        var id: Date { start }
        var hours = 0.0
        var count = 0
    }

    private var weeks: [Week] {
        var map: [Date: Week] = [:]
        for row in rows {
            let start = cal.dateInterval(of: .weekOfYear, for: row.day)?.start ?? row.day
            var week = map[start] ?? Week(start: start)
            week.hours += row.hours
            week.count += row.count
            map[start] = week
        }
        return map.values.sorted { $0.start < $1.start }
    }

    var body: some View {
        let totalHours = rows.reduce(0) { $0 + $1.hours }
        let totalCount = rows.reduce(0) { $0 + $1.count }
        let cancelled = rows.reduce(0) { $0 + $1.cancelled }
        let busyDays = rows.filter { $0.count > 0 }.count
        List {
            Section("Итого за период") {
                LabeledContent("Часов в журнале", value: StatisticsWorkload.hoursText(totalHours))
                LabeledContent("Записей", value: "\(totalCount)")
                LabeledContent("Отменено", value: "\(cancelled)")
                LabeledContent("Занятых дней", value: "\(busyDays)")
                if busyDays > 0 {
                    LabeledContent("В среднем за занятый день", value: StatisticsWorkload.hoursText(totalHours / Double(busyDays)))
                }
            }
            if !weeks.isEmpty {
                Section("По неделям") {
                    ForEach(weeks) { week in
                        StatisticsDetailRow(
                            title: "Неделя с \(StatisticsFormat.day(week.start))",
                            caption: "\(week.count) зап.",
                            value: StatisticsWorkload.hoursText(week.hours)
                        )
                    }
                }
            }
            Section("По дням") {
                if rows.isEmpty { Text("В этом периоде записей нет").foregroundStyle(.secondary) }
                ForEach(rows.reversed()) { row in
                    let free = StatisticsWorkload.freeWindows(row)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(PlannerCalendar.format(row.day, "EEE, d MMM")).font(.subheadline)
                            Spacer()
                            Text("\(row.count) зап. · \(StatisticsWorkload.hoursText(row.hours))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if free.isEmpty {
                            Text("Свободных окон нет").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Свободно: " + free.map { "\(StatisticsWorkload.clock($0.0))–\(StatisticsWorkload.clock($0.1))" }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
