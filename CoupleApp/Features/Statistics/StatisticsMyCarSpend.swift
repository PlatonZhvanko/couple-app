import SwiftData
import SwiftUI

/// Траты на свою машину в личной статистике: у Платони Volvo, у Насти Audi.
/// Чужую машину здесь не видно, её можно смотреть только внутри раздела «Авто».
struct StatisticsMyCarSpend: View {
    let period: StatisticsPeriod

    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil }, sort: \CarEntry.date, order: .reverse)
    private var entries: [CarEntry]

    private var myCarID: UUID? {
        UUID(uuidString: account.current == .owner
             ? "6A0F3C10-0000-4000-8000-00000000C001"
             : "6A0F3C10-0000-4000-8000-00000000C002")
    }

    var body: some View {
        let id = myCarID
        let mine = entries.filter { $0.carID == id && $0.amount > 0 && period.contains($0.date) }
        let total = mine.reduce(0) { $0 + $1.amount }
        StatisticsLine(title: "🚗 Траты на машину", value: PlannerPricing.format(total)) {
            if mine.isEmpty {
                Text("За период трат на машину нет").foregroundStyle(.secondary)
            }
            ForEach(mine) { entry in
                StatisticsDetailRow(
                    title: entry.note.isEmpty ? entry.categoryTitle : entry.note,
                    caption: "\(StatisticsFormat.day(entry.date)) · \(entry.categoryTitle)",
                    value: "−" + PlannerPricing.format(entry.amount)
                )
            }
        }
    }
}
