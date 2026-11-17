import Foundation
import SwiftData

/// Продукт с ценностью на 100 г. Общий вид для встроенной базы,
/// своих продуктов, найденных в интернете и блюд.
struct NutritionFoodValues: Hashable {
    var name: String
    var brand: String = ""
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    /// Вес одной штуки в граммах (яйцо, банан). 0 — не задан.
    var pieceGrams: Double = 0
    /// Вес, который подставляется по умолчанию.
    var defaultGrams: Double = 100

    var displayName: String {
        brand.isEmpty ? name : "\(name) · \(brand)"
    }

    func totals(grams: Double) -> NutritionTotals {
        let k = grams / 100
        return NutritionTotals(calories: kcal * k, protein: protein * k, fat: fat * k, carbs: carbs * k)
    }
}

/// Один ингредиент блюда: вес и ценность на 100 г.
struct NutritionIngredient: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var grams: Double
    var kcal100: Double
    var protein100: Double
    var fat100: Double
    var carbs100: Double

    var totals: NutritionTotals {
        let k = grams / 100
        return NutritionTotals(calories: kcal100 * k, protein: protein100 * k, fat: fat100 * k, carbs: carbs100 * k)
    }
}

/// Своё блюдо или продукт — общие для пары.
@Model
final class NutritionFood: SyncableModel {
    struct Payload: Codable {
        var member: String
        var name: String
        var brand: String
        var store: String
        var barcode: String
        var source: String
        var kcal: Double
        var protein: Double
        var fat: Double
        var carbs: Double
        var pieceGrams: Double
        var createdAt: Date
    }

    static let recordKind = "nutrition.food"

    var syncID: UUID = UUID()
    /// Кто добавил.
    var member: String = CoupleMember.owner.rawValue
    var name: String = ""
    var brand: String = ""
    /// Магазин, где продаётся (по данным Open Food Facts или вручную).
    var store: String = ""
    var barcode: String = ""
    /// "custom" — добавлен вручную, "off" — найден в Open Food Facts.
    var source: String = "custom"
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    var pieceGrams: Double = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember) {
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var values: NutritionFoodValues {
        NutritionFoodValues(name: name, brand: brand, kcal: kcal, protein: protein, fat: fat,
                            carbs: carbs, pieceGrams: pieceGrams, defaultGrams: pieceGrams > 0 ? pieceGrams : 100)
    }

    var payload: Payload {
        Payload(member: member, name: name, brand: brand, store: store, barcode: barcode, source: source,
                kcal: kcal, protein: protein, fat: fat, carbs: carbs, pieceGrams: pieceGrams, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        name = payload.name
        brand = payload.brand
        store = payload.store
        barcode = payload.barcode
        source = payload.source
        kcal = payload.kcal
        protein = payload.protein
        fat = payload.fat
        carbs = payload.carbs
        pieceGrams = payload.pieceGrams
        createdAt = payload.createdAt
    }
}

/// Своё блюдо: ингредиенты, число порций и рецепт.
@Model
final class NutritionDish: SyncableModel {
    struct Payload: Codable {
        var member: String
        var name: String
        var servings: Int
        var recipe: String
        var ingredientsJSON: String
        var createdAt: Date
    }

    static let recordKind = "nutrition.dish"

    var syncID: UUID = UUID()
    var member: String = CoupleMember.owner.rawValue
    var name: String = ""
    var servings: Int = 1
    /// Шаги рецепта, каждый с новой строки.
    var recipe: String = ""
    /// Ингредиенты в виде JSON (массив `NutritionIngredient`).
    var ingredientsJSON: String = "[]"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember) {
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var ingredients: [NutritionIngredient] {
        get {
            guard let data = ingredientsJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([NutritionIngredient].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue), let text = String(data: data, encoding: .utf8) {
                ingredientsJSON = text
            }
        }
    }

    var payload: Payload {
        Payload(member: member, name: name, servings: servings, recipe: recipe,
                ingredientsJSON: ingredientsJSON, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        name = payload.name
        servings = payload.servings
        recipe = payload.recipe
        ingredientsJSON = payload.ingredientsJSON
        createdAt = payload.createdAt
    }

    /// Блюдо как продукт: ценность на 100 г готового блюда, вес по умолчанию — одна порция.
    var values: NutritionFoodValues {
        NutritionDishMath.values(name: name, ingredients: ingredients, servings: servings)
    }
}

/// Подсчёт ценности блюда по ингредиентам.
enum NutritionDishMath {
    static func total(_ ingredients: [NutritionIngredient]) -> NutritionTotals {
        ingredients.reduce(into: NutritionTotals()) { sum, item in
            let t = item.totals
            sum.calories += t.calories
            sum.protein += t.protein
            sum.fat += t.fat
            sum.carbs += t.carbs
        }
    }

    static func weight(_ ingredients: [NutritionIngredient]) -> Double {
        ingredients.reduce(0) { $0 + $1.grams }
    }

    static func values(name: String, ingredients: [NutritionIngredient], servings: Int) -> NutritionFoodValues {
        let total = total(ingredients)
        let weight = max(weight(ingredients), 1)
        let k = 100 / weight
        let count = Double(max(servings, 1))
        return NutritionFoodValues(
            name: name, kcal: total.calories * k, protein: total.protein * k,
            fat: total.fat * k, carbs: total.carbs * k,
            pieceGrams: weight / count, defaultGrams: weight / count
        )
    }
}
