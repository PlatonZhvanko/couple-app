import SwiftData
import SwiftUI

/// Быстрая продажа абонемента: вид, клиент, сумма (можно поправить).
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

    @State private var selectedType: PlannerSubscriptionType?
    @State private var amountText = ""
    @State private var validText = "30"
    /// Срок: на N дней или до выбранного дня включительно.
    @State private var untilMode = false
    @State private var untilDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var chargeText = "500"
    @State private var query = ""
    @State private var typeQuery = ""
    @State private var client: PlannerClientDirectory.Entry?
    @State private var directory: [PlannerClientDirectory.Entry] = []

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [PlannerClientDirectory.Entry] {
        guard !trimmedQuery.isEmpty else { return Array(directory.prefix(2)) }
        return Array(directory.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }.prefix(5))
    }

    private var typeMatches: [PlannerSubscriptionType] {
        let q = typeQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(types.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(5))
    }

    private var trimmedTypeQuery: String { typeQuery.trimmingCharacters(in: .whitespaces) }

    private var canCreateType: Bool {
        !trimmedTypeQuery.isEmpty
            && !types.contains { $0.name.caseInsensitiveCompare(trimmedTypeQuery) == .orderedSame }
    }

    private func createType() {
        let item = PlannerSubscriptionType(name: trimmedTypeQuery, price: amount ?? 0)
        context.insert(item)
        item.markChanged()
        try? context.save()
        sync.requestSync()
        selectedType = item
        typeQuery = ""
    }

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("📜 Вид абонемента") {
                    if let selectedType {
                        HStack {
                            Label(selectedType.name, systemImage: "checkmark.circle.fill")
                            Spacer()
                            Button { self.selectedType = nil; amountText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        HStack {
                            TextField("Поиск абонемента", text: $typeQuery)
                                .autocorrectionDisabled()
                            if canCreateType {
                                Button(action: createType) {
                                    Image(systemName: "plus.circle.fill").font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Создать новый абонемент")
                            }
                        }
                        ForEach(typeMatches) { type in
                            Button {
                                selectedType = type
                                typeQuery = ""
                                amountText = "\(Int(type.price.rounded()))"
                                validText = "\(type.validDays)"
                                chargeText = "\(Int(type.charge.rounded()))"
                            } label: {
                                HStack {
                                    Text(type.name).foregroundStyle(Color.primary)
                                    Spacer()
                                    Text(PlannerPricing.format(type.price)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
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
                    HStack {
                        Text("Списание за занятие")
                        Spacer()
                        TextField("500", text: $chargeText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("₽").foregroundStyle(.secondary)
                    }
                }

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
                            }
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Месяц: \(PlannerCalendar.monthTitle(month)). С абонемента сами списываются групповые тренировки месяца.")
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
            .onAppear {
                directory = PlannerClientDirectory.all(context)
                PlannerSubscriptionTypeStore.ensureDefault(context)
            }
        }
        .presentationDetents([.large])
        .environment(\.locale, PlannerCalendar.locale)
    }

    private func save() {
        guard let client, let amount else { return }
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
