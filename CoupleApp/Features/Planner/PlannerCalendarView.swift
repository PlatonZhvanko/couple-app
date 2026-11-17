import SwiftData
import SwiftUI

/// Какие записи показывать.
enum PlannerFilter: String, CaseIterable, Identifiable {
    case all, shared, mine, partner
    var id: String { rawValue }

    func matches(_ scope: PlannerScope, me: CoupleMember) -> Bool {
        switch self {
        case .all: true
        case .shared: scope == .shared
        case .mine: scope == .personal(me)
        case .partner: scope == .personal(me.other)
        }
    }

    @MainActor
    func title(_ account: AccountStore) -> String {
        switch self {
        case .all: "Все"
        case .shared: "Общие"
        case .mine: "Мои"
        case .partner: account.partnerName
        }
    }
}

/// Календарь: сетка месяца или недели и список на выбранный день.
struct PlannerCalendarView: View {
    enum Mode: String { case month, week }
    /// Планировщик (время по часам) или обычный календарь (сетка месяца).
    enum Style: String { case planner, calendar }

    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var allEvents: [PlannerEvent]
    @Query(filter: #Predicate<PlannerTask> { $0.deletedAt == nil })
    private var allTasks: [PlannerTask]

    @AppStorage("planner.mode") private var mode: Mode = .month
    @AppStorage("planner.style") private var style: Style = .planner
    /// В планировщике: открыт один день вместо недели.
    @AppStorage("planner.dayFocus") private var dayFocus = false
    @AppStorage("planner.filter") private var filter: PlannerFilter = .all
    @State private var selectedDay = PlannerCalendar.calendar.startOfDay(for: .now)
    @State private var editorTarget: EditorTarget?
    /// Элементы из других разделов (например, записи клиентов).
    @State private var externalItems: [CalendarItem] = []

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let event: PlannerEvent?
        let day: Date
        var time: Date? = nil
    }

    private var cal: Calendar { PlannerCalendar.calendar }

    private var events: [PlannerEvent] {
        allEvents.filter { filter.matches($0.scopeValue, me: account.current) }
    }

    /// Свои записи из других разделов: только во вкладках «Все» и «Мои».
    private func items(on day: Date) -> [CalendarItem] {
        guard filter == .all || filter == .mine else { return [] }
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = PlannerCalendar.addDays(1, to: dayStart)
        return externalItems
            .filter { ($0.member == nil || $0.member == account.current) && $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }
    }

    /// Меняется при листании и после синхронизации: тогда перечитываем записи других разделов.
    private var externalItemsKey: String {
        let first = days.first?.timeIntervalSince1970 ?? 0
        let synced = sync.lastSyncedAt?.timeIntervalSince1970 ?? 0
        return "\(first)-\(days.count)-\(synced)"
    }

    private func loadExternalItems() {
        guard let first = days.first, let last = days.last else { return }
        let interval = DateInterval(start: first, end: PlannerCalendar.addDays(1, to: last))
        externalItems = FeatureRegistry.calendarItems(context: context, interval: interval)
    }

    private var days: [Date] {
        if style == .planner {
            return dayFocus ? [cal.startOfDay(for: selectedDay)] : PlannerCalendar.week(containing: selectedDay)
        }
        return mode == .month ? PlannerCalendar.monthGrid(selectedDay) : PlannerCalendar.week(containing: selectedDay)
    }

    var body: some View {
        Group {
            if style == .planner {
                plannerBody
            } else {
                calendarBody
            }
        }
        .task(id: externalItemsKey) {
            loadExternalItems()
        }
        .onAppear(perform: loadExternalItems)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Сегодня") {
                    withAnimation { selectedDay = cal.startOfDay(for: .now) }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation { style = style == .planner ? .calendar : .planner }
                } label: {
                    Image(systemName: style == .planner ? "calendar" : "calendar.day.timeline.left")
                }
                .accessibilityLabel(style == .planner ? "Обычный календарь" : "Планировщик")
                Button {
                    editorTarget = EditorTarget(event: nil, day: selectedDay)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новое событие")
            }
        }
        .sheet(item: $editorTarget) { target in
            if PlannerTrainingEditor.shouldUse(for: target.event, me: account.current) {
                PlannerTrainingEditor(event: target.event, day: target.day, at: target.time)
            } else {
                PlannerEventEditor(event: target.event, day: target.day, at: target.time)
            }
        }
    }

    // MARK: - Планировщик

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
                Menu {
                    Picker("Показывать", selection: $filter) {
                        ForEach(PlannerFilter.allCases) { Text($0.title(account)).tag($0) }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                Button { movePlanner(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, 8)

            PlannerTimelineView(
                days: days,
                isDayMode: dayFocus,
                events: events,
                externalItems: { items(on: $0) },
                onHeaderTap: { day in
                    withAnimation(.snappy) {
                        selectedDay = day
                        dayFocus.toggle()
                    }
                },
                onSlotTap: { start in
                    selectedDay = cal.startOfDay(for: start)
                    editorTarget = EditorTarget(event: nil, day: start, time: start)
                },
                onEventTap: { event in
                    editorTarget = EditorTarget(event: event, day: selectedDay)
                }
            )
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width < -60 { movePlanner(1) }
                if value.translation.width > 60 { movePlanner(-1) }
            })
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
                filterBar
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
        let hasTasks = tasks(on: day).contains { !$0.isDone }
        let isBusy = !items(on: day).isEmpty

        return Button {
            withAnimation(.snappy) { selectedDay = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(isToday ? Color.accentColor : Color.primary)
                        } else if isToday {
                            Circle().stroke(Color.accentColor, lineWidth: 1.5)
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
                    if hasTasks {
                        Circle().stroke(Color.secondary, lineWidth: 1).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Фильтр

    private var filterBar: some View {
        Picker("Показывать", selection: $filter) {
            ForEach(PlannerFilter.allCases) { Text($0.title(account)).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Список на день

    private func tasks(on day: Date) -> [PlannerTask] {
        allTasks.filter { task in
            guard let due = task.dueDate, filter.matches(task.scopeValue, me: account.current) else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }
    }

    private var dayList: some View {
        let occurrences = events.occurrences(on: selectedDay)
        let dayTasks = tasks(on: selectedDay).sorted { !$0.isDone && $1.isDone }
        let dayItems = items(on: selectedDay)

        return VStack(alignment: .leading, spacing: 10) {
            Text(PlannerCalendar.dayTitle(selectedDay))
                .font(.headline)

            if occurrences.isEmpty && dayTasks.isEmpty && dayItems.isEmpty {
                VStack(spacing: 8) {
                    Text("Ничего не запланировано")
                        .foregroundStyle(.secondary)
                    Button("Добавить событие") {
                        editorTarget = EditorTarget(event: nil, day: selectedDay)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            ForEach(occurrences) { occurrence in
                Button {
                    editorTarget = EditorTarget(event: occurrence.event, day: selectedDay)
                } label: {
                    PlannerEventRow(occurrence: occurrence, day: selectedDay)
                }
                .buttonStyle(.plain)
            }

            ForEach(dayItems) { item in
                PlannerExternalItemRow(item: item)
            }

            ForEach(dayTasks) { task in
                PlannerTaskRow(task: task, showsDue: false)
                    .padding(.vertical, 4)
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
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
