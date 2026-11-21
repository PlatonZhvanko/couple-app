import SwiftUI
import UserNotifications

// MARK: - Данные

/// Напоминание, которое можно создать и настроить: про вес, про еду или своё.
struct AppReminder: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case weight, meal, custom
    }

    var id = UUID()
    var title: String
    /// Свой текст. Пусто: кот придумает реплику сам (для веса и еды).
    var text: String = ""
    var kind: Kind = .custom
    /// Кто пишет: `Cat.rawValue`.
    var cat: String = Cat.miron.rawValue
    var hour: Int = 12
    var minute: Int = 0
    /// Дни недели в формате `Calendar` (1 — воскресенье … 7 — суббота). Пусто: каждый день.
    var weekdays: [Int] = []
    var enabled: Bool = true

    var catValue: Cat { Cat(rawValue: cat) ?? .miron }
}

enum ReminderStore {
    private static let key = "reminders.list.v1"

    static func defaults() -> [AppReminder] {
        [
            AppReminder(title: "Записать вес", kind: .weight, cat: Cat.miron.rawValue, hour: 8, minute: 30),
            AppReminder(title: "Записать завтрак и обед", kind: .meal, cat: Cat.chloe.rawValue, hour: 11, minute: 0),
            AppReminder(title: "Записать обед и перекус", kind: .meal, cat: Cat.chloe.rawValue, hour: 16, minute: 0),
        ]
    }

    static func load() -> [AppReminder] {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([AppReminder].self, from: data) {
            return list
        }
        return defaults()
    }

    static func save(_ list: [AppReminder]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Реплики

enum ReminderPhrases {
    static let weight: [String] = [
        "Пора записать вес. Один шаг на весы, и динамика на месте.",
        "Давай сверимся: сколько сегодня на весах?",
        "Пора записать результат. Мур, я не буду осуждать.",
        "Взвешивание дня. Лапкой по весам и в приложение.",
        "Вес сам себя не запишет. Зайдёшь на минутку?",
        "Утро, весы, запись. Я уже жду.",
        "Хочу знать, как у тебя с весом. Запишешь?",
        "Пора свериться с графиком. Сначала взвесимся.",
    ]

    static let meal: [String] = [
        "Мяу! Ты уже поел(а)? Запиши, что было.",
        "Пора записать приём пищи. Я проверяю по запаху.",
        "Хлоя интересуется: что ты сегодня ел(а)? Запиши.",
        "Не забудь внести еду, а то я всё забуду вместе с тобой.",
        "Мур. Время записать, что в тарелке.",
        "Поели? Тогда быстро в приложение, пока не забылось.",
        "Хлоя напоминает: еда сама не записывается.",
        "Чем кормились? Расскажи Хлое.",
    ]

    static func line(for reminder: AppReminder, on date: Date) -> String {
        if !reminder.text.isEmpty { return reminder.text }
        let list: [String]
        switch reminder.kind {
        case .weight: list = weight
        case .meal: list = meal
        case .custom: return "Пора: \(reminder.title)"
        }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return list[(day + reminder.hour) % list.count]
    }
}

// MARK: - Планирование

enum ReminderScheduler {
    private static let prefix = "app.reminder."
    /// iPhone хранит не больше 64 запланированных уведомлений, поэтому заранее ставим неделю.
    private static let horizon = 7

    static func refresh() {
        Task { await rebuild(requestPermission: false) }
    }

    /// Пересоздать очередь. Если разрешение на уведомления ещё не спрашивали, оно запрашивается.
    @discardableResult
    static func rebuild(requestPermission: Bool) async -> Bool {
        _ = requestPermission
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let active = ReminderStore.load().filter(\.enabled)
        guard !active.isEmpty else { return true }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !granted { return false }
        } else if settings.authorizationStatus == .denied {
            return false
        }

        let calendar = Calendar.current
        for reminder in active {
            for offset in 0..<horizon {
                guard let day = calendar.date(byAdding: .day, value: offset, to: .now),
                      let fire = calendar.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: day),
                      fire > .now else { continue }
                if !reminder.weekdays.isEmpty, !reminder.weekdays.contains(calendar.component(.weekday, from: day)) { continue }
                var parts = calendar.dateComponents([.year, .month, .day], from: day)
                parts.hour = reminder.hour
                parts.minute = reminder.minute
                let content = UNMutableNotificationContent()
                content.title = "\(reminder.catValue.name) пишет 🐾"
                content.body = ReminderPhrases.line(for: reminder, on: day)
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "\(prefix)\(reminder.id.uuidString).\(offset)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
                try? await center.add(request)
            }
        }
        return true
    }
}

// MARK: - Экран

/// Все напоминания приложения в одном месте: итог дня и сон от Мирони,
/// вес, питание и свои собственные.
struct RemindersView: View {
    @State private var list: [AppReminder] = ReminderStore.load()
    @State private var editing: AppReminder?
    @State private var denied = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    MoodReminderSettingsView()
                } label: {
                    Label("Итог дня и подготовка ко сну", systemImage: "moon.stars")
                }
            } header: {
                Text("Мироня")
            } footer: {
                Text("Вечером в 22:00 про сон и в 22:30 про итог дня.")
            }

            Section {
                ForEach(list) { item in
                    Button { editing = item } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(.primary)
                                Text("\(item.catValue.name) · \(timeText(item)) · \(daysText(item))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: item.enabled ? "bell.fill" : "bell.slash")
                                .foregroundStyle(item.enabled ? Color.accentColor : .secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    list.remove(atOffsets: offsets)
                    commit()
                }
                Button {
                    editing = AppReminder(title: "", kind: .custom)
                } label: {
                    Label("Добавить напоминание", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Вес, питание и свои")
            } footer: {
                if denied {
                    Text("Уведомления выключены. Разрешите их в Настройках iPhone → Вдвоём → Уведомления.")
                        .foregroundStyle(.red)
                } else {
                    Text("Пустой текст значит, что кот каждый раз придумает реплику сам. Напоминания обновляются при каждом открытии приложения.")
                }
            }
        }
        .navigationTitle("Напоминания")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            ReminderEditView(reminder: item) { saved in
                if let index = list.firstIndex(where: { $0.id == saved.id }) {
                    list[index] = saved
                } else {
                    list.append(saved)
                }
                commit()
            }
        }
        .onAppear { commit() }
    }

    private func commit() {
        ReminderStore.save(list)
        Task { denied = !(await ReminderScheduler.rebuild(requestPermission: true)) }
    }

    private func timeText(_ item: AppReminder) -> String {
        String(format: "%02d:%02d", item.hour, item.minute)
    }

    private func daysText(_ item: AppReminder) -> String {
        item.weekdays.isEmpty ? "каждый день" : "по выбранным дням"
    }
}

private struct ReminderEditView: View {
    @State var reminder: AppReminder
    let onSave: (AppReminder) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let weekdays: [(title: String, value: Int)] = [
        ("Пн", 2), ("Вт", 3), ("Ср", 4), ("Чт", 5), ("Пт", 6), ("Сб", 7), ("Вс", 1),
    ]

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: .now) ?? .now },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                reminder.hour = parts.hour ?? 12
                reminder.minute = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название, например «Выпить воду»", text: $reminder.title)
                    TextField(reminder.kind == .custom ? "Текст уведомления" : "Свой текст (пусто: кот придумает)", text: $reminder.text, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Кто напомнит") {
                    Picker("Кот", selection: $reminder.cat) {
                        ForEach(Cat.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Когда") {
                    DatePicker("Время", selection: time, displayedComponents: .hourAndMinute)
                    HStack(spacing: 6) {
                        ForEach(Self.weekdays, id: \.value) { day in
                            let on = reminder.weekdays.isEmpty || reminder.weekdays.contains(day.value)
                            Button {
                                toggle(day.value)
                            } label: {
                                Text(day.title)
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 32)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Toggle("Включено", isOn: $reminder.enabled)
                }
            }
            .navigationTitle(reminder.title.isEmpty ? "Новое напоминание" : "Напоминание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if reminder.title.trimmingCharacters(in: .whitespaces).isEmpty { reminder.title = "Напоминание" }
                        onSave(reminder)
                        dismiss()
                    }
                }
            }
        }
    }

    /// Пустой список значит «каждый день»: при первом касании разворачиваем его в семь дней.
    private func toggle(_ value: Int) {
        var days = reminder.weekdays.isEmpty ? Self.weekdays.map(\.value) : reminder.weekdays
        if let index = days.firstIndex(of: value) {
            days.remove(at: index)
        } else {
            days.append(value)
        }
        reminder.weekdays = days.count == 7 || days.isEmpty ? [] : days
    }
}
