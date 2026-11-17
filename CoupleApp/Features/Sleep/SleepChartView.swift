import Charts
import SwiftUI

/// Столбики: сколько часов спали каждую ночь, линия — цель.
struct SleepChartView: View {
    let nights: [SleepStats.Night]
    let days: Int
    let goalHours: Double

    var body: some View {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let domainEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end

        Chart {
            ForEach(nights) { night in
                BarMark(
                    x: .value("Ночь", night.day, unit: .day),
                    y: .value("Часы", night.hours)
                )
                .foregroundStyle(night.hours >= goalHours ? Color.indigo : Color.orange)
                .cornerRadius(4)
            }
            RuleMark(y: .value("Цель", goalHours))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("цель \(goalHours.formatted(.number.precision(.fractionLength(0...1)))) ч")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: start...domainEnd)
        .chartYScale(domain: 0...max(12, (nights.map(\.hours).max() ?? 0) + 1))
        .chartXAxis {
            if days <= 7 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .frame(height: 180)
    }
}
