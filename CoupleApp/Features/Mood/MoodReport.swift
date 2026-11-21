import SwiftData
import SwiftUI

/// Сводка за день, неделю или месяц: настроение, сон, вес, питание, загруженность, деньги.
struct MoodReportView: View {
    enum Period: Int, CaseIterable, Identifiable {
        case day = 1, week = 7, month = 30
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .day: "День"
            case .week: "Неделя"
            case .month: "Месяц"
            }
        }
        var phrase: String {
            switch self {
            case .day: "за сегодня"
            case .week: "за неделю"
            case .month: "за месяц"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(AccountStore.self) private var account

    @AppStorage("health.targetKg") private var targetKg: Double = 0
    @State private var period: Period = .week
    @State private var days: [MoodDayData] = []
    @State private var weights: [MoodWeightEntry] = []
    @State private var weightInsights: [MoodInsight] = []

    private var slice: [MoodDayData] {
        let today = Calendar.current.startOfDay(for: .now)
        let from = Calendar.current.date(byAdding: .day, value: -(period.rawValue - 1), to: today) ?? today
        return days.filter { $0.day >= from }
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        let slice = slice
        let mood = average(slice.compactMap(\.mood))
        let sleep = average(slice.compactMap(\.sleepHours))
        let quality = average(slice.compactMap(\.sleepQuality))
        let kcal = average(slice.compactMap(\.kcal))
        let water = average(slice.compactMap { $0.waterMl.map(Double.init) })
        let sessions = slice.compactMap(\.sessions).reduce(0, +)
        let income = slice.compactMap(\.income).reduce(0, +)
        let debtDays = slice.filter { $0.hasDebt == true }.count

        List {
            Section {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                MoodMironSpeech(text: summary(mood: mood, sleep: sleep, kcal: kcal)) { EmptyView() }
                    .listRowBackground(Color.clear)
            }

            Section("Настроение") {
                if let mood {
                    LabeledContent("Среднее", value: "\(MoodLevel.nearest(to: mood).emoji) \(MoodWeightStore.format(mood)) из 5")
                    LabeledContent("Дней с отметками", value: "\(slice.filter { $0.mood != nil }.count)")
                } else {
                    Text("Нет отметок \(period.phrase)").foregroundStyle(.secondary)
                }
            }

            Section("Сон") {
                if let sleep {
                    LabeledContent("Спишь в среднем", value: SleepFormat.duration(sleep * 3600))
                    if let quality { LabeledContent("Как спалось", value: "\(MoodWeightStore.format(quality)) из 5") }
                } else {
                    Text("Нет записей сна \(period.phrase)").foregroundStyle(.secondary)
                }
            }

            Section("Вес") {
                let rows = weightsInPeriod
                if let first = rows.first, let last = rows.last {
                    LabeledContent("Сейчас", value: "\(MoodWeightStore.format(last.kg)) кг")
                    if rows.count >= 2 {
                        let delta = last.kg - first.kg
                        LabeledContent("Изменение", value: "\(delta >= 0 ? "+" : "−")\(MoodWeightStore.format(abs(delta))) кг")
                    }
                } else {
                    Text("Нет взвешиваний \(period.phrase)").foregroundStyle(.secondary)
                }
            }

            Section("Питание") {
                if let kcal {
                    LabeledContent("Калории в день", value: "\(Int(kcal)) ккал")
                    if let water { LabeledContent("Вода в день", value: "\(MoodWeightStore.format(water / 1000)) л") }
                } else {
                    Text("Нет записей питания \(period.phrase)").foregroundStyle(.secondary)
                }
            }

            if sessions > 0 {
                Section("Работа") {
                    LabeledContent("Занятий", value: "\(sessions)")
                    LabeledContent("Получено", value: PlannerPricing.format(income))
                    if debtDays > 0 { LabeledContent("Дней с долгами", value: "\(debtDays)") }
                }
            }

            if period != .day {
                let found = MoodInsights.insights(from: days).prefix(3) + weightInsights.prefix(2)
                if !found.isEmpty {
                    Section("Что заметил Мироня") {
                        ForEach(Array(found)) { Text("🐾 \($0.text)") }
                    }
                }
            }
        }
        .navigationTitle("Сводка")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            days = MoodInsights.collect(context: context, member: account.current, includeEmptyMood: true)
            let who = account.current.rawValue
            weights = ((try? context.fetch(FetchDescriptor<MoodWeightEntry>())) ?? [])
                .filter { $0.deletedAt == nil && $0.member == who }
                .sorted { $0.day < $1.day }
            weightInsights = MoodWeightInsights.insights(context: context, member: account.current, targetKg: targetKg)
        }
    }

    private var weightsInPeriod: [MoodWeightEntry] {
        let today = Calendar.current.startOfDay(for: .now)
        let from = Calendar.current.date(byAdding: .day, value: -(period.rawValue - 1), to: today) ?? today
        return weights.filter { $0.day >= from }
    }

    private func summary(mood: Double?, sleep: Double?, kcal: Double?) -> String {
        guard mood != nil || sleep != nil || kcal != nil else {
            return "Пока пусто \(period.phrase). Расскажи мне про день, и я соберу сводку."
        }
        var parts: [String] = []
        if let mood {
            parts.append(mood >= 4 ? "Настроение \(period.phrase) хорошее." : mood >= 3 ? "Настроение \(period.phrase) ровное." : "Настроение \(period.phrase) просело, побереги себя.")
        }
        if let sleep {
            parts.append(sleep >= 7 ? "Со сном порядок." : "Сна маловато, это стоит поправить.")
        }
        return parts.joined(separator: " ")
    }
}
