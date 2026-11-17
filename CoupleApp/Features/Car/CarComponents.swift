import SwiftData
import SwiftUI

/// Какое окно редактирования открыть.
enum CarSheet: Identifiable {
    /// `nil` — новая машина.
    case car(CarVehicle?)
    case entry(car: CarVehicle, entry: CarEntry?, category: CarEntryCategory)
    case reminder(car: CarVehicle, reminder: CarReminder?)

    var id: String {
        switch self {
        case .car(let car): "car-\(car?.syncID.uuidString ?? "new")"
        case .entry(_, let entry, let category): "entry-\(entry?.syncID.uuidString ?? "new-\(category.rawValue)")"
        case .reminder(_, let reminder): "reminder-\(reminder?.syncID.uuidString ?? "new")"
        }
    }
}

/// Показывает нужную форму для `CarSheet`.
struct CarSheetView: View {
    let sheet: CarSheet
    let currentOdometer: Int

    var body: some View {
        switch sheet {
        case .car(let car):
            CarVehicleFormView(car: car)
        case .entry(let car, let entry, let category):
            CarEntryFormView(car: car, entry: entry, initialCategory: category, currentOdometer: currentOdometer)
        case .reminder(let car, let reminder):
            CarReminderFormView(car: car, reminder: reminder, currentOdometer: currentOdometer)
        }
    }
}

/// Строка журнала: категория, дата, кто добавил, сумма.
struct CarEntryRow: View {
    let entry: CarEntry
    @Environment(AccountStore.self) private var account

    var body: some View {
        HStack(spacing: 12) {
            CarCategoryIcon(category: entry.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(CarFormat.money(entry.amount))
                .monospacedDigit()
        }
    }

    private var title: String {
        let note = entry.note.trimmingCharacters(in: .whitespaces)
        if entry.category == .fuel, entry.liters > 0 {
            let fuel = "\(entry.category.title), \(CarFormat.liters(entry.liters))"
            return note.isEmpty ? fuel : "\(fuel) · \(note)"
        }
        return note.isEmpty ? entry.category.title : note
    }

    private var subtitle: String {
        var parts = [entry.date.formatted(date: .abbreviated, time: .omitted)]
        if entry.odometer > 0 { parts.append(CarFormat.km(entry.odometer)) }
        parts.append(account.name(of: entry.memberValue))
        return parts.joined(separator: " · ")
    }
}

/// Строка напоминания с цветной меткой срочности.
struct CarReminderRow: View {
    let reminder: CarReminder
    let currentOdometer: Int

    var body: some View {
        let urgency = reminder.urgency(currentOdometer: currentOdometer)
        HStack(spacing: 12) {
            Image(systemName: reminder.kind == .document ? "doc.text.fill" : "wrench.adjustable.fill")
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(urgency.color, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title.isEmpty ? "Напоминание" : reminder.title)
                    .strikethrough(reminder.isDone)
                Text(reminder.statusText(currentOdometer: currentOdometer))
                    .font(.caption)
                    .foregroundStyle(urgency == .ok || urgency == .done ? Color.secondary : urgency.color)
            }
            Spacer()
            if let due = reminder.dueDate, !reminder.isDone {
                Text(due.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CarCategoryIcon: View {
    let category: CarEntryCategory

    var body: some View {
        Image(systemName: category.systemImage)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(category.color, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Плитка с цифрой на главном экране.
struct CarStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Разбор числа, введённого с запятой или точкой.
enum CarNumber {
    static func double(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    static func int(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    static func text(_ value: Double) -> String {
        value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    static func text(_ value: Int) -> String {
        value == 0 ? "" : String(value)
    }
}

/// Записи и напоминания одной машины.
extension Array where Element == CarEntry {
    func of(_ car: CarVehicle) -> [CarEntry] { filter { $0.carID == car.syncID } }
}

extension Array where Element == CarReminder {
    func of(_ car: CarVehicle) -> [CarReminder] { filter { $0.carID == car.syncID } }

    /// Сначала просроченные, потом ближайшие.
    func sortedByUrgency(currentOdometer: Int) -> [CarReminder] {
        sorted { a, b in
            let ua = a.urgency(currentOdometer: currentOdometer)
            let ub = b.urgency(currentOdometer: currentOdometer)
            if ua != ub { return ua < ub }
            let da = a.dueDate ?? .distantFuture
            let db = b.dueDate ?? .distantFuture
            if da != db { return da < db }
            return (a.kmLeft(currentOdometer: currentOdometer) ?? .max) < (b.kmLeft(currentOdometer: currentOdometer) ?? .max)
        }
    }
}
