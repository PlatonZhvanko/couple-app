import SwiftData
import SwiftUI

/// Окно «Добавить еду» и правка уже записанной еды.
struct NutritionEntryEditor: View {
    let member: CoupleMember
    let dayKey: String
    /// nil — новая запись.
    let entry: NutritionEntry?

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @Query private var favorites: [NutritionFavorite]

    @State private var name: String
    @State private var meal: NutritionMealType
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var fat: Double?
    @State private var carbs: Double?
    @State private var saveToFavorites = false

    init(member: CoupleMember, dayKey: String, meal: NutritionMealType, entry: NutritionEntry?) {
        self.member = member
        self.dayKey = dayKey
        self.entry = entry
        _name = State(initialValue: entry?.name ?? "")
        _meal = State(initialValue: entry?.mealType ?? meal)
        _calories = State(initialValue: entry?.calories)
        _protein = State(initialValue: entry?.protein)
        _fat = State(initialValue: entry?.fat)
        _carbs = State(initialValue: entry?.carbs)
        let memberID = member.rawValue
        _favorites = Query(
            filter: #Predicate<NutritionFavorite> { $0.deletedAt == nil && $0.member == memberID },
            sort: \NutritionFavorite.name
        )
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var canSave: Bool { !trimmedName.isEmpty || (calories ?? 0) > 0 }

    /// Избранное, подходящее под введённое название.
    private var matchingFavorites: [NutritionFavorite] {
        guard !trimmedName.isEmpty else { return favorites }
        return favorites.filter { $0.name.localizedCaseInsensitiveContains(trimmedName) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что съели", text: $name)
                    Picker("Приём пищи", selection: $meal) {
                        ForEach(NutritionMealType.allCases) { meal in
                            Text(meal.title).tag(meal)
                        }
                    }
                }

                Section("Калории и БЖУ") {
                    numberField("Калории", unit: "ккал", value: $calories)
                    numberField("Белки", unit: "г", value: $protein)
                    numberField("Жиры", unit: "г", value: $fat)
                    numberField("Углеводы", unit: "г", value: $carbs)
                }

                if entry == nil {
                    Section {
                        Toggle("Сохранить в избранное", isOn: $saveToFavorites)
                    }

                    if !matchingFavorites.isEmpty {
                        Section("Избранное") {
                            ForEach(matchingFavorites) { favorite in
                                Button {
                                    fill(from: favorite)
                                } label: {
                                    HStack {
                                        Text(favorite.name)
                                        Spacer()
                                        Text("\(favorite.calories.nutritionText) ккал")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                            .onDelete(perform: deleteFavorites)
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Добавить еду" : "Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func numberField(_ title: String, unit: String, value: Binding<Double?>) -> some View {
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

    private func fill(from favorite: NutritionFavorite) {
        name = favorite.name
        calories = favorite.calories
        protein = favorite.protein
        fat = favorite.fat
        carbs = favorite.carbs
        saveToFavorites = false
    }

    private func deleteFavorites(at offsets: IndexSet) {
        let items = matchingFavorites
        for index in offsets { items[index].markDeleted() }
        try? context.save()
        sync.requestSync()
    }

    private func save() {
        let target = entry ?? {
            let new = NutritionEntry(member: member, dayKey: dayKey, meal: meal)
            context.insert(new)
            return new
        }()
        target.name = trimmedName
        target.meal = meal.rawValue
        target.calories = max(calories ?? 0, 0)
        target.protein = max(protein ?? 0, 0)
        target.fat = max(fat ?? 0, 0)
        target.carbs = max(carbs ?? 0, 0)
        target.markChanged()

        if saveToFavorites, !trimmedName.isEmpty,
           !favorites.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            context.insert(NutritionFavorite(
                member: member,
                name: trimmedName,
                calories: target.calories,
                protein: target.protein,
                fat: target.fat,
                carbs: target.carbs
            ))
        }

        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
