import SwiftData
import SwiftUI

/// Создание и правка тренировки (профиль Настеньки): клиент, группа или дело.
struct PlannerTrainingEditor: View {
    enum Mode: String, CaseIterable, Identifiable {
        case client, group, errand
        var id: String { rawValue }
        var title: String {
            switch self {
            case .client: "Клиент"
            case .group: "Группа"
            case .errand: "Дело"
            }
        }
    }

    let event: PlannerEvent?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var mode: Mode
    @State private var groupCategory: PlannerCategory
    @State private var title: String
    @State private var notes: String
    @State private var start: Date
    @State private var durationMinutes: Int
    @State private var isPrivate: Bool
    /// «Совместное дело»: общая запись, видна и у Платони, и у Настеньки.
    @State private var isTogether: Bool
    @State private var repeatRule: PlannerRepeat
    @State private var repeatInterval: Int
    @State private var repeatWeekdays: [Int]
    @State private var repeatUntil: Date?
    @State private var colorHex: String
    @State private var reminder: Int
    @State private var participants: [PlannerClientDirectory.Entry] = []
    @State private var participantIDs: [UUID]
    @State private var query = ""
    @State private var directory: [PlannerClientDirectory.Entry] = []
    @State private var confirmDelete = false
    @State private var newKindName = ""
    @State private var errandRegular = false
    @State private var pMoney: PlannerMoneyDirection = .none
    @State private var pAmount: Double?
    @State private var pType = ""
    @State private var pTypeQuery = ""
    @Query(filter: #Predicate<PlannerMoneyKind> { $0.deletedAt == nil }, sort: \PlannerMoneyKind.name)
    private var moneyKinds: [PlannerMoneyKind]
    @Query(filter: #Predicate<PlannerErrandKind> { $0.deletedAt == nil }, sort: \PlannerErrandKind.name)
    private var errandKinds: [PlannerErrandKind]
    @Query(filter: #Predicate<PlannerGroupKind> { $0.deletedAt == nil }, sort: \PlannerGroupKind.name)
    private var groupKinds: [PlannerGroupKind]

    /// Какую форму открывать: тренировочную (для Настеньки и для её записей) или обычную.
    static func shouldUse(for event: PlannerEvent?, me: CoupleMember) -> Bool {
        // У Платони свой упрощённый редактор: клиентов, групп и оплат нет.
        guard me == .partner else { return false }
        guard let event else { return true }
        return [.personal, .group, .school, .errand].contains(event.categoryValue)
    }

    init(event: PlannerEvent?, day: Date, at time: Date? = nil) {
        self.event = event
        let cal = PlannerCalendar.calendar
        if let event {
            let category = event.categoryValue
            _mode = State(initialValue: category == .errand ? .errand : (category == .personal ? .client : .group))
            _groupCategory = State(initialValue: category == .school ? .school : .group)
            _title = State(initialValue: event.title)
            _errandRegular = State(initialValue: category == .errand && event.repeatRule != PlannerRepeat.none.rawValue)
            _pMoney = State(initialValue: PlannerMoneyDirection(rawValue: event.partnerMoneyKindRaw) ?? .none)
            _pAmount = State(initialValue: event.partnerMoneyAmount > 0 ? event.partnerMoneyAmount : nil)
            _pType = State(initialValue: event.partnerMoneyType)
            _notes = State(initialValue: event.notes)
            _start = State(initialValue: event.start)
            _durationMinutes = State(initialValue: max(30, Int(event.end.timeIntervalSince(event.start) / 60)))
            _isPrivate = State(initialValue: event.isPrivate)
            _isTogether = State(initialValue: event.scopeValue == .shared)
            _repeatRule = State(initialValue: event.repeatValue)
            _repeatInterval = State(initialValue: event.repeatInterval)
            _repeatWeekdays = State(initialValue: event.repeatWeekdays)
            _repeatUntil = State(initialValue: event.repeatUntil)
            _colorHex = State(initialValue: event.colorHex)
            _reminder = State(initialValue: event.reminderMinutes)
            _participantIDs = State(initialValue: event.participantIDs)
        } else {
            let hour = cal.isDateInToday(day) ? min(cal.component(.hour, from: .now) + 1, 22) : 10
            let begin = time ?? cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            _mode = State(initialValue: .client)
            _groupCategory = State(initialValue: .group)
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _start = State(initialValue: begin)
            _durationMinutes = State(initialValue: 60)
            _isPrivate = State(initialValue: false)
            _isTogether = State(initialValue: false)
            _repeatRule = State(initialValue: .none)
            _repeatInterval = State(initialValue: 1)
            _repeatWeekdays = State(initialValue: [])
            _repeatUntil = State(initialValue: nil)
            _colorHex = State(initialValue: "")
            _reminder = State(initialValue: PlannerReminderOption.none)
            _participantIDs = State(initialValue: [])
        }
    }

    private var canEdit: Bool {
        event?.scopeValue.canEdit(by: account.current) ?? true
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var category: PlannerCategory {
        switch mode {
        case .client: .personal
        case .group: groupCategory
        case .errand: .errand
        }
    }

    private var isValid: Bool {
        switch mode {
        case .client: !participants.isEmpty || !trimmedQuery.isEmpty
        case .group: true
        case .errand: !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) },
            set: { newEnd in
                let minutes = Int((newEnd.timeIntervalSince(start) / 60).rounded())
                durationMinutes = min(max(minutes, 15), 24 * 60)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEdit {
                    Section {
                        Label("Это запись другого человека, её можно только смотреть.", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Что записываем", selection: $mode.animation()) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .client:
                    Section("🙋 Клиент") { participantsPicker(multiple: false) }
                case .group:
                    Section {
                        Picker("Категория", selection: $groupCategory) {
                            ForEach([PlannerCategory.group, .school]) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        groupKindChips
                        HStack {
                            TextField("Новая группа", text: $newKindName)
                                .textInputAutocapitalization(.sentences)
                                .onSubmit(addGroupKind)
                            if !trimmedKindName.isEmpty && !kindExists {
                                Button(action: addGroupKind) {
                                    Image(systemName: "plus.circle.fill").font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Добавить вид группы")
                            }
                        }
                    } header: {
                        Text(title.isEmpty ? "👧👦 Какая группа" : "Группа: \(title)")
                    }
                    Section {
                        participantsPicker(multiple: true)
                    } header: {
                        Text("👥 Клиенты группы")
                    } footer: {
                        Text("Блок можно создать без клиентов и записать их потом.")
                    }
                case .errand:
                    Section {
                        Picker("Вид дела", selection: $errandRegular.animation()) {
                            Text("Разовое").tag(false)
                            Text("Регулярное").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if errandRegular {
                            HStack {
                                TextField("Поиск или новый тип", text: $title)
                                    .textInputAutocapitalization(.sentences)
                                if !trimmedTitle.isEmpty && !errandKindExists {
                                    Button {
                                        PlannerErrandKindStore.ensure(context, name: trimmedTitle, owner: account.current)
                                        sync.requestSync()
                                    } label: {
                                        Image(systemName: "plus.circle.fill").font(.title3)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Добавить тип дела")
                                }
                            }
                            ForEach(errandMatches) { kind in
                                Button { title = kind.name } label: {
                                    Label(kind.name, systemImage: kind.name == trimmedTitle ? "checkmark" : "tag")
                                }
                            }
                        } else {
                            TextField("Что нужно сделать (например, купить кастрюли)", text: $title)
                        }
                    } header: {
                        Text("🧳 Дело")
                    }
                    partnerMoneySection
                }

                Section {
                    DatePicker("Дата", selection: $start, displayedComponents: [.date])
                    HStack {
                        Text("Время")
                        Spacer()
                        DatePicker("Начало", selection: $start, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                        Text("–")
                        DatePicker("Конец", selection: endBinding, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                    }
                    HStack {
                        Text("Длительность")
                        Spacer()
                        Text(durationText)
                            .foregroundStyle(.secondary)
                        Button { durationMinutes = max(30, durationMinutes - 30) } label: {
                            Image(systemName: "minus.circle.fill").font(.title2)
                        }
                        .disabled(durationMinutes <= 30)
                        Button { durationMinutes = min(durationMinutes + 30, 24 * 60) } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                    }
                    .buttonStyle(.borderless)
                    PlannerRepeatFields(
                        rule: $repeatRule, interval: $repeatInterval, weekdays: $repeatWeekdays,
                        until: $repeatUntil, start: start
                    )
                }

                Section {
                    Toggle("Не показывать партнёру", isOn: $isPrivate)
                        .disabled(isTogether)
                    PlannerColorField(title: "Свой цвет записи", hex: $colorHex, defaultColor: category.color)
                    Picker("Напоминание", selection: $reminder) {
                        ForEach(PlannerReminderOption.options(allDay: false)) { Text($0.title).tag($0.minutes) }
                    }
                }

                Section {
                    Toggle("💞 Совместное дело", isOn: $isTogether)
                } footer: {
                    Text("Появится в планнере и у Платони, и у Настеньки. Цвет по умолчанию бледно-розовый, его можно поменять в «Свой цвет записи».")
                }

                Section("📝 Заметка") {
                    TextField("Что взять, детали", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if event != nil && canEdit {
                    Section {
                        Button("Удалить", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .disabled(!canEdit)
            .navigationTitle(event == nil ? "Новая тренировка" : "Тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить", action: save).disabled(!isValid)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
            }
            .onAppear(perform: loadDirectory)
        }
        .environment(\.locale, PlannerCalendar.locale)
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

    // MARK: - Деньги дела (личные)

    private var trimmedPType: String { pTypeQuery.trimmingCharacters(in: .whitespaces) }

    private var partnerMoneySection: some View {
        Section {
            Picker("Деньги", selection: $pMoney.animation()) {
                ForEach(PlannerMoneyDirection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if pMoney != .none {
                HStack {
                    Text("Сумма")
                    Spacer()
                    TextField("0", value: $pAmount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("₽")
                }
                if !pType.isEmpty {
                    Label("Тип: \(pType)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                HStack {
                    TextField("Поиск или новый тип", text: $pTypeQuery)
                    if !trimmedPType.isEmpty,
                       !moneyKinds.contains(where: { $0.isProfit == (pMoney == .profit) && $0.name.caseInsensitiveCompare(trimmedPType) == .orderedSame }) {
                        Button {
                            if let kind = PlannerMoneyKindStore.ensure(context, name: trimmedPType, isProfit: pMoney == .profit) {
                                pType = kind.name
                            }
                            pTypeQuery = ""
                        } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .buttonStyle(.borderless)
                    }
                }
                if !trimmedPType.isEmpty {
                    ForEach(moneyKinds.filter { $0.isProfit == (pMoney == .profit) && $0.name.localizedCaseInsensitiveContains(trimmedPType) }.prefix(3)) { kind in
                        Button { pType = kind.name; pTypeQuery = "" } label: {
                            Label(kind.title, systemImage: kind.name == pType ? "checkmark" : "tag")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        } header: {
            Text("💰 Деньги за дело")
        } footer: {
            Text("По умолчанию ничего. Это твои личные деньги: у совместного дела у каждого свои, в статистике «Дела».")
        }
        .onChange(of: pMoney) { _, _ in pType = "" }
    }

    // MARK: - Клиенты

    private func loadDirectory() {
        // Сначала те, кого записывали недавно, потом остальные по алфавиту.
        let recent = (try? context.fetch(FetchDescriptor<PlannerEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))) ?? []
        var rank: [UUID: Int] = [:]
        for event in recent {
            for id in event.participantIDs where rank[id] == nil { rank[id] = rank.count }
        }
        directory = PlannerClientDirectory.all(context).sorted { lhs, rhs in
            let l = rank[lhs.id] ?? Int.max
            let r = rank[rhs.id] ?? Int.max
            if l != r { return l < r }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        participants = participantIDs.compactMap { id in directory.first { $0.id == id } }
    }

    // MARK: - Виды групп

    private var trimmedKindName: String { newKindName.trimmingCharacters(in: .whitespaces) }

    private var kindExists: Bool {
        groupKinds.contains { $0.name.caseInsensitiveCompare(trimmedKindName) == .orderedSame }
    }

    private var groupKindChips: some View {
        Group {
            if trimmedKindName.isEmpty {
                Text("Впиши название для поиска или нового вида и нажми +.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groupKinds.filter { $0.name.localizedCaseInsensitiveContains(trimmedKindName) }.prefix(3)) { kind in
                            let selected = title == kind.name
                            Button {
                                selectGroupKind(kind)
                            } label: {
                                Text(kind.name)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(selected ? kind.categoryValue.color.opacity(0.35) : Color.secondary.opacity(0.15)))
                                    .overlay(Capsule().strokeBorder(selected ? kind.categoryValue.color : Color.clear, lineWidth: 1.5))
                                    .foregroundStyle(Color.primary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func selectGroupKind(_ kind: PlannerGroupKind) {
        title = kind.name
        groupCategory = kind.categoryValue
        // Подставляем постоянных клиентов группы (их можно убрать).
        if !kind.memberIDs.isEmpty {
            participants = kind.memberIDs.compactMap { id in directory.first { $0.id == id } }
        }
    }

    private func addGroupKind() {
        let name = trimmedKindName
        guard !name.isEmpty else { return }
        let kind = PlannerGroupKindStore.ensure(context, name: name, category: groupCategory)
        sync.requestSync()
        newKindName = ""
        selectGroupKind(kind)
    }

    private var suggestions: [PlannerClientDirectory.Entry] {
        let selected = Set(participants.map(\.id))
        let pool = directory.filter { !selected.contains($0.id) }
        // Без запроса показываем только двух недавних.
        guard !trimmedQuery.isEmpty else { return [] }
        return Array(pool.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }.prefix(6))
    }

    private var queryMatchesExisting: Bool {
        directory.contains { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    @ViewBuilder
    private func participantsPicker(multiple: Bool) -> some View {
        ForEach(participants) { client in
            HStack {
                Label(client.name, systemImage: "person.fill")
                Spacer()
                Button {
                    participants.removeAll { $0.id == client.id }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }

        if multiple || participants.isEmpty {
            HStack {
                TextField(multiple ? "Добавить клиента" : "Найти клиента", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit(addTypedClient)
                if !trimmedQuery.isEmpty && !queryMatchesExisting {
                    Button(action: addTypedClient) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Новый клиент")
                }
            }
            if !trimmedQuery.isEmpty && !queryMatchesExisting {
                Text("Такого клиента нет. Нажми +, чтобы добавить «\(trimmedQuery)» в базу.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if trimmedQuery.isEmpty && !suggestions.isEmpty {
                Text("Недавние")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(suggestions) { client in
                Button {
                    select(client, multiple: multiple)
                } label: {
                    Label(client.name, systemImage: "person")
                }
            }
        }
    }

    private func select(_ client: PlannerClientDirectory.Entry, multiple: Bool) {
        if multiple { participants.append(client) } else { participants = [client] }
        query = ""
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    private var errandKindExists: Bool {
        errandKinds.visible(to: account.current).contains { $0.name.caseInsensitiveCompare(trimmedTitle) == .orderedSame }
    }

    private var errandMatches: [PlannerErrandKind] {
        let mine = errandKinds.visible(to: account.current)
        guard !trimmedTitle.isEmpty else { return [] }
        return Array(mine.filter { $0.name.localizedCaseInsensitiveContains(trimmedTitle) }.prefix(5))
    }

    /// Если такой клиент уже есть, выбираем его, иначе заводим нового в общей базе.
    private func addTypedClient() {
        let name = trimmedQuery
        guard !name.isEmpty else { return }
        let multiple = mode == .group
        if let existing = directory.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if !participants.contains(where: { $0.id == existing.id }) { select(existing, multiple: multiple) }
            query = ""
            return
        }
        let created = PlannerClientDirectory.add(name: name, member: account.current, context: context)
        directory.insert(created, at: 0)
        sync.requestSync()
        select(created, multiple: multiple)
    }

    // MARK: - Сохранение

    private func save() {
        // Если имя набрано, но плюс не нажат, добавляем клиента сами.
        if mode != .errand, !trimmedQuery.isEmpty, mode == .client || !queryMatchesExisting {
            addTypedClient()
        }

        let target = event ?? {
            let new = PlannerEvent()
            new.createdBy = account.current.rawValue
            new.createdAt = .now
            context.insert(new)
            return new
        }()

        target.errandType = ""
        switch mode {
        case .client:
            target.title = participants.first?.name ?? ""
            target.participantIDs = participants.prefix(1).map(\.id)
        case .group:
            var custom = title.trimmingCharacters(in: .whitespaces)
            if !trimmedKindName.isEmpty { custom = trimmedKindName }
            if !custom.isEmpty {
                PlannerGroupKindStore.ensure(context, name: custom, category: groupCategory)
            }
            target.title = custom.isEmpty ? groupCategory.title : custom
            target.participantIDs = participants.map(\.id)
        case .errand:
            target.title = title.trimmingCharacters(in: .whitespaces)
            target.participantIDs = []
            if errandRegular { PlannerErrandKindStore.ensure(context, name: target.title, owner: account.current)
                if isTogether { PlannerErrandKindStore.ensureForBoth(context, name: target.title) } }
            target.errandType = errandRegular ? target.title : ""
        }
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.isAllDay = false
        target.start = start
        target.end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
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
        if category == .errand {
            target.partnerMoneyKindRaw = pMoney.rawValue
            target.partnerMoneyAmount = pMoney == .none ? 0 : max(0, pAmount ?? 0)
            target.partnerMoneyType = pMoney == .none ? "" : pType
        }
        target.markChanged()
        try? context.save()
        sync.requestSync()
        if reminder >= 0 {
            let me = account.current
            let context = context
            Task { @MainActor in
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
