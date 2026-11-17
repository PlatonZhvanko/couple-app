import SwiftData
import SwiftUI

/// Главный экран раздела «Питание»: дневник за выбранный день.
struct NutritionRootView: View {
    @Environment(AccountStore.self) private var account
    @State private var showingPartner = false
    @State private var date = Date.now

    private var member: CoupleMember {
        showingPartner ? account.current.other : account.current
    }

    var body: some View {
        NavigationStack {
            NutritionDayView(
                member: member,
                dayKey: NutritionDay.key(for: date),
                isMine: !showingPartner,
                showingPartner: $showingPartner,
                date: $date
            )
            .navigationTitle("Питание")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        NutritionWeekView(member: member)
                    } label: {
                        Label("Неделя", systemImage: "chart.bar")
                    }
                }
                if !showingPartner {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            NutritionGoalsView(member: account.current)
                        } label: {
                            Label("Цели", systemImage: "target")
                        }
                    }
                }
            }
        }
    }
}

/// Что открыть в окне редактирования еды.
struct NutritionEditorTarget: Identifiable {
    let id = UUID()
    var meal: NutritionMealType
    var entry: NutritionEntry?
}

/// Дневник одного человека за один день.
struct NutritionDayView: View {
    let member: CoupleMember
    let dayKey: String
    let isMine: Bool
    @Binding var showingPartner: Bool
    @Binding var date: Date

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query private var entries: [NutritionEntry]
    @Query private var water: [NutritionWater]
    @Query private var goals: [NutritionGoal]
    @State private var editor: NutritionEditorTarget?

    init(member: CoupleMember, dayKey: String, isMine: Bool, showingPartner: Binding<Bool>, date: Binding<Date>) {
        self.member = member
        self.dayKey = dayKey
        self.isMine = isMine
        _showingPartner = showingPartner
        _date = date
        let memberID = member.rawValue
        _entries = Query(
            filter: #Predicate<NutritionEntry> { $0.deletedAt == nil && $0.member == memberID && $0.dayKey == dayKey },
            sort: \NutritionEntry.createdAt
        )
        _water = Query(
            filter: #Predicate<NutritionWater> { $0.deletedAt == nil && $0.member == memberID && $0.dayKey == dayKey },
            sort: \NutritionWater.createdAt
        )
        _goals = Query(filter: #Predicate<NutritionGoal> { $0.deletedAt == nil && $0.member == memberID })
    }

    private var targets: NutritionTargets { goals.first?.targets ?? .standard }
    private var waterTotal: Int { water.reduce(0) { $0 + $1.milliliters } }

    var body: some View {
        List {
            Section {
                Picker("Чей дневник", selection: $showingPartner) {
                    Text(account.myName).tag(false)
                    Text(account.partnerName).tag(true)
                }
                .pickerStyle(.segmented)
                dayPicker
            }

            Section {
                NutritionSummaryCard(totals: NutritionTotals.sum(entries), targets: targets)
            }

            waterSection

            ForEach(NutritionMealType.allCases) { meal in
                mealSection(meal)
            }
        }
        .refreshable { await sync.syncNow() }
        .sheet(item: $editor) { target in
            NutritionEntryEditor(member: member, dayKey: dayKey, meal: target.meal, entry: target.entry)
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

    // MARK: Вода

    private var waterSection: some View {
        Section("Вода") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.blue)
                    Text("\(waterTotal) из \(targets.water) мл")
                    Spacer()
                }
                ProgressView(value: min(Double(waterTotal) / Double(max(targets.water, 1)), 1))
                    .tint(.blue)
            }
            if isMine {
                HStack {
                    Button("+250 мл") { addWater(250) }
                    Button("+500 мл") { addWater(500) }
                    Spacer()
                    Button {
                        removeLastWater()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(water.isEmpty)
                    .accessibilityLabel("Отменить последнюю воду")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func addWater(_ milliliters: Int) {
        context.insert(NutritionWater(member: member, dayKey: dayKey, milliliters: milliliters))
        saveAndSync()
    }

    private func removeLastWater() {
        water.last?.markDeleted()
        saveAndSync()
    }

    // MARK: Приёмы пищи

    private func mealSection(_ meal: NutritionMealType) -> some View {
        let items = entries.filter { $0.mealType == meal }
        let calories = items.reduce(0) { $0 + $1.calories }
        return Section {
            ForEach(items) { entry in
                if isMine {
                    Button {
                        editor = NutritionEditorTarget(meal: meal, entry: entry)
                    } label: {
                        NutritionEntryRow(entry: entry)
                    }
                    .foregroundStyle(.primary)
                } else {
                    NutritionEntryRow(entry: entry)
                }
            }
            .onDelete(perform: isMine ? { offsets in delete(items, at: offsets) } : nil)

            if isMine {
                Button {
                    editor = NutritionEditorTarget(meal: meal, entry: nil)
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            } else if items.isEmpty {
                Text("Ничего не записано")
                    .foregroundStyle(.secondary)
            }
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

    private func delete(_ items: [NutritionEntry], at offsets: IndexSet) {
        for index in offsets { items[index].markDeleted() }
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
                Text("Б \(entry.protein.nutritionText) · Ж \(entry.fat.nutritionText) · У \(entry.carbs.nutritionText)")
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
