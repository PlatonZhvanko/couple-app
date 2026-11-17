import SwiftData
import SwiftUI

/// Журнал «Личный» (мои записи и общие) или «Общий» (записи обоих).
/// Главный вид: время по часам. Кнопка в углу переключает на обычный календарь-месяц.
struct PlannerCalendarView: View {
    enum Mode: String { case month, week }
    /// Журнал по времени или обычный календарь-месяц.
    enum Style: String { case planner, calendar }

    /// `true` — записи обоих, `false` — мои и общие.
    let showsEveryone: Bool

    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var allEvents: [PlannerEvent]
    @Query(filter: #Predicate<PlannerPayment> { $0.deletedAt == nil })
    private var payments: [PlannerPayment]
    @State private var showSale = false

    @AppStorage("planner.mode") private var mode: Mode = .month
    @AppStorage("planner.style") private var style: Style = .planner
    /// В журнале: открыт один день вместо недели.
    @AppStorage("planner.dayFocus") private var dayFocus = false
    @State private var selectedDay = PlannerCalendar.calendar.startOfDay(for: .now)
    @State private var sheetTarget: SheetTarget?
    /// Запись, которую сейчас переносят: нужно выбрать новое время.
    @State private var moving: MovingState?
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
    }

    private var cal: Calendar { PlannerCalendar.calendar }

    private var events: [PlannerEvent] {
        guard !showsEveryone else { return allEvents }
        let me = PlannerScope.personal(account.current)
        return allEvents.filter { $0.scopeValue == .shared || $0.scopeValue == me }
    }

    /// Свои записи из других разделов.
    private func items(on day: Date) -> [CalendarItem] {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = PlannerCalendar.addDays(1, to: dayStart)
        return externalItems
            .filter { ($0.member == nil || $0.member == account.current) && $0.start < dayEnd && $0.end > dayStart }
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
        externalItems = FeatureRegistry.calendarItems(context: context, interval: interval)
        // Тренировки клиентов с абонементом списываются сами.
        PlannerPaymentStore.autoCharge(context, events: allEvents, days: days)
    }

    var body: some View {
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
            }
        }
        .task(id: refreshKey) { refresh() }
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
                    .accessibilityLabel("Продать абонемент")
                    Button {
                        sheetTarget = SheetTarget(kind: .edit, event: nil, day: selectedDay)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(account.current == .partner ? "Новая тренировка" : "Новое событие")
                }
            }
        }
        .sheet(item: $sheetTarget) { target in
            sheetContent(target)
        }
        .sheet(isPresented: $showSale) {
            PlannerSubscriptionSaleSheet(month: selectedDay)
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
                    }
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
                Text("Куда перенести?").font(.subheadline.weight(.semibold))
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

    private func finishMove(to start: Date) {
        guard let moving else { return }
        PlannerMover.move(moving.event, occurrenceStart: moving.occurrenceStart, to: start, context: context)
        sync.requestSync()
        withAnimation {
            self.moving = nil
            selectedDay = cal.startOfDay(for: start)
        }
    }

    private func moveByDrag(_ event: PlannerEvent, from occurrenceStart: Date, to start: Date) {
        PlannerMover.move(event, occurrenceStart: occurrenceStart, to: start, context: context)
        sync.requestSync()
    }

    // MARK: - Журнал по времени

    private func ownerLetter(_ event: PlannerEvent) -> String? {
        guard showsEveryone else { return nil }
        let member = event.scopeValue.member ?? CoupleMember(rawValue: event.createdBy) ?? .owner
        return account.name(of: member).prefix(1).uppercased()
    }

    /// Сколько денег уже оплачено за сегодня.
    private var todayEarned: Double {
        payments
            .filter { $0.deletedAt == nil && $0.methodValue.isPaid && cal.isDateInToday($0.day) }
            .reduce(0) { $0 + $1.amount }
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
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40 { movePlanner(1) }
                if value.translation.width > 40 { movePlanner(-1) }
            })

            PlannerTimelineView(
                days: days,
                isDayMode: dayFocus,
                events: events,
                externalItems: { items(on: $0) },
                badge: { event, day in PlannerPaymentStore.badge(for: event, day: day, payments: payments) },
                ownerLetter: { ownerLetter($0) },
                canMove: { $0.scopeValue.canEdit(by: account.current) },
                onHeaderTap: { day in
                    withAnimation(.snappy) {
                        selectedDay = day
                        dayFocus.toggle()
                    }
                },
                onSlotTap: { start in
                    if moving != nil {
                        finishMove(to: start)
                    } else {
                        selectedDay = cal.startOfDay(for: start)
                        sheetTarget = SheetTarget(kind: .edit, event: nil, day: start, time: start)
                    }
                },
                onEventTap: { event, day in
                    guard moving == nil else { return }
                    sheetTarget = SheetTarget(kind: .detail, event: event, day: day)
                },
                onMove: { event, from, to in moveByDrag(event, from: from, to: to) }
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

        return Button {
            if let moving {
                // Перенос на другой день: то же время суток.
                let time = PlannerCalendar.combine(day: day, time: moving.occurrenceStart)
                finishMove(to: moving.event.isAllDay ? day : time)
            } else {
                withAnimation(.snappy) { selectedDay = day }
            }
        } label: {
            VStack(spacing: 3) {
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
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    Button(account.current == .partner ? "Добавить тренировку" : "Добавить событие") {
                        sheetTarget = SheetTarget(kind: .edit, event: nil, day: selectedDay)
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
                        badge: PlannerPaymentStore.badge(for: occurrence.event, day: selectedDay, payments: payments)
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(dayItems) { item in
                PlannerExternalItemRow(item: item)
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
                Text(event.displayTitle)
                    .font(.body.weight(.medium))
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
            if let symbol = badge.symbol {
                Text(symbol)
            }
            Text(event.scopeValue.title(account))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(event.categoryValue.color.opacity(0.15)))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
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
