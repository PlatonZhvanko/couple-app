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

/// Траты по Audi Q3, перенесённые из списка владельца. Даты неизвестны, поэтому «ранее».
enum CarAudiExpensesSeed {
    static let flagKey = "car.audiExpenses.v1"
    private static let audiID = "6A0F3C10-0000-4000-8000-00000000C002"

    private struct Item {
        let title: String
        let price: Double
        let category: CarEntryCategory
        let custom: String
    }

    private static let items: [Item] = [
        Item(title: "Покупка", price: 1_115_000, category: .other, custom: "Покупка"),
        Item(title: "Учёт", price: 15_000, category: .other, custom: "Оформление"),
        Item(title: "Лоб (очистка)", price: 2_500, category: .repair, custom: ""),
        Item(title: "Катушка + лямбда", price: 11_600, category: .repair, custom: ""),
        Item(title: "Подбор", price: 7_700, category: .other, custom: "Подбор"),
        Item(title: "Парктроники + установка (Илья)", price: 1_500, category: .repair, custom: ""),
        Item(title: "Рулевой шлейф", price: 11_800, category: .repair, custom: ""),
        Item(title: "Ультра Мега Супер страховка", price: 32_700, category: .insurance, custom: ""),
        Item(title: "Запчасти по подвеске и для ТО", price: 15_300, category: .repair, custom: ""),
        Item(title: "Масло в редуктор (2 л)", price: 2_800, category: .service, custom: ""),
        Item(title: "Вскрытие и покупка полного набора секретки", price: 6_000, category: .repair, custom: ""),
        Item(title: "Пружины с Тигуана, 2 передние", price: 10_000, category: .repair, custom: ""),
        Item(title: "Запчасти с сервиса (кольцо, стойка стаба, два отбойника, две опоры)", price: 8_000, category: .repair, custom: ""),
        Item(title: "Шлейф рулевой (Н)", price: 10_000, category: .repair, custom: ""),
        Item(title: "Работа мастера (Илья)", price: 13_500, category: .repair, custom: ""),
        Item(title: "Антикор и много всего", price: 90_000, category: .repair, custom: ""),
        Item(title: "Стекло + поклейка", price: 12_000, category: .repair, custom: ""),
    ]

    private static func id(_ prefix: String, _ index: Int) -> UUID {
        UUID(uuidString: "6A0F3C10-0000-4000-8000-" + prefix + String(format: "%08d", index)) ?? UUID()
    }

    /// Добавляет оплаченные ремонты и траты Audi. Идёт один раз, id фиксированные.
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flagKey),
              let carID = UUID(uuidString: audiID) else { return }
        let cars = (try? context.fetch(FetchDescriptor<CarVehicle>())) ?? []
        guard cars.contains(where: { $0.syncID == carID && $0.deletedAt == nil }) else { return }
        UserDefaults.standard.set(true, forKey: flagKey)

        let knownRepairs = Set(((try? context.fetch(FetchDescriptor<CarRepair>())) ?? []).map(\.syncID))
        let knownEntries = Set(((try? context.fetch(FetchDescriptor<CarEntry>())) ?? []).map(\.syncID))
        let when = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now

        for (index, item) in items.enumerated() {
            let repairID = id("D000", index)
            let entryID = id("E000", index)
            if !knownEntries.contains(entryID) {
                let entry = CarEntry(carID: carID, category: item.category, member: .owner)
                entry.syncID = entryID
                entry.customCategory = item.custom
                entry.amount = item.price
                entry.date = when
                entry.note = item.title + " (ранее, дата неизвестна)"
                context.insert(entry)
                entry.markChanged()
            }
            if !knownRepairs.contains(repairID) {
                let repair = CarRepair(carID: carID, member: .owner)
                repair.syncID = repairID
                repair.title = item.title
                repair.price = item.price
                repair.isPaid = true
                repair.paidAt = when
                repair.entryID = entryID
                repair.note = "Перенесено из списка трат, дата неизвестна."
                context.insert(repair)
                repair.markChanged()
            }
        }
        try? context.save()
    }
}
