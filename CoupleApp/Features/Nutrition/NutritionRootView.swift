import SwiftData
import SwiftUI

/// Главный экран раздела «Питание»: дневник выбранного профиля за выбранный день.
struct NutritionRootView: View {
    @Environment(AccountStore.self) private var account
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            NutritionDayView(
                member: account.current,
                dayKey: NutritionDay.key(for: date),
                date: $date
            )
            .navigationTitle("Питание")
            .catVisit(.chloe, topic: .food)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        NutritionWeekView(member: account.current)
                    } label: {
                        Label("Неделя", systemImage: "chart.bar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            NutritionGoalsView(member: account.current)
                        } label: {
                            Label("Моя норма и калькулятор", systemImage: "target")
                        }
                        NavigationLink {
                            NutritionDishesView()
                        } label: {
                            Label("Мои блюда", systemImage: "fork.knife")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

/// Что открыть поверх дневника.
enum NutritionSheet: Identifiable {
    case add(NutritionMealType)
    case generate(NutritionMealType)
    case manual(NutritionEntry)
    case weight(NutritionEntry)

    var id: String {
        switch self {
        case .add(let meal): "add-\(meal.rawValue)"
        case .generate(let meal): "gen-\(meal.rawValue)"
        case .manual(let entry): "manual-\(entry.syncID)"
        case .weight(let entry): "weight-\(entry.syncID)"
        }
    }
}

/// Дневник одного человека за один день.
struct NutritionDayView: View {
    let member: CoupleMember
    let dayKey: String
    @Binding var date: Date

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query private var entries: [NutritionEntry]
    @Query private var goals: [NutritionGoal]
    @State private var sheet: NutritionSheet?

    init(member: CoupleMember, dayKey: String, date: Binding<Date>) {
        self.member = member
        self.dayKey = dayKey
        _date = date
        let memberID = member.rawValue
        _entries = Query(
            filter: #Predicate<NutritionEntry> { $0.deletedAt == nil && $0.member == memberID && $0.dayKey == dayKey },
            sort: \NutritionEntry.createdAt
        )
        _goals = Query(filter: #Predicate<NutritionGoal> { $0.deletedAt == nil && $0.member == memberID })
    }

    private var targets: NutritionTargets { goals.first?.targets ?? .standard }

    var body: some View {
        List {
            Section {
                dayPicker
            }

            Section {
                NutritionSummaryCard(totals: NutritionTotals.sum(entries), targets: targets)
                    .catAnchor()
            }

            ForEach(NutritionMealType.allCases) { meal in
                mealSection(meal)
            }
        }
        .refreshable { await sync.syncNow() }
        .sheet(item: $sheet) { item in
            switch item {
            case .add(let meal):
                NutritionFoodPicker(diary: NutritionDiaryTarget(member: member, dayKey: dayKey, meal: meal))
            case .generate(let meal):
                NutritionGeneratorView(
                    diary: NutritionDiaryTarget(member: member, dayKey: dayKey, meal: meal),
                    dailyCalories: targets.calories
                )
            case .manual(let entry):
                NutritionEntryEditor(member: member, dayKey: dayKey, meal: entry.mealType, entry: entry)
            case .weight(let entry):
                NavigationStack {
                    NutritionPortionView(
                        food: NutritionFoodValues(
                            name: entry.name, kcal: entry.kcal100, protein: entry.protein100,
                            fat: entry.fat100, carbs: entry.carbs100
                        ),
                        initialGrams: entry.grams, meal: entry.mealType, confirmTitle: "Сохранить"
                    ) { values, grams, meal in
                        entry.kcal100 = values.kcal
                        entry.protein100 = values.protein
                        entry.fat100 = values.fat
                        entry.carbs100 = values.carbs
                        entry.grams = grams
                        entry.meal = meal.rawValue
                        entry.recalculate()
                        entry.markChanged()
                        saveAndSync()
                        sheet = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { sheet = nil }
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Button("Удалить из приёма пищи", role: .destructive) {
                                remove(entry)
                                sheet = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Выбор дня

    private var dayPicker: some View {
        HStack {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(dayTitle)
                .font(.headline)
            Spacer()
            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(date))
        }
        .buttonStyle(.borderless)
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func shiftDay(_ days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: date) {
            date = newDate
        }
    }

    // MARK: Приёмы пищи

    private func mealSection(_ meal: NutritionMealType) -> some View {
        let items = entries.filter { $0.mealType == meal }
        let calories = items.reduce(0) { $0 + $1.calories }
        return Section {
            ForEach(items) { entry in
                Button {
                    sheet = entry.grams > 0 ? .weight(entry) : .manual(entry)
                } label: {
                    NutritionEntryRow(entry: entry)
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        remove(entry)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        remove(entry)
                    } label: {
                        Label("Удалить из приёма пищи", systemImage: "trash")
                    }
                }
            }

            HStack {
                Button {
                    sheet = .add(meal)
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
                Spacer()
                Button {
                    sheet = .generate(meal)
                } label: {
                    Label("Сгенерировать", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderless)
        } header: {
            HStack {
                Label(meal.title, systemImage: meal.systemImage)
                Spacer()
                if calories > 0 {
                    Text("\(calories.nutritionText) ккал")
                }
            }
        }
    }

    private func remove(_ entry: NutritionEntry) {
        entry.markDeleted()
        saveAndSync()
    }

    private func saveAndSync() {
        try? context.save()
        sync.requestSync()
    }
}

/// Строка с одним блюдом.
struct NutritionEntryRow: View {
    let entry: NutritionEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.isEmpty ? "Без названия" : entry.name)
                Text(entry.grams > 0
                     ? "\(entry.grams.nutritionText) г · Б \(entry.protein.nutritionText) · Ж \(entry.fat.nutritionText) · У \(entry.carbs.nutritionText)"
                     : "Б \(entry.protein.nutritionText) · Ж \(entry.fat.nutritionText) · У \(entry.carbs.nutritionText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.calories.nutritionText) ккал")
                .monospacedDigit()
        }
    }
}

/// Итог за день: калории и БЖУ относительно цели.
struct NutritionSummaryCard: View {
    let totals: NutritionTotals
    let targets: NutritionTargets

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(totals.calories.nutritionText)
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                Text("из \(targets.calories.nutritionText) ккал")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress(totals.calories, targets.calories))
                .tint(totals.calories > targets.calories ? .orange : .green)
            Text(remainingText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                macro("Белки", totals.protein, targets.protein, .red)
                macro("Жиры", totals.fat, targets.fat, .yellow)
                macro("Углеводы", totals.carbs, targets.carbs, .blue)
            }
        }
        .padding(.vertical, 4)
    }

    private var remainingText: String {
        let rest = targets.calories - totals.calories
        if rest >= 0 {
            return "Осталось \(rest.nutritionText) ккал"
        }
        return "Больше нормы на \((-rest).nutritionText) ккал"
    }

    private func progress(_ value: Double, _ target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(value / target, 1)
    }

    private func macro(_ title: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value.nutritionText) / \(target.nutritionText) г")
                .font(.caption.monospacedDigit())
            ProgressView(value: progress(value, target))
                .tint(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
