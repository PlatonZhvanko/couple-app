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

/// Аналитика трат машины. Всё считается один раз при открытии, без тяжёлых элементов:
/// простые строки с суммами.
struct CarStatsView: View {
    let car: CarVehicle

    /// Оставлено для совместимости с другими экранами.
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

    private struct Summary {
        var total = 0.0
        var year = 0.0
        var month = 0.0
        var categories: [(title: String, sum: Double)] = []
        var payers: [(name: String, sum: Double)] = []
        var average: String = "—"
        var last: String = "—"
        var perKm: String = "—"
        var planned = 0.0
        var count = 0
    }

    @Environment(\.modelContext) private var context
    @Environment(AccountStore.self) private var account
    @State private var summary: Summary?

    var body: some View {
        List {
            if let summary {
                if summary.count == 0 {
                    Section { Text("Трат пока нет.").foregroundStyle(.secondary) }
                }
                Section("Сколько потрачено") {
                    LabeledContent("Всё время", value: CarFormat.money(summary.total))
                    LabeledContent("За год", value: CarFormat.money(summary.year))
                    LabeledContent("За месяц", value: CarFormat.money(summary.month))
                    if summary.planned > 0 {
                        LabeledContent("Ремонты в планах", value: CarFormat.money(summary.planned))
                    }
                }
                if !summary.categories.isEmpty {
                    Section("На что (всё время)") {
                        ForEach(0..<summary.categories.count, id: \.self) { index in
                            LabeledContent(summary.categories[index].title,
                                           value: CarFormat.money(summary.categories[index].sum))
                        }
                    }
                }
                if !summary.payers.isEmpty {
                    Section("Кто платил") {
                        ForEach(0..<summary.payers.count, id: \.self) { index in
                            LabeledContent(summary.payers[index].name,
                                           value: CarFormat.money(summary.payers[index].sum))
                        }
                    }
                }
                Section("Топливо и пробег") {
                    LabeledContent("Средний расход", value: summary.average)
                    LabeledContent("Последний бак", value: summary.last)
                    LabeledContent("Стоимость 1 км", value: summary.perKm)
                }
            } else {
                Section { Text("Считаю…").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Аналитика")
        .task { summary = load() }
    }

    /// Один запрос по этой машине и простые подсчёты.
    private func load() -> Summary {
        let carID = car.syncID
        let descriptor = FetchDescriptor<CarEntry>(
            predicate: #Predicate { $0.carID == carID && $0.deletedAt == nil }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        let repairDescriptor = FetchDescriptor<CarRepair>(
            predicate: #Predicate { $0.carID == carID && $0.deletedAt == nil && $0.isPaid == false }
        )
        let planned = ((try? context.fetch(repairDescriptor)) ?? []).reduce(0) { $0 + $1.price }

        var result = Summary()
        result.count = entries.count
        result.planned = planned
        let now = Date.now
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? now

        var byCategory: [String: Double] = [:]
        var byMember: [String: Double] = [:]
        for entry in entries where entry.amount > 0 {
            result.total += entry.amount
            if entry.date >= yearStart { result.year += entry.amount }
            if entry.date >= monthStart { result.month += entry.amount }
            byCategory[entry.categoryTitle, default: 0] += entry.amount
            byMember[entry.member, default: 0] += entry.amount
        }
        result.categories = byCategory.map { (title: $0.key, sum: $0.value) }.sorted { $0.sum > $1.sum }
        result.payers = CoupleMember.allCases.compactMap { member in
            guard let sum = byMember[member.rawValue], sum > 0 else { return nil }
            return (name: account.name(of: member), sum: sum)
        }

        let fuel = CarMath.fuelStats(entries)
        result.average = fuel.averageLitersPer100.map { CarFormat.consumption($0) } ?? "—"
        result.last = fuel.lastLitersPer100.map { CarFormat.consumption($0) } ?? "—"
        result.perKm = CarMath.costPerKm(entries).map { CarFormat.money($0) } ?? "—"
        return result
    }
}
