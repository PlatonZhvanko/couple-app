import SwiftUI

/// Выбор веса порции: вес всегда можно поправить вручную, калории пересчитываются сами.
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
                Text("На 100 г")
            } footer: {
                Text("Значения можно поправить по упаковке: пересчёт порции идёт сразу.")
            }

            Section("Вес порции") {
                HStack {
                    Text("Граммы")
                    Spacer()
                    TextField("0", value: $grams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                    Text("г").foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach([-50.0, -10.0, 10.0, 50.0], id: \.self) { step in
                        Button(step > 0 ? "+\(Int(step))" : "−\(Int(-step))") {
                            grams = max(current + step, 0)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                if food.pieceGrams > 0 {
                    Stepper(value: pieces, in: 0...100, step: 0.5) {
                        Text("Штук: \(pieces.wrappedValue.nutritionText) (по \(food.pieceGrams.nutritionText) г)")
                    }
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

    private var pieces: Binding<Double> {
        Binding(
            get: { (current / max(food.pieceGrams, 1) * 2).rounded() / 2 },
            set: { grams = $0 * food.pieceGrams }
        )
    }
}
