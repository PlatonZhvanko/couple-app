import SwiftData
import SwiftUI

/// Запланированные ремонты по дате и времени для календаря «Планера».
/// Двигаются в разделе «Авто» (дата и время в ремонте), изменения синхронизируются.
enum CarCalendar {
    /// Чья машина: Volvo у Платони, Audi у Насти. Остальные видят оба.
    private static let owners: [String: CoupleMember] = [
        "6A0F3C10-0000-4000-8000-00000000C001": .owner,
        "6A0F3C10-0000-4000-8000-00000000C002": .partner,
    ]

    @MainActor
    static func items(context: ModelContext, interval: DateInterval) -> [CalendarItem] {
        let from = interval.start.addingTimeInterval(-86_400)
        let to = interval.end
        let descriptor = FetchDescriptor<CarRepair>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.isPaid == false && $0.desiredDate != nil
            }
        )
        guard let repairs = try? context.fetch(descriptor) else { return [] }
        let cars = (try? context.fetch(FetchDescriptor<CarVehicle>())) ?? []
        let names = Dictionary(cars.map { ($0.syncID, $0.displayName) }, uniquingKeysWith: { first, _ in first })

        return repairs.compactMap { repair in
            guard let start = repair.desiredDate, start >= from, start < to else { return nil }
            let end = start.addingTimeInterval(Double(max(30, repair.durationMinutes)) * 60)
            guard end > interval.start else { return nil }
            let car = names[repair.carID] ?? "Машина"
            return CalendarItem(
                id: "car.repair.\(repair.syncID.uuidString)",
                title: "\(repair.title.isEmpty ? "Ремонт" : repair.title) · \(car)",
                start: start,
                end: end,
                member: owners[repair.carID.uuidString],
                color: .orange,
                systemImage: "wrench.and.screwdriver.fill"
            )
        }
    }
}
