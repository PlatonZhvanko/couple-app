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
    @State private var confirmDelete = false
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<PlannerPayment> { $0.deletedAt == nil })
    private var payments: [PlannerPayment]
    @Query(filter: #Predicate<PlannerSubscription> { $0.deletedAt == nil })
    private var subscriptions: [PlannerSubscription]

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
                if canEdit {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Удалить запись")
                    }
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                if event.repeatValue != .none {
                    Button("Только этот день", role: .destructive) { deleteRecord(onlyThisDay: true) }
                    Button("Все повторы", role: .destructive) { deleteRecord(onlyThisDay: false) }
                } else {
                    Button("Удалить", role: .destructive) { deleteRecord(onlyThisDay: false) }
                }
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
                    isGroup: event.categoryValue != .personal,
                    hasSubscription: subscriptions.contains {
                        $0.clientID == client.id && $0.covers(day)
                    },
                    onSelect: { select($0, for: client) },
                    onSubscription: { subscriptionClient = client },
                    onAmount: { setAmount($0, for: client) }
                )
            }
            if canEdit && participants.count > 1 {
                Menu {
                    ForEach(bulkMethods) { item in
                        Button("\(item.emoji) \(item.title)") { markAllPaid(with: item) }
                    }
                } label: {
                    Label("Все оплатили", systemImage: "checkmark.circle.fill")
                }
            }
        } header: {
            Text("Оплата")
        } footer: {
            if canEdit && !participants.isEmpty {
                Text("Нажми на кружок и выбери, как оплатили.")
            }
        }
    }

    private func balanceText(for client: PlannerClientDirectory.Entry) -> String? {
        guard let sub = PlannerPaymentStore.subscription(context, clientID: client.id, month: day) else { return nil }
        let balance = PlannerPaymentStore.balance(context, of: sub)
        return "Абонемент: остаток \(PlannerPricing.format(balance))"
    }

    private func select(_ method: PlannerPayMethod, for client: PlannerClientDirectory.Entry) {
        guard canEdit else { return }
        apply(method, for: client)
    }

    private func apply(_ method: PlannerPayMethod, for client: PlannerClientDirectory.Entry) {
        PlannerPaymentStore.set(context, event: event, day: day, clientID: client.id, method: method)
        sync.requestSync()
    }

    private func setAmount(_ value: Double, for client: PlannerClientDirectory.Entry) {
        guard canEdit else { return }
        PlannerPaymentStore.set(context, event: event, day: day, clientID: client.id, amount: value)
        sync.requestSync()
    }

    /// Способы для кнопки «Все оплатили».
    private var bulkMethods: [PlannerPayMethod] { [.cash, .transfer] }

    private func markAllPaid(with method: PlannerPayMethod) {
        for client in participants where self.method(of: client) == .none {
            PlannerPaymentStore.set(context, event: event, day: day, clientID: client.id, method: method)
        }
        sync.requestSync()
    }

    private func deleteRecord(onlyThisDay: Bool) {
        if onlyThisDay {
            event.skippedDays.append(PlannerCalendar.calendar.startOfDay(for: day))
            PlannerPaymentStore.purge(context, eventID: event.syncID, day: day)
        } else {
            event.markDeleted()
            PlannerPaymentStore.purge(context, eventID: event.syncID)
        }
        event.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
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

/// Строка клиента: кружок оплаты, имя, сумма. По нажатию на кружок снизу
/// появляется выбор способа: наличные, перевод, абонемент (у групп), не оплатил.
private struct PlannerPaymentRow: View {
    let name: String
    let method: PlannerPayMethod
    let amount: Double
    let balanceText: String?
    let canEdit: Bool
    let isGroup: Bool
    let hasSubscription: Bool
    let onSelect: (PlannerPayMethod) -> Void
    let onSubscription: () -> Void
    let onAmount: (Double) -> Void

    @State private var expanded = false
    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    private var color: Color {
        if method.isPaid { return .green }
        if method == .unpaid { return .red }
        return .secondary
    }

    private var choices: [PlannerPayMethod] {
        hasSubscription ? [.cash, .transfer, .subscription, .unpaid] : [.cash, .transfer, .unpaid]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    guard canEdit else { return }
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Image(systemName: method == .none ? "circle" : (method.isPaid ? "checkmark.circle.fill" : "xmark.circle.fill"))
                        .font(.title)
                        .foregroundStyle(color)
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.medium))
                    if method != .none {
                        Text("\(method.emoji) \(method == .unpaid ? "не оплачено" : method.title)")
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

            if expanded && canEdit {
                HStack(spacing: 8) {
                    ForEach(choices) { item in chip(item) }
                }
                HStack {
                    if isGroup {
                        Button {
                            onSubscription()
                        } label: {
                            Label(hasSubscription ? "Абонемент клиента…" : "Оформить абонемент…", systemImage: "ticket")
                                .font(.footnote)
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    if method != .none {
                        Button("Сбросить") {
                            onSelect(.none)
                            withAnimation(.snappy) { expanded = false }
                        }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear { amountText = Self.text(amount) }
        .onChange(of: amount) { _, newValue in
            if !amountFocused { amountText = Self.text(newValue) }
        }
        .onChange(of: amountFocused) { _, focused in
            if !focused { commitAmount() }
        }
    }

    private func chip(_ item: PlannerPayMethod) -> some View {
        let selected = method == item
        let tint: Color = item == .unpaid ? .red : .green
        return Button {
            onSelect(item)
            withAnimation(.snappy) { expanded = false }
        } label: {
            VStack(spacing: 2) {
                Text(item.emoji).font(.title3)
                Text(item.chipTitle).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? tint.opacity(0.25) : Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? tint : Color.clear, lineWidth: 1.5))
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.borderless)
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
