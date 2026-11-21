import SwiftData
import SwiftUI

/// Отдельное окно «Траты»: период сверху, суммы по категориям, внутри свёрнутые списки.
struct CarSpendingView: View {
    let car: CarVehicle

    enum Period: String, CaseIterable, Identifiable {
        case all, month, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Всё время"
            case .month: "Месяц"
            case .custom: "Период"
            }
        }
    }

    private struct Bucket: Identifiable {
        let title: String
        let entries: [CarEntry]
        var id: String { title }
        var sum: Double { entries.reduce(0) { $0 + $1.amount } }
    }

    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil }, sort: \CarEntry.date, order: .reverse)
    private var allEntries: [CarEntry]
    @State private var period: Period = .all
    @State private var from = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var to = Date.now
    @State private var sheet: CarSheet?

    private var interval: DateInterval {
        switch period {
        case .all: DateInterval(start: .distantPast, end: .distantFuture)
        case .month: CarMath.currentMonth()
        case .custom:
            let start = Calendar.current.startOfDay(for: min(from, to))
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(from, to))) ?? max(from, to)
            return DateInterval(start: start, end: end)
        }
    }

    private var groups: [Bucket] {
        let spent = allEntries.of(car).filter { interval.contains($0.date) && $0.amount > 0 }
        return Dictionary(grouping: spent, by: \.categoryTitle)
            .map { Bucket(title: $0.key, entries: $0.value) }
            .sorted { $0.sum > $1.sum }
    }

    var body: some View {
        let groups = groups
        let total = groups.reduce(0) { $0 + $1.sum }
        List {
            Section {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if period == .custom {
                    DatePicker("С", selection: $from, displayedComponents: .date)
                    DatePicker("По", selection: $to, displayedComponents: .date)
                }
                LabeledContent("Потрачено") {
                    Text(CarFormat.money(total)).font(.title3.weight(.semibold)).monospacedDigit()
                }
            }

            if groups.isEmpty {
                Section { Text("За этот период трат нет.").foregroundStyle(.secondary) }
            } else {
                Section("По категориям") {
                    ForEach(groups) { group in
                        DisclosureGroup {
                            ForEach(group.entries) { entry in
                                Button {
                                    sheet = .entry(car: car, entry: entry, category: entry.category)
                                } label: {
                                    CarEntryRow(entry: entry)
                                }
                                .tint(.primary)
                            }
                        } label: {
                            HStack {
                                Text(group.title)
                                Spacer()
                                Text(CarFormat.money(group.sum)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink("Аналитика трат") { CarStatsView(car: car) }
                NavigationLink("Весь журнал") { CarHistoryView(car: car) }
            }
        }
        .navigationTitle("Траты")
        .sheet(item: $sheet) { sheet in
            CarSheetView(sheet: sheet, currentOdometer: CarMath.currentOdometer(car: car, entries: allEntries.of(car)))
        }
    }
}
