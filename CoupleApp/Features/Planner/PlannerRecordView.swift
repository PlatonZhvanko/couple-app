import SwiftData
import SwiftUI

/// Запись изнутри: когда, кто, оплата клиентов, «Перенести» и «Изменить».
struct PlannerRecordView: View {
    let event: PlannerEvent
    /// День, в который открыта запись (для повторяющихся).
    let day: Date
    let onEdit: () -> Void
    let onMove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<PlannerPayment> { $0.deletedAt == nil })
    private var payments: [PlannerPayment]
    @Query(filter: #Predicate<PlannerSubscription> { $0.deletedAt == nil })
    private var subscriptions: [PlannerSubscription]

    @AppStorage("planner.lastPayMethod") private var lastPayMethod = PlannerPayMethod.cash.rawValue
    @State private var clients: [PlannerClientDirectory.Entry] = []
    @State private var subscriptionClient: PlannerClientDirectory.Entry?

    private var cal: Calendar { PlannerCalendar.calendar }
    private var canEdit: Bool { event.scopeValue.canEdit(by: account.current) }
    private var showsPayments: Bool { PlannerPaymentStore.isTraining(event) }

    private var participants: [PlannerClientDirectory.Entry] {
        event.participantIDs.compactMap { id in clients.first { $0.id == id } }
    }

    private var dayPayments: [PlannerPayment] {
        payments.filter { $0.eventID == event.syncID && cal.isDate($0.day, inSameDayAs: day) }
    }

    private func method(of client: PlannerClientDirectory.Entry) -> PlannerPayMethod {
        dayPayments.first { $0.clientID == client.id }?.methodValue ?? PlannerPayMethod.none
    }

    private var badge: PlannerPayBadge {
        PlannerPaymentStore.badge(for: event, day: day, payments: payments)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if showsPayments {
                    paymentsSection
                }
                actionsSection
            }
            .navigationTitle("Запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .onAppear {
                clients = PlannerClientDirectory.all(context)
            }
            .sheet(item: $subscriptionClient) { client in
                PlannerSubscriptionSheet(client: client, month: day)
            }
        }
        .environment(\.locale, PlannerCalendar.locale)
    }

    // MARK: - Шапка

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.displayTitle)
                        .font(.title2.bold())
                    Spacer()
                    if let symbol = badge.symbol {
                        Text(symbol).font(.title2)
                    }
                }
                Text(PlannerCalendar.dayTitle(day))
                    .foregroundStyle(.secondary)
                Text(timeText)
                    .font(.headline)
                    .foregroundStyle(event.categoryValue.color)
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var timeText: String {
        if event.isAllDay { return "Весь день" }
        let duration = event.end.timeIntervalSince(event.start)
        let start = PlannerCalendar.combine(day: day, time: event.start)
        return "\(PlannerCalendar.time(start))–\(PlannerCalendar.time(start.addingTimeInterval(duration)))"
    }

    // MARK: - Оплата

    private var paymentsSection: some View {
        Section {
            if participants.isEmpty {
                Text(event.categoryValue == .personal ? "Клиент не выбран." : "В группе пока нет клиентов. Добавь их через «Изменить».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(participants) { client in
                PlannerPaymentRow(
                    name: client.name,
                    method: method(of: client),
                    amount: dayPayments.first { $0.clientID == client.id }?.amount
                        ?? PlannerPricing.price(for: event.categoryValue),
                    balanceText: balanceText(for: client),
                    canEdit: canEdit,
                    onCycle: { cycle(client) },
                    onSelect: { select($0, for: client) },
                    onSubscription: { subscriptionClient = client },
                    onAmount: { setAmount($0, for: client) }
                )
            }
            if canEdit && participants.count > 1 {
                Button {
                    markAllPaid()
                } label: {
                    Label("Все оплатили", systemImage: "checkmark.circle.fill")
                }
            }
        } header: {
            Text("Оплата")
        } footer: {
            if canEdit && !participants.isEmpty {
                Text("Нажми на кружок: оплачено, потом крестик. Удерживай, чтобы выбрать способ.")
            }
        }
    }

    private func balanceText(for client: PlannerClientDirectory.Entry) -> String? {
        guard let sub = PlannerPaymentStore.subscription(context, clientID: client.id, month: day) else { return nil }
        let balance = PlannerPaymentStore.balance(context, of: sub)
        return "Абонемент: остаток \(PlannerPricing.format(balance))"
    }

    private func cycle(_ client: PlannerClientDirectory.Entry) {
        guard canEdit else { return }
        let next: PlannerPayMethod
        switch method(of: client) {
        case .none: next = PlannerPayMethod(rawValue: lastPayMethod) ?? .cash
        case .cash, .transfer, .subscription: next = .unpaid
        case .unpaid: next = .none
        }
        apply(next, for: client)
    }

    private func select(_ method: PlannerPayMethod, for client: PlannerClientDirectory.Entry) {
        guard canEdit else { return }
        apply(method, for: client)
    }

    private func apply(_ method: PlannerPayMethod, for client: PlannerClientDirectory.Entry) {
        if method == .cash || method == .transfer { lastPayMethod = method.rawValue }
        PlannerPaymentStore.set(context, event: event, day: day, clientID: client.id, method: method)
        sync.requestSync()
    }

    private func setAmount(_ value: Double, for client: PlannerClientDirectory.Entry) {
        guard canEdit else { return }
        PlannerPaymentStore.set(context, event: event, day: day, clientID: client.id, amount: value)
        sync.requestSync()
    }

    private func markAllPaid() {
        let paid = PlannerPayMethod(rawValue: lastPayMethod) ?? .cash
        for client in participants where method(of: client) == .none {
            PlannerPaymentStore.set(context, event: event, day: day, clientID: client.id, method: paid)
        }
        sync.requestSync()
    }

    // MARK: - Действия

    private var actionsSection: some View {
        Section {
            if canEdit {
                Button {
                    dismiss()
                    onMove()
                } label: {
                    Label("Перенести", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
                Button {
                    dismiss()
                    onEdit()
                } label: {
                    Label("Изменить", systemImage: "pencil")
                }
            } else {
                Label("Это запись другого человека, её можно только смотреть.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Строка клиента: кружок оплаты, имя, сумма.
private struct PlannerPaymentRow: View {
    let name: String
    let method: PlannerPayMethod
    let amount: Double
    let balanceText: String?
    let canEdit: Bool
    let onCycle: () -> Void
    let onSelect: (PlannerPayMethod) -> Void
    let onSubscription: () -> Void
    let onAmount: (Double) -> Void

    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    private var color: Color {
        if method.isPaid { return .green }
        if method == .unpaid { return .red }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach([PlannerPayMethod.cash, .transfer, .subscription, .unpaid, .none]) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        Label(item == .none ? "Сбросить" : item.title, systemImage: item.systemImage)
                    }
                }
                Divider()
                Button {
                    onSubscription()
                } label: {
                    Label("Абонемент клиента…", systemImage: "ticket")
                }
            } label: {
                Image(systemName: method == .none ? "circle" : (method.isPaid ? "checkmark.circle.fill" : "xmark.circle.fill"))
                    .font(.title)
                    .foregroundStyle(color)
            } primaryAction: {
                onCycle()
            }
            .disabled(!canEdit)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium))
                if method != .none {
                    HStack(spacing: 4) {
                        Image(systemName: method.systemImage)
                        Text(method == .unpaid ? "не оплачено" : method.title)
                    }
                    .font(.caption)
                    .foregroundStyle(color)
                }
                if let balanceText {
                    Text(balanceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 2) {
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .focused($amountFocused)
                    .disabled(!canEdit)
                Text("₽").foregroundStyle(.secondary)
            }
        }
        .onAppear { amountText = Self.text(amount) }
        .onChange(of: amount) { _, newValue in
            if !amountFocused { amountText = Self.text(newValue) }
        }
        .onChange(of: amountFocused) { _, focused in
            if !focused { commitAmount() }
        }
    }

    private func commitAmount() {
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else {
            amountText = Self.text(amount)
            return
        }
        if abs(value - amount) > 0.001 { onAmount(value) }
    }

    private static func text(_ value: Double) -> String {
        let rounded = value.rounded()
        return abs(value - rounded) < 0.005 ? "\(Int(rounded))" : String(format: "%.2f", value)
    }
}

/// Абонемент клиента на месяц: сумма, остаток.
struct PlannerSubscriptionSheet: View {
    let client: PlannerClientDirectory.Entry
    let month: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @State private var amountText = ""

    private var existing: PlannerSubscription? {
        PlannerPaymentStore.subscription(context, clientID: client.id, month: month)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Сумма абонемента")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("₽").foregroundStyle(.secondary)
                    }
                    if let existing {
                        LabeledContent("Остаток", value: PlannerPricing.format(PlannerPaymentStore.balance(context, of: existing)))
                    }
                } header: {
                    Text("\(client.name), \(PlannerCalendar.monthTitle(month))")
                } footer: {
                    Text("За каждую тренировку месяца с абонемента списывается \(PlannerPricing.format(PlannerPricing.subscriptionCharge)), галочки не нужны. Если оплатить иначе, поменяй вручную в самой записи.")
                }
            }
            .navigationTitle("Абонемент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(Double(amountText.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
            .onAppear {
                let value = existing?.amount ?? PlannerPricing.subscriptionDefault
                amountText = "\(Int(value.rounded()))"
            }
        }
        .presentationDetents([.medium])
        .environment(\.locale, PlannerCalendar.locale)
    }

    private func save() {
        guard let value = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
        PlannerPaymentStore.saveSubscription(context, clientID: client.id, month: month, amount: max(0, value))
        sync.requestSync()
        dismiss()
    }
}
