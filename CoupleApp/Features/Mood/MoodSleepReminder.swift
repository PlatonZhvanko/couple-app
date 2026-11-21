import SwiftUI
import UserNotifications

/// Вечернее напоминание «пора готовиться ко сну» от Мирони (по умолчанию 22:00).
enum MoodSleepReminder {
    static let identifier = "mood.sleepReminder"
    static let defaultHour = 22
    static let defaultMinute = 0
    private static let horizon = 7

    enum Keys {
        static let enabled = "mood.sleepReminder.enabled"
        static let hour = "mood.sleepReminder.hour"
        static let minute = "mood.sleepReminder.minute"
    }

    static let phrases: [String] = [
        "Пора потихоньку готовиться ко сну. Я уже грею место.",
        "Отложи телефон на часок до сна, а я посторожу.",
        "Мур. Вода, зубы, свет потише. Скоро спать.",
        "Хорошо выспаться важнее, чем доделать всё сегодня.",
        "Одеяло зовёт. Подготовимся ко сну?",
        "Экраны гасим, дыхание замедляем. Мироня рядом.",
        "Лечь вовремя, значит завтра будет настроение. Проверено котом.",
        "Доброй ночи почти. Давай собираться ко сну.",
    ]

    static func phrase(for date: Date) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return phrases[(day + 3) % phrases.count]
    }

    private static func id(for date: Date) -> String { "\(identifier).\(MoodDayKey.key(for: date))" }

    @discardableResult
    static func schedule(hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
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
            content.title = "Мироня пишет 🌙"
            content.body = phrase(for: day)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id(for: day), content: content, trigger: trigger))
        }
        return true
    }

    static func refreshIfEnabled() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.enabled) as? Bool ?? true else { return }
        let hour = defaults.object(forKey: Keys.hour) as? Int ?? defaultHour
        let minute = defaults.object(forKey: Keys.minute) as? Int ?? defaultMinute
        Task { await schedule(hour: hour, minute: minute) }
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

/// Раздел настроек: напоминание о подготовке ко сну.
struct MoodSleepReminderSection: View {
    @AppStorage(MoodSleepReminder.Keys.enabled) private var enabled = true
    @AppStorage(MoodSleepReminder.Keys.hour) private var hour = MoodSleepReminder.defaultHour
    @AppStorage(MoodSleepReminder.Keys.minute) private var minute = MoodSleepReminder.defaultMinute
    @State private var denied = false

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = parts.hour ?? MoodSleepReminder.defaultHour
                minute = parts.minute ?? MoodSleepReminder.defaultMinute
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Напоминать про сон", isOn: $enabled)
            if enabled {
                DatePicker("Время", selection: time, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Подготовка ко сну")
        } footer: {
            if denied {
                Text("Уведомления выключены. Разрешите их в Настройках iPhone → Вдвоём → Уведомления.")
                    .foregroundStyle(.red)
            } else {
                Text("Мироня напомнит вечером, что пора собираться спать.")
            }
        }
        .onChange(of: enabled) { _, _ in apply() }
        .onChange(of: hour) { _, _ in apply() }
        .onChange(of: minute) { _, _ in apply() }
    }

    private func apply() {
        guard enabled else {
            MoodSleepReminder.cancel()
            return
        }
        Task {
            let ok = await MoodSleepReminder.schedule(hour: hour, minute: minute)
            denied = !ok
            if !ok { enabled = false }
        }
    }
}
