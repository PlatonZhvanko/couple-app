import SwiftData
import SwiftUI

/// Один вывод аналитики: что и как влияет на настроение.
struct MoodInsight: Identifiable {
    enum Tone { case warning, good, trend }

    let id: String
    let tone: Tone
    let text: String
    /// Подробность для экрана аналитики.
    let detail: String
    /// Тёплая версия для хороших дней (если есть).
    var positiveText: String? = nil
}

/// Данные одного дня: настроение и всё, что рядом (питание, сон, занятия, деньги).
struct MoodDayData {
    var day: Date
    var mood: Double?
    var moodValue: Double { mood ?? 0 }
    var sleepHours: Double?
    /// Минуты от полудня (23:00 → 660, 01:00 → 780).
    var bedtimeShifted: Int?
    /// Минуты от полуночи.
    var wakeMinutes: Int?
    var sleepQuality: Double?
    var awakeHours: Double?
    var kcal: Double?
    var waterMl: Int?
    var sessions: Int?
    var hasDebt: Bool?
    var income: Double?
}

/// Собирает данные из разделов и ищет закономерности. Всё считается на телефоне.
enum MoodInsights {
    private static let windowDays = 60

    @MainActor
    static func collect(context: ModelContext, member: CoupleMember, includeEmptyMood: Bool = false) -> [MoodDayData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let from = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let who = member.rawValue

        let checkIns = ((try? context.fetch(FetchDescriptor<MoodDayCheckIn>())) ?? [])
            .filter { $0.deletedAt == nil && $0.member == who && $0.day >= from }
        let entries = ((try? context.fetch(FetchDescriptor<MoodEntry>())) ?? [])
            .filter { $0.deletedAt == nil && $0.member == who && $0.createdAt >= from }
        let meals = ((try? context.fetch(FetchDescriptor<NutritionEntry>())) ?? [])
            .filter { $0.deletedAt == nil && $0.member == who }
        let water = ((try? context.fetch(FetchDescriptor<NutritionWater>())) ?? [])
            .filter { $0.deletedAt == nil && $0.member == who }
        let sleeps = SleepDaySummary.load(context, member: member, from: from, until: end)
        let snapshot = StatisticsSnapshot.load(context, from: from, until: end)

        let checkInByDay = Dictionary(checkIns.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        let entriesByDay = Dictionary(grouping: entries) { MoodDayKey.key(for: $0.createdAt) }
        let mealsByDay = Dictionary(grouping: meals, by: \.dayKey)
        let waterByDay = Dictionary(grouping: water, by: \.dayKey)
        let sleepByDay = Dictionary(sleeps.map { (MoodDayKey.key(for: $0.day), $0) }, uniquingKeysWith: { a, _ in a })
        let visitsByDay = Dictionary(grouping: snapshot.visits.filter { !$0.cancelled }) { MoodDayKey.key(for: $0.day) }

        var result: [MoodDayData] = []
        for offset in 0..<windowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: from) else { continue }
            let key = MoodDayKey.key(for: day)
            let mood: Double?
            if let checkIn = checkInByDay[key] {
                mood = Double(checkIn.overall)
            } else if let average = MoodStats.average(entriesByDay[key] ?? []) {
                mood = average
            } else if includeEmptyMood {
                mood = nil
            } else {
                continue
            }
            var item = MoodDayData(day: day, mood: mood)
            if let sleep = sleepByDay[key] {
                item.sleepHours = sleep.hours
                item.bedtimeShifted = sleep.bedtimeShifted
                item.wakeMinutes = sleep.wakeMinutes
                item.sleepQuality = sleep.quality
                item.awakeHours = sleep.awakeHours
            }
            if let meals = mealsByDay[key], !meals.isEmpty {
                item.kcal = meals.reduce(0) { $0 + $1.calories }
            }
            if let water = waterByDay[key], !water.isEmpty {
                item.waterMl = water.reduce(0) { $0 + $1.milliliters }
            }
            if let visits = visitsByDay[key], !visits.isEmpty {
                item.sessions = visits.count
                item.hasDebt = visits.contains { $0.isDebt }
                item.income = visits.filter { $0.method == .cash || $0.method == .transfer }.reduce(0) { $0 + $1.amount }
            }
            result.append(item)
        }
        return result
    }

    // MARK: - Выводы

    private struct Factor {
        let id: String
        let name: String
        /// В какую группу попал день: true — «хорошие условия» (сон 7+, вода, еда, нет долгов)
        /// или, для загрузки, «много занятий»; nil — нет данных.
        let group: (MoodDayData) -> Bool?
        /// true — группа «true» ожидаемо тяжелее (загрузка), поэтому считаем наоборот.
        var inverted = false
        let lowText: (Double) -> String
        var highText: ((Double) -> String)? = nil
        var positive: ((Double) -> String)? = nil
    }

    private static let factors: [Factor] = [
        Factor(id: "sleep", name: "Сон 7+ часов", group: { $0.sleepHours.map { $0 >= 7 } },
               lowText: { "В дни, когда сна меньше 7 часов, настроение в среднем ниже на \(MoodInsights.format($0))." },
               positive: { "Ты хорошо спишь, и это видно: после 7+ часов сна настроение выше на \(MoodInsights.format($0))." }),
        Factor(id: "sleepq", name: "Сон хорошего качества (4+)", group: { $0.sleepQuality.map { $0 >= 4 } },
               lowText: { "После ночей, когда спалось хуже, настроение ниже на \(MoodInsights.format($0))." },
               positive: { "Когда спалось хорошо, настроение выше на \(MoodInsights.format($0))." }),
        Factor(id: "sleepbed", name: "Лёг(ла) до 23:30", group: { $0.bedtimeShifted.map { $0 <= 690 } },
               lowText: { "Когда ложишься позже 23:30, настроение на следующий день ниже на \(MoodInsights.format($0))." },
               positive: { "Ранний отход ко сну (до 23:30) поднимает настроение на \(MoodInsights.format($0))." }),
        Factor(id: "sleepwake", name: "Проснулся(ась) до 8:30", group: { $0.wakeMinutes.map { $0 <= 8 * 60 + 30 } },
               lowText: { "В дни, когда просыпаешься после 8:30, настроение ниже на \(MoodInsights.format($0))." },
               positive: { "Раннее пробуждение (до 8:30) идёт тебе на пользу: настроение выше на \(MoodInsights.format($0))." }),
        Factor(id: "water", name: "Воды 1,5 л и больше", group: { $0.waterMl.map { $0 >= 1500 } },
               lowText: { "Когда воды меньше 1,5 л, настроение ниже на \(MoodInsights.format($0))." },
               positive: { "Вода творит чудеса: с 1,5 л и больше настроение выше на \(MoodInsights.format($0))." }),
        Factor(id: "kcal", name: "Нормально поел(а)", group: { $0.kcal.map { $0 >= 1400 } },
               lowText: { "В дни, когда еды было совсем мало, настроение ниже на \(MoodInsights.format($0))." },
               positive: { "Сытый день, светлое настроение: выше на \(MoodInsights.format($0))." }),
        Factor(id: "load", name: "Много занятий (4+)", group: { $0.sessions.map { $0 >= 4 } }, inverted: true,
               lowText: { "В дни с большой загрузкой (4+ занятия) настроение ниже на \(MoodInsights.format($0))." },
               highText: { "В насыщенные дни (4+ занятия) настроение даже выше на \(MoodInsights.format($0))." }),
        Factor(id: "debt", name: "Без долгов", group: { $0.hasDebt.map { !$0 } },
               lowText: { "Когда есть неоплаченные занятия, настроение ниже на \(MoodInsights.format($0))." },
               positive: { "Когда все расплатились, на душе легче: настроение выше на \(MoodInsights.format($0))." }),
    ]

    fileprivate static func format(_ value: Double) -> String {
        String(format: "%.1f", abs(value)).replacingOccurrences(of: ".", with: ",")
    }

    /// Закономерности и тенденция по последним дням.
    static func insights(from allDays: [MoodDayData]) -> [MoodInsight] {
        let days = allDays.filter { $0.mood != nil }
        var result: [MoodInsight] = []

        for factor in factors {
            var yes: [Double] = []
            var no: [Double] = []
            for day in days {
                switch factor.group(day) {
                case .some(true): yes.append(day.moodValue)
                case .some(false): no.append(day.moodValue)
                case .none: break
                }
            }
            guard yes.count >= 3, no.count >= 3 else { continue }
            let yesAverage = yes.reduce(0, +) / Double(yes.count)
            let noAverage = no.reduce(0, +) / Double(no.count)
            // Положительная разница: в «хорошей» группе настроение выше.
            let difference = yesAverage - noAverage
            // Положительное число: условия «лучше» дают настроение выше.
            let effect = factor.inverted ? -difference : difference
            let detail = "\(factor.name): \(format(yesAverage)) из 5 (\(yes.count) дн.), иначе \(format(noAverage)) (\(no.count) дн.)"
            if effect >= 0.4 {
                result.append(MoodInsight(id: factor.id, tone: .warning, text: factor.lowText(effect), detail: detail,
                                          positiveText: factor.positive?(effect)))
            } else if effect <= -0.4, let high = factor.highText {
                result.append(MoodInsight(id: factor.id, tone: .good, text: high(-effect), detail: detail))
            }
        }

        // Тенденция: последние 7 дней против предыдущих 7.
        let sorted = days.sorted { $0.day < $1.day }
        let last = sorted.suffix(7).map(\.moodValue)
        let before = sorted.dropLast(min(7, sorted.count)).suffix(7).map(\.moodValue)
        if last.count >= 3, before.count >= 3 {
            let delta = last.reduce(0, +) / Double(last.count) - before.reduce(0, +) / Double(before.count)
            if delta >= 0.4 {
                result.insert(MoodInsight(id: "trend", tone: .good, text: "Последняя неделя заметно светлее прошлой, так держать.", detail: "Рост настроения на \(format(delta))"), at: 0)
            } else if delta <= -0.4 {
                result.insert(MoodInsight(id: "trend", tone: .warning, text: "Последние дни настроение чуть ниже обычного. Может, стоит выдохнуть и поберечь себя.", detail: "Снижение настроения на \(format(delta))"), at: 0)
            }
        }
        return result
    }

    /// Какой вывод показать «невзначай» сегодня: один в день, по очереди.
    static func gentleInsight(_ list: [MoodInsight], on date: Date = .now, goodMood: Bool = false, preferSleep: Bool = false) -> (item: MoodInsight, text: String)? {
        guard !list.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        // Если ночь была короткой, Мироня первым делом вспоминает про сон.
        let sleepFirst = preferSleep ? list.first { $0.id.hasPrefix("sleep") } : nil
        let item = sleepFirst ?? list[day % list.count]
        return (item, goodMood ? (item.positiveText ?? item.text) : item.text)
    }
}

// MARK: - Экран

/// «Мироня заметил»: все наблюдения и данные, на которых они основаны.
struct MoodInsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AccountStore.self) private var account

    @State private var days: [MoodDayData] = []
    @State private var loaded = false
    @State private var sleepRows: [SleepDaySummary] = []

    @State private var weightInsights: [MoodInsight] = []
    @AppStorage("health.targetKg") private var targetKg: Double = 0

    private var insights: [MoodInsight] { weightInsights + MoodInsights.insights(from: days) }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    MoodMironAvatar(size: 44)
                    Text("Я смотрю, как настроение и вес связаны со сном, едой, водой, загрузкой и деньгами. Это не диагноз, просто наблюдения.")
                        .font(.subheadline)
                }
                .listRowBackground(Color.clear)
            }

            if loaded, insights.isEmpty {
                Section {
                    Text(days.count < 7
                         ? "Пока мало данных: отмечайте итог дня каждый вечер, и через неделю-другую я начну замечать закономерности."
                         : "Ничего особенного не замечаю, день ото дня всё довольно ровно.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(insights) { item in
                Section {
                    Text("\(icon(item.tone)) \(item.text)")
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !sleepRows.isEmpty {
                Section {
                    LabeledContent("Спишь в среднем", value: SleepFormat.duration(sleepRows.map(\.hours).reduce(0, +) / Double(sleepRows.count) * 3600))
                    if let bed = SleepStats.averageClockMinutes(sleepRows.map(\.bedtime), calendar: .current) {
                        LabeledContent("Обычно ложишься", value: SleepFormat.clock(minutes: bed))
                    }
                    if let wake = SleepStats.averageClockMinutes(sleepRows.map(\.wakeTime), calendar: .current) {
                        LabeledContent("Обычно встаёшь", value: SleepFormat.clock(minutes: wake))
                    }
                    LabeledContent("Как спалось", value: String(format: "%.1f из 5", sleepRows.map(\.quality).reduce(0, +) / Double(sleepRows.count)))
                    let awake = sleepRows.compactMap(\.awakeHours)
                    if !awake.isEmpty {
                        LabeledContent("Бодрствуешь за день", value: SleepFormat.duration(awake.reduce(0, +) / Double(awake.count) * 3600))
                    }
                } header: {
                    Text("Сон за 60 дней")
                } footer: {
                    Text("Сон записывается в итоге дня. Чем больше ночей, тем точнее подсказки.")
                }
            }

            Section {
                LabeledContent("Дней с отметками", value: "\(days.count)")
                if let average = MoodStats.average(days.compactMap { $0.mood.map { MoodEntryProxy(level: $0) } }) {
                    LabeledContent("Среднее настроение", value: String(format: "%.1f из 5", average))
                }
            } header: {
                Text("За последние 60 дней")
            }
        }
        .navigationTitle("Мироня заметил")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            days = MoodInsights.collect(context: context, member: account.current)
            let today = Calendar.current.startOfDay(for: .now)
            sleepRows = SleepDaySummary.load(
                context, member: account.current,
                from: Calendar.current.date(byAdding: .day, value: -59, to: today) ?? today,
                until: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            )
            weightInsights = MoodWeightInsights.insights(context: context, member: account.current, targetKg: targetKg)
            loaded = true
        }
    }

    private func icon(_ tone: MoodInsight.Tone) -> String {
        switch tone {
        case .warning: "🌧"
        case .good: "☀️"
        case .trend: "🌿"
        }
    }
}

/// Нужна только для среднего по числам.
private struct MoodEntryProxy {
    let level: Double
}

private extension MoodStats {
    static func average(_ items: [MoodEntryProxy]) -> Double? {
        guard !items.isEmpty else { return nil }
        return items.reduce(0) { $0 + $1.level } / Double(items.count)
    }
}
