import SwiftData
import SwiftUI

// MARK: - Модели

/// «Что сделать по здоровью»: прививка, кастрация, визит к врачу и т.п.
/// Срок: по дате (появляется в планере) или по возрасту питомца. Общие для обоих.
@Model
final class PetsTask: SyncableModel {
    struct Payload: Codable {
        var petID: UUID
        var title: String
        var price: Double
        var desiredDate: Date?
        var desiredAgeMonths: Int?
        var durationMinutes: Int?
        var note: String
        var isDone: Bool
        var doneAt: Date?
        var entryID: UUID?
        var member: String
        var createdAt: Date
    }

    static let recordKind = "pets.task"

    var syncID: UUID = UUID()
    var petID: UUID = UUID()
    var title: String = ""
    var price: Double = 0
    var desiredDate: Date? = nil
    /// Возраст в месяцах, к которому надо сделать. 0 — без возраста.
    var desiredAgeMonths: Int = 0
    var durationMinutes: Int = 60
    var note: String = ""
    var isDone: Bool = false
    var doneAt: Date? = nil
    var entryID: UUID? = nil
    var member: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(petID: UUID, member: CoupleMember) {
        self.petID = petID
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(petID: petID, title: title, price: price, desiredDate: desiredDate,
                desiredAgeMonths: desiredAgeMonths > 0 ? desiredAgeMonths : nil,
                durationMinutes: durationMinutes, note: note, isDone: isDone, doneAt: doneAt,
                entryID: entryID, member: member, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        petID = payload.petID
        title = payload.title
        price = payload.price
        desiredDate = payload.desiredDate
        desiredAgeMonths = payload.desiredAgeMonths ?? 0
        durationMinutes = payload.durationMinutes ?? 60
        note = payload.note
        isDone = payload.isDone
        doneAt = payload.doneAt
        entryID = payload.entryID
        member = payload.member
        createdAt = payload.createdAt
    }
}

/// Трата на питомца.
@Model
final class PetsEntry: SyncableModel {
    struct Payload: Codable {
        var petID: UUID
        var category: String
        var date: Date
        var amount: Double
        var note: String
        var member: String
        var createdAt: Date
    }

    static let recordKind = "pets.entry"

    var syncID: UUID = UUID()
    var petID: UUID = UUID()
    var category: String = "Другое"
    var date: Date = Date.now
    var amount: Double = 0
    var note: String = ""
    var member: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(petID: UUID, member: CoupleMember) {
        self.petID = petID
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(petID: petID, category: category, date: date, amount: amount, note: note,
                member: member, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        petID = payload.petID
        category = payload.category
        date = payload.date
        amount = payload.amount
        note = payload.note
        member = payload.member
        createdAt = payload.createdAt
    }
}

// MARK: - Возраст

enum PetsAge {
    /// Полных месяцев от дня рождения. `nil`, если дата не указана.
    static func months(_ pet: PetsPet, at date: Date = .now) -> Int? {
        guard let birthday = pet.birthday else { return nil }
        return Calendar.current.dateComponents([.month], from: birthday, to: date).month
    }

    /// «2 г. 3 мес.», «5 мес.», «малыш».
    static func text(months: Int) -> String {
        let years = months / 12
        let rest = months % 12
        if years == 0 { return rest == 0 ? "малыш" : "\(rest) мес." }
        return rest == 0 ? "\(years) г." : "\(years) г. \(rest) мес."
    }

    static func text(_ pet: PetsPet) -> String? {
        months(pet).map { text(months: max(0, $0)) }
    }

    /// Дата, когда питомцу исполнится `months` месяцев.
    static func date(for months: Int, pet: PetsPet) -> Date? {
        guard let birthday = pet.birthday else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: birthday)
    }

    /// Ближайший день рождения.
    static func nextBirthday(_ pet: PetsPet, from now: Date = .now) -> Date? {
        guard let birthday = pet.birthday else { return nil }
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: birthday)
        let today = cal.startOfDay(for: now)
        return cal.nextDate(after: today.addingTimeInterval(-1), matching: comps, matchingPolicy: .nextTime)
    }
}

// MARK: - Действия

enum PetsTaskActions {
    /// Отметить сделанным: сумма попадает в траты питомца.
    @MainActor
    static func done(_ task: PetsTask, context: ModelContext, date: Date = .now, amount: Double? = nil,
                     member: CoupleMember) {
        if let amount { task.price = amount }
        let entry = PetsEntry(petID: task.petID, member: member)
        entry.category = "Здоровье"
        entry.amount = task.price
        entry.date = date
        entry.note = task.title
        context.insert(entry)
        entry.markChanged()
        task.isDone = true
        task.doneAt = date
        task.entryID = entry.syncID
        task.markChanged()
        try? context.save()
    }

    /// Снять отметку: трата удаляется.
    @MainActor
    static func undone(_ task: PetsTask, context: ModelContext) {
        if let id = task.entryID {
            let all = (try? context.fetch(FetchDescriptor<PetsEntry>())) ?? []
            all.first { $0.syncID == id }?.markDeleted()
        }
        task.isDone = false
        task.doneAt = nil
        task.entryID = nil
        task.markChanged()
        try? context.save()
    }

    static let presets = [
        "Прививка", "Кастрация", "Стерилизация", "Обработка от паразитов",
        "Визит к врачу", "Анализы", "Стрижка когтей", "Груминг",
    ]
}

// MARK: - Список дел по здоровью

struct PetsTasksView: View {
    let pet: PetsPet

    @Query(filter: #Predicate<PetsTask> { $0.deletedAt == nil }, sort: \PetsTask.createdAt)
    private var allTasks: [PetsTask]
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @State private var editing: PetsTask?
    @State private var adding = false

    private var tasks: [PetsTask] { allTasks.filter { $0.petID == pet.syncID } }

    var body: some View {
        let todo = tasks.filter { !$0.isDone }
        let done = tasks.filter(\.isDone)
        List {
            if tasks.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "cross.case",
                                       description: Text("Запишите, что сделать по здоровью: прививка, визит к врачу. Коты напомнят."))
            }
            if !todo.isEmpty {
                Section {
                    ForEach(todo) { task in
                        row(task)
                            .swipeActions(edge: .leading) {
                                Button("Сделано", systemImage: "checkmark.circle") {
                                    PetsTaskActions.done(task, context: context, date: task.desiredDate ?? .now,
                                                         member: account.current)
                                    sync.requestSync()
                                }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Удалить", systemImage: "trash", role: .destructive) { remove(task) }
                            }
                    }
                } header: {
                    HStack {
                        Text("Нужно сделать")
                        Spacer()
                        Text(CarFormat.money(todo.reduce(0) { $0 + $1.price }))
                    }
                } footer: {
                    Text("Смахните вправо: «Сделано» запишет сумму в траты питомца в день по расписанию.")
                }
            }
            if !done.isEmpty {
                Section("Сделано") {
                    ForEach(done) { task in
                        row(task)
                            .swipeActions {
                                Button("Не сделано", systemImage: "arrow.uturn.backward") {
                                    PetsTaskActions.undone(task, context: context)
                                    sync.requestSync()
                                }.tint(.orange)
                            }
                    }
                }
            }
        }
        .navigationTitle("Здоровье и дела")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Добавить", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { PetsTaskFormView(pet: pet, task: nil) }
        .sheet(item: $editing) { PetsTaskFormView(pet: pet, task: $0) }
    }

    private func row(_ task: PetsTask) -> some View {
        Button { editing = task } label: {
            HStack {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "pawprint.fill")
                    .foregroundStyle(task.isDone ? .green : .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "Без названия" : task.title)
                    if !task.isDone, task.desiredAgeMonths > 0 {
                        Text("В возрасте \(PetsAge.text(months: task.desiredAgeMonths))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if task.isDone, let at = task.doneAt {
                        Text("Сделано \(at.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let due = task.desiredDate {
                        Text("\(due.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(due < .now ? .red : .secondary)
                    }
                }
                Spacer()
                Text(task.price > 0 ? CarFormat.money(task.price) : "—").foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
    }

    private func remove(_ task: PetsTask) {
        if task.isDone { PetsTaskActions.undone(task, context: context) }
        task.markDeleted()
        try? context.save()
        sync.requestSync()
    }
}

// MARK: - Форма дела

struct PetsTaskFormView: View {
    let pet: PetsPet
    let task: PetsTask?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var title: String
    @State private var priceText: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var duration: Int
    @State private var hasAge: Bool
    @State private var ageYears: Int
    @State private var ageMonths: Int
    @State private var note: String
    @State private var isDone: Bool
    @State private var showPicker = false

    init(pet: PetsPet, task: PetsTask?) {
        self.pet = pet
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _priceText = State(initialValue: (task?.price ?? 0) > 0 ? CarNumber.text(Int(task?.price ?? 0)) : "")
        _hasDate = State(initialValue: task?.desiredDate != nil)
        _date = State(initialValue: task?.desiredDate ?? Self.defaultDate())
        _duration = State(initialValue: task?.durationMinutes ?? 60)
        _hasAge = State(initialValue: (task?.desiredAgeMonths ?? 0) > 0)
        _ageYears = State(initialValue: (task?.desiredAgeMonths ?? 0) / 12)
        _ageMonths = State(initialValue: (task?.desiredAgeMonths ?? 0) % 12)
        _note = State(initialValue: task?.note ?? "")
        _isDone = State(initialValue: task?.isDone ?? false)
    }

    private static func defaultDate() -> Date {
        let day = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
    }

    private var suggestions: [String] {
        let text = title.trimmingCharacters(in: .whitespaces).lowercased()
        let all = PetsTaskActions.presets
        if text.isEmpty { return all }
        return all.filter { $0.lowercased().contains(text) && $0.lowercased() != text }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(pet.displayName, systemImage: "pawprint.fill")
                } header: { Text("Питомец") }
                Section("Что сделать") {
                    TextField("Название, например «Прививка»", text: $title)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { preset in
                                    Button(preset) { title = preset }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    LabeledContent("Цена, ₽") {
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Toggle("По дате", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Дата и время", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        Button("Выбрать в календаре", systemImage: "calendar") { showPicker = true }
                        Stepper("Длительность: \(duration) мин", value: $duration, in: 30...600, step: 30)
                    }
                    Toggle("По возрасту", isOn: $hasAge)
                    if hasAge {
                        Stepper("Лет: \(ageYears)", value: $ageYears, in: 0...30)
                        Stepper("Месяцев: \(ageMonths)", value: $ageMonths, in: 0...11)
                        if pet.birthday == nil {
                            Text("Укажите день рождения питомца, тогда напомним в нужный месяц.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Когда")
                } footer: {
                    Text("По дате запись появится в планере у обоих (розовая, с лапкой). По возрасту напомним, когда питомцу исполнится нужный возраст.")
                }
                Section("Заметка") { TextField("Где, какая вакцина", text: $note, axis: .vertical) }
                if task != nil {
                    Section {
                        Toggle("Сделано", isOn: $isDone)
                    } footer: {
                        Text("Дата берётся из записи, сумма из цены. Сумма попадёт в траты и статистику.")
                    }
                }
            }
            .sheet(isPresented: $showPicker) { CarDateTimePickerSheet(date: $date) }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(task == nil ? "Новое дело" : "Дело по здоровью")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let target = task ?? PetsTask(petID: pet.syncID, member: account.current)
        target.title = title
        target.price = CarNumber.double(priceText) ?? 0
        target.desiredDate = hasDate ? date : nil
        target.durationMinutes = duration
        target.desiredAgeMonths = hasAge ? ageYears * 12 + ageMonths : 0
        target.note = note
        if task == nil { context.insert(target) }
        target.markChanged()
        try? context.save()

        if isDone && !target.isDone {
            PetsTaskActions.done(target, context: context, date: target.desiredDate ?? .now,
                                 amount: target.price, member: account.current)
        } else if isDone, let id = target.entryID {
            let entries = (try? context.fetch(FetchDescriptor<PetsEntry>())) ?? []
            if let entry = entries.first(where: { $0.syncID == id }) {
                let when = target.desiredDate ?? target.doneAt ?? .now
                entry.date = when
                entry.amount = target.price
                entry.markChanged()
                target.doneAt = when
                target.markChanged()
                try? context.save()
            }
        } else if !isDone && target.isDone {
            PetsTaskActions.undone(target, context: context)
        }
        sync.requestSync()
        dismiss()
    }
}

// MARK: - Траты

struct PetsEntryFormView: View {
    let pet: PetsPet
    let entry: PetsEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<PetsEntry> { $0.deletedAt == nil }) private var allEntries: [PetsEntry]

    @State private var amountText: String
    @State private var category: String
    @State private var date: Date
    @State private var note: String

    private static let basic = ["Корм", "Наполнитель", "Ветеринар", "Здоровье", "Игрушки", "Груминг", "Другое"]

    init(pet: PetsPet, entry: PetsEntry?) {
        self.pet = pet
        self.entry = entry
        _amountText = State(initialValue: (entry?.amount ?? 0) > 0 ? CarNumber.text(Int(entry?.amount ?? 0)) : "")
        _category = State(initialValue: entry?.category ?? "")
        _date = State(initialValue: entry?.date ?? .now)
        _note = State(initialValue: entry?.note ?? "")
    }

    private var suggestions: [String] {
        let custom = Set(allEntries.map(\.category)).subtracting(Self.basic).sorted()
        let all = Self.basic + custom
        let text = category.trimmingCharacters(in: .whitespaces).lowercased()
        if text.isEmpty { return Array(all.prefix(7)) }
        return all.filter { $0.lowercased().contains(text) && $0.lowercased() != text }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(pet.displayName, systemImage: "pawprint.fill")
                } header: { Text("Питомец") }
                Section {
                    LabeledContent("Сумма, ₽") {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                }
                Section {
                    TextField("Категория: найти или создать новую", text: $category)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { item in
                                    Button(item) { category = item }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Категория")
                } footer: {
                    Text("Нет нужной? Просто напишите своё название, оно сохранится как новая категория.")
                }
                Section("Заметка") { TextField("Необязательно", text: $note, axis: .vertical) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(entry == nil ? "Новая трата" : "Трата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled((CarNumber.double(amountText) ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        let target = entry ?? PetsEntry(petID: pet.syncID, member: account.current)
        target.amount = CarNumber.double(amountText) ?? 0
        target.date = date
        let name = category.trimmingCharacters(in: .whitespaces)
        target.category = name.isEmpty ? "Другое" : name
        target.note = note
        if entry == nil { context.insert(target) }
        target.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}

/// Траты питомца: за всё время, месяц или выбранный период, по категориям.
struct PetsSpendingView: View {
    let pet: PetsPet

    private enum Period: String, CaseIterable, Identifiable {
        case all = "Всё время", month = "Месяц", custom = "Период"
        var id: String { rawValue }
    }

    private struct SpendGroup: Identifiable {
        let name: String
        let items: [PetsEntry]
        let sum: Double
        var id: String { name }
    }

    @Query(filter: #Predicate<PetsEntry> { $0.deletedAt == nil }, sort: \PetsEntry.date, order: .reverse)
    private var allEntries: [PetsEntry]
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @State private var period: Period = .all
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now
    @State private var adding = false
    @State private var editing: PetsEntry?

    private func inPeriod(_ date: Date) -> Bool {
        switch period {
        case .all: return true
        case .month:
            let start = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
            return date >= start
        case .custom:
            let start = Calendar.current.startOfDay(for: from)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
            return date >= start && date < end
        }
    }

    var body: some View {
        let entries = allEntries.filter { $0.petID == pet.syncID && inPeriod($0.date) }
        let total = entries.reduce(0) { $0 + $1.amount }
        let groups: [SpendGroup] = Dictionary(grouping: entries, by: \.category)
            .map { SpendGroup(name: $0.key, items: $0.value, sum: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.sum > $1.sum }
        List {
            Section {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if period == .custom {
                    DatePicker("С", selection: $from, displayedComponents: .date)
                    DatePicker("По", selection: $to, displayedComponents: .date)
                }
                LabeledContent("Итого") { Text(CarFormat.money(total)).bold() }
            }
            if entries.isEmpty {
                Section { Text("За период трат нет").foregroundStyle(.secondary) }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in
                        Button { editing = item } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.note.isEmpty ? item.category : item.note)
                                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(CarFormat.money(item.amount))
                            }
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) { remove(item) }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text(CarFormat.money(group.sum))
                    }
                }
            }
        }
        .navigationTitle("Траты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Добавить", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { PetsEntryFormView(pet: pet, entry: nil) }
        .sheet(item: $editing) { PetsEntryFormView(pet: pet, entry: $0) }
    }

    private func remove(_ item: PetsEntry) {
        item.markDeleted()
        try? context.save()
        sync.requestSync()
    }
}
