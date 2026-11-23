import SwiftData
import SwiftUI

/// Журнал «Личный» (мои записи и общие) или «Общий» (записи обоих).
/// Главный вид: время по часам. Кнопка в углу переключает на обычный календарь-месяц.
struct PlannerCalendarView: View {
    enum Mode: String { case month, week }
    /// Журнал по времени или обычный календарь-месяц.
    enum Style: String { case planner, calendar }

    /// `true` — планнер партнёра (его дела, кроме скрытых галочкой), `false` — мои и общие.
    let showsPartner: Bool

    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var allEvents: [PlannerEvent]
    @Query(filter: #Predicate<PlannerPayment> { $0.deletedAt == nil })
    private var payments: [PlannerPayment]
    @State private var showSale = false
    @Query(filter: #Predicate<PlannerShift> { $0.deletedAt == nil })
    private var shifts: [PlannerShift]
    @Query(filter: #Predicate<PlannerMoneyOp> { $0.deletedAt == nil })
    private var moneyOps: [PlannerMoneyOp]
    @Query(filter: #Predicate<MoodDayCheckIn> { $0.deletedAt == nil })
    private var moodCheckIns: [MoodDayCheckIn]
    @AppStorage("planner.shiftAmount") private var shiftAmount: Double = PlannerShift.defaultAmount
    /// Режим «Смены»: нажатие на день ставит или снимает смену.
    @State private var shiftMode = false
    @Query(filter: #Predicate<PlannerErrandKind> { $0.deletedAt == nil })
    private var errandKinds: [PlannerErrandKind]
    @State private var shiftEdit: ShiftEditTarget?
    /// Несколько записей в одном времени: меню снизу, чтобы выбрать нужную.
    @State private var pickChoices: [PlannerPickChoice] = []
    @State private var showPick = false
    /// Глазик: скрыть отменённые, перенесённые и «не сделано» (записи не удаляются).
    @AppStorage("planner.hideCancelled") private var hideCancelled = false

    private struct ShiftEditTarget: Identifiable {
        let day: Date
        var id: Date { day }
    }
    @Query(filter: #Predicate<PlannerStatusStyle> { $0.deletedAt == nil })
    private var statusStyles: [PlannerStatusStyle]
    @Query(filter: #Predicate<PlannerColorRule> { $0.deletedAt == nil })
    private var colorRules: [PlannerColorRule]
    @Query(filter: #Predicate<PlannerSubscription> { $0.deletedAt == nil })
    private var subscriptions: [PlannerSubscription]

    @AppStorage("planner.mode") private var mode: Mode = .month
    @AppStorage("planner.style") private var style: Style = .planner
    /// В журнале: открыт один день вместо недели.
    @AppStorage("planner.dayFocus") private var dayFocus = false
    @State private var selectedDay = PlannerCalendar.calendar.startOfDay(for: .now)
    @State private var sheetTarget: SheetTarget?
    @State private var externalDetail: CalendarItem?
    /// Запись, которую сейчас переносят: нужно выбрать новое время.
    @State private var moving: MovingState?
    /// Перенос записи другого раздела (например, ремонта авто): тоже касанием по журналу.
    @State private var movingExternal: CalendarItem?
    /// Элементы из других разделов (например, записи клиентов).
    @State private var externalItems: [CalendarItem] = []

    private struct SheetTarget: Identifiable {
        enum Kind { case detail, edit }
        let id = UUID()
        let kind: Kind
        let event: PlannerEvent?
        let day: Date
        var time: Date? = nil
    }

    private struct MovingState {
        let event: PlannerEvent
        let occurrenceStart: Date
        /// `true` — «Перенос» дела (белый след и статистика), `false` — просто «Переместить».
        var isCarry = false
    }

    private var cal: Calendar { PlannerCalendar.calendar }

    private var events: [PlannerEvent] {
        // Записи с галочкой «Не показывать партнёру» видит только автор.
        let visible = allEvents.filter { event in
            guard event.isPrivate else { return true }
            let author = event.scopeValue.member ?? CoupleMember(rawValue: event.createdBy) ?? .owner
            return author == account.current
        }
        // Планнер партнёра: его личные записи и общие (скрытые уже отфильтрованы выше).
        let owner = showsPartner ? account.current.other : account.current
        let scope = PlannerScope.personal(owner)
        return visible.filter { $0.scopeValue == .shared || $0.scopeValue == scope }
    }

    /// Чьи записи из других разделов показаны: свои или (в режиме наблюдателя) партнёра.
    private var viewedMember: CoupleMember { showsPartner ? account.current.other : account.current }

    /// Двигать и править запись другого раздела может только её владелец.
    private func canEditExternal(_ item: CalendarItem) -> Bool {
        !showsPartner && (item.member == account.current || item.sharedWith.contains(account.current))
    }

    /// Свои записи из других разделов.
    private func items(on day: Date) -> [CalendarItem] {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = PlannerCalendar.addDays(1, to: dayStart)
        return externalItems
            .filter { ($0.member == nil || $0.member == viewedMember || $0.sharedWith.contains(viewedMember)) && $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }
    }

    private var days: [Date] {
        if style == .planner {
            return dayFocus ? [cal.startOfDay(for: selectedDay)] : PlannerCalendar.week(containing: selectedDay)
        }
        return mode == .month ? PlannerCalendar.monthGrid(selectedDay) : PlannerCalendar.week(containing: selectedDay)
    }

    /// Меняется при листании и после синхронизации: тогда перечитываем записи других разделов.
    private var refreshKey: String {
        let first = days.first?.timeIntervalSince1970 ?? 0
        let synced = sync.lastSyncedAt?.timeIntervalSince1970 ?? 0
        return "\(first)-\(days.count)-\(synced)-\(allEvents.count)"
    }

    private func refresh() {
        guard let first = days.first, let last = days.last else { return }
        let interval = DateInterval(start: first, end: PlannerCalendar.addDays(1, to: last))
        // Записи настроения в журнал не попадают: у дня просто смайлик.
        externalItems = FeatureRegistry.calendarItems(context: context, interval: interval)
            .filter { !$0.id.hasPrefix("mood.") }
        // Тренировки клиентов с абонементом списываются сами.
        PlannerPaymentStore.autoCharge(context, events: allEvents, days: days)
    }

    /// Оплаты, разложенные по записям: строится один раз за перерисовку, а не для каждого блока.
    private final class PaymentIndex {
        var byEvent: [UUID: [PlannerPayment]] = [:]
    }
    @State private var paymentIndex = PaymentIndex()

    var body: some View {
        let _ = { paymentIndex.byEvent = Dictionary(grouping: payments, by: \.eventID) }()
        Group {
            if style == .planner {
                plannerBody
            } else {
                calendarBody
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let moving {
                movingBanner(moving)
            } else if let movingExternal {
                externalMovingBanner(movingExternal)
            }
        }
        .task(id: refreshKey) { refresh() }
        .task {
            // Разовые починки данных: не на старте, один раз, с флагом «выполнено».
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: "planner.dataRepair.v2") else { return }
            defaults.set(true, forKey: "planner.dataRepair.v2")
            try? await Task.sleep(for: .seconds(4))
            var changed = PlannerGroupKindStore.repairTypedDuplicates(context)
            let kinds = (try? context.fetch(FetchDescriptor<PlannerGroupKind>())) ?? []
            for kind in kinds where kind.deletedAt == nil && !kind.memberIDs.isEmpty {
                if PlannerGroupKindStore.propagate(context, kind: kind, ids: kind.memberIDs) { changed = true }
            }
            if changed { sync.requestSync() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Сегодня") {
                    withAnimation { selectedDay = cal.startOfDay(for: .now) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 2) {
                    Button {
                        withAnimation { style = style == .planner ? .calendar : .planner }
                    } label: {
                        Image(systemName: style == .planner ? "calendar" : "calendar.day.timeline.left")
                    }
                    .accessibilityLabel(style == .planner ? "Обычный календарь" : "Журнал по времени")
                    Button { showSale = true } label: {
                        Image(systemName: "dollarsign.circle.fill")
                    }
                    .disabled(showsPartner)
                    .accessibilityLabel(account.current == .owner ? "Приход денег" : "Продать абонемент")
                    Button {
                        sheetTarget = SheetTarget(kind: .edit, event: nil, day: selectedDay)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(showsPartner)
                    .accessibilityLabel(account.current == .partner ? "Новая тренировка" : "Новое событие")
                }
            }
        }
        .sheet(item: $sheetTarget) { target in
            sheetContent(target)
        }
        .sheet(item: $externalDetail, onDismiss: { refresh() }) { item in
            Group {
                if let detail = item.detail { detail() } else { EmptyView() }
            }
            .safeAreaInset(edge: .bottom) {
                if canEditExternal(item), item.move != nil {
                    Button {
                        externalDetail = nil
                        withAnimation { movingExternal = item }
                    } label: {
                        Label("Перенести", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showPick) {
            PlannerPickSheet(choices: pickChoices) { choice in
                showPick = false
                DispatchQueue.main.async { choice.open() }
            }
            .presentationDetents([.height(CGFloat(120 + min(pickChoices.count, 6) * 64)), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $shiftEdit) { target in
            PlannerShiftSheet(day: target.day, defaultAmount: shiftAmount)
        }
        .sheet(isPresented: $showSale) {
            if account.current == .owner {
                PlannerMoneyOpSheet(day: selectedDay)
            } else {
                PlannerSubscriptionSaleSheet(month: selectedDay)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ target: SheetTarget) -> some View {
        switch target.kind {
        case .detail:
            if let event = target.event {
                PlannerRecordView(
                    event: event,
                    day: target.day,
                    onEdit: {
                        afterSheet { sheetTarget = SheetTarget(kind: .edit, event: event, day: target.day) }
                    },
                    onMove: {
                        afterSheet {
                            let start = PlannerCalendar.combine(day: target.day, time: event.start)
                            moving = MovingState(event: event, occurrenceStart: event.isAllDay ? target.day : start)
                            style = .planner
                            selectedDay = target.day
                        }
                    },
                    onCarry: {
                        afterSheet {
                            let start = PlannerCalendar.combine(day: target.day, time: event.start)
                            moving = MovingState(event: event, occurrenceStart: event.isAllDay ? target.day : start, isCarry: true)
                            style = .planner
                            selectedDay = target.day
                        }
                    },
                    readOnly: showsPartner
                )
            }
        case .edit:
            if PlannerTrainingEditor.shouldUse(for: target.event, me: account.current) {
                PlannerTrainingEditor(event: target.event, day: target.day, at: target.time)
            } else {
                PlannerEventEditor(event: target.event, day: target.day, at: target.time)
            }
        }
    }

    /// Дать закрыться текущему листу, потом сделать следующее действие.
    private func afterSheet(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    // MARK: - Перенос

    private func movingBanner(_ moving: MovingState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            VStack(alignment: .leading, spacing: 1) {
                Text(moving.isCarry ? "Куда перенести дело?" : "Куда переместить?").font(.subheadline.weight(.semibold))
                Text("Нажми на любое время или день: «\(moving.event.displayTitle)»")
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            Button("Отмена") { withAnimation { self.moving = nil } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.2))
        .foregroundStyle(Color.primary)
    }

    private func externalMovingBanner(_ item: CalendarItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            VStack(alignment: .leading, spacing: 1) {
                Text("Куда перенести?").font(.subheadline.weight(.semibold))
                Text("Нажми на любое время или день: «\(item.title)»")
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            Button("Отмена") { withAnimation { self.movingExternal = nil } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.2))
        .foregroundStyle(Color.primary)
    }

    private func finishExternalMove(to start: Date) {
        guard let item = movingExternal else { return }
        item.move?(start)
        sync.requestSync()
        withAnimation {
            movingExternal = nil
            selectedDay = cal.startOfDay(for: start)
        }
        refresh()
    }

    private func finishMove(to start: Date) {
        guard let moving else { return }
        if moving.isCarry {
            PlannerErrandCarry.carry(moving.event, day: moving.occurrenceStart, to: start, context: context)
        } else {
            PlannerMover.move(moving.event, occurrenceStart: moving.occurrenceStart, to: start, context: context)
        }
        sync.requestSync()
        withAnimation {
            self.moving = nil
            selectedDay = cal.startOfDay(for: start)
        }
    }

    private func moveByDrag(_ event: PlannerEvent, from occurrenceStart: Date, to start: Date) {
        guard !showsPartner else { return }
        PlannerMover.move(event, occurrenceStart: occurrenceStart, to: start, context: context)
        sync.requestSync()
    }

    // MARK: - Журнал по времени

    private func ownerLetter(_ event: PlannerEvent) -> String? {
        guard showsPartner else { return nil }
        let member = event.scopeValue.member ?? CoupleMember(rawValue: event.createdBy) ?? .owner
        return account.name(of: member).prefix(1).uppercased()
    }

    /// Сколько денег уже оплачено за сегодня.
    private var todayEarned: Double {
        if isOwner {
            let entries = PlannerLedger.entries(events: allEvents, shifts: shifts, ops: moneyOps)
            return PlannerLedger.income(on: .now, entries: entries)
        }
        let map = PlannerPaymentStore.eventMap(allEvents)
        let cash = payments
            .filter {
                ($0.methodValue == .cash || $0.methodValue == .transfer)
                    && PlannerPaymentStore.isLive($0, events: map) && cal.isDateInToday($0.day)
            }
            .reduce(0) { $0 + $1.amount }
        let sold = subscriptions
            .filter { cal.isDateInToday($0.soldAt) }
            .reduce(0) { $0 + $1.amount }
        return cash + sold
    }

    private var plannerBody: some View {
        VStack(spacing: 0) {
            HStack {
                Button { movePlanner(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                if dayFocus {
                    Button {
                        withAnimation { dayFocus = false }
                    } label: {
                        Label("Неделя", systemImage: "rectangle.split.3x1")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Text(PlannerCalendar.monthTitle(selectedDay))
                    .font(.headline)
                Spacer()
                Button { movePlanner(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .overlay {
                // Глазик «Скрыть»: на высоте месяца и года, над субботой (в дневном режиме правее).
                GeometryReader { geo in
                    let timeColumn: CGFloat = 44
                    let column = (geo.size.width - timeColumn) / 7
                    Button { withAnimation { hideCancelled.toggle() } } label: {
                        Image(systemName: hideCancelled ? "eye.slash" : "eye.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(hideCancelled ? Color.secondary : Color.plannerToday)
                            .frame(width: 36, height: 30)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(hideCancelled ? "Показать отменённые и перенесённые" : "Скрыть отменённые и перенесённые")
                    .position(x: dayFocus ? geo.size.width - 52 : timeColumn + column * 5.5,
                              y: geo.size.height / 2)
                }
            }
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40 { movePlanner(1) }
                if value.translation.width > 40 { movePlanner(-1) }
            })

            PlannerTimelineView(
                days: days,
                isDayMode: dayFocus,
                events: events,
                colorFor: { event, day in blockColor(event, day) },
                externalItems: { items(on: $0) },
                onExternalTap: { item in
                    let choices = choicesAt(start: item.start, end: item.end, day: item.start)
                    if choices.count > 1 {
                        pickChoices = choices
                        showPick = true
                    } else {
                        externalDetail = item
                    }
                },
                canMoveExternal: { item in canEditExternal(item) && item.move != nil },
                onExternalMove: { item, newStart in
                    item.move?(newStart)
                    sync.requestSync()
                    refresh()
                },
                shiftDays: shiftDays,
                shiftParts: shiftParts,
                errandEmojis: errandEmojis,
                onShiftHold: { day in
                    if isOwner && !showsPartner { shiftEdit = ShiftEditTarget(day: day) }
                },
                badgeEmoji: { event, day in styledEmoji(event, day) },
                isHidden: { event, day in isHiddenByEye(event, day) },
                dayMark: { moodMark($0) },
                badge: { event, day in blockBadge(event, day) },
                ownerLetter: { ownerLetter($0) },
                canMove: { $0.scopeValue.canEdit(by: account.current) && !$0.isFromYClients },
                onHeaderTap: { day in
                    withAnimation(.snappy) {
                        selectedDay = day
                        dayFocus.toggle()
                    }
                },
                onSlotTap: { start in
                    // Чужой журнал только для просмотра.
                    if showsPartner { return }
                    if moving != nil {
                        finishMove(to: start)
                    } else if movingExternal != nil {
                        finishExternalMove(to: start)
                    } else {
                        selectedDay = cal.startOfDay(for: start)
                        sheetTarget = SheetTarget(kind: .edit, event: nil, day: start, time: start)
                    }
                },
                onEventTap: { event, day in
                    guard moving == nil, movingExternal == nil else { return }
                    guard let tapped = events.occurrences(on: cal.startOfDay(for: day)).first(where: { $0.event === event }) else {
                        sheetTarget = SheetTarget(kind: .detail, event: event, day: day)
                        return
                    }
                    let choices = choicesAt(start: tapped.start, end: tapped.end, day: day)
                    if choices.count > 1 {
                        pickChoices = choices
                        showPick = true
                    } else {
                        sheetTarget = SheetTarget(kind: .detail, event: event, day: day)
                    }
                },
                onMove: { event, from, to in moveByDrag(event, from: from, to: to) },
                onSwipe: { movePlanner($0) }
            )
            .overlay(alignment: .bottomTrailing) {
                Text("Сегодня 💰 \(Int(todayEarned)) ₽")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Профиль Платони: статусы дел, смены, настроение

    private var isOwner: Bool { account.current == .owner }

    /// Смены Платони: он видит их в своём планнере, Настенька только в планнере партнёра.
    private var shiftDays: Set<Date> {
        let viewingOwner = (account.current == .owner) != showsPartner
        guard viewingOwner else { return [] }
        return Set(shifts.map { cal.startOfDay(for: $0.day) })
    }

    /// Цвета типов дел (если заданы) у текущего человека.
    private var errandColors: [String: String] {
        var result: [String: String] = [:]
        for kind in errandKinds where kind.member == account.current && !kind.colorHex.isEmpty {
            result[kind.name.lowercased()] = kind.colorHex
        }
        return result
    }

    /// Эмодзи типов дел для журнала: у текущего человека, иначе чемодан.
    private var errandEmojis: [String: String] {
        var result: [String: String] = [:]
        for kind in errandKinds where kind.member == account.current { result[kind.name.lowercased()] = kind.displayEmoji }
        return result
    }

    /// Все записи (и дела, и ремонты и т. п.), которые идут в этом промежутке времени.
    private func choicesAt(start: Date, end: Date, day: Date) -> [PlannerPickChoice] {
        var result: [PlannerPickChoice] = []
        let dayStart = cal.startOfDay(for: day)
        for occurrence in events.occurrences(on: dayStart)
            where !occurrence.event.isAllDay && !isHiddenByEye(occurrence.event, day) && occurrence.start < end && occurrence.end > start {
            result.append(PlannerPickChoice(
                id: occurrence.id, title: occurrence.event.plainTitle,
                start: occurrence.start, end: occurrence.end,
                color: blockColor(occurrence.event, day), symbol: "calendar",
                open: { sheetTarget = SheetTarget(kind: .detail, event: occurrence.event, day: day) }))
        }
        for item in items(on: day) where item.detail != nil && item.start < end && item.end > start {
            result.append(PlannerPickChoice(
                id: item.id, title: item.title, start: item.start, end: item.end,
                color: item.color, symbol: item.systemImage, open: { externalDetail = item }))
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Записи, которые идут одновременно с нажатой (для выбора, если в одном месте их несколько).
    private func overlappingOccurrences(of event: PlannerEvent, at time: Date) -> [PlannerOccurrence] {
        let occurrences = events.occurrences(on: cal.startOfDay(for: time)).filter { !$0.event.isAllDay }
        guard let tapped = occurrences.first(where: { $0.event === event }) else { return [] }
        return occurrences.filter { $0.start < tapped.end && $0.end > tapped.start }
    }

    /// Часть смены по дням: 0 — вся, 1 — первая половина, 2 — вторая.
    private var shiftParts: [Date: Int] {
        var result: [Date: Int] = [:]
        for shift in shifts { result[cal.startOfDay(for: shift.day)] = shift.part }
        return result
    }

    /// Смайлики настроения за день: свой и партнёра (виден обоим).
    private func moodMark(_ day: Date) -> String {
        let rows = moodCheckIns.filter { cal.isDate($0.day, inSameDayAs: day) }
        let mine = rows.first { $0.coupleMember == account.current }
        let other = rows.first { $0.coupleMember != account.current }
        return [mine, other].compactMap { $0?.level.emoji }.joined()
    }

    private func blockColor(_ event: PlannerEvent, _ day: Date) -> Color {
        var base = PlannerColorStore.color(for: event, rules: colorRules)
        if event.colorHex.isEmpty, !event.errandType.isEmpty,
           let hex = errandColors[event.errandType.lowercased()], let typeColor = Color(hex: hex) {
            base = typeColor
        }
        guard viewedMember == .owner || event.categoryValue == .errand else { return base }
        let current = event.status(on: day, for: viewedMember)
        let hex = PlannerStatusStyleStore.resolve(statusStyles, errandType: event.errandType, status: current,
                                                         sharedMember: event.scopeValue == .shared ? viewedMember.rawValue : nil).colorHex
        if !hex.isEmpty, let custom = Color(hex: hex) { return custom }
        guard let status = current else { return base }
        switch status {
        case .done: return Color.green.opacity(0.75)
        case .notDone: return Color.red.opacity(0.65)
        case .moved: return Color.white
        }
    }

    /// Режим «глазик»: прячем отменённые, перенесённые (белые) и «не сделано».
    private func isHiddenByEye(_ event: PlannerEvent, _ day: Date) -> Bool {
        guard hideCancelled else { return false }
        if [.cancelled, .fineUnpaid, .finePaid, .errandNotDone, .errandMoved].contains(blockBadge(event, day)) { return true }
        switch event.status(on: day, for: viewedMember) {
        case .notDone?, .moved?: return true
        default: break
        }
        return false
    }

    private func styledEmoji(_ event: PlannerEvent, _ day: Date) -> String? {
        guard viewedMember == .owner || event.categoryValue == .errand else { return nil }
        let r = PlannerStatusStyleStore.resolve(statusStyles, errandType: event.errandType,
                                                status: event.status(on: day, for: viewedMember),
                                                sharedMember: event.scopeValue == .shared ? viewedMember.rawValue : nil)
        if r.hideEmoji { return "" }
        return r.emoji.isEmpty ? nil : r.emoji
    }

    private func blockBadge(_ event: PlannerEvent, _ day: Date) -> PlannerPayBadge {
        guard viewedMember == .owner || event.categoryValue == .errand else {
            return PlannerPaymentStore.badge(for: event, day: day, payments: paymentIndex.byEvent[event.syncID] ?? [])
        }
        switch event.status(on: day, for: viewedMember) {
        case .done: return .errandDone
        case .notDone: return .errandNotDone
        case .moved: return .errandMoved
        case nil: return .none
        }
    }

    private func movePlanner(_ step: Int) {
        withAnimation {
            selectedDay = PlannerCalendar.addDays(step * (dayFocus ? 1 : 7), to: cal.startOfDay(for: selectedDay))
        }
    }

    // MARK: - Обычный календарь

    private var calendarBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if shiftMode && isOwner {
                    Text("Нажимай на дни, чтобы поставить или снять смену: 9:00–21:00, \(PlannerPricing.format(shiftAmount)) за день.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                grid
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width < -40 { move(1) }
                        if value.translation.width > 40 { move(-1) }
                    })
                Divider()
                dayList
            }
            .padding()
        }
        .refreshable { await sync.syncNow() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(PlannerCalendar.monthTitle(selectedDay))
                .font(.title3.bold())
            Spacer()
            Button {
                withAnimation { mode = mode == .month ? .week : .month }
            } label: {
                Image(systemName: mode == .month ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .accessibilityLabel(mode == .month ? "Показать неделю" : "Показать месяц")
            if isOwner {
                Button {
                    withAnimation { shiftMode.toggle() }
                } label: {
                    Label("Смены", systemImage: shiftMode ? "checkmark.circle.fill" : "briefcase")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(shiftMode ? Color.red.opacity(0.25) : Color.secondary.opacity(0.15)))
                }
                .accessibilityLabel("Расставить смены")
            }
            Button { move(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }

    private func move(_ step: Int) {
        let component: Calendar.Component = mode == .month ? .month : .weekOfYear
        guard let next = cal.date(byAdding: component, value: step, to: selectedDay) else { return }
        withAnimation {
            selectedDay = mode == .month ? PlannerCalendar.startOfMonth(next) : cal.startOfDay(for: next)
        }
    }

    // MARK: - Сетка

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let month = cal.component(.month, from: selectedDay)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(PlannerCalendar.weekdaySymbols, id: \.self) { symbol in
                Text(symbol.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                dayCell(day, inMonth: mode == .week || cal.component(.month, from: day) == month)
            }
        }
    }

    private func dayCell(_ day: Date, inMonth: Bool) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let dayEvents = events.occurrences(on: day)
        let colors = Array(dayEvents.map(\.event.categoryValue.color).prefix(3))
        let isBusy = !items(on: day).isEmpty
        let shiftPart = shiftParts[cal.startOfDay(for: day)]
        let isShift = shiftPart != nil && shiftDays.contains(cal.startOfDay(for: day))
        let mood = moodMark(day)

        let tapAction: () -> Void = {
            if shiftMode && isOwner && !showsPartner {
                PlannerShiftStore.toggle(context, day: day, amount: shiftAmount)
                sync.requestSync()
            } else if let item = movingExternal {
                finishExternalMove(to: PlannerCalendar.combine(day: day, time: item.start))
            } else if let moving {
                // Перенос на другой день: то же время суток.
                let time = PlannerCalendar.combine(day: day, time: moving.occurrenceStart)
                finishMove(to: moving.event.isAllDay ? day : time)
            } else {
                withAnimation(.snappy) { selectedDay = day }
            }
        }

        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: day))")
                .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(isToday ? Color.plannerToday : Color.primary)
                    } else if isToday {
                        Circle().stroke(Color.plannerToday, lineWidth: 1.5)
                    }
                }
                .background {
                    // Смена: полный кружок вокруг даты, половина смены: левая или правая половинка.
                    if isShift, let part = shiftPart {
                        PlannerShiftDisc(part: part)
                            .fill(Color.red.opacity(0.4))
                    }
                }
                .foregroundStyle(isSelected ? Color(.systemBackground) : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
            HStack(spacing: 3) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
                if isBusy {
                    Circle().fill(Color.gray).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
            Text(mood).font(.system(size: 10)).frame(height: 12)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(
                isToday ? Color.plannerToday.opacity(0.18) : Color.clear
            )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: tapAction)
        .onLongPressGesture(minimumDuration: 0.6) {
            if isOwner && !showsPartner { shiftEdit = ShiftEditTarget(day: day) }
        }
    }

    // MARK: - Список на день

    private var dayList: some View {
        let occurrences = events.occurrences(on: selectedDay)
        let dayItems = items(on: selectedDay)

        return VStack(alignment: .leading, spacing: 10) {
            Text(PlannerCalendar.dayTitle(selectedDay))
                .font(.headline)

            if occurrences.isEmpty && dayItems.isEmpty {
                VStack(spacing: 8) {
                    Text("Ничего не запланировано")
                        .foregroundStyle(.secondary)
                    if !showsPartner {
                        Button(account.current == .partner ? "Добавить тренировку" : "Добавить событие") {
                            sheetTarget = SheetTarget(kind: .edit, event: nil, day: selectedDay)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            ForEach(occurrences) { occurrence in
                Button {
                    sheetTarget = SheetTarget(kind: .detail, event: occurrence.event, day: selectedDay)
                } label: {
                    PlannerEventRow(
                        occurrence: occurrence,
                        day: selectedDay,
                        badge: blockBadge(occurrence.event, selectedDay)
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(dayItems) { item in
                if item.detail != nil {
                    Button { externalDetail = item } label: { PlannerExternalItemRow(item: item) }
                        .buttonStyle(.plain)
                } else {
                    PlannerExternalItemRow(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка события в списке дня.
struct PlannerEventRow: View {
    @Environment(AccountStore.self) private var account
    let occurrence: PlannerOccurrence
    let day: Date
    var badge: PlannerPayBadge = .none

    private var event: PlannerEvent { occurrence.event }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.categoryValue.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if event.isFromYClients { ClientsYClientsBadge(size: 14) }
                    Text(event.isFromYClients ? event.plainTitle : event.displayTitle)
                        .font(.body.weight([.cancelled, .fineUnpaid, .finePaid].contains(badge) ? .heavy : .medium))
                }
                HStack(spacing: 6) {
                    Text(timeText)
                    if event.repeatValue != .none {
                        Image(systemName: "repeat")
                    }
                    if event.reminderMinutes >= 0 {
                        Image(systemName: "bell")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let symbol = badge.symbol, ![.cancelled, .fineUnpaid, .finePaid].contains(badge) {
                Text(symbol)
            }
            Text(event.scopeValue.title(account))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(event.categoryValue.color.opacity(0.15)))
        }
        .padding(10)
        .background(
            Group {
                if event.isFromYClients {
                    // Записи YClients: прозрачный жёлтый фон с обводкой.
                    RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.yellow))
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
                }
            }
        )
        .overlay {
            // Отменённое занятие или группа: большой знак запрета поверх бледной записи.
            if [.cancelled, .fineUnpaid, .finePaid].contains(badge) {
                Text("🚫").font(.system(size: 44)).opacity(0.75).allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
    }

    private var timeText: String {
        if event.isAllDay { return "Весь день" }
        let cal = PlannerCalendar.calendar
        let startsToday = cal.isDate(occurrence.start, inSameDayAs: day)
        let endsToday = cal.isDate(occurrence.end, inSameDayAs: day)
        switch (startsToday, endsToday) {
        case (true, true): return "\(PlannerCalendar.time(occurrence.start))–\(PlannerCalendar.time(occurrence.end))"
        case (true, false): return "с \(PlannerCalendar.time(occurrence.start))"
        case (false, true): return "до \(PlannerCalendar.time(occurrence.end))"
        case (false, false): return "Весь день"
        }
    }
}

/// Запись из другого раздела (например, клиент): только для просмотра.
struct PlannerExternalItemRow: View {
    let item: CalendarItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text("\(PlannerCalendar.time(item.start))–\(PlannerCalendar.time(item.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Занят")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}


struct PlannerPickChoice: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let symbol: String
    let open: () -> Void
}

/// Красивое меню снизу: что открыть, если в одном времени несколько записей.
struct PlannerPickSheet: View {
    let choices: [PlannerPickChoice]
    let onPick: (PlannerPickChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Что открыть?")
                .font(.title3.weight(.bold))
                .padding(.top, 24)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(choices) { choice in
                        Button { onPick(choice) } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(choice.color)
                                    .frame(width: 6, height: 40)
                                Image(systemName: choice.symbol)
                                    .foregroundStyle(choice.color)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                    Text("\(PlannerCalendar.time(choice.start))–\(PlannerCalendar.time(choice.end))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
