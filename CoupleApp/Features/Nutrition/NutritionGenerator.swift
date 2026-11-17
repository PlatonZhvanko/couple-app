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

/// Генератор случайных чисел: с зерном даёт одинаковый результат в пределах дня,
/// без зерна — каждый раз новый.
struct NutritionRNG: RandomNumberGenerator {
    private var state: UInt64
    private let seeded: Bool
    private var system = SystemRandomNumberGenerator()

    init(seed: UInt64?) {
        state = seed ?? 0
        seeded = seed != nil
    }

    mutating func next() -> UInt64 {
        guard seeded else { return system.next() }
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Зерно из строки (день + приём пищи): одно и то же в течение дня, разное по дням.
    static func seed(from text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return hash
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
    /// `seed` — зерно для варианта дня: на один день одни и те же блюда, завтра другие.
    /// Без зерна каждый вызов даёт новый набор.
    static func generate(meal: NutritionMealType, targetCalories: Double, count: Int = 6,
                         avoiding: Set<String> = [], seed: UInt64? = nil) -> [NutritionDishDraft] {
        var rng = NutritionRNG(seed: seed)
        var result: [NutritionDishDraft] = []

        var fresh = NutritionRecipeData.recipes.filter { $0.meal == meal && !avoiding.contains($0.name) }
        if fresh.count < count {
            // Все варианты уже показывали — начинаем круг заново.
            fresh = NutritionRecipeData.recipes.filter { $0.meal == meal }
        }
        fresh.shuffle(using: &rng)

        let comboCount = (meal == .snack || meal == .breakfast) ? count / 2 : count / 3
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
            if let combo = makeCombo(meal: meal, target: targetCalories, rng: &rng),
               !combos.contains(where: { $0.name == combo.name }), !avoiding.contains(combo.name) {
                combos.append(combo)
            }
        }
        result.append(contentsOf: combos)
        return result.shuffled(using: &rng)
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

    private static func makeCombo(meal: NutritionMealType, target: Double,
                                  rng: inout NutritionRNG) -> NutritionDishDraft? {
        switch meal {
        case .breakfast: return breakfastCombo(target: target, rng: &rng)
        case .snack: return snackCombo(target: target, rng: &rng)
        default: return mainCombo(meal: meal, target: target, rng: &rng)
        }
    }

    private static func mainCombo(meal: NutritionMealType, target: Double,
                                  rng: inout NutritionRNG) -> NutritionDishDraft? {
        guard let protein = proteins.randomElement(using: &rng), let side = sides.randomElement(using: &rng),
              let veg = vegetables.randomElement(using: &rng),
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

    // Завтраки: основа + добавка + фрукт/ягоды + топпинг.
    private static let breakfastBases: [(name: String, items: [(String, Double)], step: String)] = [
        ("Овсянка на молоке", [("Овсяные хлопья", 50), ("Молоко 2.5%", 200)], "Сварить хлопья на молоке 5–7 минут, помешивая."),
        ("Овсянка на воде", [("Овсяные хлопья", 50), ("Вода", 150)], "Сварить хлопья на воде 5 минут."),
        ("Гречневая каша на молоке", [("Гречка (сухая)", 45), ("Молоко 2.5%", 150)], "Отварить гречку, залить горячим молоком."),
        ("Рисовая каша", [("Рис белый (сухой)", 45), ("Молоко 2.5%", 200)], "Варить рис в молоке 20 минут."),
        ("Пшённая каша", [("Пшено (сухое)", 45), ("Молоко 2.5%", 200)], "Варить пшено в молоке 20 минут."),
        ("Творог", [("Творог 5%", 180)], "Выложить творог в миску."),
        ("Творог 0%", [("Творог 0%", 200)], "Выложить творог в миску."),
        ("Греческий йогурт", [("Йогурт греческий", 200)], "Выложить йогурт в миску."),
        ("Кефир с хлопьями", [("Кефир 1%", 200), ("Овсяные хлопья", 40)], "Залить хлопья кефиром и подождать 10 минут."),
        ("Омлет", [("Яйцо куриное", 165), ("Молоко 2.5%", 50), ("Масло подсолнечное", 5)], "Взбить яйца с молоком, жарить под крышкой 5 минут."),
        ("Яичница", [("Яйцо куриное", 110), ("Масло подсолнечное", 5)], "Пожарить яичницу из двух яиц."),
        ("Варёные яйца с хлебом", [("Яйцо куриное", 110), ("Хлеб цельнозерновой", 50)], "Отварить яйца 9 минут и подать с хлебом."),
        ("Сырники", [("Сырники", 200), ("Сметана 15%", 25)], "Разогреть сырники, подать со сметаной."),
        ("Блины", [("Блины", 150), ("Сметана 15%", 25)], "Разогреть блины, подать со сметаной."),
    ]
    private static let breakfastFruits = [
        "Банан", "Яблоко", "Груша", "Клубника", "Черника", "Малина", "Киви", "Апельсин", "Персик", "Ягоды замороженные (смесь)",
    ]
    private static let breakfastToppings: [(String, Double)] = [
        ("Мёд", 12), ("Грецкий орех", 15), ("Миндаль", 15), ("Семена чиа", 8), ("Изюм", 15),
        ("Курага", 20), ("Арахисовая паста", 15), ("Варенье", 20), ("Гранола", 25),
    ]

    private static func breakfastCombo(target: Double, rng: inout NutritionRNG) -> NutritionDishDraft? {
        guard let base = breakfastBases.randomElement(using: &rng),
              let fruitName = breakfastFruits.randomElement(using: &rng),
              let top = breakfastToppings.randomElement(using: &rng),
              let fruit = ingredient(fruitName, grams: 100),
              let topping = ingredient(top.0, grams: top.1) else { return nil }
        var items = base.items.compactMap { ingredient($0.0, grams: $0.1) }
        guard items.count == base.items.count else { return nil }
        let isEggs = base.name.contains("яйц") || base.name == "Омлет" || base.name == "Яичница"
        var steps = [base.step]
        var name = base.name
        if isEggs {
            if let veg = ingredient("Помидор", grams: 100) { items.append(veg) }
            name += " с помидором"
            steps.append("Нарезать помидор и подать к блюду.")
        } else {
            items.append(fruit)
            items.append(topping)
            name += " с \(fruitName.lowercased().replacingOccurrences(of: " (смесь)", with: "")) и \(topping.name.lowercased())"
            steps.append("Нарезать фрукты (\(fruitName.lowercased())) и добавить сверху.")
            steps.append("Посыпать или полить добавкой: \(topping.name.lowercased()).")
        }
        return NutritionDishDraft(name: name, meal: .breakfast, minutes: 10,
                                  ingredients: scaled(items, to: target), steps: steps)
    }

    // Перекусы: основа + добавка.
    private static let snackBases: [(name: String, items: [(String, Double)], step: String)] = [
        ("Яблоко", [("Яблоко", 180)], "Помыть и нарезать яблоко."),
        ("Банан", [("Банан", 120)], "Очистить банан."),
        ("Груша", [("Груша", 170)], "Помыть и нарезать грушу."),
        ("Апельсин", [("Апельсин", 200)], "Очистить апельсин и разделить на дольки."),
        ("Йогурт натуральный", [("Йогурт натуральный", 150)], "Выложить йогурт в стакан."),
        ("Кефир", [("Кефир 1%", 250)], "Налить кефир в стакан."),
        ("Творог 0%", [("Творог 0%", 150)], "Выложить творог в миску."),
        ("Хлебцы с сыром", [("Хлебцы", 30), ("Сыр творожный", 30)], "Намазать сыр на хлебцы."),
        ("Варёное яйцо", [("Яйцо куриное", 110)], "Отварить яйца 9 минут."),
        ("Огурец и морковь", [("Огурец", 100), ("Морковь", 100)], "Нарезать овощи брусочками."),
        ("Хумус с овощами", [("Хумус", 50), ("Перец болгарский", 100)], "Нарезать овощи и подать с хумусом."),
    ]
    private static let snackAdds: [(String, Double)] = [
        ("Миндаль", 15), ("Грецкий орех", 15), ("Фундук", 15), ("Курага", 25), ("Изюм", 15),
        ("Мёд", 10), ("Семена чиа", 8), ("Шоколад тёмный", 15), ("Арахисовая паста", 15), ("Сыр твёрдый", 25),
    ]

    private static func snackCombo(target: Double, rng: inout NutritionRNG) -> NutritionDishDraft? {
        guard let base = snackBases.randomElement(using: &rng),
              let add = snackAdds.randomElement(using: &rng),
              let extra = ingredient(add.0, grams: add.1) else { return nil }
        var items = base.items.compactMap { ingredient($0.0, grams: $0.1) }
        guard items.count == base.items.count else { return nil }
        items.append(extra)
        let name = "\(base.name) + \(extra.name.lowercased())"
        return NutritionDishDraft(
            name: name, meal: .snack, minutes: 5, ingredients: scaled(items, to: target),
            steps: [base.step, "Добавить: \(extra.name.lowercased())."]
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
