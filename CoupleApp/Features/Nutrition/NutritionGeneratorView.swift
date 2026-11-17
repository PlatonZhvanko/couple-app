import SwiftData
import SwiftUI

/// Генератор рациона для одного приёма пищи: несколько вариантов блюд с рецептом.
struct NutritionGeneratorView: View {
    let diary: NutritionDiaryTarget
    let dailyCalories: Double

    @Environment(\.dismiss) private var dismiss

    @State private var target: Double
    @State private var drafts: [NutritionDishDraft] = []
    @State private var shown: Set<String> = []

    init(diary: NutritionDiaryTarget, dailyCalories: Double) {
        self.diary = diary
        self.dailyCalories = dailyCalories
        _target = State(initialValue: NutritionGenerator.targetCalories(for: diary.meal, daily: dailyCalories))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $target, in: 50...2000, step: 50) {
                        Text("Около \(target.nutritionText) ккал")
                    }
                    Button {
                        regenerate()
                    } label: {
                        Label("Показать другие варианты", systemImage: "arrow.triangle.2.circlepath")
                    }
                } footer: {
                    Text("Калории приёма пищи — доля от суточной нормы (\(dailyCalories.nutritionText) ккал). Можно поменять.")
                }

                Section("Варианты") {
                    ForEach(drafts) { draft in
                        NavigationLink {
                            NutritionDraftDetail(draft: draft, diary: diary) { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(draft.name)
                                Text("\(draft.total.calories.nutritionText) ккал · Б \(draft.total.protein.nutritionText) · Ж \(draft.total.fat.nutritionText) · У \(draft.total.carbs.nutritionText) · \(draft.minutes) мин")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Рацион: \(diary.meal.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .onChange(of: target) { regenerate(daily: true) }
            .onAppear { if drafts.isEmpty { regenerate(daily: true) } }
        }
    }

    /// Первый показ зависит от даты: сегодня одни варианты, завтра другие.
    /// Кнопка «другие варианты» даёт случайные новые.
    private func regenerate(daily: Bool = false) {
        let seed = daily ? NutritionRNG.seed(from: "\(diary.dayKey)-\(diary.meal.rawValue)-\(Int(target))") : nil
        drafts = NutritionGenerator.generate(meal: diary.meal, targetCalories: target,
                                             avoiding: daily ? [] : shown, seed: seed)
        shown.formUnion(drafts.map(\.name))
    }
}

/// Блюдо из генератора: ингредиенты, рецепт, запись в дневник.
struct NutritionDraftDetail: View {
    let draft: NutritionDishDraft
    let diary: NutritionDiaryTarget
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @State private var saved = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(draft.total.calories.nutritionText) ккал")
                        .font(.title.bold())
                    Text("Белки \(draft.total.protein.nutritionText) г · Жиры \(draft.total.fat.nutritionText) г · Углеводы \(draft.total.carbs.nutritionText) г")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Вес \(draft.weight.nutritionText) г · \(draft.minutes) мин")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Ингредиенты") {
                ForEach(draft.ingredients) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text("\(item.grams.nutritionText) г").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Рецепт") {
                ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
            }
            Section {
                NavigationLink {
                    NutritionPortionView(
                        food: draft.values, initialGrams: draft.weight, meal: diary.meal,
                        confirmTitle: "Записать"
                    ) { values, grams, meal in
                        let entry = NutritionEntry(member: diary.member, dayKey: diary.dayKey, meal: meal)
                        context.insert(entry)
                        entry.meal = meal.rawValue
                        entry.set(food: values, grams: grams)
                        entry.markChanged()
                        try? context.save()
                        sync.requestSync()
                        onFinish()
                    }
                } label: {
                    Label("Записать в \(diary.meal.title.lowercased())", systemImage: "plus.circle.fill")
                }
                Button {
                    saveDish()
                } label: {
                    Label(saved ? "Сохранено в «Мои блюда»" : "Сохранить в «Мои блюда»",
                          systemImage: saved ? "checkmark" : "tray.and.arrow.down")
                }
                .disabled(saved)
            } footer: {
                Text("При записи вес порции можно поправить.")
            }
        }
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveDish() {
        let dish = NutritionDish(member: diary.member)
        context.insert(dish)
        dish.name = draft.name
        dish.servings = 1
        dish.recipe = draft.steps.joined(separator: "\n")
        dish.ingredients = draft.ingredients
        dish.markChanged()
        try? context.save()
        sync.requestSync()
        saved = true
    }
}
