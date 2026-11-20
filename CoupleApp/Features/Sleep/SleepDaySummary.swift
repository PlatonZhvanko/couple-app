import Foundation
import SwiftData

/// Сон одного человека по дням. Нужен аналитике (настроение, загруженность):
/// для каждого дня — сколько спал(а) прошлой ночью, когда лёг(ла), когда встал(а),
/// как спалось и сколько часов был(а) на ногах до следующего сна.
struct SleepDaySummary: Identifiable {
    /// Начало дня, в который человек проснулся.
    let day: Date
    let hours: Double
    let bedtime: Date
    let wakeTime: Date
    /// 1…5.
    let quality: Double
    /// Часы бодрствования в этот день (от пробуждения до следующего отхода ко сну), если известно.
    let awakeHours: Double?

    var id: Date { day }

    /// Минуты от полудня: 23:00 → 660, 01:00 → 780. Удобно усреднять и сравнивать.
    var bedtimeShifted: Int { Self.shifted(bedtime) }
    var wakeMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func shifted(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0) + 12 * 60) % 1440
    }

    /// Сводка по дням за период `[from, until)` для одного человека.
    @MainActor
    static func load(_ context: ModelContext, member: CoupleMember, from: Date, until: Date) -> [SleepDaySummary] {
        let who = member.rawValue
        let all = ((try? context.fetch(FetchDescriptor<SleepEntry>())) ?? [])
            .filter { $0.deletedAt == nil && $0.member == who }
            .sorted { $0.bedtime < $1.bedtime }
        let byDay = Dictionary(grouping: all, by: \.nightDay)
        var result: [SleepDaySummary] = []
        for (day, rows) in byDay where day >= from && day < until {
            // Основной сон ночи — самый длинный.
            guard let main = rows.max(by: { $0.duration < $1.duration }) else { continue }
            let nextBed = all.first { $0.bedtime > main.wakeTime }?.bedtime
            let awake = nextBed.map { $0.timeIntervalSince(main.wakeTime) / 3600 }
            result.append(SleepDaySummary(
                day: day,
                hours: rows.reduce(0) { $0 + $1.duration } / 3600,
                bedtime: main.bedtime,
                wakeTime: main.wakeTime,
                quality: Double(main.quality),
                awakeHours: awake.flatMap { $0 > 0 && $0 < 24 ? $0 : nil }
            ))
        }
        return result.sorted { $0.day < $1.day }
    }
}
