import SwiftData
import SwiftUI

/// Загруженность одного дня: сколько занятий и часов в журнале.
struct StatisticsWorkloadDay: Identifiable {
    let day: Date
    var id: Date { day }
    var count = 0
    var minutes = 0
    /// Личные тренировки, группы, дела и прочее.
    var personal = 0
    var groups = 0
    var errands = 0
    var other = 0
    var clients: Set<UUID> = []
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
                    if !event.isCancelled(on: day) {
                        switch event.categoryValue {
                        case .personal: item.personal += 1
                        case .group, .school: item.groups += 1
                        case .errand: item.errands += 1
                        default: item.other += 1
                        }
                        item.clients.formUnion(event.participantIDs)
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

/// Сон за ночь для аналитики (минуты от начала суток для «лёг» и «встал»).
struct StatisticsSleepNight {
    let day: Date
    let hours: Double
    let bedMinutes: Int
    let wakeMinutes: Int
    let quality: Int
}

enum StatisticsSleep {
    static func nights(_ entries: [SleepEntry], member: CoupleMember, period: StatisticsPeriod) -> [Date: StatisticsSleepNight] {
        let cal = PlannerCalendar.calendar
        var out: [Date: StatisticsSleepNight] = [:]
        for entry in entries where entry.deletedAt == nil && entry.member == member.rawValue && period.contains(entry.nightDay) {
            let bed = cal.component(.hour, from: entry.bedtime) * 60 + cal.component(.minute, from: entry.bedtime)
            let wake = cal.component(.hour, from: entry.wakeTime) * 60 + cal.component(.minute, from: entry.wakeTime)
            out[entry.nightDay] = StatisticsSleepNight(
                day: entry.nightDay, hours: entry.duration / 3600, bedMinutes: bed, wakeMinutes: wake, quality: entry.quality
            )
        }
        return out
    }

    /// Среднее время «лёг»: после полуночи считаем как «за полночь», чтобы 23:30 и 00:30 усреднялись верно.
    static func averageBed(_ nights: [StatisticsSleepNight]) -> Int? {
        guard !nights.isEmpty else { return nil }
        let shifted = nights.map { $0.bedMinutes < 12 * 60 ? $0.bedMinutes + 24 * 60 : $0.bedMinutes }
        return (shifted.reduce(0, +) / shifted.count) % (24 * 60)
    }

    static func averageWake(_ nights: [StatisticsSleepNight]) -> Int? {
        guard !nights.isEmpty else { return nil }
        return nights.map(\.wakeMinutes).reduce(0, +) / nights.count
    }
}

/// Загруженность: клиенты, группы, дела, свободное время и сон по дням и неделям.
struct StatisticsWorkloadView: View {
    let days: [Date: StatisticsWorkloadDay]
    let sleep: [Date: StatisticsSleepNight]
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

    /// Сколько часов человек бодрствует в день: сутки минус сон (8 ч, если сон не записан).
    private func awake(_ day: Date) -> Double { 24 - (sleep[day]?.hours ?? 8) }

    var body: some View {
        let totalHours = rows.reduce(0) { $0 + $1.hours }
        let totalCount = rows.reduce(0) { $0 + $1.count }
        let busyDays = rows.filter { $0.count > 0 }.count
        let clients = rows.reduce(into: Set<UUID>()) { $0.formUnion($1.clients) }
        let nights = Array(sleep.values)
        let freeHours = rows.reduce(0.0) { $0 + max(0, awake($1.day) - $1.hours) }
        List {
            Section("Что в журнале") {
                LabeledContent("Записей", value: "\(totalCount)")
                LabeledContent("Личных тренировок", value: "\(rows.reduce(0) { $0 + $1.personal })")
                LabeledContent("Групп", value: "\(rows.reduce(0) { $0 + $1.groups })")
                LabeledContent("Дел", value: "\(rows.reduce(0) { $0 + $1.errands })")
                LabeledContent("Прочих записей", value: "\(rows.reduce(0) { $0 + $1.other })")
                LabeledContent("Разных клиентов", value: "\(clients.count)")
            }
            Section("Время") {
                LabeledContent("Часов в журнале", value: StatisticsWorkload.hoursText(totalHours))
                LabeledContent("Занятых дней", value: "\(busyDays)")
                if busyDays > 0 {
                    LabeledContent("В среднем за занятый день", value: StatisticsWorkload.hoursText(totalHours / Double(busyDays)))
                }
                LabeledContent("Свободного времени (без сна)", value: StatisticsWorkload.hoursText(freeHours))
            }
            Section("Сон") {
                if nights.isEmpty {
                    Text("Нет отметок сна за период. Их можно записать в «Настроении».").foregroundStyle(.secondary)
                } else {
                    let avg = nights.reduce(0) { $0 + $1.hours } / Double(nights.count)
                    LabeledContent("Ночей записано", value: "\(nights.count)")
                    LabeledContent("Сплю в среднем", value: StatisticsWorkload.hoursText(avg))
                    LabeledContent("Бодрствую в среднем", value: StatisticsWorkload.hoursText(24 - avg))
                    if let bed = StatisticsSleep.averageBed(nights) {
                        LabeledContent("Ложусь около", value: StatisticsWorkload.clock(bed))
                    }
                    if let wake = StatisticsSleep.averageWake(nights) {
                        LabeledContent("Встаю около", value: StatisticsWorkload.clock(wake))
                    }
                    LabeledContent("Среднее качество", value: String(format: "%.1f из 5", Double(nights.reduce(0) { $0 + $1.quality }) / Double(nights.count)))
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
                        Text("Клиентов \(row.clients.count), групп \(row.groups), дел \(row.errands)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let night = sleep[row.day] {
                            Text("Сон \(StatisticsWorkload.hoursText(night.hours)), свободно без сна \(StatisticsWorkload.hoursText(max(0, awake(row.day) - row.hours)))")
                                .font(.caption).foregroundStyle(.secondary)
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
