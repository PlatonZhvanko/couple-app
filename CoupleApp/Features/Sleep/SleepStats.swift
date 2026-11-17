import Foundation

/// Подсчёты для экрана сна: средние значения и данные для графика.
struct SleepStats {
    struct Night: Identifiable {
        let day: Date
        let hours: Double
        var id: Date { day }
    }

    let nights: [Night]
    let averageDuration: TimeInterval?
    /// Среднее время отхода ко сну, минуты от полуночи (0..<1440).
    let averageBedtimeMinutes: Int?
    let averageWakeMinutes: Int?
    let averageQuality: Double?
    /// Сколько ночей из записанных уложились в цель.
    let goalHits: Int

    /// Считает статистику за последние `days` дней (включая сегодня).
    init(entries: [SleepEntry], days: Int, goalHours: Double, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let inRange = entries.filter { $0.nightDay >= start && $0.nightDay <= today }

        // Если за ночь несколько записей (например, дневной сон), складываем.
        let byDay = Dictionary(grouping: inRange, by: \.nightDay)
        nights = byDay
            .map { Night(day: $0.key, hours: $0.value.reduce(0) { $0 + $1.duration } / 3600) }
            .sorted { $0.day < $1.day }

        if nights.isEmpty {
            averageDuration = nil
        } else {
            averageDuration = nights.reduce(0) { $0 + $1.hours } / Double(nights.count) * 3600
        }
        averageBedtimeMinutes = Self.averageClockMinutes(inRange.map(\.bedtime), calendar: calendar)
        averageWakeMinutes = Self.averageClockMinutes(inRange.map(\.wakeTime), calendar: calendar)
        averageQuality = inRange.isEmpty ? nil : Double(inRange.reduce(0) { $0 + $1.quality }) / Double(inRange.count)
        goalHits = nights.filter { $0.hours >= goalHours }.count
    }

    /// Среднее «время на часах». Считаем от полудня, чтобы 23:30 и 00:30
    /// давали в среднем полночь, а не полдень.
    static func averageClockMinutes(_ dates: [Date], calendar: Calendar) -> Int? {
        guard !dates.isEmpty else { return nil }
        let shifted = dates.map { date -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            return (minutes + 12 * 60) % 1440
        }
        let average = shifted.reduce(0, +) / shifted.count
        return (average + 12 * 60) % 1440
    }
}

enum SleepFormat {
    /// 7 ч 45 мин
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        let hours = total / 60
        let minutes = total % 60
        if minutes == 0 { return "\(hours) ч" }
        if hours == 0 { return "\(minutes) мин" }
        return "\(hours) ч \(minutes) мин"
    }

    /// 23:40
    static func clock(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static let qualityEmoji = ["😫", "😕", "😐", "🙂", "😴"]
    static let qualityTitle = ["Ужасно", "Плохо", "Нормально", "Хорошо", "Отлично"]

    static func emoji(for quality: Int) -> String {
        qualityEmoji[min(max(quality, 1), 5) - 1]
    }

    static func title(for quality: Int) -> String {
        qualityTitle[min(max(quality, 1), 5) - 1]
    }
}
