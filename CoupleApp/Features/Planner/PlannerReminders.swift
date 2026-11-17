import Foundation
import UserNotifications

/// Напоминания о событиях: обычные локальные уведомления iPhone
/// (работают без платного аккаунта и без сервера).
///
/// Каждый телефон сам планирует уведомления по своим данным: общие события
/// напоминают обоим, личные только хозяину.
enum PlannerReminders {
    private static let prefix = "planner.event."
    /// iOS хранит не больше 64 запланированных уведомлений на приложение.
    private static let limit = 50
    /// На сколько дней вперёд планировать.
    private static let horizonDays = 45

    private struct Planned {
        let id: String
        let title: String
        let body: String
        let fireDate: Date
    }

    /// Попросить разрешение на уведомления (один раз, при первом напоминании).
    static func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Пересчитать все уведомления раздела.
    @MainActor
    static func reschedule(events: [PlannerEvent], me: CoupleMember) {
        let planned = plan(events: events, me: me)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let old = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for item in planned {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                let parts = PlannerCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }

    @MainActor
    private static func plan(events: [PlannerEvent], me: CoupleMember) -> [Planned] {
        let now = Date.now
        let cal = PlannerCalendar.calendar
        let today = cal.startOfDay(for: now)
        var result: [Planned] = []

        for event in events where event.deletedAt == nil
            && event.reminderMinutes >= 0
            && event.scopeValue.concerns(me) {
            // Напоминание может быть за неделю, поэтому смотрим чуть дальше горизонта.
            let lookAhead = horizonDays + event.reminderMinutes / 1440 + 1
            for offset in 0...lookAhead {
                let day = PlannerCalendar.addDays(offset, to: today)
                guard event.startsOn(day) else { continue }
                let start = event.isAllDay ? day : PlannerCalendar.combine(day: day, time: event.start)
                let anchor = event.isAllDay
                    ? (cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
                    : start
                let fire = anchor.addingTimeInterval(-Double(event.reminderMinutes) * 60)
                guard fire > now else { continue }
                result.append(Planned(
                    id: "\(prefix)\(event.syncID.uuidString).\(Int(start.timeIntervalSince1970))",
                    title: event.title.isEmpty ? "Событие" : event.title,
                    body: body(for: event, start: start),
                    fireDate: fire
                ))
                if event.repeatValue == .none { break }
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    private static func body(for event: PlannerEvent, start: Date) -> String {
        let day = PlannerCalendar.dayTitle(start)
        return event.isAllDay ? day : "\(day), \(PlannerCalendar.time(start))"
    }
}
