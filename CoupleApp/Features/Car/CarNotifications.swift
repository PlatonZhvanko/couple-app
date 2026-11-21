import Foundation
import UserNotifications

/// Локальные уведомления о сроках (работают без платного аккаунта разработчика).
/// Для напоминаний с датой: за 30, 7 и 1 день и в сам день, в 10:00.
enum CarNotifications {
    private static let prefix = "car.reminder."
    private static let daysBefore = [30, 7, 1, 0]
    /// iOS хранит не больше 64 уведомлений на приложение, оставляем место другим разделам.
    private static let limit = 24

    private struct Plan: Sendable {
        let id: String
        let title: String
        let body: String
        let fireDate: Date
    }

    /// Пересоздать все уведомления раздела по текущим напоминаниям.
    @MainActor
    static func reschedule(reminders: [CarReminder], cars: [CarVehicle], repairs: [CarRepair] = [], viewer: String? = nil, lastMileage: Date? = nil) {
        let names = Dictionary(cars.map { ($0.syncID, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let calendar = Calendar.current
        let now = Date.now

        var plans: [Plan] = []
        for reminder in reminders where reminder.deletedAt == nil && !reminder.isDone {
            guard let due = reminder.dueDate else { continue }
            let carName = names[reminder.carID] ?? "Машина"
            for days in daysBefore {
                guard let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: due)),
                      let fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day),
                      fire > now else { continue }
                let when = days == 0 ? "сегодня" : "через \(days) дн."
                plans.append(Plan(
                    id: "\(prefix)\(reminder.syncID.uuidString).\(days)",
                    title: "\(carName): \(reminder.title)",
                    body: "Срок \(when), \(due.formatted(date: .long, time: .omitted)).",
                    fireDate: fire
                ))
            }
        }
        // Желаемые даты ремонтов: напоминают коты-механики, за неделю, за день и в сам день.
        let mechanics = ["Мироня", "Гоша", "Хлоя"]
        for repair in repairs where repair.deletedAt == nil && !repair.isPaid && (viewer == nil || repair.member == viewer) {
            guard let due = repair.desiredDate else { continue }
            let carName = names[repair.carID] ?? "Машина"
            for days in [7, 1, 0] {
                guard let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: due)),
                      let fire = days == 0 ? due : calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day),
                      fire > now else { continue }
                let cat = mechanics[abs(repair.syncID.hashValue &+ days) % mechanics.count]
                let when = days == 0 ? "сегодня" : (days == 1 ? "завтра" : "через неделю")
                let price = repair.price > 0 ? " Бюджет: \(CarFormat.money(repair.price))." : ""
                plans.append(Plan(
                    id: "\(prefix)repair.\(repair.syncID.uuidString).\(days)",
                    title: "\(cat) в каске: \(carName)",
                    body: "Не забыли про «\(repair.title)»? Желательно \(when).\(price)",
                    fireDate: fire
                ))
            }
        }
        // Раз в неделю без записи пробега: напоминает кот-механик.
        if !cars.isEmpty, let last = lastMileage {
            var day = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: last)) ?? now
            if day <= now { day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now }
            if let fire = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day), fire > now {
                plans.append(Plan(
                    id: "\(prefix)mileage",
                    title: "Гоша в каске",
                    body: "Что-то ты давно не записывал пробег. Пора исправить?",
                    fireDate: fire
                ))
            }
        }
        plans.sort { $0.fireDate < $1.fireDate }
        let selected = Array(plans.prefix(limit))

        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard !selected.isEmpty else { return }

            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }

            for plan in selected {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
            }
        }
    }
}
