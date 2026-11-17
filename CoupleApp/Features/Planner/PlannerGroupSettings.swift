import SwiftData
import SwiftUI

/// Настройки групп: готовые виды групп и их постоянные клиенты.
/// Показывается во вкладке «Группы» раздела «Клиенты».
struct PlannerGroupSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PlannerGroupKind> { $0.deletedAt == nil }, sort: \PlannerGroupKind.name)
    private var kinds: [PlannerGroupKind]

    @State private var newName = ""
    @State private var newCategory: PlannerCategory = .group

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            Section {
                ForEach(kinds) { kind in
                    NavigationLink {
                        PlannerGroupEditor(kind: kind)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.name)
                                .font(.body.weight(.medium))
                            Text(kind.memberIDs.isEmpty ? "Без постоянных клиентов" : "Постоянных клиентов: \(kind.memberIDs.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if kinds.isEmpty {
                    Text("Групп пока нет. Добавь первую ниже.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("👧👦 Готовые группы")
            } footer: {
                Text("Постоянные клиенты подставляются сами, когда выбираешь группу в журнале. Их можно убрать в конкретной записи.")
            }

            Section("➕ Новая группа") {
                Picker("Тип", selection: $newCategory) {
                    ForEach([PlannerCategory.group, .school]) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField("Название", text: $newName)
                        .onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func add() {
        guard !trimmedName.isEmpty else { return }
        PlannerGroupKindStore.ensure(context, name: trimmedName, category: newCategory)
        sync.requestSync()
        newName = ""
    }
}

/// Правка одной группы: название, тип, постоянные клиенты.
struct PlannerGroupEditor: View {
    let kind: PlannerGroupKind

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: PlannerCategory
    @State private var memberIDs: [UUID]
    @State private var priceText: String
    @State private var query = ""
    @State private var directory: [PlannerClientDirectory.Entry] = []
    @State private var confirmDelete = false
    @State private var deleted = false

    init(kind: PlannerGroupKind) {
        self.kind = kind
        _name = State(initialValue: kind.name)
        _category = State(initialValue: kind.categoryValue)
        _memberIDs = State(initialValue: kind.memberIDs)
        _priceText = State(initialValue: "\(Int(kind.price.rounded()))")
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var members: [PlannerClientDirectory.Entry] {
        memberIDs.compactMap { id in directory.first { $0.id == id } }
    }

    private var suggestions: [PlannerClientDirectory.Entry] {
        let pool = directory.filter { !memberIDs.contains($0.id) }
        guard !trimmedQuery.isEmpty else { return Array(pool.prefix(2)) }
        return Array(pool.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }.prefix(6))
    }

    private var queryMatchesExisting: Bool {
        directory.contains { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        Form {
            Section {
                TextField("Название", text: $name)
                Picker("Тип", selection: $category) {
                    ForEach([PlannerCategory.group, .school]) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Цена с клиента")
                    Spacer()
                    TextField("750", text: $priceText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("₽").foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(members) { client in
                    HStack {
                        Label(client.name, systemImage: "person.fill")
                        Spacer()
                        Button {
                            memberIDs.removeAll { $0 == client.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Добавить клиента", text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit(addTyped)
                    if !trimmedQuery.isEmpty && !queryMatchesExisting {
                        Button(action: addTyped) {
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
                ForEach(suggestions) { client in
                    Button {
                        memberIDs.append(client.id)
                        query = ""
                    } label: {
                        Label(client.name, systemImage: "person")
                    }
                }
            } header: {
                Text("👥 Постоянные клиенты")
            } footer: {
                Text("Они сами добавятся, когда выберешь эту группу при создании записи.")
            }

            Section {
                Button("Удалить группу", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Старые записи в журнале останутся.")
            }
        }
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { directory = PlannerClientDirectory.all(context) }
        .onDisappear(perform: save)
        .confirmationDialog("Удалить группу?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                deleted = true
                kind.markDeleted()
                try? context.save()
                sync.requestSync()
                dismiss()
            }
        }
    }

    private func addTyped() {
        let text = trimmedQuery
        guard !text.isEmpty else { return }
        if let existing = directory.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) {
            if !memberIDs.contains(existing.id) { memberIDs.append(existing.id) }
        } else {
            let created = PlannerClientDirectory.add(name: text, member: account.current, context: context)
            directory.append(created)
            memberIDs.append(created.id)
            sync.requestSync()
        }
        query = ""
    }

    /// Сохраняем при выходе с экрана.
    private func save() {
        guard !deleted else { return }
        let clean = name.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty { kind.name = clean }
        kind.category = category.rawValue
        kind.memberIDs = memberIDs
        if let value = Double(priceText) { kind.price = max(0, value) }
        kind.markChanged()
        try? context.save()
        sync.requestSync()
    }
}
