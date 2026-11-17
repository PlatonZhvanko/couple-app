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

    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var allEvents: [PlannerEvent]
    @Query(filter: #Predicate<PlannerTask> { $0.deletedAt == nil })
    private var allTasks: [PlannerTask]

    @AppStorage("planner.mode") private var mode: Mode = .month
    @AppStorage("planner.filter") private var filter: PlannerFilter = .all
    @State private var selectedDay = PlannerCalendar.calendar.startOfDay(for: .now)
    @State private var editorTarget: EditorTarget?

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let event: PlannerEvent?
        let day: Date
    }

    private var cal: Calendar { PlannerCalendar.calendar }

    private var events: [PlannerEvent] {
        allEvents.filter { filter.matches($0.scopeValue, me: account.current) }
    }

    private var days: [Date] {
        mode == .month ? PlannerCalendar.monthGrid(selectedDay) : PlannerCalendar.week(containing: selectedDay)
    }

    var body: some View {
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Сегодня") {
                    withAnimation { selectedDay = cal.startOfDay(for: .now) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = EditorTarget(event: nil, day: selectedDay)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новое событие")
            }
        }
        .sheet(item: $editorTarget) { target in
            PlannerEventEditor(event: target.event, day: target.day)
        }
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

        return VStack(alignment: .leading, spacing: 10) {
            Text(PlannerCalendar.dayTitle(selectedDay))
                .font(.headline)

            if occurrences.isEmpty && dayTasks.isEmpty {
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
                Text(event.title.isEmpty ? "Без названия" : event.title)
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
