import Foundation
import SwiftData

// MARK: - Вспомогательные типы

/// Приём пищи.
enum NutritionMealType: String, CaseIterable, Identifiable, Codable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Завтрак"
        case .lunch: "Обед"
        case .dinner: "Ужин"
        case .snack: "Перекус"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    /// Какой приём пищи подставить по текущему времени.
    static func suggested(for date: Date = .now) -> NutritionMealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case ..<11: return .breakfast
        case ..<16: return .lunch
        case ..<21: return .dinner
        default: return .snack
        }
    }
}

/// День хранится строкой `yyyy-MM-dd` по времени телефона,
/// чтобы запись не переезжала на другой день из-за часового пояса.
enum NutritionDay {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String {
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Ключи последних `count` дней, от старого к сегодняшнему.
    static func lastKeys(_ count: Int, endingAt end: Date = .now) -> [(key: String, date: Date)] {
        (0..<count).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return (key(for: date), date)
        }
    }
}

/// Калории и БЖУ вместе.
struct NutritionTotals {
    var calories: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0

    static func sum(_ entries: [NutritionEntry]) -> NutritionTotals {
        entries.reduce(into: NutritionTotals()) { total, entry in
            total.calories += entry.calories
            total.protein += entry.protein
            total.fat += entry.fat
            total.carbs += entry.carbs
        }
    }
}

/// Дневные цели человека.
struct NutritionTargets {
    var calories: Double = 2000
    var protein: Double = 100
    var fat: Double = 70
    var carbs: Double = 250
    var water: Int = 2000

    static let standard = NutritionTargets()
}

extension Double {
    /// Число без лишних знаков: 12, 12.5.
    var nutritionText: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Запись о еде

@Model
final class NutritionEntry: SyncableModel {
    struct Payload: Codable {
        var member: String
        var dayKey: String
        var meal: String
        var name: String
        var calories: Double
        var protein: Double
        var fat: Double
        var carbs: Double
        var createdAt: Date
    }

    static let recordKind = "nutrition.entry"

    var syncID: UUID = UUID()
    var member: String = CoupleMember.owner.rawValue
    var dayKey: String = ""
    var meal: String = NutritionMealType.snack.rawValue
    var name: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember, dayKey: String, meal: NutritionMealType) {
        self.member = member.rawValue
        self.dayKey = dayKey
        self.meal = meal.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var mealType: NutritionMealType {
        NutritionMealType(rawValue: meal) ?? .snack
    }

    var payload: Payload {
        Payload(member: member, dayKey: dayKey, meal: meal, name: name, calories: calories,
                protein: protein, fat: fat, carbs: carbs, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        dayKey = payload.dayKey
        meal = payload.meal
        name = payload.name
        calories = payload.calories
        protein = payload.protein
        fat = payload.fat
        carbs = payload.carbs
        createdAt = payload.createdAt
    }
}

// MARK: - Вода

/// Одна порция воды. Каждое нажатие «+250 мл» — отдельная запись.
@Model
final class NutritionWater: SyncableModel {
    struct Payload: Codable {
        var member: String
        var dayKey: String
        var milliliters: Int
        var createdAt: Date
    }

    static let recordKind = "nutrition.water"

    var syncID: UUID = UUID()
    var member: String = CoupleMember.owner.rawValue
    var dayKey: String = ""
    var milliliters: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember, dayKey: String, milliliters: Int) {
        self.member = member.rawValue
        self.dayKey = dayKey
        self.milliliters = milliliters
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(member: member, dayKey: dayKey, milliliters: milliliters, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        dayKey = payload.dayKey
        milliliters = payload.milliliters
        createdAt = payload.createdAt
    }
}

// MARK: - Избранное блюдо

@Model
final class NutritionFavorite: SyncableModel {
    struct Payload: Codable {
        var member: String
        var name: String
        var calories: Double
        var protein: Double
        var fat: Double
        var carbs: Double
        var createdAt: Date
    }

    static let recordKind = "nutrition.favorite"

    var syncID: UUID = UUID()
    var member: String = CoupleMember.owner.rawValue
    var name: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember, name: String, calories: Double, protein: Double, fat: Double, carbs: Double) {
        self.member = member.rawValue
        self.name = name
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(member: member, name: name, calories: calories, protein: protein,
                fat: fat, carbs: carbs, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        name = payload.name
        calories = payload.calories
        protein = payload.protein
        fat = payload.fat
        carbs = payload.carbs
        createdAt = payload.createdAt
    }
}

// MARK: - Цели

/// Дневные цели одного человека. У каждого ровно одна запись
/// с постоянным `syncID`, поэтому правки с разных телефонов не дублируются.
@Model
final class NutritionGoal: SyncableModel {
    struct Payload: Codable {
        var member: String
        var calories: Double
        var protein: Double
        var fat: Double
        var carbs: Double
        var water: Int
    }

    static let recordKind = "nutrition.goal"

    static func syncID(for member: CoupleMember) -> UUID {
        switch member {
        case .owner: UUID(uuidString: "6E757472-0000-4000-8000-000000000001")!
        case .partner: UUID(uuidString: "6E757472-0000-4000-8000-000000000002")!
        }
    }

    var syncID: UUID = UUID()
    var member: String = CoupleMember.owner.rawValue
    var calories: Double = NutritionTargets.standard.calories
    var protein: Double = NutritionTargets.standard.protein
    var fat: Double = NutritionTargets.standard.fat
    var carbs: Double = NutritionTargets.standard.carbs
    var water: Int = NutritionTargets.standard.water
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember) {
        self.syncID = NutritionGoal.syncID(for: member)
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var targets: NutritionTargets {
        NutritionTargets(calories: calories, protein: protein, fat: fat, carbs: carbs, water: water)
    }

    var payload: Payload {
        Payload(member: member, calories: calories, protein: protein, fat: fat, carbs: carbs, water: water)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        calories = payload.calories
        protein = payload.protein
        fat = payload.fat
        carbs = payload.carbs
        water = payload.water
    }
}
