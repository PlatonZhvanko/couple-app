import SwiftData
import SwiftUI

/// Быстрая продажа абонемента: вид, клиент, сумма (можно поправить).
struct PlannerSubscriptionSaleSheet: View {
    let month: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PlannerSubscriptionType> { $0.deletedAt == nil }, sort: \PlannerSubscriptionType.name)
    private var types: [PlannerSubscriptionType]

    @State private var selectedType: PlannerSubscriptionType?
    @State private var amountText = ""
    @State private var validText = "30"
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
        guard !q.isEmpty else { return Array(types.prefix(3)) }
        return Array(types.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(5))
    }

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Вид абонемента") {
                    if types.isEmpty {
                        Text("Видов пока нет. Добавь их в разделе «Клиенты» → «Абонементы».")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
                        TextField("Поиск абонемента", text: $typeQuery)
                            .autocorrectionDisabled()
                        ForEach(typeMatches) { type in
                            Button {
                                selectedType = type
                                typeQuery = ""
                                amountText = "\(Int(type.price.rounded()))"
                                validText = "\(type.validDays)"
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
                    HStack {
                        Text("Срок действия")
                        Spacer()
                        TextField("30", text: $validText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("дн.").foregroundStyle(.secondary)
                    }
                }

                Section("Клиент") {
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
            kindName: selectedType?.name, validDays: Int(validText) ?? 30
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
                Text("Виды абонементов")
            }

            Section {
                if sold.isEmpty {
                    Text("Пока никому не продан.").foregroundStyle(.secondary)
                }
                ForEach(sold) { item in
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
            } header: {
                Text("Кому продан")
            }
        }
        .onAppear {
            PlannerSubscriptionTypeStore.ensureDefault(context)
            names = Dictionary(PlannerClientDirectory.all(context).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        }
        .task(id: sold.count) {
            var result: [UUID: Double] = [:]
            for id in Set(sold.map(\.clientID)) {
                result[id] = PlannerClientDirectory.stats(for: id, context: context).earned
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
    @State private var deleted = false

    init(type: PlannerSubscriptionType) {
        self.type = type
        _name = State(initialValue: type.name)
        _price = State(initialValue: "\(Int(type.price.rounded()))")
        _validDays = State(initialValue: "\(type.validDays)")
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
            type.markChanged()
            try? context.save()
            sync.requestSync()
        }
    }
}
