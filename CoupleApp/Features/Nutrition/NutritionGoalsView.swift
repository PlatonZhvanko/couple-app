import SwiftData
import SwiftUI

/// Калькулятор суточной нормы: считает калории и БЖУ, норму можно поправить вручную.
struct NutritionGoalsView: View {
    let member: CoupleMember

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [NutritionGoal]

    @State private var sex = "female"
    @State private var age: Int? = 25
    @State private var height: Double? = 165
    @State private var weight: Double? = 60
    @State private var activity = 1.4
    @State private var aim = "keep"

    @State private var calories = NutritionTargets.standard.calories
    @State private var protein = NutritionTargets.standard.protein
    @State private var fat = NutritionTargets.standard.fat
    @State private var carbs = NutritionTargets.standard.carbs
    @State private var loaded = false

    init(member: CoupleMember) {
        self.member = member
        let memberID = member.rawValue
        _goals = Query(filter: #Predicate<NutritionGoal> { $0.member == memberID })
    }

    private static let activities: [(Double, String)] = [
        (1.2, "Сидячий образ жизни"), (1.375, "Лёгкая активность (1–3 тренировки)"),
        (1.55, "Средняя (3–5 тренировок)"), (1.725, "Высокая (6–7 тренировок)"),
    ]

    /// Основной обмен по формуле Миффлина — Сан-Жеора.
    private var bmr: Double {
        let base = 10 * (weight ?? 0) + 6.25 * (height ?? 0) - 5 * Double(age ?? 0)
        return sex == "male" ? base + 5 : base - 161
    }

    private var maintenance: Double { bmr * activity }

    private var suggested: Double {
        let factor: Double = aim == "lose" ? 0.85 : (aim == "gain" ? 1.10 : 1.0)
        return (maintenance * factor / 10).rounded() * 10
    }

    private var suggestedMacros: (p: Double, f: Double, c: Double) {
        let kg = weight ?? 0
        let p = (kg * (aim == "lose" ? 2.0 : 1.7)).rounded()
        let f = (kg * 0.9).rounded()
        let c = max(((suggested - p * 4 - f * 9) / 4).rounded(), 0)
        return (p, f, c)
    }

    var body: some View {
        Form {
            Section("О вас") {
                Picker("Пол", selection: $sex) {
                    Text("Женщина").tag("female")
                    Text("Мужчина").tag("male")
                }
                .pickerStyle(.segmented)
                intField("Возраст", "лет", $age)
                numberField("Рост", "см", $height)
                numberField("Вес", "кг", $weight)
                Picker("Активность", selection: $activity) {
                    ForEach(Self.activities, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Цель", selection: $aim) {
                    Text("Похудеть").tag("lose")
                    Text("Держать вес").tag("keep")
                    Text("Набрать").tag("gain")
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("На месте (обмен)", value: "\(bmr.nutritionText) ккал")
                LabeledContent("С учётом активности", value: "\(maintenance.nutritionText) ккал")
                LabeledContent("Рекомендую для цели", value: "\(suggested.nutritionText) ккал")
                Button("Подставить расчёт в норму") {
                    calories = suggested
                    protein = suggestedMacros.p
                    fat = suggestedMacros.f
                    carbs = suggestedMacros.c
                }
            } header: {
                Text("Расчёт")
            } footer: {
                Text("Ориентир, не медицинская рекомендация. При похудении −15%, при наборе +10% к норме поддержания.")
            }

            Section {
                field("Калории в день", "ккал", $calories)
            } header: {
                Text("Моя норма")
            } footer: {
                Text("Главное — калории. БЖУ ниже по желанию, их можно не трогать.")
            }

            Section("БЖУ (по желанию)") {
                field("Белки", "г", $protein)
                field("Жиры", "г", $fat)
                field("Углеводы", "г", $carbs)
            }
        }
        .navigationTitle("Моя норма")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", action: save)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let goal = goals.first {
                sex = goal.sex
                age = goal.age
                height = goal.heightCm
                weight = goal.weightKg
                activity = goal.activity
                aim = goal.aim
                calories = goal.calories
                protein = goal.protein
                fat = goal.fat
                carbs = goal.carbs
            }
        }
    }

    private func field(_ title: String, _ unit: String, _ value: Binding<Double>) -> some View {
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

    private func numberField(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
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

    private func intField(_ title: String, _ unit: String, _ value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let goal = goals.first ?? {
            let new = NutritionGoal(member: member)
            context.insert(new)
            return new
        }()
        goal.calories = max(calories, 0)
        goal.protein = max(protein, 0)
        goal.fat = max(fat, 0)
        goal.carbs = max(carbs, 0)
        goal.sex = sex
        goal.age = age ?? 25
        goal.heightCm = height ?? 165
        goal.weightKg = weight ?? 60
        goal.activity = activity
        goal.aim = aim
        goal.deletedAt = nil
        goal.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
