import SwiftData
import SwiftUI

/// Куда записывать выбранный продукт.
struct NutritionDiaryTarget {
    let member: CoupleMember
    let dayKey: String
    let meal: NutritionMealType
}

/// Поиск продукта: встроенная база, свои продукты и блюда, интернет.
/// Работает в двух режимах: запись в дневник или выбор ингредиента для блюда.
struct NutritionFoodPicker: View {
    /// Если задано — выбранное идёт в дневник.
    var diary: NutritionDiaryTarget?
    /// Если задано — выбираем ингредиент и возвращаем его наружу.
    var onPickIngredient: ((NutritionFoodValues, Double) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<NutritionFood> { $0.deletedAt == nil }, sort: \NutritionFood.name)
    private var myFoods: [NutritionFood]
    @Query(filter: #Predicate<NutritionDish> { $0.deletedAt == nil }, sort: \NutritionDish.name)
    private var myDishes: [NutritionDish]
    @Query(sort: \NutritionEntry.createdAt, order: .reverse)
    private var allEntries: [NutritionEntry]

    private enum Source: String, CaseIterable, Identifiable {
        case base = "База"
        case mine = "Мои"
        case web = "Магазины"
        var id: String { rawValue }
    }

    @State private var source: Source = .base
    @State private var query = ""
    @State private var webQuery = ""
    @State private var store: String?
    @State private var webResults: [NutritionOFFProduct] = []
    @State private var webState: WebState = .idle
    @State private var showingNewFood = false
    @State private var showingManual = false

    private enum WebState { case idle, loading, failed, done }

    private var tokens: [String] {
        query.lowercased().split(separator: " ").map(String.init)
    }

    private func matches(_ values: NutritionFoodValues) -> Bool {
        guard !tokens.isEmpty else { return true }
        let haystack = values.displayName.lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Где искать", selection: $source) {
                        ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch source {
                case .base: baseSections
                case .mine: mineSections
                case .web: webSections
                }
            }
            .searchable(text: source == .web ? $webQuery : $query, prompt: "Название продукта")
            .onSubmit(of: .search) {
                if source == .web { Task { await runWebSearch() } }
            }
            .navigationTitle(diary?.meal.title ?? "Продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Свой продукт", systemImage: "plus") { showingNewFood = true }
                        if diary != nil {
                            Button("Только калории вручную", systemImage: "pencil") { showingManual = true }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewFood) {
                NutritionFoodEditor(member: account.current)
            }
            .sheet(isPresented: $showingManual) {
                if let diary {
                    NutritionEntryEditor(member: diary.member, dayKey: diary.dayKey, meal: diary.meal, entry: nil)
                }
            }
        }
    }

    // MARK: База

    @ViewBuilder private var baseSections: some View {
        if query.isEmpty, diary != nil, !recent.isEmpty {
            Section("Недавние") {
                ForEach(recent, id: \.name) { food in
                    row(food, subtitle: nil)
                }
            }
        }
        if query.isEmpty {
            ForEach(NutritionFoodData.categories, id: \.self) { category in
                Section(category) {
                    ForEach(NutritionFoodData.foods.filter { $0.category == category }, { item in
                        row(item.values, subtitle: nil)
                    }
                }
            }
        } else {
            let found = NutritionFoodData.foods.filter { matches($0.values) }
            Section("Найдено: \(found.count)") {
                ForEach(found, { item in
                    row(item.values, subtitle: item.category)
                }
            }
            if found.isEmpty {
                Text("В базе нет. Попробуйте вкладку «Магазины» или создайте свой продукт (+).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Недавно записанные продукты без повторов.
    private var recent: [NutritionFoodValues] {
        var seen = Set<String>()
        var result: [NutritionFoodValues] = []
        for entry in allEntries where entry.deletedAt == nil && entry.grams > 0 && entry.kcal100 > 0 {
            guard seen.insert(entry.name).inserted else { continue }
            result.append(NutritionFoodValues(
                name: entry.name, kcal: entry.kcal100, protein: entry.protein100,
                fat: entry.fat100, carbs: entry.carbs100, defaultGrams: entry.grams
            ))
            if result.count >= 8 { break }
        }
        return result
    }

    // MARK: Мои

    @ViewBuilder private var mineSections: some View {
        let dishes = myDishes.filter { matches($0.values) }
        let foods = myFoods.filter { matches($0.values) }
        if !dishes.isEmpty {
            Section("Мои блюда") {
                ForEach(dishes) { dish in
                    row(dish.values, subtitle: "порция \(dish.values.defaultGrams.nutritionText) г")
                }
            }
        }
        if !foods.isEmpty {
            Section("Мои продукты") {
                ForEach(foods) { food in
                    row(food.values, subtitle: food.store.isEmpty ? nil : food.store)
                }
                .onDelete { offsets in
                    for index in offsets { foods[index].markDeleted() }
                    try? context.save()
                    sync.requestSync()
                }
            }
        }
        if dishes.isEmpty && foods.isEmpty {
            Text("Пока пусто. Свои продукты — кнопка «+», блюда — в разделе «Мои блюда».")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Магазины (Open Food Facts)

    @ViewBuilder private var webSections: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Все магазины", selected: store == nil) { store = nil }
                    ForEach(NutritionOpenFoodFacts.stores, id: \.self) { name in
                        chip(name, selected: store == name) { store = name }
                    }
                }
            }
            Button {
                Task { await runWebSearch() }
            } label: {
                Label("Искать в интернете", systemImage: "magnifyingglass")
            }
            .disabled(webQuery.trimmingCharacters(in: .whitespaces).isEmpty)
        } footer: {
            Text("Данные из Open Food Facts (открытая база упаковок, вносят пользователи). Нужен интернет. Найденное сохраняется в «Мои» и дальше работает без сети.")
        }

        switch webState {
        case .idle:
            EmptyView()
        case .loading:
            HStack { ProgressView(); Text("Ищу…") }
        case .failed:
            Text("Не удалось найти. Проверьте интернет и попробуйте ещё раз.")
                .foregroundStyle(.secondary)
        case .done:
            if webResults.isEmpty {
                Text("Ничего не нашлось. Попробуйте другой запрос или «Все магазины».")
                    .foregroundStyle(.secondary)
            } else {
                Section("Найдено: \(webResults.count)") {
                    ForEach(webResults) { product in
                        row(product.values, subtitle: product.store.isEmpty ? nil : product.store, web: product)
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(selected ? .accentColor : .gray)
            .font(.footnote)
    }

    private func runWebSearch() async {
        let text = webQuery.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        webState = .loading
        do {
            webResults = try await NutritionOpenFoodFacts.search(text, store: store)
            webState = .done
        } catch {
            webState = .failed
        }
    }

    // MARK: Строка и порция

    private func row(_ food: NutritionFoodValues, subtitle: String?, web: NutritionOFFProduct? = nil) -> some View {
        NavigationLink {
            NutritionPortionView(
                food: food,
                showsMeal: diary != nil,
                meal: diary?.meal ?? .snack,
                confirmTitle: diary != nil ? "Записать" : "Добавить",
                onSaveFood: { saveCustom($0) }
            ) { values, grams, meal in
                if let web { cache(web) }
                confirm(values, grams, meal)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.displayName)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(food.kcal.nutritionText) ккал")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func confirm(_ values: NutritionFoodValues, _ grams: Double, _ meal: NutritionMealType) {
        if let diary {
            let entry = NutritionEntry(member: diary.member, dayKey: diary.dayKey, meal: meal)
            context.insert(entry)
            entry.meal = meal.rawValue
            entry.set(food: values, grams: grams)
            entry.markChanged()
            try? context.save()
            sync.requestSync()
        } else {
            onPickIngredient?(values, grams)
        }
        dismiss()
    }

    /// Сохранить исправленный продукт как свой.
    private func saveCustom(_ values: NutritionFoodValues) {
        let food = NutritionFood(member: account.current)
        food.name = values.name
        food.brand = values.brand
        food.kcal = values.kcal
        food.protein = values.protein
        food.fat = values.fat
        food.carbs = values.carbs
        food.pieceGrams = values.pieceGrams
        context.insert(food)
        try? context.save()
        sync.requestSync()
    }

    /// Запоминаем найденный в интернете продукт, чтобы он был и без сети.
    private func cache(_ product: NutritionOFFProduct) {
        guard !myFoods.contains(where: { !$0.barcode.isEmpty && $0.barcode == product.barcode }) else { return }
        let food = NutritionFood(member: account.current)
        food.name = product.values.name
        food.brand = product.values.brand
        food.store = product.store
        food.barcode = product.barcode
        food.source = "off"
        food.kcal = product.values.kcal
        food.protein = product.values.protein
        food.fat = product.values.fat
        food.carbs = product.values.carbs
        context.insert(food)
    }
}

/// Создание своего продукта с ценностью на 100 г.
struct NutritionFoodEditor: View {
    let member: CoupleMember

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var fat: Double?
    @State private var carbs: Double?
    @State private var piece: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                    TextField("Бренд (необязательно)", text: $brand)
                }
                Section("На 100 г") {
                    field("Калории", "ккал", $kcal)
                    field("Белки", "г", $protein)
                    field("Жиры", "г", $fat)
                    field("Углеводы", "г", $carbs)
                }
                Section {
                    field("Вес одной штуки", "г", $piece)
                } footer: {
                    Text("Необязательно: например, для яйца 55 г, чтобы считать в штуках.")
                }
            }
            .navigationTitle("Свой продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (kcal ?? 0) <= 0)
                }
            }
        }
    }

    private func field(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
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

    private func save() {
        let food = NutritionFood(member: member)
        food.name = name.trimmingCharacters(in: .whitespaces)
        food.brand = brand.trimmingCharacters(in: .whitespaces)
        food.kcal = max(kcal ?? 0, 0)
        food.protein = max(protein ?? 0, 0)
        food.fat = max(fat ?? 0, 0)
        food.carbs = max(carbs ?? 0, 0)
        food.pieceGrams = max(piece ?? 0, 0)
        context.insert(food)
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
