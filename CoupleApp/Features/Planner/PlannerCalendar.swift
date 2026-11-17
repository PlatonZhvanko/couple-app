import Foundation
import SwiftUI

/// Календарь раздела: русский язык, неделя с понедельника.
enum PlannerCalendar {
    static let locale = Locale(identifier: "ru_RU")

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }()

    /// Короткие названия дней недели, начиная с понедельника.
    static var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    static func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func startOfWeek(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let index = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -index, to: day) ?? day
    }

    /// Дни сетки месяца: целые недели, включая хвосты соседних месяцев.
    static func monthGrid(_ month: Date) -> [Date] {
        let first = startOfMonth(month)
        let gridStart = startOfWeek(first)
        let lead = calendar.dateComponents([.day], from: gridStart, to: first).day ?? 0
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let total = Int((Double(lead + daysInMonth) / 7).rounded(.up)) * 7
        return (0..<total).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    static func week(containing date: Date) -> [Date] {
        let start = startOfWeek(date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// Тот же день, но с часами и минутами из `time`.
    static func combine(day: Date, time: Date) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    static func format(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func monthTitle(_ date: Date) -> String {
        format(date, "LLLLyyyy").capitalized(with: locale)
    }

    static func dayTitle(_ date: Date) -> String {
        let text = format(date, "EEEEdMMMM")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// «Пн», «Вт», ...
    static func weekdayShort(_ date: Date) -> String {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let text = symbols[calendar.component(.weekday, from: date) - 1]
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func time(_ date: Date) -> String {
        format(date, "Hm")
    }
}

/// Один конкретный раз события (для повторяющихся их много).
struct PlannerOccurrence: Identifiable {
    let event: PlannerEvent
    let start: Date
    let end: Date

    var id: String { "\(event.syncID.uuidString)-\(start.timeIntervalSince1970)" }
}

extension PlannerEvent {
    private var cal: Calendar { PlannerCalendar.calendar }

    /// Сколько дополнительных дней захватывает событие.
    var spanDays: Int {
        let first = cal.startOfDay(for: start)
        let lastMoment = isAllDay ? end : max(start, end.addingTimeInterval(-1))
        let last = cal.startOfDay(for: lastMoment)
        return max(0, cal.dateComponents([.day], from: first, to: last).day ?? 0)
    }

    /// Начинается ли какой-то повтор события в этот день.
    func startsOn(_ day: Date) -> Bool {
        let day = cal.startOfDay(for: day)
        let firstDay = cal.startOfDay(for: start)
        guard day >= firstDay else { return false }
        if skippedDays.contains(where: { cal.isDate($0, inSameDayAs: day) }) { return false }
        if let until = repeatUntil, day > cal.startOfDay(for: until) { return false }
        let step = max(1, repeatInterval)
        switch repeatValue {
        case .none:
            return day == firstDay
        case .daily:
            let days = cal.dateComponents([.day], from: firstDay, to: day).day ?? 0
            return days % step == 0
        case .weekly:
            let weekdays = repeatWeekdays.isEmpty ? [cal.component(.weekday, from: firstDay)] : repeatWeekdays
            guard weekdays.contains(cal.component(.weekday, from: day)) else { return false }
            let firstWeek = cal.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay
            let thisWeek = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            let weeks = (cal.dateComponents([.day], from: firstWeek, to: thisWeek).day ?? 0) / 7
            return weeks % step == 0
        case .monthly:
            guard cal.component(.day, from: day) == cal.component(.day, from: firstDay) else { return false }
            let months = cal.dateComponents([.month], from: firstDay, to: day).month ?? 0
            return months % step == 0
        case .yearly:
            guard cal.component(.day, from: day) == cal.component(.day, from: firstDay)
                && cal.component(.month, from: day) == cal.component(.month, from: firstDay) else { return false }
            let years = cal.dateComponents([.year], from: firstDay, to: day).year ?? 0
            return years % step == 0
        }
    }

    /// Раз события, который захватывает этот день, если есть.
    func occurrence(on day: Date) -> PlannerOccurrence? {
        let day = cal.startOfDay(for: day)
        let duration = end.timeIntervalSince(start)
        for back in 0...spanDays {
            let candidate = PlannerCalendar.addDays(-back, to: day)
            if startsOn(candidate) {
                let occurrenceStart = isAllDay ? candidate : PlannerCalendar.combine(day: candidate, time: start)
                return PlannerOccurrence(event: self, start: occurrenceStart, end: occurrenceStart.addingTimeInterval(duration))
            }
        }
        return nil
    }
}

extension Array where Element == PlannerEvent {
    /// События дня: сначала «весь день», потом по времени начала.
    func occurrences(on day: Date) -> [PlannerOccurrence] {
        compactMap { $0.occurrence(on: day) }
            .sorted { lhs, rhs in
                if lhs.event.isAllDay != rhs.event.isAllDay { return lhs.event.isAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.event.title < rhs.event.title
            }
    }
}

extension Color {
    /// Подсветка сегодняшнего дня: мягкий розовый.
    static let plannerToday = Color(red: 1.0, green: 0.45, blue: 0.62)
}
