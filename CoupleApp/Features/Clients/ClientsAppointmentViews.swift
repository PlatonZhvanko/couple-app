import SwiftData
import SwiftUI

/// Подробности записи: отметить результат, напомнить клиенту, изменить.
struct ClientsAppointmentDetailView: View {
    let appointment: ClientsAppointment
    let member: CoupleMember

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Query private var matchingClients: [ClientsClient]
    @State private var sheet: ClientsSheet?

    init(appointment: ClientsAppointment, member: CoupleMember) {
        self.appointment = appointment
        self.member = member
        let id = appointment.clientID ?? UUID()
        _matchingClients = Query(filter: #Predicate<ClientsClient> { $0.syncID == id })
    }

    private var client: ClientsClient? { matchingClients.first }

    var body: some View {
        List {
            Section {
                if let client, client.deletedAt == nil {
                    NavigationLink(value: client) {
                        LabeledContent("Клиент", value: client.name)
                    }
                } else {
                    LabeledContent("Клиент", value: client?.name ?? "Без клиента")
                }
                if !appointment.service.isEmpty {
                    LabeledContent("Услуга", value: appointment.service)
                }
                if appointment.isFromIClients {
                    LabeledContent("Источник") {
                        HStack(spacing: 6) { ClientsIClientsBadge(); Text("журнал iClients") }
                    }
                }
                LabeledContent("Дата", value: ClientsFormat.dayTitle(appointment.start))
                LabeledContent("Время", value: ClientsFormat.time(appointment))
                LabeledContent("Цена", value: ClientsFormat.money(appointment.price))
                LabeledContent("Статус") {
                    Label(appointment.needsOutcome ? "Нужно отметить" : appointment.status.title,
                          systemImage: appointment.needsOutcome ? "questionmark.circle.fill" : appointment.status.systemImage)
                        .foregroundStyle(appointment.needsOutcome ? .orange : appointment.status.color)
                }
            }

            Section("Отметить") {
                ForEach(ClientsAppointmentStatus.allCases) { status in
                    Button {
                        setStatus(status)
                    } label: {
                        HStack {
                            Label(status.title, systemImage: status.systemImage)
                                .foregroundStyle(status.color)
                            Spacer()
                            if appointment.status == status {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }

            if let client, !client.phone.isEmpty {
                let text = ClientsContact.reminderText(clientName: client.name, appointment: appointment)
                Section {
                    if let url = ClientsContact.whatsApp(client.phone, text: text) {
                        Button("Напомнить в WhatsApp", systemImage: "message.fill") { openURL(url) }
                    }
                    if let url = ClientsContact.sms(client.phone, text: text) {
                        Button("Напомнить по SMS", systemImage: "bubble.left.fill") { openURL(url) }
                    }
                    if let url = ClientsContact.call(client.phone) {
                        Button("Позвонить", systemImage: "phone.fill") { openURL(url) }
                    }
                } header: {
                    Text("Связаться с клиентом")
                } footer: {
                    Text("Откроется сообщение с готовым текстом: «\(text)»")
                }
            }

            if !appointment.note.isEmpty {
                Section("Заметка") {
                    Text(appointment.note)
                }
            }
        }
        .navigationTitle(appointment.service.isEmpty ? "Запись" : appointment.service)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Изменить") { sheet = .editAppointment(appointment) }
        }
        .sheet(item: $sheet) { sheet in
            ClientsSheetView(sheet: sheet, member: member)
        }
        .onChange(of: appointment.deletedAt) { _, deleted in
            if deleted != nil { dismiss() }
        }
    }

    private func setStatus(_ status: ClientsAppointmentStatus) {
        guard appointment.status != status else { return }
        appointment.status = status
        appointment.markChanged()
        try? context.save()
        sync.requestSync()
    }
}

/// Создание и правка записи. Клиента можно выбрать или сразу создать нового.
struct ClientsAppointmentEditor: View {
    let member: CoupleMember
    let appointment: ClientsAppointment?

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query private var clients: [ClientsClient]
    @Query private var allAppointments: [ClientsAppointment]

    @State private var clientID: UUID?
    @State private var newClientName = ""
    @State private var newClientPhone = ""
    @State private var service: String
    @State private var start: Date
    @State private var duration: Int
    @State private var price: Double
    @State private var status: ClientsAppointmentStatus
    @State private var reminderMinutes: Int
    @State private var note: String
    @State private var confirmDelete = false

    private static let durations = [15, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300, 360, 480]

    init(member: CoupleMember, appointment: ClientsAppointment?, presetClientID: UUID?) {
        self.member = member
        self.appointment = appointment
        let raw = member.rawValue
        _clients = Query(
            filter: #Predicate<ClientsClient> { $0.deletedAt == nil && $0.member == raw },
            sort: \ClientsClient.name
        )
        _allAppointments = Query(
            filter: #Predicate<ClientsAppointment> { $0.deletedAt == nil && $0.member == raw },
            sort: \ClientsAppointment.start,
            order: .reverse
        )
        _clientID = State(initialValue: presetClientID)
        _service = State(initialValue: appointment?.service ?? "")
        _start = State(initialValue: appointment?.start ?? Self.nextSlot())
        _duration = State(initialValue: appointment?.durationMinutes ?? 60)
        _price = State(initialValue: appointment?.price ?? 0)
        _status = State(initialValue: appointment?.status ?? .planned)
        _reminderMinutes = State(initialValue: appointment?.reminderMinutes ?? 60)
        _note = State(initialValue: appointment?.note ?? "")
    }

    /// Ближайший целый час.
    private static func nextSlot() -> Date {
        let cal = Calendar.current
        let hour = cal.dateInterval(of: .hour, for: .now)?.start ?? .now
        return cal.date(byAdding: .hour, value: 1, to: hour) ?? .now
    }

    /// Услуги из прошлых записей, самые свежие сначала.
    private var recentServices: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in allAppointments {
            let name = item.service.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            result.append(name)
            if result.count == 8 { break }
        }
        return result
    }

    /// Другие записи, которые пересекаются по времени.
    private var overlapping: [ClientsAppointment] {
        let end = start.addingTimeInterval(TimeInterval(duration * 60))
        return allAppointments.filter {
            $0.syncID != appointment?.syncID
                && $0.status != .cancelled
                && $0.start < end && $0.end > start
        }
    }

    private var isNewClient: Bool { clientID == nil }

    private var canSave: Bool {
        !isNewClient || !newClientName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var durationOptions: [Int] {
        Self.durations.contains(duration) ? Self.durations : (Self.durations + [duration]).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Клиент") {
                    Picker("Клиент", selection: $clientID) {
                        Text("Новый клиент").tag(UUID?.none)
                        ForEach(clients) { client in
                            Text(client.name).tag(Optional(client.syncID))
                        }
                    }
                    if isNewClient {
                        TextField("Имя", text: $newClientName)
                            .textContentType(.name)
                        TextField("Телефон (необязательно)", text: $newClientPhone)
                            .keyboardType(.phonePad)
                    }
                }

                Section("Услуга") {
                    TextField("Например, стрижка", text: $service)
                    if !recentServices.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(recentServices, id: \.self) { name in
                                    Button(name) { pickService(name) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section {
                    DatePicker("Начало", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    Picker("Длительность", selection: $duration) {
                        ForEach(durationOptions, id: \.self) { Text(ClientsFormat.duration($0)).tag($0) }
                    }
                    LabeledContent("Цена") {
                        TextField("0", value: $price, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if !overlapping.isEmpty {
                        Label("В это время уже есть запись (\(overlapping.map { ClientsFormat.time($0) }.joined(separator: ", ")))",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    if appointment != nil {
                        Picker("Статус", selection: $status) {
                            ForEach(ClientsAppointmentStatus.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Напоминание", selection: $reminderMinutes) {
                        ForEach(ClientsReminders.options) { option in
                            Text(option.title).tag(option.minutes)
                        }
                    }
                } footer: {
                    Text("Напоминание придёт на этот телефон.")
                }

                Section("Заметка") {
                    TextField("Необязательно", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }

                if appointment != nil {
                    Section {
                        Button("Удалить запись", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(appointment == nil ? "Новая запись" : "Запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
            }
        }
    }

    /// Выбрать услугу и подставить цену и длительность из прошлой такой же записи.
    private func pickService(_ name: String) {
        service = name
        if let last = allAppointments.first(where: { $0.service.caseInsensitiveCompare(name) == .orderedSame }) {
            duration = last.durationMinutes
            if price == 0 || appointment == nil { price = last.price }
        }
    }

    private func save() {
        var targetClientID = clientID
        if isNewClient {
            let client = ClientsClient(
                name: newClientName.trimmingCharacters(in: .whitespaces),
                phone: newClientPhone.trimmingCharacters(in: .whitespaces),
                member: member
            )
            context.insert(client)
            targetClientID = client.syncID
        }

        let target = appointment ?? ClientsAppointment(member: member)
        target.clientID = targetClientID
        target.service = service.trimmingCharacters(in: .whitespaces)
        target.start = start
        target.durationMinutes = duration
        target.price = max(0, price)
        target.status = status
        target.reminderMinutes = reminderMinutes
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.markChanged()
        if appointment == nil { context.insert(target) }
        try? context.save()
        sync.requestSync()
        dismiss()
    }

    private func delete() {
        appointment?.markDeleted()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
