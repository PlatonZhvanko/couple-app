import SwiftData
import SwiftUI

/// Весь журнал машины по месяцам, с фильтром по категории.
struct CarHistoryView: View {
    let car: CarVehicle

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil }, sort: \CarEntry.date, order: .reverse)
    private var allEntries: [CarEntry]
    @State private var filter: CarEntryCategory?
    @State private var sheet: CarSheet?

    private var entries: [CarEntry] {
        let mine = allEntries.of(car)
        guard let filter else { return mine }
        return mine.filter { $0.category == filter }
    }

    private var months: [(month: Date, entries: [CarEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("Записей нет", systemImage: "list.bullet.rectangle")
            }
            ForEach(months, id: \.month) { group in
                Section {
                    ForEach(group.entries) { entry in
                        Button {
                            sheet = .entry(car: car, entry: entry, category: entry.category)
                        } label: {
                            CarEntryRow(entry: entry)
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                entry.markDeleted()
                                try? context.save()
                                sync.requestSync()
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text(CarFormat.money(group.entries.reduce(0) { $0 + $1.amount }))
                    }
                }
            }
        }
        .navigationTitle("Журнал")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Категория", selection: $filter) {
                        Text("Все").tag(CarEntryCategory?.none)
                        ForEach(CarEntryCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(CarEntryCategory?.some(category))
                        }
                    }
                } label: {
                    Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Добавить", systemImage: "plus") {
                    sheet = .entry(car: car, entry: nil, category: filter ?? .fuel)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            CarSheetView(sheet: sheet, currentOdometer: CarMath.currentOdometer(car: car, entries: allEntries.of(car)))
        }
    }
}

/// Все напоминания машины: активные и выполненные.
struct CarRemindersView: View {
    let car: CarVehicle

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Query(filter: #Predicate<CarReminder> { $0.deletedAt == nil }, sort: \CarReminder.createdAt)
    private var allReminders: [CarReminder]
    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil })
    private var allEntries: [CarEntry]
    @State private var sheet: CarSheet?

    var body: some View {
        let odometer = CarMath.currentOdometer(car: car, entries: allEntries.of(car))
        let reminders = allReminders.of(car)
        let active = reminders.filter { !$0.isDone }.sortedByUrgency(currentOdometer: odometer)
        let done = reminders.filter(\.isDone)

        List {
            if reminders.isEmpty {
                ContentUnavailableView(
                    "Напоминаний нет",
                    systemImage: "bell",
                    description: Text("Нажмите «+», чтобы добавить ОСАГО, техосмотр или замену масла.")
                )
            }
            if !active.isEmpty {
                Section("Активные") {
                    ForEach(active) { reminder in
                        row(reminder, odometer: odometer)
                            .swipeActions(edge: .leading) {
                                Button("Сделано", systemImage: "checkmark") {
                                    reminder.complete(currentOdometer: odometer)
                                    save()
                                }
                                .tint(.green)
                            }
                    }
                }
            }
            if !done.isEmpty {
                Section("Выполненные") {
                    ForEach(done) { reminder in
                        row(reminder, odometer: odometer)
                    }
                }
            }
        }
        .navigationTitle("Напоминания")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Добавить", systemImage: "plus") {
                    sheet = .reminder(car: car, reminder: nil)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            CarSheetView(sheet: sheet, currentOdometer: odometer)
        }
    }

    private func row(_ reminder: CarReminder, odometer: Int) -> some View {
        Button {
            sheet = .reminder(car: car, reminder: reminder)
        } label: {
            CarReminderRow(reminder: reminder, currentOdometer: odometer)
        }
        .tint(.primary)
        .swipeActions {
            Button("Удалить", systemImage: "trash", role: .destructive) {
                reminder.markDeleted()
                save()
            }
        }
    }

    private func save() {
        try? context.save()
        sync.requestSync()
    }
}

/// Итоги: сколько потрачено, на что, кем, и расход топлива.
struct CarStatsView: View {
    let car: CarVehicle

    enum Period: String, CaseIterable, Identifiable {
        case month, year, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: "Месяц"
            case .year: "Год"
            case .all: "Всё время"
            }
        }
    }

    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil }, sort: \CarEntry.date)
    private var allEntries: [CarEntry]
    @Query(filter: #Predicate<CarRepair> { $0.deletedAt == nil })
    private var allRepairs: [CarRepair]
    @State private var period: Period = .month

    private var interval: DateInterval {
        switch period {
        case .month: CarMath.currentMonth()
        case .year: CarMath.currentYear()
        case .all: DateInterval(start: Date(timeIntervalSince1970: 0), end: Date.now.addingTimeInterval(3650 * 86400))
        }
    }

    var body: some View {
        let entries = allEntries.of(car)
        let inPeriod = entries.filter { interval.contains($0.date) }
        let total = inPeriod.reduce(0) { $0 + $1.amount }
        let byCategory = CarMath.totalsByCategory(entries, in: interval)
        let fuel = CarMath.fuelStats(entries)

        List {
            Section {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Всего потрачено") {
                    Text(CarFormat.money(total)).font(.headline).monospacedDigit()
                }
            }

            let planned = allRepairs.of(car).filter { !$0.isPaid }
            if !planned.isEmpty {
                Section("Запланировано по ремонтам") {
                    LabeledContent("Ещё не оплачено", value: CarFormat.money(planned.reduce(0) { $0 + $1.price }))
                }
            }

            if !byCategory.isEmpty {
                Section("На что") {
                    ForEach(byCategory) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(item.category.title, systemImage: item.category.systemImage)
                                    .foregroundStyle(item.category.color)
                                Spacer()
                                Text(CarFormat.money(item.sum)).monospacedDigit()
                            }
                            ProgressView(value: total > 0 ? min(1, max(0, item.sum / total)) : 0)
                                .tint(item.category.color)
                        }
                    }
                }

                Section("Кто платил") {
                    ForEach(CoupleMember.allCases) { member in
                        let sum = inPeriod.filter { $0.memberValue == member }.reduce(0) { $0 + $1.amount }
                        LabeledContent(account.name(of: member), value: CarFormat.money(sum))
                    }
                }
            }

            Section {
                LabeledContent("Средний расход", value: fuel.averageLitersPer100.map { CarFormat.consumption($0) } ?? "—")
                LabeledContent("Последний бак", value: fuel.lastLitersPer100.map { CarFormat.consumption($0) } ?? "—")
                LabeledContent("Стоимость 1 км", value: CarMath.costPerKm(entries).map { CarFormat.money($0) } ?? "—")
            } header: {
                Text("Топливо и пробег")
            } footer: {
                Text("Расход и стоимость километра считаются за всё время. Для расхода нужны хотя бы две заправки до полного бака с пробегом.")
            }
        }
        .navigationTitle("Аналитика")
    }
}
