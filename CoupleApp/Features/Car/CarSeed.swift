import Foundation
import SwiftData

/// Наши две машины, добавляются один раз при первом открытии раздела.
/// id фиксированные, чтобы на втором телефоне не было дублей.
enum CarSeed {
    static let flagKey = "car.seeded.v1"

    static let cars: [(id: String, name: String, year: Int)] = [
        ("6A0F3C10-0000-4000-8000-00000000C001", "Volvo S40 (седан)", 2007),
        ("6A0F3C10-0000-4000-8000-00000000C002", "Audi Q3 белая", 2013),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        UserDefaults.standard.set(true, forKey: flagKey)
        let existing = (try? context.fetch(FetchDescriptor<CarVehicle>())) ?? []
        let known = Set(existing.map(\.syncID))
        for item in cars {
            guard let id = UUID(uuidString: item.id), !known.contains(id) else { continue }
            let car = CarVehicle(name: item.name)
            car.syncID = id
            car.year = item.year
            context.insert(car)
        }
        try? context.save()
    }
}
