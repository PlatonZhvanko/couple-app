import SwiftData
import SwiftUI

// MARK: - Модель

/// Пункт «что нужно сделать по машине»: ремонт, замена, покупка. У каждого цена и желаемая дата.
/// Когда пункт оплачен, в журнал трат машины добавляется запись (`entryID`).
@Model
final class CarRepair: SyncableModel {
    struct Payload: Codable {
        var carID: UUID
        var title: String
        var price: Double
        var desiredDate: Date?
        var desiredOdometer: Int?
        var durationMinutes: Int?
        var note: String
        var isPaid: Bool
        var paidAt: Date?
        var entryID: UUID?
        var member: String
        var createdAt: Date
    }

    static let recordKind = "car.repair"

    var syncID: UUID = UUID()
    var carID: UUID = UUID()
    var title: String = ""
    /// Ожидаемая или фактическая цена, ₽.
    var price: Double = 0
    /// Когда желательно сделать. `nil` — без срока.
    var desiredDate: Date? = nil
    /// Желаемый пробег, км. 0 — без пробега. Работает как срок: «по дате или по пробегу».
    var desiredOdometer: Int = 0
    /// Сколько занимает в планере, минут (для ремонта по дате со временем).
    var durationMinutes: Int = 60
    var note: String = ""
    var isPaid: Bool = false
    var paidAt: Date? = nil
    /// Запись в журнале трат, созданная при оплате.
    var entryID: UUID? = nil
    var member: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(carID: UUID, member: CoupleMember) {
        self.carID = carID
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(carID: carID, title: title, price: price, desiredDate: desiredDate,
                desiredOdometer: desiredOdometer > 0 ? desiredOdometer : nil,
                durationMinutes: durationMinutes, note: note,
                isPaid: isPaid, paidAt: paidAt, entryID: entryID, member: member, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        carID = payload.carID
        title = payload.title
        price = payload.price
        desiredDate = payload.desiredDate
        desiredOdometer = payload.desiredOdometer ?? 0
        durationMinutes = payload.durationMinutes ?? 60
        note = payload.note
        isPaid = payload.isPaid
        paidAt = payload.paidAt
        entryID = payload.entryID
        member = payload.member
        createdAt = payload.createdAt
    }
}

extension Array where Element == CarRepair {
    func of(_ car: CarVehicle) -> [CarRepair] { filter { $0.carID == car.syncID } }
}

// MARK: - Оплата и отмена оплаты

enum CarRepairActions {
    /// Отметить оплаченным: сумма попадает в траты машины как «Ремонт».
    @MainActor
    static func pay(_ repair: CarRepair, context: ModelContext, member: CoupleMember, odometer: Int = 0,
                    date: Date = .now, amount: Double? = nil) {
        if let amount { repair.price = amount }
        let entry = CarEntry(carID: repair.carID, category: .repair, member: member)
        entry.amount = repair.price
        entry.date = date
        entry.note = repair.title
        entry.odometer = odometer
        context.insert(entry)
        entry.markChanged()
        repair.isPaid = true
        repair.paidAt = date
        repair.entryID = entry.syncID
        repair.markChanged()
        try? context.save()
    }

    /// Снять оплату: запись в тратах удаляется.
    @MainActor
    static func unpay(_ repair: CarRepair, context: ModelContext) {
        if let id = repair.entryID {
            let all = (try? context.fetch(FetchDescriptor<CarEntry>())) ?? []
            all.first { $0.syncID == id }?.markDeleted()
        }
        repair.isPaid = false
        repair.paidAt = nil
        repair.entryID = nil
        repair.markChanged()
        try? context.save()
    }
}

// MARK: - Список

struct CarRepairsView: View {
    let car: CarVehicle

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<CarRepair> { $0.deletedAt == nil }, sort: \CarRepair.createdAt)
    private var allRepairs: [CarRepair]
    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil })
    private var allEntries: [CarEntry]
    @State private var editing: CarRepair?
    @State private var startDone = false
    @State private var adding = false

    private var todo: [CarRepair] {
        allRepairs.of(car).filter { !$0.isPaid }.sorted {
            ($0.desiredDate ?? .distantFuture) < ($1.desiredDate ?? .distantFuture)
        }
    }
    private var paid: [CarRepair] {
        allRepairs.of(car).filter(\.isPaid).sorted { ($0.paidAt ?? .distantPast) > ($1.paidAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if todo.isEmpty && paid.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "wrench.and.screwdriver",
                                       description: Text("Запишите, что нужно сделать, с ценой и желаемой датой. Коты-механики напомнят."))
            }
            if !todo.isEmpty {
                Section {
                    ForEach(todo) { repair in
                        row(repair)
                            .swipeActions(edge: .leading) {
                                if isMine(repair) {
                                    Button("Сделано", systemImage: "checkmark.circle") { pay(repair) }.tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if isMine(repair) {
                                    Button("Удалить", systemImage: "trash", role: .destructive) { remove(repair) }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("Нужно сделать")
                        Spacer()
                        Text(CarFormat.money(todo.reduce(0) { $0 + $1.price }))
                    }
                } footer: {
                    Text("Смахните вправо или откройте пункт и отметьте «Сделано»: спросим дату и стоимость, сумма попадёт в траты машины в этот день.")
                }
            }
            if !paid.isEmpty {
                Section("Сделано") {
                    ForEach(paid) { repair in
                        row(repair)
                            .swipeActions {
                                if isMine(repair) {
                                    Button("Не сделано", systemImage: "arrow.uturn.backward") {
                                        CarRepairActions.unpay(repair, context: context)
                                        sync.requestSync()
                                    }.tint(.orange)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Ремонты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Добавить", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { CarRepairFormView(car: car, repair: nil) }
        .sheet(item: $editing, onDismiss: { startDone = false }) { CarRepairFormView(car: car, repair: $0, startDone: startDone) }
    }

    /// Менять ремонт может только тот, кто его поставил.
    private func isMine(_ repair: CarRepair) -> Bool { CarCalendar.canSee(repair, account.current) }

    private func row(_ repair: CarRepair) -> some View {
        Button { editing = repair } label: {
            HStack {
                Image(systemName: repair.isPaid ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill")
                    .foregroundStyle(repair.isPaid ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repair.title.isEmpty ? "Без названия" : repair.title)
                    if !repair.isPaid, repair.desiredOdometer > 0 {
                        Text("На пробеге \(CarFormat.km(repair.desiredOdometer))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if repair.isPaid, let at = repair.paidAt {
                        Text("Сделано \(at.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let due = repair.desiredDate {
                        Text("Желательно до \(due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(due < .now ? .red : .secondary)
                    }
                }
                Spacer()
                Text(repair.price > 0 ? CarFormat.money(repair.price) : "—").foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
    }

    private func pay(_ repair: CarRepair) {
        let odo = CarMath.currentOdometer(car: car, entries: allEntries.of(car))
        CarRepairActions.pay(repair, context: context, member: CarCalendar.owner(of: repair.carID) ?? account.current, odometer: odo,
                             date: repair.desiredDate ?? .now)
        sync.requestSync()
    }

    private func remove(_ repair: CarRepair) {
        repair.markDeleted()
        try? context.save()
        sync.requestSync()
    }
}

// MARK: - Быстрый выбор

/// ТО (масло, фильтры, тормозная жидкость) тут не нужно: это одна запись «ТО».
enum CarRepairPresets {
    static let titles = [
        "ОСАГО", "КАСКО", "Техосмотр", "Смена шин", "Тормозные колодки",
        "Аккумулятор", "Развал-схождение", "Диагностика", "Мойка и химчистка",
    ]
}

// MARK: - Форма

struct CarRepairFormView: View {
    let car: CarVehicle
    let repair: CarRepair?
    var startDone = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var title: String
    @State private var priceText: String
    @State private var hasDate: Bool
    @State private var showPicker = false
    @State private var date: Date
    @State private var odometerText: String
    @State private var note: String
    @State private var duration: Int
    @State private var isDone: Bool
    @State private var doneDate: Date
    @State private var doneOdometerText: String

    /// Чужой ремонт (поставил другой человек): только просмотр.
    private var readOnly: Bool {
        guard let repair else { return false }
        return !CarCalendar.canSee(repair, account.current)
    }

    init(car: CarVehicle, repair: CarRepair?, startDone: Bool = false) {
        self.car = car
        self.repair = repair
        self.startDone = startDone
        _duration = State(initialValue: repair?.durationMinutes ?? 60)
        _isDone = State(initialValue: repair?.isPaid ?? startDone)
        _doneDate = State(initialValue: repair?.paidAt ?? .now)
        _doneOdometerText = State(initialValue: "")
        _title = State(initialValue: repair?.title ?? "")
        _priceText = State(initialValue: (repair?.price ?? 0) > 0 ? CarNumber.text(Int(repair?.price ?? 0)) : "")
        _hasDate = State(initialValue: repair?.desiredDate != nil)
        _odometerText = State(initialValue: (repair?.desiredOdometer ?? 0) > 0 ? String(repair?.desiredOdometer ?? 0) : "")
        _date = State(initialValue: repair?.desiredDate ?? Self.defaultDate())
        _note = State(initialValue: repair?.note ?? "")
    }

    /// По умолчанию: через две недели в 10:00.
    private static func defaultDate() -> Date {
        let day = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(car.displayName, systemImage: "car.fill")
                } header: {
                    Text("Машина")
                }
                if repair == nil {
                    Section("Быстрый выбор") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(CarRepairPresets.titles, id: \.self) { preset in
                                    Button(preset) { title = preset }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("Что сделать, например «Замена колодок»", text: $title)
                    LabeledContent("Цена, ₽") {
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Срок можно задать датой, пробегом или обоими сразу. Напомним, что придёт первым.")
                }
                Section("Когда желательно") {
                    Toggle("По дате", isOn: $hasDate)
                    if hasDate {
                        if repair == nil {
                            DatePicker("Дата и время", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            Button("Выбрать в календаре", systemImage: "calendar") { showPicker = true }
                        } else {
                            // Дату существующего ремонта меняют касанием по журналу: кнопка «Перенести» в Планере.
                            LabeledContent("Дата и время", value: "\(PlannerCalendar.dayTitle(date)), \(PlannerCalendar.time(date))")
                            Text("Чтобы перенести, открой ремонт в Планере и нажми «Перенести».")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Stepper("Длительность: \(duration) мин", value: $duration, in: 30...600, step: 30)
                    }
                    LabeledContent("По пробегу, км") {
                        TextField("необязательно", text: $odometerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Заметка") { TextField("Где делать, какие запчасти", text: $note, axis: .vertical) }
                if repair != nil {
                    Section {
                        Toggle("Сделано", isOn: $isDone)
                    } footer: {
                        Text("Дата берётся из записи, сумма из цены ремонта. Сделали в другой день: сначала перенесите запись, потом поставьте галочку. Сумма попадёт в траты и аналитику.")
                    }
                }
            }
            .disabled(readOnly)
            .sheet(isPresented: $showPicker) { CarDateTimePickerSheet(date: $date) }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(repair == nil ? "Новый пункт" : (readOnly ? "Ремонт (просмотр)" : "Ремонт"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(readOnly ? "Закрыть" : "Отмена") { dismiss() } }
                if !readOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") { save() }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        let target = repair ?? CarRepair(carID: car.syncID, member: account.current)
        target.title = title
        target.price = CarNumber.double(priceText) ?? 0
        target.desiredDate = hasDate ? date : nil
        target.durationMinutes = duration
        target.desiredOdometer = CarNumber.int(odometerText) ?? 0
        target.note = note
        if repair == nil { context.insert(target) }
        target.markChanged()
        try? context.save()

        let entries = ((try? context.fetch(FetchDescriptor<CarEntry>())) ?? [])
            .filter { $0.carID == car.syncID && $0.deletedAt == nil }
        if isDone && !target.isPaid {
            let odo = CarMath.currentOdometer(car: car, entries: entries)
            CarRepairActions.pay(target, context: context, member: CarCalendar.owner(of: target.carID) ?? account.current, odometer: odo,
                                 date: target.desiredDate ?? .now, amount: target.price)
        } else if isDone, let id = target.entryID, let entry = entries.first(where: { $0.syncID == id }) {
            // Уже было сделано: обновляем дату и сумму в тратах.
            let when = target.desiredDate ?? target.paidAt ?? .now
            entry.date = when
            entry.amount = target.price
            entry.markChanged()
            target.paidAt = when
            target.markChanged()
            try? context.save()
        } else if !isDone && target.isPaid {
            CarRepairActions.unpay(target, context: context)
        }
        sync.requestSync()
        dismiss()
    }
}

// MARK: - ТО и пробег

/// Когда и на каком пробеге делалось ТО, сколько ехали с тех пор.
struct CarServiceHistoryView: View {
    let car: CarVehicle

    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil }, sort: \CarEntry.date, order: .reverse)
    private var allEntries: [CarEntry]
    @State private var sheet: CarSheet?
    @State private var showOdometer = false
    @State private var odometerText = ""
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    private var entries: [CarEntry] { allEntries.of(car) }
    private var services: [CarEntry] { entries.filter { $0.category == .service } }
    private var odometer: Int { CarMath.currentOdometer(car: car, entries: entries) }

    var body: some View {
        List {
            Section {
                LabeledContent("Пробег сейчас", value: odometer > 0 ? CarFormat.km(odometer) : "—")
                if let last = services.first(where: { $0.odometer > 0 }) {
                    LabeledContent("Последнее ТО на", value: CarFormat.km(last.odometer))
                    if odometer > last.odometer {
                        LabeledContent("С тех пор проехали", value: CarFormat.km(odometer - last.odometer))
                    }
                }
            }
            Section {
                Button("Записать ТО", systemImage: "wrench.and.screwdriver.fill") {
                    sheet = .entry(car: car, entry: nil, category: .service)
                }
                Button("Записать пробег", systemImage: "gauge.with.needle") {
                    odometerText = ""
                    showOdometer = true
                }
            }
            Section("История ТО") {
                if services.isEmpty {
                    Text("ТО ещё не записывали. Указывайте пробег, на котором делали.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(services) { entry in
                    Button { sheet = .entry(car: car, entry: entry, category: .service) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date.formatted(date: .long, time: .omitted))
                                Text(entry.odometer > 0 ? "на \(CarFormat.km(entry.odometer))" : "пробег не указан")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(CarFormat.money(entry.amount)).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationTitle("ТО и пробег")
        .alert("Пробег сейчас, км", isPresented: $showOdometer) {
            TextField("Например 185000", text: $odometerText).keyboardType(.numberPad)
            Button("Сохранить") { saveOdometer() }
            Button("Отмена", role: .cancel) {}
        } message: {
            if let text = CarOdometerAction.lowerWarning(text: odometerText, current: odometer) { Text(text) }
        }
        .sheet(item: $sheet) { CarSheetView(sheet: $0, currentOdometer: odometer) }
    }
}

extension CarServiceHistoryView {
    fileprivate func saveOdometer() {
        guard let km = CarNumber.int(odometerText), km > 0 else { return }
        let entry = CarEntry(carID: car.syncID, category: .other, member: account.current)
        entry.odometer = km
        entry.note = "Запись пробега"
        context.insert(entry)
        entry.markChanged()
        try? context.save()
        sync.requestSync()
    }
}

// MARK: - Сенсорный выбор даты и времени

/// Весь календарь одним касанием и время колёсиком, кнопка «Поставить».
struct CarDateTimePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    DatePicker("День", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    DatePicker("Время", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(height: 140)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Когда делать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Поставить") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
