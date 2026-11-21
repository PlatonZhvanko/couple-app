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
                desiredOdometer: desiredOdometer > 0 ? desiredOdometer : nil, note: note,
                isPaid: isPaid, paidAt: paidAt, entryID: entryID, member: member, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        carID = payload.carID
        title = payload.title
        price = payload.price
        desiredDate = payload.desiredDate
        desiredOdometer = payload.desiredOdometer ?? 0
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
    static func pay(_ repair: CarRepair, context: ModelContext, member: CoupleMember, odometer: Int = 0) {
        let entry = CarEntry(carID: repair.carID, category: .repair, member: member)
        entry.amount = repair.price
        entry.date = .now
        entry.note = repair.title
        entry.odometer = odometer
        context.insert(entry)
        entry.markChanged()
        repair.isPaid = true
        repair.paidAt = .now
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
                                Button("Оплачено", systemImage: "checkmark.circle") {
                                    pay(repair)
                                }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Удалить", systemImage: "trash", role: .destructive) { remove(repair) }
                            }
                    }
                } header: {
                    HStack {
                        Text("Нужно сделать")
                        Spacer()
                        Text(CarFormat.money(todo.reduce(0) { $0 + $1.price }))
                    }
                } footer: {
                    Text("Смахните вправо, чтобы отметить оплату: сумма попадёт в траты на машину.")
                }
            }
            if !paid.isEmpty {
                Section("Оплачено") {
                    ForEach(paid) { repair in
                        row(repair)
                            .swipeActions {
                                Button("Вернуть", systemImage: "arrow.uturn.backward") {
                                    CarRepairActions.unpay(repair, context: context)
                                    sync.requestSync()
                                }.tint(.orange)
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
        .sheet(item: $editing) { CarRepairFormView(car: car, repair: $0) }
    }

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
                        Text("Оплачено \(at.formatted(date: .abbreviated, time: .omitted))")
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
        CarRepairActions.pay(repair, context: context, member: account.current, odometer: odo)
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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var title: String
    @State private var priceText: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var odometerText: String
    @State private var note: String

    init(car: CarVehicle, repair: CarRepair?) {
        self.car = car
        self.repair = repair
        _title = State(initialValue: repair?.title ?? "")
        _priceText = State(initialValue: (repair?.price ?? 0) > 0 ? CarNumber.text(Int(repair?.price ?? 0)) : "")
        _hasDate = State(initialValue: repair?.desiredDate != nil)
        _odometerText = State(initialValue: (repair?.desiredOdometer ?? 0) > 0 ? String(repair?.desiredOdometer ?? 0) : "")
        _date = State(initialValue: repair?.desiredDate ?? Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now)
        _note = State(initialValue: repair?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
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
                        DatePicker("Дата", selection: $date, displayedComponents: .date)
                    }
                    LabeledContent("По пробегу, км") {
                        TextField("необязательно", text: $odometerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Заметка") { TextField("Где делать, какие запчасти", text: $note, axis: .vertical) }
                if let repair, repair.isPaid {
                    Section { Text("Оплачено, сумма уже в тратах на машину.") .foregroundStyle(.secondary) }
                } else if repair != nil {
                    Section {
                        Button("Отметить оплаченным") { save(pay: true) }
                    } footer: {
                        Text("Сумма попадёт в список трат на машину.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(repair == nil ? "Новый пункт" : "Ремонт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save(pay: false) }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save(pay: Bool) {
        let target = repair ?? CarRepair(carID: car.syncID, member: account.current)
        target.title = title
        target.price = CarNumber.double(priceText) ?? 0
        target.desiredDate = hasDate ? date : nil
        target.desiredOdometer = CarNumber.int(odometerText) ?? 0
        target.note = note
        if repair == nil { context.insert(target) }
        target.markChanged()
        try? context.save()
        if pay {
            let entries = (try? context.fetch(FetchDescriptor<CarEntry>())) ?? []
            let odo = CarMath.currentOdometer(car: car, entries: entries.filter { $0.carID == car.syncID && $0.deletedAt == nil })
            CarRepairActions.pay(target, context: context, member: account.current, odometer: odo)
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
