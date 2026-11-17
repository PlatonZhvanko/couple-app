import SwiftData
import SwiftUI

/// Список своих блюд.
struct NutritionDishesView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<NutritionDish> { $0.deletedAt == nil }, sort: \NutritionDish.name)
    private var dishes: [NutritionDish]

    @State private var editing: NutritionDishTarget?

    var body: some View {
        List {
            if dishes.isEmpty {
                Text("Своих блюд пока нет. Нажмите «+», чтобы собрать блюдо из продуктов, или сохраните вариант из генератора.")
                    .foregroundStyle(.secondary)
            }
            ForEach(dishes) { dish in
                Button {
                    editing = NutritionDishTarget(dish: dish)
                } label: {
                    let v = dish.values
                    let per = NutritionDishMath.total(dish.ingredients)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(dish.name).foregroundStyle(.primary)
                            Text("\(max(dish.servings, 1)) порц. · \(v.defaultGrams.nutritionText) г порция")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\((per.calories / Double(max(dish.servings, 1))).nutritionText) ккал")
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { dishes[index].markDeleted() }
                try? context.save()
                sync.requestSync()
            }
        }
        .navigationTitle("Мои блюда")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = NutritionDishTarget(dish: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { target in
            NutritionDishEditor(member: account.current, dish: target.dish, draft: nil)
        }
    }
}

struct NutritionDishTarget: Identifiable {
    let id = UUID()
    let dish: NutritionDish?
}

/// Создание и правка блюда: ингредиенты с весом, порции и рецепт.
struct NutritionDishEditor: View {
    let member: CoupleMember
    let dish: NutritionDish?
    let draft: NutritionDishDraft?

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var servings: Int
    @State private var recipe: String
    @State private var ingredients: [NutritionIngredient]
    @State private var addingIngredient = false

    init(member: CoupleMember, dish: NutritionDish?, draft: NutritionDishDraft?) {
        self.member = member
        self.dish = dish
        self.draft = draft
        _name = State(initialValue: dish?.name ?? draft?.name ?? "")
        _servings = State(initialValue: max(dish?.servings ?? 1, 1))
        _recipe = State(initialValue: dish?.recipe ?? draft?.steps.joined(separator: "\n") ?? "")
        _ingredients = State(initialValue: dish?.ingredients ?? draft?.ingredients ?? [])
    }

    private var total: NutritionTotals { NutritionDishMath.total(ingredients) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название блюда", text: $name)
                    Stepper("Порций: \(servings)", value: $servings, in: 1...20)
                }

                Section("Ингредиенты") {
                    ForEach($ingredients) { $item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text("\(item.totals.calories.nutritionText) ккал")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("0", value: $item.grams, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 70)
                            Text("г").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    Button {
                        addingIngredient = true
                    } label: {
                        Label("Добавить продукт", systemImage: "plus")
                    }
                }

                Section {
                    LabeledContent("Всего", value: "\(total.calories.nutritionText) ккал")
                    LabeledContent("На порцию", value: "\((total.calories / Double(servings)).nutritionText) ккал")
                    LabeledContent("Б / Ж / У на порцию",
                                   value: "\((total.protein / Double(servings)).nutritionText) / \((total.fat / Double(servings)).nutritionText) / \((total.carbs / Double(servings)).nutritionText) г")
                    LabeledContent("Вес порции",
                                   value: "\((NutritionDishMath.weight(ingredients) / Double(servings)).nutritionText) г")
                } header: {
                    Text("Итого")
                }

                Section("Рецепт (по шагу в строке)") {
                    TextEditor(text: $recipe)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(dish == nil ? "Новое блюдо" : "Блюдо")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(!canSave)
                }
            }
            .sheet(isPresented: $addingIngredient) {
                NutritionFoodPicker(diary: nil) { food, grams in
                    ingredients.append(NutritionIngredient(
                        name: food.name, grams: grams, kcal100: food.kcal,
                        protein100: food.protein, fat100: food.fat, carbs100: food.carbs
                    ))
                }
            }
        }
    }

    private func save() {
        let target = dish ?? {
            let new = NutritionDish(member: member)
            context.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.servings = servings
        target.recipe = recipe
        target.ingredients = ingredients
        target.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
