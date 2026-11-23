import SwiftData
import SwiftUI

/// Продажа абонемента одним окном: вид (поиск и «+»), группы со своим списанием, сумма, срок, клиент.
struct PlannerSubscriptionSaleSheet: View {
    let month: Date

    init(month: Date, client: PlannerClientDirectory.Entry? = nil) {
        self.month = month
        _client = State(initialValue: client)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PlannerSubscriptionType> { $0.deletedAt == nil }, sort: \PlannerSubscriptionType.name)
    private var types: [PlannerSubscriptionType]
    @Query(filter: #Predicate<PlannerGroupKind> { $0.deletedAt == nil }, sort: \PlannerGroupKind.name)
    private var groupKinds: [PlannerGroupKind]

    /// Выбранный вид храним по номеру, а не самой записью: если запись заменит синхронизация, окно не упадёт.
    @State private var selectedTypeID: UUID?
    /// Галочка «для конкретных групп»: без неё абонемент общий, на все группы.
    @State private var forGroups = false
    /// Цены списания по группам, пока вводятся: в вид абонемента попадают при продаже или закрытии окна.
    @State private var chargeDrafts: [String: String] = [:]
    @State private var amountText = ""
    @State private var validText = "30"
    /// Срок: на N дней или до выбранного дня включительно.
    @State private var untilMode = false
    @State private var untilDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var chargeText = "500"
    @State private var typeQuery = ""
    @State private var groupQuery = ""
    @State private var client: PlannerClientDirectory.Entry?

    private var trimmedTypeQuery: String { typeQuery.trimmingCharacters(in: .whitespaces) }
    private var trimmedGroupQuery: String { groupQuery.trimmingCharacters(in: .whitespaces) }
    private var selectedType: PlannerSubscriptionType? {
        guard let selectedTypeID else { return nil }
        return types.first { $0.syncID == selectedTypeID }
    }

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    /// Без запроса показываем только два готовых абонемента, с запросом настоящий поиск по подстроке.
    private var typeMatches: [PlannerSubscriptionType] {
        guard !trimmedTypeQuery.isEmpty else { return Array(types.prefix(2)) }
        return Array(types.filter { $0.name.localizedCaseInsensitiveContains(trimmedTypeQuery) }.prefix(6))
    }

    private var canCreateType: Bool {
        !trimmedTypeQuery.isEmpty
            && !types.contains { $0.name.caseInsensitiveCompare(trimmedTypeQuery) == .orderedSame }
    }

    private var groupMatches: [PlannerGroupKind] {
        guard let type = selectedType else { return [] }
        let taken = Set(type.groupNames.map { $0.lowercased() })
        let pool = groupKinds.filter { !taken.contains($0.name.lowercased()) }
        guard !trimmedGroupQuery.isEmpty else { return Array(pool.prefix(2)) }
        return Array(pool.filter { $0.name.localizedCaseInsensitiveContains(trimmedGroupQuery) }.prefix(6))
    }

    private var canCreateGroup: Bool {
        !trimmedGroupQuery.isEmpty
            && !groupKinds.contains { $0.name.caseInsensitiveCompare(trimmedGroupQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                if let type = selectedType {
                    Section {
                        Toggle("Абонемент для конкретных групп", isOn: $forGroups)
                            .onChange(of: forGroups) { _, on in
                                // Выключили: у вида не остаётся групп, он общий.
                                if !on, !type.groupNames.isEmpty { clearGroups(type) }
                            }
                    }
                    if forGroups {
                        groupsSection(type)
                    } else {
                        Section {
                            HStack {
                                Text("Списание за занятие")
                                Spacer()
                                TextField("500", text: $chargeText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                Text("₽").foregroundStyle(.secondary)
                            }
                        } footer: {
                            Text("Абонемент действует на все группы и школы.")
                        }
                    }
                }
                termSection
                PlannerSaleClientSection(client: $client)
                Section {
                    EmptyView()
                } footer: {
                    Text("Месяц: \(PlannerCalendar.monthTitle(month)). С абонемента сами списываются групповые тренировки, на которые он действует.")
                }
            }
            .navigationTitle("Продать абонемент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Продать", action: save).disabled(client == nil || amount == nil)
                }
            }
            .onDisappear {
                commitCharges()
                sync.requestSync()
            }
        }
        .presentationDetents([.large])
        .environment(\.locale, PlannerCalendar.locale)
    }

    // MARK: Вид абонемента

    private var typeSection: some View {
        Section("📜 Абонемент") {
            if let type = selectedType {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.name).font(.headline)
                        Text(PlannerPricing.format(type.price)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        commitCharges()
                        selectedTypeID = nil
                        forGroups = false
                        chargeDrafts = [:]
                        amountText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                TextField("Найти абонемент", text: $typeQuery)
                    .autocorrectionDisabled()
                if canCreateType {
                    Button(action: createType) {
                        Label("Создать «\(trimmedTypeQuery)»", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                ForEach(typeMatches) { type in
                    Button { choose(type) } label: {
                        HStack {
                            Text(type.name).foregroundStyle(Color.primary)
                            Spacer()
                            Text(PlannerPricing.format(type.price)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                if !trimmedTypeQuery.isEmpty && typeMatches.isEmpty {
                    Text("Такого абонемента нет. Нажми +, чтобы создать.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func choose(_ type: PlannerSubscriptionType) {
        selectedTypeID = type.syncID
        forGroups = !type.groupNames.isEmpty
        chargeDrafts = [:]
        typeQuery = ""
        amountText = "\(Int(type.price.rounded()))"
        validText = "\(type.validDays)"
        chargeText = "\(Int(type.charge.rounded()))"
    }

    private func createType() {
        // Вид с таким названием мог быть удалён раньше: возвращаем его, а не заводим второй с тем же номером.
        let id = PlannerSubscriptionType.makeID(name: trimmedTypeQuery)
        let existing = (try? context.fetch(FetchDescriptor<PlannerSubscriptionType>(predicate: #Predicate { $0.syncID == id })))?.first
        let item: PlannerSubscriptionType
        if let existing {
            item = existing
            item.deletedAt = nil
        } else {
            item = PlannerSubscriptionType(name: trimmedTypeQuery, price: amount ?? 0)
            context.insert(item)
        }
        item.markChanged()
        try? context.save()
        sync.requestSync()
        choose(item)
        if let amount { amountText = "\(Int(amount.rounded()))" }
    }

    // MARK: Группы и списание

    private func groupsSection(_ type: PlannerSubscriptionType) -> some View {
        Section {
            ForEach(type.groupNames, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    TextField("500", text: draftBinding(type, name))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("₽").foregroundStyle(.secondary)
                    Button { removeGroup(type, name) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            TextField("Добавить группу или школу", text: $groupQuery)
                .autocorrectionDisabled()
            if canCreateGroup {
                Button { createGroup(type) } label: {
                    Label("Создать «\(trimmedGroupQuery)»", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            ForEach(groupMatches) { kind in
                Button { addGroup(type, kind.name) } label: {
                    Label(kind.name, systemImage: "plus")
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("👥 Для каких групп")
        } footer: {
            Text(type.groupNames.isEmpty
                 ? "Найди группу и добавь её. Рядом появится цена списания за одно занятие этой группы. Можно добавить несколько групп, у каждой своя цена. Пока групп нет, абонемент действует на все."
                 : "Справа цена списания за одно занятие этой группы. Будущие занятия считаются по ней.")
        }
    }

    private func draftBinding(_ type: PlannerSubscriptionType, _ name: String) -> Binding<String> {
        let key = name.lowercased()
        return Binding(
            get: { chargeDrafts[key] ?? "\(Int(type.charge(forGroup: name).rounded()))" },
            set: { chargeDrafts[key] = $0 }
        )
    }

    /// Записывает введённые цены списания в вид абонемента (один раз, а не на каждую цифру).
    private func commitCharges() {
        guard let type = selectedType, !chargeDrafts.isEmpty else { return }
        var map = type.groupCharges
        for (key, text) in chargeDrafts {
            if let value = Double(text) { map[key] = max(0, value) }
        }
        type.groupCharges = map
        type.markChanged()
        chargeDrafts = [:]
        try? context.save()
    }

    private func addGroup(_ type: PlannerSubscriptionType, _ name: String) {
        commitCharges()
        guard !type.groupNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        // Первое добавленное название: новая цена списания по умолчанию как в общем поле.
        var map = type.groupCharges
        map[name.lowercased()] = Double(chargeText) ?? type.charge
        type.groupNames = type.groupNames + [name]
        type.groupCharges = map
        type.markChanged()
        try? context.save()
        sync.requestSync()
        groupQuery = ""
    }

    private func clearGroups(_ type: PlannerSubscriptionType) {
        type.groupNames = []
        type.groupCharges = [:]
        chargeDrafts = [:]
        type.markChanged()
        try? context.save()
        sync.requestSync()
    }

    private func removeGroup(_ type: PlannerSubscriptionType, _ name: String) {
        chargeDrafts.removeValue(forKey: name.lowercased())
        type.groupNames = type.groupNames.filter { $0 != name }
        var map = type.groupCharges
        map.removeValue(forKey: name.lowercased())
        type.groupCharges = map
        type.markChanged()
        try? context.save()
        sync.requestSync()
    }

    private func createGroup(_ type: PlannerSubscriptionType) {
        let kind = PlannerGroupKindStore.ensure(context, name: trimmedGroupQuery, category: .group)
        addGroup(type, kind.name)
    }

    // MARK: Сумма и срок

    private var termSection: some View {
        Section("💰 Сумма и срок") {
            HStack {
                Text("Сумма")
                Spacer()
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("₽").foregroundStyle(.secondary)
            }
            Picker("Срок действия", selection: $untilMode) {
                Text("На N дней").tag(false)
                Text("До даты").tag(true)
            }
            .pickerStyle(.segmented)
            if untilMode {
                DatePicker("Включительно по", selection: $untilDate, displayedComponents: [.date])
            } else {
                HStack {
                    Text("Дней")
                    Spacer()
                    TextField("30", text: $validText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("дн.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
        guard let client, let amount else { return }
        commitCharges()
        PlannerPaymentStore.saveSubscription(
            context, clientID: client.id, month: month, amount: max(0, amount),
            kindName: selectedType?.name, validDays: untilMode ? nil : (Int(validText) ?? 30),
            expiresOn: untilMode ? untilDate : nil,
            charge: Double(chargeText)
        )
        sync.requestSync()
        dismiss()
    }
}

/// Выбор клиента: свой экран со своим поиском, чтобы набор текста в других полях не пересчитывал список.
private struct PlannerSaleClientSection: View {
    @Binding var client: PlannerClientDirectory.Entry?
    @Environment(\.modelContext) private var context

    @State private var query = ""
    @State private var rows: [(entry: PlannerClientDirectory.Entry, lower: String)] = []
    @State private var loaded = false

    private var matches: [PlannerClientDirectory.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows.prefix(2).map(\.entry) }
        return Array(rows.lazy.filter { $0.lower.contains(q) }.prefix(5).map(\.entry))
    }

    var body: some View {
        Section("🙋 Клиент") {
            if let client {
                HStack {
                    Label(client.name, systemImage: "person.fill")
                    Spacer()
                    Button { self.client = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                TextField("Поиск клиента", text: $query)
                    .autocorrectionDisabled()
                ForEach(matches) { entry in
                    Button { client = entry; query = "" } label: {
                        Label(entry.name, systemImage: "person")
                            .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .task {
            guard !loaded else { return }
            // Список клиентов читаем после показа окна, а не при открытии.
            await Task.yield()
            rows = PlannerClientDirectory.all(context).map { ($0, $0.name.lowercased()) }
            loaded = true
        }
    }
}

/// Настройки абонементов: виды и список проданных.
struct PlannerSubscriptionSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PlannerSubscriptionType> { $0.deletedAt == nil }, sort: \PlannerSubscriptionType.name)
    private var types: [PlannerSubscriptionType]
    @Query(filter: #Predicate<PlannerSubscription> { $0.deletedAt == nil }, sort: \PlannerSubscription.month, order: .reverse)
    private var sold: [PlannerSubscription]

    @State private var newName = ""
    @State private var newPrice = ""
    @State private var names: [UUID: String] = [:]
    @State private var earned: [UUID: Double] = [:]

    var body: some View {
        List {
            Section {
                ForEach(types) { type in
                    NavigationLink {
                        PlannerSubscriptionTypeEditor(type: type)
                    } label: {
                        HStack {
                            Text(type.name)
                            Spacer()
                            Text(PlannerPricing.format(type.price)).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    TextField("Название", text: $newName)
                    TextField("₽", text: $newPrice)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                        .buttonStyle(.borderless)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || Double(newPrice) == nil)
                }
            } header: {
                Text("📜 Виды абонементов")
            }

            Section {
                if sold.isEmpty {
                    Text("Пока никому не продан.").foregroundStyle(.secondary)
                }
                ForEach(sold) { item in
                    NavigationLink {
                        PlannerSubscriptionSaleEditor(sale: item, clientName: names[item.clientID] ?? "Клиент")
                    } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(names[item.clientID] ?? "Клиент").font(.body.weight(.medium))
                            Spacer()
                            Text(PlannerPricing.format(item.amount))
                        }
                        Text("\(item.kindName.isEmpty ? "Абонемент" : item.kindName) · \(PlannerCalendar.monthTitle(item.month))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Заработано с клиента всего: \(PlannerPricing.format(earned[item.clientID] ?? 0))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { PlannerSubscriptionTypeStore.deleteSale(context, sub: sold[index]) }
                    sync.requestSync()
                }
            } header: {
                Text("🧾 Кому продан")
            }
        }
        .onAppear {
            PlannerSubscriptionTypeStore.ensureDefault(context)
            names = Dictionary(PlannerClientDirectory.all(context).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        }
        .task(id: sold.count) {
            // Один проход по оплатам для всех клиентов сразу.
            var result: [UUID: Double] = [:]
            for payment in PlannerPaymentStore.cashPayments(context) {
                result[payment.clientID, default: 0] += payment.amount
            }
            for sub in PlannerPaymentStore.allSubscriptions(context) {
                result[sub.clientID, default: 0] += sub.amount
            }
            earned = result
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let price = Double(newPrice) else { return }
        let item = PlannerSubscriptionType(name: name, price: price)
        context.insert(item)
        item.markChanged()
        try? context.save()
        sync.requestSync()
        newName = ""
        newPrice = ""
    }
}

struct PlannerSubscriptionTypeEditor: View {
    let type: PlannerSubscriptionType

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var price: String
    @State private var validDays: String
    @State private var charge: String
    @State private var deleted = false
    @State private var groups: [String]
    @State private var groupQuery = ""
    @Query(filter: #Predicate<PlannerGroupKind> { $0.deletedAt == nil }, sort: \PlannerGroupKind.name)
    private var groupKinds: [PlannerGroupKind]

    init(type: PlannerSubscriptionType) {
        self.type = type
        _name = State(initialValue: type.name)
        _price = State(initialValue: "\(Int(type.price.rounded()))")
        _validDays = State(initialValue: "\(type.validDays)")
        _charge = State(initialValue: "\(Int(type.charge.rounded()))")
        _groups = State(initialValue: type.groupNames)
    }

    var body: some View {
        Form {
            Section {
                TextField("Название", text: $name)
                HStack {
                    Text("Цена")
                    Spacer()
                    TextField("0", text: $price)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("₽").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Срок действия")
                    Spacer()
                    TextField("30", text: $validDays)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("дн.").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Списание за занятие")
                    Spacer()
                    TextField("500", text: $charge)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("₽").foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(groups, id: \.self) { name in
                    Button { groups.removeAll { $0 == name } } label: {
                        Label(name, systemImage: "checkmark.circle.fill")
                    }
                }
                TextField("Поиск группы", text: $groupQuery)
                let query = groupQuery.trimmingCharacters(in: .whitespaces)
                if !query.isEmpty {
                    ForEach(groupKinds.filter { $0.name.localizedCaseInsensitiveContains(query) && !groups.contains($0.name) }.prefix(4)) { kind in
                        Button { groups.append(kind.name); groupQuery = "" } label: {
                            Label(kind.name, systemImage: "plus.circle")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("На какие группы действует")
            } footer: {
                Text(groups.isEmpty ? "Ничего не выбрано: абонемент действует на все группы. Нажми на выбранную группу, чтобы убрать." : "Абонемент спишется только на занятиях этих групп.")
            }
            Section {
                Button("Удалить вид", role: .destructive) {
                    deleted = true
                    PlannerSubscriptionTypeStore.delete(context, type: type)
                    sync.requestSync()
                    dismiss()
                }
            } footer: {
                Text("Вместе с видом удалятся проданные по нему абонементы и их списания.")
            }
        }
        .navigationTitle("Абонемент")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            guard !deleted else { return }
            let clean = name.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { type.name = clean }
            if let value = Double(price) { type.price = value }
            if let days = Int(validDays), days > 0 { type.validDays = days }
            if let value = Double(charge) { type.charge = max(0, value) }
            type.groupNames = groups
            type.markChanged()
            try? context.save()
            sync.requestSync()
        }
    }
}

/// Правка проданного абонемента: сумма, срок, списание за занятие, удаление.
struct PlannerSubscriptionSaleEditor: View {
    let sale: PlannerSubscription
    let clientName: String

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String
    @State private var charge: String
    @State private var kindName: String
    @State private var expires: Date
    @State private var deleted = false
    @State private var confirmDelete = false

    init(sale: PlannerSubscription, clientName: String) {
        self.sale = sale
        self.clientName = clientName
        _amount = State(initialValue: "\(Int(sale.amount.rounded()))")
        _charge = State(initialValue: "\(Int(sale.charge.rounded()))")
        _kindName = State(initialValue: sale.kindName)
        _expires = State(initialValue: sale.expiresAt)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Клиент", value: clientName)
                TextField("Вид абонемента", text: $kindName)
                HStack {
                    Text("Сумма")
                    Spacer()
                    TextField("0", text: $amount)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("₽").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Списание за занятие")
                    Spacer()
                    TextField("500", text: $charge)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("₽").foregroundStyle(.secondary)
                }
                DatePicker("Действует до", selection: $expires, displayedComponents: .date)
            }
            Section {
                Button("Удалить продажу", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Вместе с продажей удалятся списания с неё.")
            }
        }
        .navigationTitle("Абонемент")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Удалить продажу?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                deleted = true
                PlannerSubscriptionTypeStore.deleteSale(context, sub: sale)
                sync.requestSync()
                dismiss()
            }
        }
        .onDisappear {
            guard !deleted else { return }
            if let value = Double(amount) { sale.amount = max(0, value) }
            if let value = Double(charge) { sale.charge = max(0, value) }
            sale.kindName = kindName.trimmingCharacters(in: .whitespaces)
            let cal = PlannerCalendar.calendar
            sale.expiresAt = cal.startOfDay(for: expires).addingTimeInterval(86400 - 1)
            sale.markChanged()
            try? context.save()
            sync.requestSync()
        }
    }
}
