import SwiftUI

/// Выбор веса порции: вес всегда можно поправить вручную, калории пересчитываются сами.
/// Определяет, жидкость ли продукт (по названию): для неё объём вводится в мл или литрах.
enum NutritionLiquid {
    private static let words = [
        "сок", "напит", "молоко", "кефир", "суп", "борщ", "щи", "бульон", "вода", "чай", "кофе", "компот",
        "морс", "квас", "пиво", "вино", "кола", "лимонад", "смузи", "коктейль", "какао", "ряженка", "уха",
        "солянка", "окрошка", "харчо", "сливки", "кисель", "простокваша", "ацидофилин", "тан", "айран",
        "капучино", "латте", "американо", "эспрессо", "водка", "виски", "коньяк", "ром", "джин", "ликёр",
        "мартини", "сидр", "шампанское", "тоник", "энергетик", "изотоник", "пепси", "фанта", "спрайт",
        "рамен", "рассольник", "лагман", "мисо", "том ям", "флэт", "раф", "мокка", "нектар", "газировка",
    ]

    static func isLiquid(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return words.contains { lowered.contains($0) }
    }
}

/// Единица ввода порции. Для напитков 1 мл считаем как 1 г.
enum NutritionPortionUnit: String, CaseIterable, Identifiable {
    case gram = "г"
    case milliliter = "мл"
    case liter = "л"

    var id: String { rawValue }
}

struct NutritionPortionView: View {
    let food: NutritionFoodValues
    var initialGrams: Double
    var showsMeal: Bool
    var initialMeal: NutritionMealType
    var confirmTitle: String
    /// Что сделать при подтверждении: продукт, граммы, приём пищи.
    var onConfirm: (NutritionFoodValues, Double, NutritionMealType) -> Void
    /// Если задано, можно сохранить исправленный продукт как свой.
    var onSaveFood: ((NutritionFoodValues) -> Void)?

    @State private var grams: Double?
    @State private var meal: NutritionMealType
    @State private var kcal100: Double?
    @State private var protein100: Double?
    @State private var fat100: Double?
    @State private var carbs100: Double?
    @State private var saveAsMine = false
    @State private var unit: NutritionPortionUnit

    init(food: NutritionFoodValues, initialGrams: Double? = nil, showsMeal: Bool = true,
         meal: NutritionMealType = .snack, confirmTitle: String = "Записать",
         onSaveFood: ((NutritionFoodValues) -> Void)? = nil,
         onConfirm: @escaping (NutritionFoodValues, Double, NutritionMealType) -> Void) {
        self.food = food
        self.onSaveFood = onSaveFood
        _kcal100 = State(initialValue: food.kcal)
        _protein100 = State(initialValue: food.protein)
        _fat100 = State(initialValue: food.fat)
        _carbs100 = State(initialValue: food.carbs)
        let start = initialGrams ?? food.defaultGrams
        self.initialGrams = start
        self.showsMeal = showsMeal
        self.initialMeal = meal
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        _grams = State(initialValue: start)
        _meal = State(initialValue: meal)
        _unit = State(initialValue: NutritionLiquid.isLiquid(food.name) ? .milliliter : .gram)
    }

    private var current: Double { max(grams ?? 0, 0) }
    /// Продукт с учётом поправленных значений на 100 г.
    private var edited: NutritionFoodValues {
        var copy = food
        copy.kcal = max(kcal100 ?? 0, 0)
        copy.protein = max(protein100 ?? 0, 0)
        copy.fat = max(fat100 ?? 0, 0)
        copy.carbs = max(carbs100 ?? 0, 0)
        return copy
    }
    private var totals: NutritionTotals { edited.totals(grams: current) }
    private var isChanged: Bool { edited != food }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.displayName).font(.headline)
                }
            }

            Section {
                valueField("Калории", "ккал", $kcal100)
                valueField("Белки", "г", $protein100)
                valueField("Жиры", "г", $fat100)
                valueField("Углеводы", "г", $carbs100)
                if onSaveFood != nil && isChanged {
                    Toggle("Сохранить как мой продукт", isOn: $saveAsMine)
                }
            } header: {
                Text(unit == .gram ? "На 100 г" : "На 100 г / мл")
            } footer: {
                Text("Значения можно поправить по упаковке: пересчёт порции идёт сразу.")
            }

            Section {
                Picker("Единица", selection: $unit) {
                    ForEach(NutritionPortionUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(unit == .gram ? "Вес" : "Объём")
                    Spacer()
                    TextField("0", value: amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                    Text(unit.rawValue).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(unit == .liter ? [-0.5, -0.1, 0.1, 0.5] : [-50.0, -10.0, 10.0, 50.0], id: \.self) { step in
                        Button(stepTitle(step)) {
                            grams = max(current + (unit == .liter ? step * 1000 : step), 0)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                if unit != .gram {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            presetButton("Стакан 250 мл", 250)
                            presetButton("Кружка 300 мл", 300)
                            presetButton("Бутылка 0,5 л", 500)
                            presetButton("Пачка 1 л", 1000)
                        }
                    }
                }
                if food.pieceGrams > 0 {
                    Stepper(value: pieces, in: 0...100, step: 0.5) {
                        Text("Штук: \(pieces.wrappedValue.nutritionText) (по \(food.pieceGrams.nutritionText) г)")
                    }
                }
            } header: {
                Text(unit == .gram ? "Вес порции" : "Объём порции")
            } footer: {
                if unit != .gram {
                    Text("Для напитков и супов 1 мл считаем как 1 г. Объём указан на упаковке, ккал на 100 г/мл берите оттуда же.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(totals.calories.nutritionText) ккал")
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("Белки \(totals.protein.nutritionText) г · Жиры \(totals.fat.nutritionText) г · Углеводы \(totals.carbs.nutritionText) г")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("В этой порции")
            }

            if showsMeal {
                Section {
                    Picker("Приём пищи", selection: $meal) {
                        ForEach(NutritionMealType.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Порция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) {
                    if saveAsMine, isChanged { onSaveFood?(edited) }
                    onConfirm(edited, current, meal)
                }
                    .disabled(current <= 0)
            }
        }
    }

    private func valueField(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    /// Значение в выбранной единице: граммы и мл хранятся как есть, литры переводятся.
    private var amount: Binding<Double?> {
        Binding(
            get: { unit == .liter ? (grams.map { $0 / 1000 }) : grams },
            set: { value in grams = unit == .liter ? value.map { $0 * 1000 } : value }
        )
    }

    private func stepTitle(_ step: Double) -> String {
        let value = abs(step).nutritionText
        return step > 0 ? "+\(value)" : "−\(value)"
    }

    private func presetButton(_ title: String, _ value: Double) -> some View {
        Button(title) { grams = value }
            .buttonStyle(.bordered)
            .font(.footnote)
    }

    private var pieces: Binding<Double> {
        Binding(
            get: { (current / max(food.pieceGrams, 1) * 2).rounded() / 2 },
            set: { grams = $0 * food.pieceGrams }
        )
    }
}
