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

    /// Включить или обновить напоминание. Возвращает false, если уведомления запрещены.
    @discardableResult
    static func schedule(hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Как ты сегодня?"
        content.body = "Отметь настроение, это займёт пару секунд."
        content.sound = .default

        var time = DateComponents()
        time.hour = hour
        time.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// Экран настройки напоминания.
struct MoodReminderSettingsView: View {
    @AppStorage(MoodReminder.Keys.enabled) private var enabled = false
    @AppStorage(MoodReminder.Keys.hour) private var hour = 21
    @AppStorage(MoodReminder.Keys.minute) private var minute = 0
    @State private var denied = false

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = parts.hour ?? 21
                minute = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Напоминать каждый день", isOn: $enabled)
                if enabled {
                    DatePicker("Время", selection: time, displayedComponents: .hourAndMinute)
                }
            } footer: {
                if denied {
                    Text("Уведомления выключены. Разрешите их в Настройках iPhone → Вдвоём → Уведомления.")
                        .foregroundStyle(.red)
                } else {
                    Text("Телефон сам напомнит отметить настроение в выбранное время.")
                }
            }
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
