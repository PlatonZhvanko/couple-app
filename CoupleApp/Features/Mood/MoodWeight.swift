import Charts
import SwiftData
import SwiftUI

// MARK: - Модель

/// Взвешивание. Одна запись на человека в день, видна обоим.
@Model
final class MoodWeightEntry: SyncableModel {
    struct Payload: Codable {
        var member: String
        var dayKey: String
        var day: Date
        var kg: Double
        var createdAt: Date
    }

    static let recordKind = "mood.weight"

    var syncID: UUID = UUID()
    var member: String = CoupleMember.owner.rawValue
    var dayKey: String = ""
    var day: Date = Date.now
    var kg: Double = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember, kg: Double, date: Date = .now) {
        self.member = member.rawValue
        self.kg = kg
        self.dayKey = MoodDayKey.key(for: date)
        self.day = Calendar.current.startOfDay(for: date)
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(member: member, dayKey: dayKey, day: day, kg: kg, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        dayKey = payload.dayKey
        day = payload.day
        kg = payload.kg
        createdAt = payload.createdAt
    }
}

enum MoodWeightStore {
    /// Записать вес за день: заменяет запись этого дня, если она уже есть.
    @MainActor
    static func save(kg: Double, member: CoupleMember, date: Date = .now, context: ModelContext, sync: SyncCoordinator) {
        let key = MoodDayKey.key(for: date)
        let who = member.rawValue
        let existing = ((try? context.fetch(FetchDescriptor<MoodWeightEntry>())) ?? [])
            .first { $0.deletedAt == nil && $0.member == who && $0.dayKey == key }
        if let existing {
            existing.kg = kg
            existing.markChanged()
        } else {
            context.insert(MoodWeightEntry(member: member, kg: kg, date: date))
        }
        try? context.save()
        sync.requestSync()
    }

    /// Разобрать число из поля ввода: «72,5» и «72.5».
    static func parse(_ text: String) -> Double? {
        let value = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        guard let value, value >= 25, value <= 300 else { return nil }
        return value
    }

    static func format(_ kg: Double) -> String {
        String(format: "%.1f", kg).replacingOccurrences(of: ".", with: ",")
    }
}

/// Цель по весу (берётся из «Питание → Цель»).
enum MoodWeightGoal: String {
    case lose, gain, keep

    var title: String {
        switch self {
        case .lose: "Похудение"
        case .gain: "Набор"
        case .keep: "Удержание"
        }
    }

    @MainActor
    static func current(context: ModelContext, member: CoupleMember) -> MoodWeightGoal {
        let who = member.rawValue
        let goal = ((try? context.fetch(FetchDescriptor<NutritionGoal>())) ?? [])
            .first { $0.deletedAt == nil && $0.member == who }
        return MoodWeightGoal(rawValue: goal?.aim ?? "keep") ?? .keep
    }
}

// MARK: - Карточка на главном экране

/// Быстрый ввод веса прямо на экране «Здоровье».
struct MoodWeightCard: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<MoodWeightEntry> { $0.deletedAt == nil }, sort: \MoodWeightEntry.day, order: .reverse)
    private var all: [MoodWeightEntry]

    @State private var text = ""
    @FocusState private var focused: Bool

    private var mine: [MoodWeightEntry] { all.filter { $0.member == account.current.rawValue } }

    var body: some View {
        let last = mine.first
        VStack(alignment: .leading, spacing: 10) {
            if let last {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(MoodWeightStore.format(last.kg)) кг")
                        .font(.title2.bold())
                    Text(Calendar.current.isDateInToday(last.day) ? "сегодня" : last.day.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let previous = mine.dropFirst().first {
                        let delta = last.kg - previous.kg
                        Text("\(delta >= 0 ? "+" : "−")\(MoodWeightStore.format(abs(delta)))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Вес пока не записан. Это необязательно, но так видна динамика.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Вес сегодня, кг", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .textFieldStyle(.roundedBorder)
                Button("Записать", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(MoodWeightStore.parse(text) == nil)
            }
            NavigationLink {
                MoodWeightView()
            } label: {
                Label("График и аналитика веса", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        guard let kg = MoodWeightStore.parse(text) else { return }
        MoodWeightStore.save(kg: kg, member: account.current, context: context, sync: sync)
        text = ""
        focused = false
    }
}

// MARK: - Экран веса

struct MoodWeightView: View {
    enum Period: Int, CaseIterable, Identifiable {
        case month = 30, quarter = 90, year = 365
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .month: "Месяц"
            case .quarter: "3 месяца"
            case .year: "Год"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<MoodWeightEntry> { $0.deletedAt == nil }, sort: \MoodWeightEntry.day, order: .reverse)
    private var all: [MoodWeightEntry]

    @AppStorage("health.targetKg") private var targetKg: Double = 0
    @State private var period: Period = .month
    @State private var who: CoupleMember?
    @State private var newText = ""
    @State private var targetText = ""
    @State private var insights: [MoodInsight] = []

    private var shown: CoupleMember { who ?? account.current }
    private var isMine: Bool { shown == account.current }

    private var entries: [MoodWeightEntry] { all.filter { $0.member == shown.rawValue } }

    private var inPeriod: [MoodWeightEntry] {
        let from = Calendar.current.date(byAdding: .day, value: -(period.rawValue - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        return entries.filter { $0.day >= from }.sorted { $0.day < $1.day }
    }

    var body: some View {
        List {
            Section {
                Picker("Чей вес", selection: Binding(get: { shown }, set: { who = $0 })) {
                    Text(account.myName).tag(account.current)
                    Text(account.partnerName).tag(account.current.other)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if isMine {
                Section("Записать вес") {
                    HStack {
                        TextField("кг, например 72,5", text: $newText)
                            .keyboardType(.decimalPad)
                        Button("Записать") {
                            if let kg = MoodWeightStore.parse(newText) {
                                MoodWeightStore.save(kg: kg, member: account.current, context: context, sync: sync)
                                newText = ""
                                reload()
                            }
                        }
                        .disabled(MoodWeightStore.parse(newText) == nil)
                    }
                }
            }

            Section {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if inPeriod.count < 2 {
                    Text("Для графика нужно хотя бы два взвешивания.")
                        .foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(inPeriod) { item in
                            LineMark(x: .value("День", item.day), y: .value("кг", item.kg))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("День", item.day), y: .value("кг", item.kg))
                        }
                        if targetKg > 0, isMine {
                            RuleMark(y: .value("Цель", targetKg))
                                .foregroundStyle(.green)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .frame(height: 200)
                    .padding(.vertical, 6)
                }
            }

            statsSection

            if isMine {
                Section {
                    HStack {
                        TextField("Целевой вес, кг (необязательно)", text: $targetText)
                            .keyboardType(.decimalPad)
                            .onSubmit(saveTarget)
                        Button("Сохранить", action: saveTarget)
                            .disabled(!targetText.isEmpty && MoodWeightStore.parse(targetText) == nil)
                    }
                } header: {
                    Text("Цель")
                } footer: {
                    Text("Вид цели (похудение, набор, удержание) выбирается в «Питание → Цель». Мироня сравнивает с ней динамику.")
                }

                ForEach(insights) { item in
                    Section {
                        Text("🐾 \(item.text)")
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Записи") {
                ForEach(entries.prefix(60)) { item in
                    HStack {
                        Text(item.day.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)))
                        Spacer()
                        Text("\(MoodWeightStore.format(item.kg)) кг").monospacedDigit()
                    }
                    .swipeActions {
                        if isMine {
                            Button("Удалить", role: .destructive) {
                                item.markDeleted()
                                try? context.save()
                                sync.requestSync()
                                reload()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Вес")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            targetText = targetKg > 0 ? MoodWeightStore.format(targetKg) : ""
            reload()
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = inPeriod.map(\.kg) + (targetKg > 0 && isMine ? [targetKg] : [])
        guard let low = values.min(), let high = values.max() else { return 50...100 }
        return (low - 1)...(high + 1)
    }

    @ViewBuilder
    private var statsSection: some View {
        if let first = inPeriod.first, let last = inPeriod.last, inPeriod.count >= 2 {
            Section("За период") {
                let delta = last.kg - first.kg
                LabeledContent("Изменение", value: "\(delta >= 0 ? "+" : "−")\(MoodWeightStore.format(abs(delta))) кг")
                LabeledContent("Сейчас", value: "\(MoodWeightStore.format(last.kg)) кг")
                LabeledContent("Минимум / максимум",
                               value: "\(MoodWeightStore.format(inPeriod.map(\.kg).min() ?? 0)) / \(MoodWeightStore.format(inPeriod.map(\.kg).max() ?? 0))")
                if targetKg > 0, isMine {
                    let left = last.kg - targetKg
                    LabeledContent("До цели", value: abs(left) < 0.1 ? "достигнута 🎉" : "\(MoodWeightStore.format(abs(left))) кг")
                }
            }
        }
    }

    private func saveTarget() {
        targetKg = MoodWeightStore.parse(targetText) ?? 0
        reload()
    }

    private func reload() {
        insights = MoodWeightInsights.insights(context: context, member: account.current, targetKg: targetKg)
    }
}

// MARK: - Аналитика веса

/// Мироня сравнивает динамику веса с целью и ищет, что на неё влияет:
/// питание, сон, настроение, загруженность.
enum MoodWeightInsights {
    private struct Interval {
        var perWeek: Double
        var kcal: Double?
        var sleep: Double?
        var mood: Double?
        var sessions: Double?
    }

    @MainActor
    static func insights(context: ModelContext, member: CoupleMember, targetKg: Double) -> [MoodInsight] {
        let who = member.rawValue
        let weights = ((try? context.fetch(FetchDescriptor<MoodWeightEntry>())) ?? [])
            .filter { $0.deletedAt == nil && $0.member == who }
            .sorted { $0.day < $1.day }
        guard weights.count >= 2, let first = weights.first, let last = weights.last else {
            return [MoodInsight(id: "w-empty", tone: .trend,
                                text: "Пока мало взвешиваний. Записывай вес хотя бы раз в неделю, и я найду, что на него влияет.",
                                detail: "Нужно минимум 2 записи")]
        }

        let goal = MoodWeightGoal.current(context: context, member: member)
        var result: [MoodInsight] = []

        // Общая динамика.
        let spanDays = max(1, Calendar.current.dateComponents([.day], from: first.day, to: last.day).day ?? 1)
        let delta = last.kg - first.kg
        let perWeek = delta / Double(spanDays) * 7
        let word = abs(perWeek) < 0.05 ? "почти не меняется" : (perWeek < 0 ? "уходит вниз" : "идёт вверх")
        var verdict = ""
        switch goal {
        case .lose: verdict = perWeek < -0.05 ? "Это в сторону цели." : "Для похудения пока без движения."
        case .gain: verdict = perWeek > 0.05 ? "Это в сторону цели." : "Для набора пока без движения."
        case .keep: verdict = abs(perWeek) <= 0.3 ? "Вес держится стабильно, как и задумано." : "Для удержания колебания великоваты."
        }
        result.append(MoodInsight(
            id: "w-trend", tone: .trend,
            text: "Вес \(word): примерно \(delta >= 0 ? "+" : "−")\(MoodWeightStore.format(abs(perWeek))) кг в неделю. \(verdict)",
            detail: "Цель: \(goal.title). \(MoodWeightStore.format(first.kg)) → \(MoodWeightStore.format(last.kg)) кг за \(spanDays) дн.",
            positiveText: verdict.hasPrefix("Это в сторону") || verdict.hasPrefix("Вес держится") ? "Вес идёт по плану, так держать!" : nil
        ))

        if targetKg > 0 {
            let left = last.kg - targetKg
            if abs(left) < 0.2 {
                result.append(MoodInsight(id: "w-target", tone: .good, text: "Цель по весу достигнута. Горжусь тобой. Мур.", detail: "Цель \(MoodWeightStore.format(targetKg)) кг"))
            } else if abs(perWeek) > 0.05, (left > 0) == (perWeek < 0) {
                let weeks = Int((abs(left) / abs(perWeek)).rounded())
                if weeks <= 52 {
                    result.append(MoodInsight(id: "w-eta", tone: .good,
                                              text: "С таким темпом до цели примерно \(weeks) нед.",
                                              detail: "Осталось \(MoodWeightStore.format(abs(left))) кг"))
                }
            }
        }

        // Связи: что происходит между взвешиваниями.
        let days = MoodInsights.collect(context: context, member: member, includeEmptyMood: true)
        var intervals: [Interval] = []
        for (a, b) in zip(weights, weights.dropFirst()) {
            let gap = Calendar.current.dateComponents([.day], from: a.day, to: b.day).day ?? 0
            guard gap >= 2, gap <= 21 else { continue }
            let slice = days.filter { $0.day > a.day && $0.day <= b.day }
            func avg(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
            intervals.append(Interval(
                perWeek: (b.kg - a.kg) / Double(gap) * 7,
                kcal: avg(slice.compactMap(\.kcal)),
                sleep: avg(slice.compactMap(\.sleepHours)),
                mood: avg(slice.compactMap(\.mood)),
                sessions: avg(slice.compactMap { $0.sessions.map(Double.init) })
            ))
        }

        // Питание против нормы.
        let who2 = member.rawValue
        let norm = ((try? context.fetch(FetchDescriptor<NutritionGoal>())) ?? [])
            .first { $0.deletedAt == nil && $0.member == who2 }?.calories
        let kcalDays = days.compactMap(\.kcal)
        if let norm, kcalDays.count >= 5 {
            let average = kcalDays.reduce(0, +) / Double(kcalDays.count)
            let diff = average - norm
            if abs(diff) >= 150 {
                let direction = diff > 0 ? "больше" : "меньше"
                var comment = ""
                switch goal {
                case .lose: comment = diff > 0 ? "Для похудения это многовато." : "Это помогает худеть, только не пересушивай себя."
                case .gain: comment = diff > 0 ? "Для набора как раз." : "Для набора маловато."
                case .keep: comment = "Для удержания стоит приблизиться к норме."
                }
                result.append(MoodInsight(id: "w-kcal", tone: .warning,
                                          text: "В среднем ты съедаешь на \(Int(abs(diff))) ккал \(direction) нормы. \(comment)",
                                          detail: "Среднее \(Int(average)) ккал при норме \(Int(norm))"))
            }
        }

        // Сравниваем интервалы «выше медианы» и «ниже медианы» по каждому фактору.
        func link(_ id: String, _ pick: (Interval) -> Double?, unit: String, high: String, low: String) {
            let rows = intervals.compactMap { item in pick(item).map { ($0, item.perWeek) } }
            guard rows.count >= 4 else { return }
            let sorted = rows.map(\.0).sorted()
            let median = sorted[sorted.count / 2]
            let upper = rows.filter { $0.0 >= median }.map(\.1)
            let lower = rows.filter { $0.0 < median }.map(\.1)
            guard upper.count >= 2, lower.count >= 2 else { return }
            let upperAvg = upper.reduce(0, +) / Double(upper.count)
            let lowerAvg = lower.reduce(0, +) / Double(lower.count)
            let diff = upperAvg - lowerAvg
            guard abs(diff) >= 0.2 else { return }
            let text = diff > 0 ? high : low
            result.append(MoodInsight(id: id, tone: .trend, text: text,
                                      detail: "Неделя с \(unit) выше обычного: \(MoodWeightStore.format(upperAvg)) кг/нед., ниже: \(MoodWeightStore.format(lowerAvg)) кг/нед."))
        }
        link("w-link-kcal", { $0.kcal }, unit: "питанием",
             high: "Когда еды больше, вес растёт быстрее.", low: "Когда еды больше, вес, наоборот, снижается (возможно, еды раньше не хватало).")
        link("w-link-sleep", { $0.sleep }, unit: "сном",
             high: "Когда спишь дольше, вес растёт чуть быстрее.", low: "Когда спишь меньше, вес идёт вверх: недосып подталкивает к лишнему.")
        link("w-link-mood", { $0.mood }, unit: "настроением",
             high: "В периоды хорошего настроения вес растёт быстрее.", low: "В периоды плохого настроения вес растёт: возможно, помогает заедать стресс.")
        link("w-link-load", { $0.sessions }, unit: "загруженностью",
             high: "В загруженные недели вес растёт быстрее.", low: "В загруженные недели вес снижается: на еду и отдых не хватает времени.")

        return result
    }
}
