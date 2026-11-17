import SwiftData
import SwiftUI

/// Дневные цели: калории, БЖУ и вода.
struct NutritionGoalsView: View {
    let member: CoupleMember

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [NutritionGoal]

    @State private var calories = NutritionTargets.standard.calories
    @State private var protein = NutritionTargets.standard.protein
    @State private var fat = NutritionTargets.standard.fat
    @State private var carbs = NutritionTargets.standard.carbs
    @State private var water = NutritionTargets.standard.water
    @State private var loaded = false

    init(member: CoupleMember) {
        self.member = member
        let memberID = member.rawValue
        _goals = Query(filter: #Predicate<NutritionGoal> { $0.member == memberID })
    }

    var body: some View {
        Form {
            Section {
                field("Калории", unit: "ккал", value: $calories)
            } footer: {
                Text("Сколько калорий в день вы хотите съедать.")
            }

            Section("БЖУ") {
                field("Белки", unit: "г", value: $protein)
                field("Жиры", unit: "г", value: $fat)
                field("Углеводы", unit: "г", value: $carbs)
            }

            Section("Вода") {
                Stepper(value: $water, in: 500...5000, step: 250) {
                    Text("\(water) мл")
                }
            }

            Section {
                Button("Сбросить к стандартным") {
                    apply(.standard)
                }
            }
        }
        .navigationTitle("Мои цели")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", action: save)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let goal = goals.first { apply(goal.targets) }
        }
    }

    private func field(_ title: String, unit: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func apply(_ targets: NutritionTargets) {
        calories = targets.calories
        protein = targets.protein
        fat = targets.fat
        carbs = targets.carbs
        water = targets.water
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
        goal.water = water
        goal.deletedAt = nil
        goal.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
