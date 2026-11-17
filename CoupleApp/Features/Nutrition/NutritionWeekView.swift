import Charts
import SwiftData
import SwiftUI

/// Итоги за последние 7 дней: график калорий и средние значения.
struct NutritionWeekView: View {
    let member: CoupleMember

    @Environment(AccountStore.self) private var account
    @Query private var entries: [NutritionEntry]
    @Query private var goals: [NutritionGoal]

    private let days: [(key: String, date: Date)]

    init(member: CoupleMember) {
        self.member = member
        let days = NutritionDay.lastKeys(7)
        self.days = days
        let keys = days.map(\.key)
        let memberID = member.rawValue
        _entries = Query(filter: #Predicate<NutritionEntry> {
            $0.deletedAt == nil && $0.member == memberID && keys.contains($0.dayKey)
        })
        _goals = Query(filter: #Predicate<NutritionGoal> { $0.deletedAt == nil && $0.member == memberID })
    }

    private struct DayTotal: Identifiable {
        let id: String
        let date: Date
        let totals: NutritionTotals
        var hasFood: Bool { totals.calories > 0 }
    }

    private var targets: NutritionTargets { goals.first?.targets ?? .standard }

    private var dayTotals: [DayTotal] {
        let byDay = Dictionary(grouping: entries, by: \.dayKey)
        return days.map { day in
            DayTotal(
                id: day.key,
                date: day.date,
                totals: NutritionTotals.sum(byDay[day.key] ?? [])
            )
        }
    }

    var body: some View {
        let totals = dayTotals
        let filled = totals.filter(\.hasFood)
        List {
            Section {
                Chart {
                    ForEach(totals) { day in
                        BarMark(
                            x: .value("День", day.date, unit: .day),
                            y: .value("Ккал", day.totals.calories)
                        )
                        .foregroundStyle(day.totals.calories > targets.calories ? Color.orange : Color.green)
                    }
                    RuleMark(y: .value("Цель", targets.calories))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .frame(height: 200)
                .padding(.vertical, 8)
            } header: {
                Text("Калории за 7 дней")
            } footer: {
                Text("Пунктир — дневная цель \(targets.calories.nutritionText) ккал.")
            }

            Section {
                if filled.isEmpty {
                    Text("За эту неделю ничего не записано.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Калории", value: "\(average(filled.map(\.totals.calories)).nutritionText) ккал")
                    LabeledContent("Белки", value: "\(average(filled.map(\.totals.protein)).nutritionText) г")
                    LabeledContent("Жиры", value: "\(average(filled.map(\.totals.fat)).nutritionText) г")
                    LabeledContent("Углеводы", value: "\(average(filled.map(\.totals.carbs)).nutritionText) г")
                    LabeledContent("Дней в норме", value: "\(filled.filter { $0.totals.calories <= targets.calories }.count) из \(filled.count)")
                }
            } header: {
                Text("В среднем за день")
            } footer: {
                Text("Считаются только дни, когда что-то записано.")
            }
        }
        .navigationTitle(member == account.current ? "Моя неделя" : "Неделя: \(account.partnerName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
