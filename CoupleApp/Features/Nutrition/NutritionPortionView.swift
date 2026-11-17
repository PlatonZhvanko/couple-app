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

    @State private var grams: Double?
    @State private var meal: NutritionMealType

    init(food: NutritionFoodValues, initialGrams: Double? = nil, showsMeal: Bool = true,
         meal: NutritionMealType = .snack, confirmTitle: String = "Записать",
         onConfirm: @escaping (NutritionFoodValues, Double, NutritionMealType) -> Void) {
        self.food = food
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
    private var totals: NutritionTotals { food.totals(grams: current) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.displayName).font(.headline)
                    Text("На 100 г: \(food.kcal.nutritionText) ккал · Б \(food.protein.nutritionText) · Ж \(food.fat.nutritionText) · У \(food.carbs.nutritionText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                Button(confirmTitle) { onConfirm(food, current, meal) }
                    .disabled(current <= 0)
            }
        }
    }

    private var pieces: Binding<Double> {
        Binding(
            get: { (current / max(food.pieceGrams, 1) * 2).rounded() / 2 },
            set: { grams = $0 * food.pieceGrams }
        )
    }
}
