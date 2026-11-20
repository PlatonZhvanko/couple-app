import SwiftData
import SwiftUI

/// Подразделы статистики. Чтобы добавить новый, допиши case и экран в `content`.
enum StatisticsSection: String, CaseIterable, Identifiable {
    case money = "💰 Деньги"
    case clients = "🙋 Клиенты"
    case cancels = "🚫 Отмены"
    case debts = "📋 Долги"
    var id: String { rawValue }
}

/// Крупные части статистики.
enum StatisticsPart: String, CaseIterable, Identifiable {
    case finance = "Финансы"
    case workload = "Загруженность"
    case mood = "Настроение"
    var id: String { rawValue }
}

struct StatisticsRootView: View {
    @Environment(\.modelContext) private var context

    @Environment(AccountStore.self) private var account
    @Query private var sleepEntries: [SleepEntry]
    @State private var part: StatisticsPart = .finance
    @State private var workload: [Date: StatisticsWorkloadDay] = [:]
    @Query(filter: #Predicate<MoodEntry> { $0.deletedAt == nil }) private var moods: [MoodEntry]
    @State private var section: StatisticsSection = .money
    @State private var period = StatisticsPeriod()
    @State private var snapshot = StatisticsSnapshot()
    // Любое изменение журнала обновляет отчёты.
    @Query private var events: [PlannerEvent]
    @Query private var payments: [PlannerPayment]
    @Query private var subscriptions: [PlannerSubscription]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Часть", selection: $part) {
                    ForEach(StatisticsPart.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if part == .finance {
                    Picker("Раздел", selection: $section) {
                        ForEach(StatisticsSection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                periodBar
                    .padding(.bottom, 4)

                switch part {
                case .workload:
                    StatisticsWorkloadView(days: workload, sleep: sleepNights, period: period)
                case .mood:
                    StatisticsMoodView(entries: moods, workload: workload, sleep: sleepNights, period: period)
                case .finance:
                    financeContent
                }
            }
            .navigationTitle("Статистика")
            .catVisit(.gosha, topic: .money)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: reloadKey) { reload() }
            .environment(\.locale, PlannerCalendar.locale)
        }
    }

    @ViewBuilder
    private var financeContent: some View {
        Group {
            Group {
                switch section {
                case .money:
                    StatisticsMoneyView(snapshot: snapshot, period: period)
                        .catAnchor()
                case .clients:
                    StatisticsClientsView(snapshot: snapshot, period: period)
                case .cancels:
                    StatisticsCancelsView(snapshot: snapshot, period: period)
                case .debts:
                    StatisticsDebtsView(snapshot: snapshot, period: period)
                        .catAnchor()
                }
            }
        }
    }

    private var sleepNights: [Date: StatisticsSleepNight] {
        StatisticsSleep.nights(sleepEntries, member: account.current, period: period)
    }

    private var reloadKey: String {
        "\(moods.count)-\(events.count)-\(payments.count)-\(subscriptions.count)-\(events.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)-\(payments.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)-\(period.interval.start.timeIntervalSince1970)-\(period.interval.end.timeIntervalSince1970)"
    }

    private func reload() {
        snapshot = StatisticsSnapshot.load(context, from: period.interval.start, until: period.interval.end)
        workload = StatisticsWorkload.load(context, from: period.interval.start, until: period.interval.end)
    }

    private var periodBar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatisticsPeriod.Preset.allCases) { item in
                        Button { period.preset = item } label: {
                            Text(item.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(period.preset == item ? Color.appAccent.opacity(0.3) : Color.secondary.opacity(0.15)))
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 40)
            if period.preset == .custom {
                HStack {
                    DatePicker("С", selection: $period.customStart, displayedComponents: .date)
                    DatePicker("По", selection: $period.customEnd, displayedComponents: .date)
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 6)
    }
}
