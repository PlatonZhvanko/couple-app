import SwiftData
import SwiftUI

/// Создание и правка события. Личное событие партнёра открывается только для просмотра.
struct PlannerEventEditor: View {
    let event: PlannerEvent?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var title: String
    @State private var notes: String
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay: Bool
    @State private var isPrivate: Bool
    @State private var category: PlannerCategory
    @State private var repeatRule: PlannerRepeat
    @State private var repeatInterval: Int
    @State private var repeatWeekdays: [Int]
    @State private var repeatUntil: Date?
    @State private var colorHex: String
    @State private var reminder: Int
    @State private var confirmDelete = false
    @State private var moneyDirection: PlannerMoneyDirection
    @State private var moneyAmount: Double?
    @State private var moneyType: String
    @Query(filter: #Predicate<PlannerMoneyKind> { $0.deletedAt == nil }, sort: \PlannerMoneyKind.name)
    private var moneyKinds: [PlannerMoneyKind]

    /// `time` — начало нового события (нажатие на время в планировщике).
    init(event: PlannerEvent?, day: Date, at time: Date? = nil) {
        self.event = event
        let cal = PlannerCalendar.calendar
        if let event {
            _title = State(initialValue: event.title)
            _notes = State(initialValue: event.notes)
            _start = State(initialValue: event.start)
            _end = State(initialValue: event.end)
            _isAllDay = State(initialValue: event.isAllDay)
            _isPrivate = State(initialValue: event.isPrivate)
            _category = State(initialValue: event.categoryValue)
            _repeatRule = State(initialValue: event.repeatValue)
            _repeatInterval = State(initialValue: event.repeatInterval)
            _repeatWeekdays = State(initialValue: event.repeatWeekdays)
            _repeatUntil = State(initialValue: event.repeatUntil)
            _colorHex = State(initialValue: event.colorHex)
            _reminder = State(initialValue: event.reminderMinutes)
            _moneyDirection = State(initialValue: event.moneyDirection)
            _moneyAmount = State(initialValue: event.moneyAmount > 0 ? event.moneyAmount : nil)
            _moneyType = State(initialValue: event.moneyType)
        } else {
            // Новое событие: сегодня со следующего часа, иначе в 10:00.
            let now = Date.now
            let hour = cal.isDateInToday(day) ? min(cal.component(.hour, from: now) + 1, 23) : 10
            let begin = time ?? cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _start = State(initialValue: begin)
            _end = State(initialValue: begin.addingTimeInterval(3600))
            _isAllDay = State(initialValue: false)
            _isPrivate = State(initialValue: false)
            _category = State(initialValue: .errand)
            _repeatRule = State(initialValue: .none)
            _repeatInterval = State(initialValue: 1)
            _repeatWeekdays = State(initialValue: [])
            _repeatUntil = State(initialValue: nil)
            _colorHex = State(initialValue: "")
            _reminder = State(initialValue: PlannerReminderOption.none)
            _moneyDirection = State(initialValue: .none)
            _moneyAmount = State(initialValue: nil)
            _moneyType = State(initialValue: "")
        }
    }

    private var canEdit: Bool {
        event?.scopeValue.canEdit(by: account.current) ?? true
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && end >= start
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEdit, let event {
                    Section {
                        Label("Это личное событие: \(account.name(of: event.scopeValue.member ?? .owner)). Его может менять только хозяин.", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Название", text: $title)
                    Toggle("Не показывать партнёру", isOn: $isPrivate)
                    PlannerColorField(title: "Свой цвет записи", hex: $colorHex, defaultColor: category.color)
                }

                Section {
                    Toggle("Весь день", isOn: $isAllDay)
                    DatePicker("Начало", selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Конец", selection: $end, in: start..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    PlannerRepeatFields(
                        rule: $repeatRule, interval: $repeatInterval, weekdays: $repeatWeekdays,
                        until: $repeatUntil, start: start
                    )
                }

                if account.current == .owner {
                    Section {
                        Picker("Деньги", selection: $moneyDirection) {
                            ForEach(PlannerMoneyDirection.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if moneyDirection != .none {
                            HStack {
                                Text("Сумма")
                                Spacer()
                                TextField("0", value: $moneyAmount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text("₽")
                            }
                            Picker("Тип", selection: $moneyType) {
                                Text("Без типа").tag("")
                                ForEach(moneyKinds.filter { $0.isProfit == (moneyDirection == .profit) }) {
                                    Text($0.title).tag($0.name)
                                }
                            }
                        }
                    } header: {
                        Text("💰 Деньги")
                    } footer: {
                        Text(moneyDirection == .none
                             ? "Если дело что-то приносит или стоит денег, выбери «Прибыль» или «Трата»."
                             : "Деньги идут в статистику, когда в записи отмечено «Сделано». Типы создаются в «Настройки дел».")
                    }
                }

                Section {
                    // У Платони только «дело»: вида (клиент, группа, школа) нет.
                    if account.current != .owner {
                        Picker("Категория", selection: $category) {
                            ForEach(PlannerCategory.regular) { item in
                                Label {
                                    Text(item.title)
                                } icon: {
                                    Image(systemName: item.systemImage).foregroundStyle(item.color)
                                }
                                .tag(item)
                            }
                        }
                    }
                    Picker("Напоминание", selection: $reminder) {
                        ForEach(PlannerReminderOption.options(allDay: isAllDay)) { Text($0.title).tag($0.minutes) }
                    }
                }

                Section("📝 Заметка") {
                    TextField("Адрес, детали, ссылка", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if event != nil && canEdit {
                    Section {
                        Button("Удалить событие", role: .destructive) { confirmDelete = true }
                    } footer: {
                        if repeatRule != .none {
                            Text("Удалятся все повторы этого события.")
                        }
                    }
                }
            }
            .disabled(!canEdit)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(event == nil ? "Новое событие" : (canEdit ? "Событие" : "Просмотр"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить", action: save).disabled(!isValid)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
            }
            .onChange(of: start) { oldValue, newValue in
                // Двигаем конец вместе с началом, сохраняя длительность.
                let duration = max(0, end.timeIntervalSince(oldValue))
                end = newValue.addingTimeInterval(duration)
            }
            .onChange(of: moneyDirection) { _, _ in moneyType = "" }
            .onChange(of: isAllDay) { _, allDay in
                if !PlannerReminderOption.options(allDay: allDay).contains(where: { $0.minutes == reminder }) {
                    reminder = PlannerReminderOption.none
                }
                if !allDay && end <= start {
                    end = start.addingTimeInterval(3600)
                }
            }
            .confirmationDialog("Удалить событие?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
            }
        }
        .environment(\.locale, PlannerCalendar.locale)
    }

    private func save() {
        let cal = PlannerCalendar.calendar
        let target = event ?? {
            let new = PlannerEvent()
            new.createdBy = account.current.rawValue
            new.createdAt = .now
            context.insert(new)
            return new
        }()
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.isAllDay = isAllDay
        if isAllDay {
            target.start = cal.startOfDay(for: start)
            target.end = max(cal.startOfDay(for: end), target.start)
        } else {
            target.start = start
            target.end = max(end, start)
        }
        if event == nil { target.scope = PlannerScope.personal(account.current).rawValue }
        target.isPrivate = isPrivate
        target.category = category.rawValue
        target.repeatRule = repeatRule.rawValue
        target.repeatInterval = repeatInterval
        target.repeatWeekdays = repeatWeekdays
        target.repeatUntil = repeatUntil
        target.colorHex = colorHex
        target.reminderMinutes = reminder
        if account.current == .owner {
            target.moneyKindRaw = moneyDirection.rawValue
            target.moneyAmount = moneyDirection == .none ? 0 : max(0, moneyAmount ?? 0)
            target.moneyType = moneyDirection == .none ? "" : moneyType
        }
        target.markChanged()
        try? context.save()
        sync.requestSync()
        if reminder >= 0 {
            let me = account.current
            let context = context
            Task { @MainActor in
                // Спросить разрешение и сразу запланировать с учётом ответа.
                await PlannerReminders.requestPermission()
                let all = (try? context.fetch(FetchDescriptor<PlannerEvent>())) ?? []
                PlannerReminders.reschedule(events: all, me: me)
            }
        }
        dismiss()
    }

    private func delete() {
        guard let event else { return }
        event.markDeleted()
        PlannerPaymentStore.purge(context, eventID: event.syncID)
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
