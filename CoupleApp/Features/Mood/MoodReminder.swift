import SwiftUI
import UserNotifications

/// Ежедневное напоминание отметить настроение.
///
/// Это локальное уведомление: телефон сам показывает его в нужное время,
/// сервер и платный аккаунт Apple не нужны.
enum MoodReminder {
    static let identifier = "mood.dailyReminder"

    enum Keys {
        static let enabled = "mood.reminder.enabled"
        static let hour = "mood.reminder.hour"
        static let minute = "mood.reminder.minute"
    }

    /// Сколько дней вперёд заранее ставим напоминания (у каждого своя фраза Мирони).
    private static let horizon = 30
    static let defaultHour = 22
    static let defaultMinute = 30

    private static func id(for date: Date) -> String { "\(identifier).\(MoodDayKey.key(for: date))" }

    /// Включить или обновить напоминания. Возвращает false, если уведомления запрещены.
    @discardableResult
    static func schedule(hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        await rebuild(hour: hour, minute: minute)
        return true
    }

    /// Пересоздать очередь напоминаний на ближайшие дни.
    static func rebuild(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        await removeAll()
        let calendar = Calendar.current
        for offset in 0..<horizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: .now),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > .now else { continue }
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = hour
            parts.minute = minute

            let content = UNMutableNotificationContent()
            content.title = "Мироня пишет 🐾"
            content.body = MoodMiron.reminder(for: day)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id(for: day), content: content, trigger: trigger))
        }
    }

    /// Если напоминания включены, подтянуть очередь (вызывается при открытии раздела).
    static func refreshIfEnabled() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        guard enabled else { return }
        let hour = defaults.object(forKey: Keys.hour) as? Int ?? defaultHour
        let minute = defaults.object(forKey: Keys.minute) as? Int ?? defaultMinute
        Task { await schedule(hour: hour, minute: minute) }
    }

    /// Итог дня уже записан: сегодняшнее напоминание не нужно.
    static func skipToday() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(for: .now)])
    }

    static func cancel() {
        Task { await removeAll() }
    }

    private static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifier) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Экран настройки напоминания.
struct MoodReminderSettingsView: View {
    @AppStorage(MoodReminder.Keys.enabled) private var enabled = true
    @AppStorage(MoodReminder.Keys.hour) private var hour = MoodReminder.defaultHour
    @AppStorage(MoodReminder.Keys.minute) private var minute = MoodReminder.defaultMinute
    @State private var denied = false

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = parts.hour ?? MoodReminder.defaultHour
                minute = parts.minute ?? MoodReminder.defaultMinute
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Мироня напоминает каждый вечер", isOn: $enabled)
                if enabled {
                    DatePicker("Время", selection: time, displayedComponents: .hourAndMinute)
                }
            } footer: {
                if denied {
                    Text("Уведомления выключены. Разрешите их в Настройках iPhone → Вдвоём → Уведомления.")
                        .foregroundStyle(.red)
                } else {
                    Text("Мироня напишет в выбранное время и спросит, как прошёл день. Каждый раз по-разному.")
                }
            }
            MoodSleepReminderSection()
        }
        .navigationTitle("Напоминание")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: enabled) { _, _ in apply() }
        .onChange(of: hour) { _, _ in apply() }
        .onChange(of: minute) { _, _ in apply() }
    }

    private func apply() {
        guard enabled else {
            MoodReminder.cancel()
            return
        }
        Task {
            let ok = await MoodReminder.schedule(hour: hour, minute: minute)
            denied = !ok
            if !ok { enabled = false }
        }
    }
}

#Preview {
    NavigationStack { MoodReminderSettingsView() }
}
