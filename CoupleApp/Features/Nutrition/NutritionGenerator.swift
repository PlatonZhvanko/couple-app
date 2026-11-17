import Foundation

/// Придуманное генератором блюдо: ещё не записано в дневник.
struct NutritionDishDraft: Identifiable {
    let id = UUID()
    var name: String
    var meal: NutritionMealType
    var minutes: Int
    var ingredients: [NutritionIngredient]
    var steps: [String]

    var total: NutritionTotals { NutritionDishMath.total(ingredients) }
    var weight: Double { NutritionDishMath.weight(ingredients) }
    /// Ценность на 100 г; вес по умолчанию — вся порция.
    var values: NutritionFoodValues {
        NutritionDishMath.values(name: name, ingredients: ingredients, servings: 1)
    }
}

/// Генератор рациона: подбирает блюда под нужные калории приёма пищи.
enum NutritionGenerator {
    /// Доля суточной нормы на каждый приём пищи.
    static func share(of meal: NutritionMealType) -> Double {
        switch meal {
        case .breakfast: 0.25
        case .lunch: 0.35
        case .dinner: 0.30
        case .snack: 0.10
        }
    }

    static func targetCalories(for meal: NutritionMealType, daily: Double) -> Double {
        (daily * share(of: meal) / 10).rounded() * 10
    }

    static func ingredient(_ name: String, grams: Double) -> NutritionIngredient? {
        guard let food = NutritionFoodData.find(name) else { return nil }
        return NutritionIngredient(name: food.name, grams: grams, kcal100: food.kcal,
                                   protein100: food.protein, fat100: food.fat, carbs100: food.carbs)
    }

    /// Подгоняет граммы так, чтобы блюдо давало примерно `target` ккал.
    static func scaled(_ items: [NutritionIngredient], to target: Double) -> [NutritionIngredient] {
        let current = NutritionDishMath.total(items).calories
        guard current > 0, target > 0 else { return items }
        let factor = min(max(target / current, 0.6), 1.7)
        return items.map { item in
            var copy = item
            copy.grams = max((item.grams * factor / 5).rounded() * 5, 5)
            return copy
        }
    }

    /// Несколько разных вариантов. `avoiding` — названия, которые уже показывали.
    static func generate(meal: NutritionMealType, targetCalories: Double, count: Int = 6,
                         avoiding: Set<String> = []) -> [NutritionDishDraft] {
        var result: [NutritionDishDraft] = []

        var fresh = NutritionRecipeData.recipes.filter { $0.meal == meal && !avoiding.contains($0.name) }
        if fresh.count < count {
            // Все варианты уже показывали — начинаем круг заново.
            fresh = NutritionRecipeData.recipes.filter { $0.meal == meal }
        }
        fresh.shuffle()

        let comboCount = (meal == .lunch || meal == .dinner) ? count / 3 : 0
        for recipe in fresh.prefix(count - comboCount) {
            let items = recipe.ingredients.compactMap { ingredient($0.name, grams: $0.grams) }
            guard !items.isEmpty else { continue }
            result.append(NutritionDishDraft(
                name: recipe.name, meal: meal, minutes: recipe.minutes,
                ingredients: scaled(items, to: targetCalories), steps: recipe.steps
            ))
        }

        var tries = 0
        var combos: [NutritionDishDraft] = []
        while combos.count < comboCount && tries < 20 {
            tries += 1
            if let combo = makeCombo(meal: meal, target: targetCalories),
               !combos.contains(where: { $0.name == combo.name }), !avoiding.contains(combo.name) {
                combos.append(combo)
            }
        }
        result.append(contentsOf: combos)
        return result.shuffled()
    }

    // MARK: Сборные блюда «белок + гарнир + овощи»

    private static let proteins: [(name: String, grams: Double, step: String)] = [
        ("Куриная грудка", 150, "Нарезать куриную грудку, посолить и обжарить на масле 8–10 минут."),
        ("Индейка филе", 150, "Нарезать индейку, посолить и обжарить на масле 8–10 минут."),
        ("Говядина", 130, "Нарезать говядину, обжарить 5 минут и потушить под крышкой 20 минут."),
        ("Свинина постная (вырезка)", 140, "Нарезать свинину и обжарить на масле 10 минут."),
        ("Лосось (сёмга)", 130, "Обжарить или запечь лосось по 4–5 минут с каждой стороны."),
        ("Треска", 170, "Запечь треску с лимоном и солью 15 минут при 190 °C."),
        ("Минтай", 170, "Запечь или потушить минтай 15 минут."),
        ("Креветки варёные", 130, "Прогреть креветки на сковороде 2–3 минуты."),
        ("Яйцо куриное", 110, "Приготовить яичницу или отварить яйца вкрутую."),
    ]
    private static let sides: [(name: String, grams: Double)] = [
        ("Гречка варёная", 160), ("Рис варёный", 160), ("Картофель варёный", 200),
        ("Макароны варёные", 160), ("Картофельное пюре", 180),
    ]
    private static let vegetables = [
        "Огурец", "Помидор", "Брокколи", "Перец болгарский", "Цветная капуста", "Кабачок", "Морковь",
    ]

    private static func makeCombo(meal: NutritionMealType, target: Double) -> NutritionDishDraft? {
        guard let protein = proteins.randomElement(), let side = sides.randomElement(),
              let veg = vegetables.randomElement(),
              let p = ingredient(protein.name, grams: protein.grams),
              let s = ingredient(side.name, grams: side.grams),
              let v = ingredient(veg, grams: 120),
              let oil = ingredient("Масло оливковое", grams: 8) else { return nil }
        let items = scaled([p, s, v, oil], to: target)
        let sideName = side.name.replacingOccurrences(of: " варёная", with: "")
            .replacingOccurrences(of: " варёный", with: "").replacingOccurrences(of: " варёные", with: "")
            .lowercased()
        let name = "\(protein.name) с \(instrumental(sideName)) и \(veg.lowercased())"
        return NutritionDishDraft(
            name: name, meal: meal, minutes: 25, ingredients: items,
            steps: [protein.step, "Гарнир (\(side.name.lowercased())) приготовить или разогреть.",
                    "Овощи (\(veg.lowercased())) нарезать, посолить, заправить маслом.", "Подать всё вместе."]
        )
    }

    /// Падеж «с чем?» для гарниров.
    private static func instrumental(_ side: String) -> String {
        switch side {
        case "гречка": "гречкой"
        case "рис": "рисом"
        case "картофель": "картофелем"
        case "макароны": "макаронами"
        case "картофельное пюре": "пюре"
        default: side
        }
    }
}
