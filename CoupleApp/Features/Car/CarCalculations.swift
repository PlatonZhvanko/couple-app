import Foundation
import SwiftUI

/// Расчёты раздела «Авто»: пробег, расход топлива, суммы, сроки.
enum CarMath {
    /// Текущий пробег: из самой свежей записи с пробегом (по дате, при равенстве — по времени ввода)
    /// или стартовый. Так опечатку можно исправить, записав меньший пробег новой записью.
    static func currentOdometer(car: CarVehicle, entries: [CarEntry]) -> Int {
        let latest = entries.filter { $0.odometer > 0 }.max {
            ($0.date, $0.createdAt) < ($1.date, $1.createdAt)
        }
        return latest?.odometer ?? car.startOdometer
    }

    struct FuelStats {
        /// Средний расход, л/100 км. `nil`, пока нет двух полных баков.
        var averageLitersPer100: Double?
        /// Расход между двумя последними полными баками.
        var lastLitersPer100: Double?
    }

    /// Расход считается между полными баками: всё, что залито после
    /// предыдущего полного бака до текущего (включительно), делится на пройденные км.
    static func fuelStats(_ entries: [CarEntry]) -> FuelStats {
        let fills = entries
            .filter { $0.category == .fuel && $0.odometer > 0 && $0.liters > 0 }
            .sorted { $0.odometer < $1.odometer }

        var lastFullOdometer: Int? = nil
        var litersSinceFull = 0.0
        var totalLiters = 0.0
        var totalKm = 0
        var last: Double? = nil

        for fill in fills {
            guard let start = lastFullOdometer else {
                if fill.isFullTank { lastFullOdometer = fill.odometer }
                continue
            }
            litersSinceFull += fill.liters
            if fill.isFullTank {
                let km = fill.odometer - start
                if km > 0 {
                    totalLiters += litersSinceFull
                    totalKm += km
                    last = litersSinceFull / Double(km) * 100
                }
                lastFullOdometer = fill.odometer
                litersSinceFull = 0
            }
        }

        let average = totalKm > 0 ? totalLiters / Double(totalKm) * 100 : nil
        return FuelStats(averageLitersPer100: average, lastLitersPer100: last)
    }

    static func total(_ entries: [CarEntry], in interval: DateInterval) -> Double {
        entries.filter { interval.contains($0.date) }.reduce(0) { $0 + $1.amount }
    }

    struct CategoryTotal: Identifiable {
        let category: CarEntryCategory
        let sum: Double
        var id: String { category.rawValue }
    }

    static func totalsByCategory(_ entries: [CarEntry], in interval: DateInterval) -> [CategoryTotal] {
        var sums: [CarEntryCategory: Double] = [:]
        for entry in entries where interval.contains(entry.date) {
            sums[entry.category, default: 0] += entry.amount
        }
        return sums.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { CategoryTotal(category: $0.key, sum: $0.value) }
    }

    static func currentMonth(now: Date = .now) -> DateInterval {
        Calendar.current.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
    }

    static func currentYear(now: Date = .now) -> DateInterval {
        Calendar.current.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 0)
    }

    /// Стоимость 1 км за всё время: все траты / пройденный по журналу путь.
    static func costPerKm(_ entries: [CarEntry]) -> Double? {
        let odometers = entries.map(\.odometer).filter { $0 > 0 }
        guard let minOdo = odometers.min(), let maxOdo = odometers.max(), maxOdo > minOdo else { return nil }
        let total = entries.reduce(0) { $0 + $1.amount }
        return total / Double(maxOdo - minOdo)
    }
}

// MARK: - Сроки напоминаний

enum CarUrgency: Int, Comparable {
    case overdue = 0, soon, ok, done

    static func < (lhs: CarUrgency, rhs: CarUrgency) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: Color {
        switch self {
        case .overdue: .red
        case .soon: .orange
        case .ok: .green
        case .done: .secondary
        }
    }
}

extension CarReminder {
    static let soonDays = 30
    static let soonKm = 1_000

    /// Сколько дней осталось до даты. Отрицательное — просрочено.
    func daysLeft(now: Date = .now) -> Int? {
        guard let dueDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)).day
    }

    /// Сколько км осталось. Отрицательное — просрочено.
    func kmLeft(currentOdometer: Int) -> Int? {
        dueOdometer > 0 ? dueOdometer - currentOdometer : nil
    }

    func urgency(currentOdometer: Int, now: Date = .now) -> CarUrgency {
        if isDone { return .done }
        let days = daysLeft(now: now)
        let km = kmLeft(currentOdometer: currentOdometer)
        if (days.map { $0 < 0 } ?? false) || (km.map { $0 <= 0 } ?? false) { return .overdue }
        if (days.map { $0 <= Self.soonDays } ?? false) || (km.map { $0 <= Self.soonKm } ?? false) { return .soon }
        return .ok
    }

    /// Например: «через 12 дн. · через 800 км» или «просрочено на 3 дн.».
    func statusText(currentOdometer: Int, now: Date = .now) -> String {
        if isDone { return "Сделано" }
        var parts: [String] = []
        if let days = daysLeft(now: now) {
            if days < 0 { parts.append("просрочено на \(-days) дн.") }
            else if days == 0 { parts.append("сегодня") }
            else { parts.append("через \(days) дн.") }
        }
        if let km = kmLeft(currentOdometer: currentOdometer) {
            if km <= 0 { parts.append("перепробег \((-km).formatted()) км") }
            else { parts.append("через \(km.formatted()) км") }
        }
        return parts.isEmpty ? "Без срока" : parts.joined(separator: " · ")
    }

    /// Отметить выполненным. Повторяющееся напоминание переносится на следующий срок:
    /// документ — от старой даты (страховку продлевают с даты окончания),
    /// обслуживание — от сегодня и текущего пробега.
    func complete(currentOdometer: Int, now: Date = .now) {
        lastDoneAt = now
        if repeats {
            let calendar = Calendar.current
            if repeatMonths > 0 {
                let base = kind == .document ? (dueDate ?? now) : now
                var next = calendar.date(byAdding: .month, value: repeatMonths, to: base) ?? now
                while next < calendar.startOfDay(for: now) {
                    next = calendar.date(byAdding: .month, value: repeatMonths, to: next) ?? now
                }
                dueDate = next
            }
            if repeatKm > 0 {
                dueOdometer = currentOdometer + repeatKm
            }
        } else {
            isDone = true
        }
        markChanged()
    }
}

// MARK: - Форматирование

enum CarFormat {
    static func money(_ value: Double) -> String {
        // Без тяжёлых форматтеров валюты: они медленные, а суммы рисуются списками.
        guard value.isFinite else { return "0\u{00A0}₽" }
        let number = Int(value.rounded())
        var out = ""
        for (index, char) in String(abs(number)).reversed().enumerated() {
            if index > 0 && index % 3 == 0 { out.append("\u{00A0}") }
            out.append(char)
        }
        return (number < 0 ? "-" : "") + String(out.reversed()) + "\u{00A0}₽"
    }

    static func km(_ value: Int) -> String {
        "\(value.formatted()) км"
    }

    static func liters(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) л"
    }

    static func consumption(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) л/100 км"
    }
}
