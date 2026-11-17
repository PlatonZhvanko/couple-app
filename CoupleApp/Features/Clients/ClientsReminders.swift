import Foundation
import UserNotifications

/// Локальные напоминания о записях (без сервера и платного аккаунта).
///
/// Расписание уведомлений целиком пересобирается из данных при каждом изменении
/// записей, поэтому записи, пришедшие со второго телефона, тоже получают напоминания.
enum ClientsReminders {
    static let identifierPrefix = "clients.reminder."
    /// iOS хранит не больше 64 запланированных уведомлений на приложение.
    private static let limit = 40

    struct Option: Identifiable {
        let minutes: Int
        let title: String
        var id: Int { minutes }
    }

    static let options: [Option] = [
        Option(minutes: 0, title: "Не напоминать"),
        Option(minutes: 15, title: "За 15 минут"),
        Option(minutes: 30, title: "За 30 минут"),
        Option(minutes: 60, title: "За 1 час"),
        Option(minutes: 120, title: "За 2 часа"),
        Option(minutes: 1440, title: "За день"),
    ]

    private struct Planned {
        let id: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Пересобрать напоминания для записей текущего человека.
    @MainActor
    static func refresh(appointments: [ClientsAppointment], clientNames: [UUID: String]) async {
        let now = Date.now
        let planned: [Planned] = appointments
            .filter { $0.deletedAt == nil && $0.status == .planned && $0.reminderMinutes > 0 }
            .compactMap { item in
                let fire = item.start.addingTimeInterval(-TimeInterval(item.reminderMinutes * 60))
                guard fire > now else { return nil }
                let name = item.clientID.flatMap { clientNames[$0] } ?? "Клиент"
                var body = ClientsFormat.time(item)
                if !item.service.isEmpty { body += " · \(item.service)" }
                return Planned(
                    id: identifierPrefix + item.syncID.uuidString,
                    fireDate: fire,
                    title: "Скоро запись: \(name)",
                    body: body
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }

        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined && !planned.isEmpty {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }

        let old = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: item.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}

/// Ссылки для связи с клиентом.
enum ClientsContact {
    /// Номер в международном виде без «+» (8XXXXXXXXXX → 7XXXXXXXXXX).
    static func internationalDigits(_ phone: String) -> String {
        var digits = phone.filter(\.isNumber)
        if digits.count == 11 && digits.hasPrefix("8") {
            digits = "7" + digits.dropFirst()
        }
        return digits
    }

    static func call(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    static func whatsApp(_ phone: String, text: String = "") -> URL? {
        let digits = internationalDigits(phone)
        guard !digits.isEmpty else { return nil }
        var components = URLComponents(string: "https://wa.me/\(digits)")
        if !text.isEmpty { components?.queryItems = [URLQueryItem(name: "text", value: text)] }
        return components?.url
    }

    static func sms(_ phone: String, text: String = "") -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        guard !text.isEmpty,
              let body = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return URL(string: "sms:\(digits)") }
        return URL(string: "sms:\(digits)&body=\(body)")
    }

    /// Готовый текст напоминания клиенту.
    static func reminderText(clientName: String, appointment: ClientsAppointment) -> String {
        let cal = Calendar.current
        let day = cal.isDateInToday(appointment.start) ? "сегодня"
            : cal.isDateInTomorrow(appointment.start) ? "завтра"
            : appointment.start.formatted(.dateTime.day().month(.wide))
        let time = appointment.start.formatted(date: .omitted, time: .shortened)
        var text = "Здравствуйте, \(clientName)! Напоминаю о записи \(day) в \(time)"
        if !appointment.service.isEmpty { text += " (\(appointment.service))" }
        return text + ". До встречи!"
    }
}
