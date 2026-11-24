import SwiftData
import SwiftUI

/// Список клиентов с поиском.
struct ClientsListView: View {
    let clients: [ClientsClient]
    let appointments: [ClientsAppointment]
    let onAdd: () -> Void

    @State private var search = ""

    private var visible: [ClientsClient] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return clients }
        let digits = query.filter(\.isNumber)
        let lowered = query.lowercased()
        return clients.filter {
            $0.name.lowercased().contains(lowered)
                || (!digits.isEmpty && $0.phoneDigits.contains(digits))
        }
    }

    /// Дата последнего визита и число визитов по клиенту.
    private var stats: [UUID: (visits: Int, last: Date?)] {
        var result: [UUID: (visits: Int, last: Date?)] = [:]
        for item in appointments where item.status == .done {
            guard let id = item.clientID else { continue }
            var entry = result[id] ?? (0, nil)
            entry.visits += 1
            if entry.last == nil || item.start > entry.last! { entry.last = item.start }
            result[id] = entry
        }
        return result
    }

    var body: some View {
        let stats = self.stats
        List {
            ForEach(visible) { client in
                NavigationLink(value: client) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name)
                            .font(.body.weight(.medium))
                        let info = stats[client.syncID]
                        let details = [
                            client.phone.isEmpty ? nil : client.phone,
                            info.map { "визитов: \($0.visits)" },
                            info?.last.map { "был \($0.formatted(date: .abbreviated, time: .omitted))" },
                        ].compactMap { $0 }
                        if !details.isEmpty {
                            Text(details.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Имя или телефон")
        .overlay {
            if clients.isEmpty {
                ContentUnavailableView {
                    Label("Клиентов пока нет", systemImage: "person.2")
                } description: {
                    Text("Добавьте клиента или сразу создайте запись: клиент добавится сам.")
                } actions: {
                    Button("Новый клиент", action: onAdd)
                        .buttonStyle(.borderedProminent)
                }
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

/// Карточка клиента: контакты, заметки, итоги и история записей.
struct ClientsClientDetailView: View {
    let client: ClientsClient
    let member: CoupleMember

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var history: [ClientsAppointment]
    @State private var sheet: ClientsSheet?
    @State private var planner: (visits: Int, earned: Double) = (0, 0)

    init(client: ClientsClient, member: CoupleMember) {
        self.client = client
        self.member = member
        let id: UUID? = client.syncID
        _history = Query(
            filter: #Predicate<ClientsAppointment> { $0.deletedAt == nil && $0.clientID == id },
            sort: \ClientsAppointment.start,
            order: .reverse
        )
    }

    private var done: [ClientsAppointment] { history.filter { $0.status == .done } }

    var body: some View {
        List {
            if !client.phone.isEmpty {
                Section {
                    LabeledContent("Телефон", value: client.phone)
                    HStack(spacing: 12) {
                        contactButton("Позвонить", "phone.fill", ClientsContact.call(client.phone))
                        contactButton("WhatsApp", "message.fill", ClientsContact.whatsApp(client.phone))
                        contactButton("SMS", "bubble.left.fill", ClientsContact.sms(client.phone))
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                LabeledContent("Дата рождения", value: client.birthday.map { $0.formatted(.dateTime.day().month(.wide).year()) } ?? "не указана")
            }

            Section("📝 Заметки") {
                Text(client.note.isEmpty ? "Пока пусто" : client.note)
                    .foregroundStyle(client.note.isEmpty ? .secondary : .primary)
            }

            Section {
                PlannerRuleColorRow(key: PlannerColorRule.clientKey(client.syncID), fallback: PlannerCategory.personal.color)
            } footer: {
                Text("Необязательно: так будут выглядеть его персональные тренировки в журнале.")
            }

            Section {
                NavigationLink {
                    StatisticsClientReportView(clientID: client.syncID, name: client.name)
                } label: {
                    Label("Посещения, отмены, долги, абонементы", systemImage: "chart.bar.doc.horizontal")
                }
            }

            Section("📊 Итоги") {
                LabeledContent("Визитов", value: "\(done.count + planner.visits)")
                LabeledContent("Заработано", value: ClientsFormat.money(done.reduce(0) { $0 + $1.price } + planner.earned))
                let noShows = history.filter { $0.status == .noShow }.count
                if noShows > 0 {
                    LabeledContent("Не пришёл", value: "\(noShows)")
                }
            }

            Section {
                Button("Новая запись", systemImage: "calendar.badge.plus") {
                    sheet = .newAppointment(clientID: client.syncID)
                }
                ForEach(history) { item in
                    NavigationLink(value: item) {
                        ClientsAppointmentRow(appointment: item, clientName: item.service.isEmpty ? "Запись" : item.service, showDate: true)
                    }
                }
            } header: {
                Text("Записи")
            }
        }
        .navigationTitle(client.name)
        .task { planner = PlannerClientDirectory.stats(for: client.syncID, context: context) }
        .toolbar {
            Button("Изменить") { sheet = .editClient(client) }
        }
        .sheet(item: $sheet) { sheet in
            ClientsSheetView(sheet: sheet, member: member)
        }
        .onChange(of: client.deletedAt) { _, deleted in
            if deleted != nil { dismiss() }
        }
    }

    private func contactButton(_ title: String, _ image: String, _ url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: image).font(.title3)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .disabled(url == nil)
    }
}

/// Добавление и правка клиента.
struct ClientsClientEditor: View {
    let member: CoupleMember
    let client: ClientsClient?

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var confirmDelete = false

    init(member: CoupleMember, client: ClientsClient?) {
        self.member = member
        self.client = client
        _name = State(initialValue: client?.name ?? "")
        _phone = State(initialValue: client?.phone ?? "")
        _note = State(initialValue: client?.note ?? "")
        _hasBirthday = State(initialValue: client?.birthday != nil)
        if let b = client?.birthday { _birthday = State(initialValue: b) }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя", text: $name)
                        .textContentType(.name)
                    TextField("Телефон", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Section {
                    Toggle("Дата рождения", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Дата", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    }
                }
                Section("Заметки") {
                    TextField("Пожелания, особенности", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                if client != nil {
                    Section {
                        Button("Удалить клиента", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Записи клиента останутся в истории и итогах.")
                    }
                }
            }
            .navigationTitle(client == nil ? "Новый клиент" : "Клиент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Удалить клиента?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить клиента и его записи", role: .destructive, action: delete)
            }
        }
    }

    private func save() {
        // Одинаковых карточек не бывает: новый клиент с уже существующим именем открывает старую карточку.
        let sameName = client == nil ? PlannerClientMerge.existing(name: trimmedName, member: member, context: context) : nil
        let target = client ?? sameName ?? ClientsClient(name: trimmedName, member: member)
        target.name = trimmedName
        target.phone = phone.trimmingCharacters(in: .whitespaces)
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.birthday = hasBirthday ? birthday : nil
        target.markChanged()
        if client == nil && sameName == nil { context.insert(target) }
        try? context.save()
        PlannerClientMerge.mergeAll(context)
        sync.requestSync()
        dismiss()
    }

    private func delete() {
        if let id = client?.syncID { PlannerClientDirectory.removeEvents(of: id, context: context) }
        client?.markDeleted()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
