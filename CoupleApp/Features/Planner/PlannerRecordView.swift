import UIKit
import SwiftData
import SwiftUI

/// Запись изнутри: когда, кто, оплата клиентов, «Перенести» и «Изменить».
struct PlannerRecordView: View {
    let event: PlannerEvent
    /// День, в который открыта запись (для повторяющихся).
    let day: Date
    let onEdit: () -> Void
    let onMove: () -> Void
    /// «Перенос» дела: режим выбора нового места в журнале.
    var onCarry: () -> Void = {}
    /// Режим наблюдателя: запись чужого журнала только для просмотра.
    var readOnly = false
    /// Запись YClients, подтвердившая корт этого занятия (корт и клиент из YClients).
    var linkedRecord: PlannerEvent? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var clientPhone = ""
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    /// Только оплаты этой записи: не все оплаты за всё время.
    @Query private var payments: [PlannerPayment]
    @Query(filter: #Predicate<PlannerSubscription> { $0.deletedAt == nil })
    private var subscriptions: [PlannerSubscription]

    /// Посчитано один раз, а не при каждой перерисовке: остаток абонемента, действие абонемента, цена.
    @State private var balances: [UUID: String] = [:]
    @State private var covered: Set<UUID> = []
    @State private var groupPrice: Double = PlannerPricing.group

    init(event: PlannerEvent, day: Date, onEdit: @escaping () -> Void, onMove: @escaping () -> Void,
         onCarry: @escaping () -> Void = {}, readOnly: Bool = false, linkedRecord: PlannerEvent? = nil) {
        self.event = event
        self.linkedRecord = linkedRecord
        self.day = day
        self.onEdit = onEdit
        self.onMove = onMove
        self.onCarry = onCarry
        self.readOnly = readOnly
        let id = event.syncID
        _payments = Query(filter: #Predicate<PlannerPayment> { $0.deletedAt == nil && $0.eventID == id })
    }

    @State private var clients: [PlannerClientDirectory.Entry] = []
    @State private var subscriptionClient: PlannerClientDirectory.Entry?
    @State private var showMoveSheet = false
    @State private var moveTarget = Date.now

    @Query(filter: #Predicate<PlannerErrandKind> { $0.deletedAt == nil })
    private var errandKinds: [PlannerErrandKind]

    /// Название; у регулярного дела впереди эмодзи его типа (меняется вместе с типом).
    private var headerTitle: String {
        guard !event.errandType.isEmpty else { return event.displayTitle }
        let kind = errandKinds.first {
            $0.member == account.current && $0.name.caseInsensitiveCompare(event.errandType) == .orderedSame
        }
        return "\(kind?.displayEmoji ?? "💼") \(event.plainTitle)"
    }

    private var cal: Calendar { PlannerCalendar.calendar }
    private var canEdit: Bool { event.scopeValue.canEdit(by: account.current) }
    private var isCancelled: Bool { event.isCancelled(on: day) }
    private var isOwnerView: Bool { account.current == .owner }
    /// Отметки «сделано / не сделано / перенос» есть у Платони и у дел Настеньки (не тренировок).
    private var showsStatus: Bool { isOwnerView || event.categoryValue == .errand }
    private var myStatus: PlannerErrandStatus? { event.status(on: day, for: account.current) }
    private var showsPayments: Bool { PlannerPaymentStore.isTraining(event) && !isOwnerView }

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
        if showsStatus {
            switch myStatus {
            case .done: return .errandDone
            case .notDone: return .errandNotDone
            case .moved: return .errandMoved
            case nil: return .none
            }
        }
        return PlannerPaymentStore.badge(for: event, day: day, payments: payments)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if readOnly {
                    observerSection
                } else {
                    if showsStatus { ownerStatusSection }
                    if showsPayments {
                        if isCancelled { finesSection } else { paymentsSection }
                    }
                    if event.isFromYClients { yclientsSection }
                    if let linkedRecord { courtConfirmedSection(linkedRecord) }
                    actionsSection
                }
            }
            .navigationTitle("Запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
                if canEdit && !readOnly {
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
                refreshDerived()
                // Телефон читаем один раз, а не при каждой перерисовке экрана.
                if event.isFromYClients, let id = event.participantIDs.first {
                    clientPhone = PlannerClientDirectory.phone(of: id, context: context)
                }
            }
            .onChange(of: paymentsSignature) { _, _ in refreshDerived() }
            .onChange(of: subscriptions.count) { _, _ in refreshDerived() }
            .sheet(isPresented: $showMoveSheet) { moveSheet }
            .sheet(item: $subscriptionClient) { client in
                PlannerSubscriptionSaleSheet(month: day, client: client)
            }
        }
        .environment(\.locale, PlannerCalendar.locale)
    }

    // MARK: - Шапка

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if event.isFromYClients {
                        HStack(spacing: 8) {
                            ClientsYClientsBadge(size: 24)
                            Text(event.plainTitle).font(.title2.bold())
                        }
                    } else {
                        Text(headerTitle)
                            .font(.title2.bold())
                    }
                    Spacer()
                    if !readOnly, let symbol = badge.symbol {
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

    /// Оранжевая запись: корт и клиент из подтвердившей её записи YClients.
    private func courtConfirmedSection(_ record: PlannerEvent) -> some View {
        Section {
            LabeledContent("Источник") {
                HStack(spacing: 6) {
                    ClientsYClientsBadge(size: 18)
                    Text("YClients")
                }
            }
            if !record.notes.isEmpty {
                LabeledContent("Корт", value: record.notes)
            }
            LabeledContent("Клиент YClients", value: record.plainTitle)
            LabeledContent("Время", value: "\(PlannerCalendar.time(record.start))–\(PlannerCalendar.time(record.end))")
        } header: {
            Text("✓ Корт подтверждён")
        }
    }

    /// Только для записей, пришедших из YClients: источник и связь с клиентом.
    private var yclientsSection: some View {
        let digits = ClientsContact.internationalDigits(clientPhone)
        return Section {
            LabeledContent("Источник") {
                HStack(spacing: 6) {
                    ClientsYClientsBadge(size: 18)
                    Text("YClients")
                }
            }
            if !digits.isEmpty {
                HStack(spacing: 6) {
                    contactLink("Звонок", "phone.fill", ClientsContact.call(clientPhone))
                    contactLink("WhatsApp", "message.fill", ClientsContact.whatsApp(clientPhone))
                    contactLink("Telegram", "paperplane.fill", URL(string: "https://t.me/+\(digits)"))
                    // У Max нет ссылки «написать по номеру»: копируем номер и открываем Max, дальше поиск по номеру.
                    Button {
                        UIPasteboard.general.string = "+" + digits
                        if let url = URL(string: "https://max.ru/") { openURL(url) }
                    } label: {
                        Label("Max", systemImage: "bubble.left.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleOnly)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Связаться с клиентом")
        } footer: {
            if digits.isEmpty {
                Text("У клиента не указан телефон.")
            } else {
                Text("Max: номер копируется, вставьте его в поиск Max.")
            }
        }
    }

    @ViewBuilder
    private func contactLink(_ title: String, _ systemImage: String, _ url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Label(title, systemImage: systemImage)
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleOnly)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// Просмотр чужой записи: кто там записан и что в ней важного, без действий.
    private var observerSection: some View {
        Group {
            if !participants.isEmpty {
                Section("Кто записан") {
                    ForEach(participants) { client in
                        Label(client.name, systemImage: "person")
                    }
                }
            }
            if !event.errandType.isEmpty {
                Section("Тип дела") {
                    Text(event.errandType)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Режим просмотра: запись чужого журнала можно только посмотреть.")
            }
        }
    }

    private var timeText: String {
        if event.isAllDay { return "Весь день" }
        let duration = event.end.timeIntervalSince(event.start)
        let start = PlannerCalendar.combine(day: day, time: event.start)
        return "\(PlannerCalendar.time(start))–\(PlannerCalendar.time(start.addingTimeInterval(duration)))"
    }

    // MARK: - Статус дела (профиль Платони)

    private var moneyText: String? {
        guard event.moneyDirection != .none, event.moneyAmount > 0 else { return nil }
        let sign = event.moneyDirection == .profit ? "+" : "−"
        let type = event.moneyType.isEmpty ? "" : " · \(event.moneyType)"
        return "\(sign)\(PlannerPricing.format(event.moneyAmount))\(type)"
    }

    private var ownerStatusSection: some View {
        Section {
            HStack(spacing: 8) {
                statusButton("✅\nСделано", color: .green, active: myStatus == .done) { setStatus(.done) }
                statusButton("❌\nНе сделано", color: .red, active: myStatus == .notDone) { setStatus(.notDone) }
                statusButton("↪️\nПеренос", color: .gray, active: isMovedStatus) {
                    moveTarget = PlannerCalendar.combine(day: PlannerCalendar.addDays(1, to: day), time: event.start)
                    showMoveSheet = true
                }
            }
            .buttonStyle(.borderless)
            if case .moved(let target) = myStatus {
                Text("Перенесено на \(PlannerCalendar.dayTitle(target)), \(PlannerCalendar.time(target))")
                    .font(.footnote.weight(.semibold))
            }
            if myStatus != nil {
                Button("Снять отметку", role: .destructive) { setStatus(nil) }
                    .font(.footnote)
            }
            if let moneyText {
                LabeledContent("Деньги", value: moneyText)
                    .foregroundStyle(event.moneyDirection == .profit ? Color.green : Color.red)
            }
        } header: {
            Text("Статус")
        } footer: {
            if moneyText != nil {
                Text("Деньги попадают в статистику, когда дело отмечено «Сделано».")
            }
        }
        .disabled(!canEdit)
    }

    private var isMovedStatus: Bool {
        if case .moved = myStatus { return true }
        return false
    }

    private func statusButton(_ title: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(active ? 0.55 : 0.15)))
                .foregroundStyle(Color.primary)
        }
    }

    private func setStatus(_ status: PlannerErrandStatus?) {
        // Если отменяется перенос, новая запись в новом дне удаляется.
        PlannerErrandCarry.revoke(event, day: day, context: context)
        event.setStatus(status, on: day, for: account.current)
        event.markChanged()
        try? context.save()
        sync.requestSync()
    }

    private var moveSheet: some View {
        NavigationStack {
            Form {
                Section {
                    quickMove("Завтра (то же время)", days: 1)
                    Button {
                        showMoveSheet = false
                        dismiss()
                        onCarry()
                    } label: {
                        Label("Выбрать место в журнале", systemImage: "hand.tap")
                    }
                } header: {
                    Text("Быстро")
                } footer: {
                    Text("В журнале выбери день и нажми пальцем на нужное время.")
                }
            }
            .navigationTitle("Перенос дела")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showMoveSheet = false } }
            }
        }
        .presentationDetents([.medium])
        .environment(\.locale, PlannerCalendar.locale)
    }

    private func quickMove(_ title: String, days: Int) -> some View {
        Button(title) {
            moveTarget = PlannerCalendar.combine(day: PlannerCalendar.addDays(days, to: day), time: event.start)
            performMove()
        }
    }

    /// Старый день остаётся белым с пометкой, а на новом дне появляется такая же запись.
    private func performMove() {
        PlannerErrandCarry.carry(event, day: day, to: moveTarget, context: context)
        sync.requestSync()
        showMoveSheet = false
        dismiss()
    }

    // MARK: - Отмена и штрафы

    private var finesSection: some View {
        Section {
            Label("Занятие отменено", systemImage: "nosign")
                .foregroundStyle(.secondary)
            ForEach(participants) { client in
                PlannerFineRow(
                    name: client.name,
                    method: method(of: client),
                    amount: dayPayments.first { $0.clientID == client.id }?.amount
                        ?? PlannerPaymentStore.price(for: event, context: context),
                    canEdit: canEdit,
                    onSelect: { select($0, for: client) },
                    onAmount: { setAmount($0, for: client) }
                )
            }
        } header: {
            Text("🚫 Отмена")
        } footer: {
            Text("Без отметки это отмена без штрафа. Штраф идёт в прибыль, неоплаченный попадает в статистику отмен.")
        }
    }

    private func cancelOccurrence() {
        PlannerPaymentStore.purge(context, eventID: event.syncID, day: day)
        event.setCancelled(true, on: day)
        event.markChanged()
        try? context.save()
        sync.requestSync()
    }

    private func restoreOccurrence() {
        PlannerPaymentStore.purge(context, eventID: event.syncID, day: day)
        event.setCancelled(false, on: day)
        event.markChanged()
        try? context.save()
        sync.requestSync()
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
                        ?? groupPrice,
                    balanceText: balances[client.id],
                    canEdit: canEdit,
                    isGroup: event.categoryValue != .personal,
                    hasSubscription: covered.contains(client.id),
                    onSelect: { select($0, for: client) },
                    onSubscription: { subscriptionClient = client },
                    onAmount: { setAmount($0, for: client) }
                )
            }
        } header: {
            Text("Оплата")
        } footer: {
            if canEdit && !participants.isEmpty {
                Text("Нажми на кружок и выбери, как оплатили.")
            }
        }
    }

    /// Один раз считаем остатки абонементов, действие абонемента и цену (раньше это делалось
    /// для каждого ребёнка при каждой перерисовке и подвешивало приложение).
    private func refreshDerived() {
        groupPrice = PlannerPaymentStore.price(for: event, context: context)
        let ids = Set(participants.map(\.id))
        guard !ids.isEmpty else { balances = [:]; covered = []; return }
        let monthStart = PlannerCalendar.startOfMonth(day)
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let subMethod = PlannerPayMethod.subscription.rawValue
        var spent: [UUID: Double] = [:]
        let rows = (try? context.fetch(FetchDescriptor<PlannerPayment>(predicate: #Predicate {
            $0.deletedAt == nil && $0.method == subMethod && $0.day >= monthStart && $0.day < monthEnd
        }))) ?? []
        for row in rows where ids.contains(row.clientID) { spent[row.clientID, default: 0] += row.amount }
        var texts: [UUID: String] = [:]
        var cover: Set<UUID> = []
        var applies: [String: Bool] = [:]
        for sub in subscriptions where ids.contains(sub.clientID) {
            if cal.isDate(sub.month, equalTo: monthStart, toGranularity: .month) {
                texts[sub.clientID] = "Абонемент: остаток \(PlannerPricing.format(sub.amount - (spent[sub.clientID] ?? 0)))"
            }
            guard sub.covers(day) else { continue }
            let ok: Bool
            if let known = applies[sub.kindName] { ok = known } else {
                ok = PlannerSubscriptionTypeStore.applies(sub, to: event, context: context)
                applies[sub.kindName] = ok
            }
            if ok { cover.insert(sub.clientID) }
        }
        balances = texts
        covered = cover
    }

    private var paymentsSignature: String {
        payments.map { "\($0.clientID)\($0.method)\($0.amount)\($0.day.timeIntervalSince1970)" }.joined(separator: "|")
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
                // Время записи YClients приходит из журнала, поэтому её нельзя двигать и менять.
                if !event.isFromYClients {
                    Button {
                        dismiss()
                        onMove()
                    } label: {
                        Label("Переместить", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                    Button {
                        dismiss()
                        onEdit()
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
                }
                if showsPayments {
                    if isCancelled {
                        Button(action: restoreOccurrence) {
                            Label("Вернуть занятие", systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button(role: .destructive, action: cancelOccurrence) {
                            Label("Отменить занятие", systemImage: "nosign")
                        }
                    }
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

/// Строка клиента в отменённом занятии: без штрафа, штраф наличными, переводом или не оплачен.
private struct PlannerFineRow: View {
    let name: String
    let method: PlannerPayMethod
    let amount: Double
    let canEdit: Bool
    let onSelect: (PlannerPayMethod) -> Void
    let onAmount: (Double) -> Void

    @State private var amountText = ""

    private let options: [(PlannerPayMethod, String, String)] = [
        (.none, "🚫", "Без штрафа"),
        (.cash, "💰", "Нал"),
        (.transfer, "🏦", "Перевод"),
        (.unpaid, "⏳", "Не оплачен"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.body.weight(.medium))
            HStack(spacing: 6) {
                ForEach(0..<options.count, id: \.self) { index in
                    let item = options[index]
                    let selected = method == item.0
                    Button { onSelect(item.0) } label: {
                        VStack(spacing: 2) {
                            Text(item.1).font(.title3)
                            Text(item.2).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.appAccent.opacity(0.3) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canEdit)
                }
            }
            if method != .none {
                HStack {
                    Text("Штраф")
                    Spacer()
                    TextField("0", text: $amountText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit { if let value = Double(amountText) { onAmount(value) } }
                    Text("₽").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .onAppear { amountText = "\(Int(amount.rounded()))" }
        .onChange(of: amountText) { _, text in
            if let value = Double(text), abs(value - amount) > 0.001 { onAmount(value) }
        }
    }
}
