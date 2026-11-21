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
    /// «Совместное дело»: общая запись, видна и у Платони, и у Настеньки.
    @State private var isTogether: Bool
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
    /// Платоня: регулярное дело (тип из базы) или разовое.
    @State private var errandRegular: Bool
    @State private var errandType: String
    @State private var newErrandType = ""
    @State private var newErrandEmoji = ""
    @State private var newMoneyType = ""
    private var durationMinutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    private func setDuration(_ minutes: Int) {
        end = start.addingTimeInterval(TimeInterval(min(max(minutes, 30), 24 * 60) * 60))
    }

    private var durationText: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes) мин"
        case (_, 0): return "\(hours) ч"
        default: return "\(hours) ч \(minutes) мин"
        }
    }

    private var trimmedMoneyType: String { newMoneyType.trimmingCharacters(in: .whitespaces) }
    private var moneyTypeExists: Bool {
        moneyKinds.contains { $0.isProfit == (moneyDirection == .profit) && $0.name.lowercased() == trimmedMoneyType.lowercased() }
    }
    @Query(filter: #Predicate<PlannerErrandKind> { $0.deletedAt == nil }, sort: \PlannerErrandKind.name)
    private var errandKinds: [PlannerErrandKind]
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
            _isTogether = State(initialValue: event.scopeValue == .shared)
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
            _errandRegular = State(initialValue: !event.errandType.isEmpty)
            _errandType = State(initialValue: event.errandType)
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
            _isTogether = State(initialValue: false)
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
            // Новое дело Платони по умолчанию регулярное.
            _errandRegular = State(initialValue: true)
            _errandType = State(initialValue: "")
        }
    }

    /// Тип дела Платони: сначала «регулярное» (тип из базы), потом «разовое».
    @ViewBuilder
    private var errandTypeSection: some View {
        Section {
            Picker("Вид дела", selection: $errandRegular.animation()) {
                Text("Регулярное").tag(true)
                Text("Разовое").tag(false)
            }
            .pickerStyle(.segmented)
            if errandRegular {
                if !errandType.isEmpty {
                    Label("Выбрано: \(errandType)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                HStack {
                    TextField("Поиск или новый тип", text: $newErrandType)
                        .textInputAutocapitalization(.sentences)
                        .onSubmit(addErrandType)
                    if !trimmedNewType.isEmpty && !newTypeExists {
                        Button(action: addErrandType) {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Добавить тип дела")
                    }
                }
                if errandType.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Без типа регулярное дело создать нельзя. Выбери или создай тип (кнопка +).", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Button("Сделать разовым делом") { errandRegular = false }
                            .font(.footnote.weight(.semibold))
                    }
                }
                PlannerEmojiStrip(selection: $newErrandEmoji)
                // Предлагаем не больше двух типов: последние или подходящие под поиск.
                ForEach(typeSuggestions) { kind in
                    Button { errandType = kind.name; newErrandType = "" } label: {
                        Label(kind.name, systemImage: kind.name == errandType ? "checkmark" : "tag")
                    }
                    .foregroundStyle(.primary)
                }
            }
        } header: {
            Text("🏷 Тип дела")
        } footer: {
            Text(errandRegular
                 ? "Тип берётся из базы и считается в статистике. Новые типы можно создать здесь."
                 : "Разовое дело без типа: попадает в «Разовые».")
        }
    }

    private var trimmedNewType: String { newErrandType.trimmingCharacters(in: .whitespaces) }

    private var newTypeExists: Bool {
        errandKinds.visible(to: account.current).contains { $0.name.caseInsensitiveCompare(trimmedNewType) == .orderedSame }
    }

    private var typeSuggestions: [PlannerErrandKind] {
        let sorted = errandKinds.visible(to: account.current).sorted { $0.updatedAt > $1.updatedAt }
        guard !trimmedNewType.isEmpty else { return [] }
        return Array(sorted.filter { $0.name.localizedCaseInsensitiveContains(trimmedNewType) }.prefix(2))
    }

    private func addErrandType() {
        let name = newErrandType.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let emoji = newErrandEmoji.trimmingCharacters(in: .whitespaces)
        PlannerErrandKindStore.ensure(context, name: name, owner: account.current, emoji: emoji)
        if isTogether { PlannerErrandKindStore.ensureForBoth(context, name: name, emoji: emoji) }
        errandType = name
        newErrandType = ""
        newErrandEmoji = ""
        sync.requestSync()
    }

    private var canEdit: Bool {
        event?.scopeValue.canEdit(by: account.current) ?? true
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && end >= start
            && (account.current != .owner || !errandRegular || !errandType.trimmingCharacters(in: .whitespaces).isEmpty)
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

                if account.current == .owner {
                    Section {
                        TextField("Название", text: $title)
                    }
                    errandTypeSection
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
                            if !moneyType.isEmpty {
                                Label("Тип: \(moneyType)", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            HStack {
                                TextField("Поиск или новый тип", text: $newMoneyType)
                                if !trimmedMoneyType.isEmpty && !moneyTypeExists {
                                    Button {
                                        if let kind = PlannerMoneyKindStore.ensure(context, name: trimmedMoneyType, isProfit: moneyDirection == .profit) {
                                            moneyType = kind.name
                                        }
                                        newMoneyType = ""
                                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                                    .buttonStyle(.borderless)
                                }
                            }
                            if !trimmedMoneyType.isEmpty {
                                ForEach(moneyKinds.filter { $0.isProfit == (moneyDirection == .profit) && $0.name.localizedCaseInsensitiveContains(trimmedMoneyType) }.prefix(3)) { kind in
                                    Button { moneyType = kind.name; newMoneyType = "" } label: {
                                        Label(kind.title, systemImage: kind.name == moneyType ? "checkmark" : "tag")
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                    } header: {
                        Text("💰 Деньги")
                    } footer: {
                        Text(moneyDirection == .none
                             ? "Если дело что-то приносит или стоит денег, выбери «Прибыль/Приход» или «Трата»."
                             : "Деньги идут в статистику, когда в записи отмечено «Сделано». Тип ищи по названию или создай через «+».")
                    }
                }

                Section {
                    if account.current != .owner {
                        TextField("Название", text: $title)
                    }
                    Toggle("Не показывать партнёру", isOn: $isPrivate)
                        .disabled(isTogether)
                    PlannerColorField(title: "Свой цвет записи", hex: $colorHex, defaultColor: category.color)
                }

                Section {
                    Toggle("Весь день", isOn: $isAllDay)
                    DatePicker("Начало", selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Конец", selection: $end, in: start..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    if !isAllDay {
                        HStack {
                            Text("Длительность")
                            Spacer()
                            Text(durationText)
                                .foregroundStyle(.secondary)
                            Button { setDuration(durationMinutes - 30) } label: {
                                Image(systemName: "minus.circle.fill").font(.title2)
                            }
                            .disabled(durationMinutes <= 30)
                            Button { setDuration(durationMinutes + 30) } label: {
                                Image(systemName: "plus.circle.fill").font(.title2)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    PlannerRepeatFields(
                        rule: $repeatRule, interval: $repeatInterval, weekdays: $repeatWeekdays,
                        until: $repeatUntil, start: start
                    )
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

                Section {
                    Toggle("💞 Совместное дело", isOn: $isTogether)
                } footer: {
                    Text("Появится в планнере и у Платони, и у Настеньки. Цвет по умолчанию бледно-розовый, его можно поменять в «Свой цвет записи».")
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
        if isTogether {
            target.scope = PlannerScope.shared.rawValue
        } else if event == nil || target.scopeValue == .shared {
            target.scope = PlannerScope.personal(account.current).rawValue
        }
        target.isPrivate = isPrivate && !isTogether
        target.category = category.rawValue
        target.repeatRule = repeatRule.rawValue
        target.repeatInterval = repeatInterval
        target.repeatWeekdays = repeatWeekdays
        target.repeatUntil = repeatUntil
        target.colorHex = colorHex
        target.reminderMinutes = reminder
        if account.current == .owner {
            let kind = errandType.trimmingCharacters(in: .whitespaces)
            target.errandType = errandRegular ? kind : ""
            if errandRegular {
                PlannerErrandKindStore.ensure(context, name: target.errandType, owner: account.current)
                if isTogether { PlannerErrandKindStore.ensureForBoth(context, name: target.errandType) }
            }
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
