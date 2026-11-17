import SwiftData
import SwiftUI

/// Главный экран раздела «Сон»: последняя ночь, график, средние значения и история.
/// Переключатель сверху показывает свой сон или сон партнёра.
struct SleepRootView: View {
    enum Period: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        var id: Int { rawValue }
        var title: String { self == .week ? "Неделя" : "Месяц" }
    }

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<SleepEntry> { $0.deletedAt == nil }, sort: \SleepEntry.wakeTime, order: .reverse)
    private var allEntries: [SleepEntry]

    @AppStorage("sleep.goalHours") private var goalHours: Double = 8
    @State private var whose: CoupleMember? = nil
    @State private var period: Period = .week
    @State private var editing: SleepEntry? = nil
    @State private var isAdding = false
    @State private var isEditingGoal = false

    private var shown: CoupleMember { whose ?? account.current }
    private var isMine: Bool { shown == account.current }

    private var entries: [SleepEntry] {
        allEntries.filter { $0.member == shown.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Чей сон", selection: Binding(get: { shown }, set: { whose = $0 })) {
                        Text(account.myName).tag(account.current)
                        Text(account.partnerName).tag(account.current.other)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                lastNightSection
                statsSection
                historySection
            }
            .navigationTitle("Сон")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isEditingGoal = true
                    } label: {
                        Label("Цель", systemImage: "target")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Добавить ночь", systemImage: "plus")
                    }
                }
            }
            .refreshable { await sync.syncNow() }
            .sheet(isPresented: $isAdding) {
                SleepEntryEditor(entry: nil)
            }
            .sheet(item: $editing) { entry in
                SleepEntryEditor(entry: entry)
            }
            .sheet(isPresented: $isEditingGoal) {
                SleepGoalView(goalHours: $goalHours)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Последняя ночь

    @ViewBuilder
    private var lastNightSection: some View {
        Section("Последняя ночь") {
            if let last = entries.first {
                HStack(spacing: 16) {
                    Text(SleepFormat.emoji(for: last.quality))
                        .font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(SleepFormat.duration(last.duration))
                            .font(.title2.bold())
                        Text("\(last.bedtime.formatted(date: .omitted, time: .shortened)) – \(last.wakeTime.formatted(date: .omitted, time: .shortened)) · \(SleepFormat.title(for: last.quality))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    goalBadge(hours: last.duration / 3600)
                }
                .padding(.vertical, 4)
            } else if isMine {
                Button {
                    isAdding = true
                } label: {
                    Label("Записать, как спал(а) сегодня", systemImage: "plus.circle.fill")
                }
            } else {
                Text("\(account.partnerName) пока не записывал(а) сон.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func goalBadge(hours: Double) -> some View {
        let reached = hours >= goalHours
        return Image(systemName: reached ? "checkmark.seal.fill" : "moon.zzz")
            .font(.title2)
            .foregroundStyle(reached ? Color.green : Color.orange)
            .accessibilityLabel(reached ? "Цель выполнена" : "Меньше цели")
    }

    // MARK: - Статистика

    @ViewBuilder
    private var statsSection: some View {
        let stats = SleepStats(entries: entries, days: period.rawValue, goalHours: goalHours)
        Section {
            Picker("Период", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            SleepChartView(nights: stats.nights, days: period.rawValue, goalHours: goalHours)
                .padding(.vertical, 8)

            if stats.nights.isEmpty {
                Text("За этот период записей нет.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("В среднем спим", value: stats.averageDuration.map { SleepFormat.duration($0) } ?? "—")
                LabeledContent("Обычно ложимся", value: stats.averageBedtimeMinutes.map { SleepFormat.clock(minutes: $0) } ?? "—")
                LabeledContent("Обычно встаём", value: stats.averageWakeMinutes.map { SleepFormat.clock(minutes: $0) } ?? "—")
                if let quality = stats.averageQuality {
                    LabeledContent("Как спалось", value: "\(SleepFormat.emoji(for: Int(quality.rounded()))) \(quality.formatted(.number.precision(.fractionLength(1)))) из 5")
                }
                LabeledContent("Ночей с целью", value: "\(stats.goalHits) из \(stats.nights.count)")
            }
        } header: {
            Text("Статистика")
        }
    }

    // MARK: - История

    @ViewBuilder
    private var historySection: some View {
        if !entries.isEmpty {
            Section("История") {
                ForEach(entries) { entry in
                    Button {
                        if isMine { editing = entry }
                    } label: {
                        SleepEntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if isMine {
                            Button("Удалить", role: .destructive) { delete(entry) }
                        }
                    }
                }
            }
        }
    }

    private func delete(_ entry: SleepEntry) {
        entry.markDeleted()
        try? context.save()
        sync.requestSync()
    }
}

/// Строка истории: дата, длительность, время и оценка.
private struct SleepEntryRow: View {
    let entry: SleepEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(SleepFormat.emoji(for: entry.quality))
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nightDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.medium))
                Text("\(entry.bedtime.formatted(date: .omitted, time: .shortened)) – \(entry.wakeTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(SleepFormat.duration(entry.duration))
                .font(.subheadline.monospacedDigit())
        }
        .contentShape(Rectangle())
    }
}

/// Цель: сколько часов хотим спать. Хранится на этом телефоне.
private struct SleepGoalView: View {
    @Binding var goalHours: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goalHours, in: 5...11, step: 0.5) {
                        LabeledContent("Спать не меньше", value: SleepFormat.duration(goalHours * 3600))
                    }
                } footer: {
                    Text("Ночи, где сна меньше цели, отмечаются на графике оранжевым.")
                }
            }
            .navigationTitle("Цель сна")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let account = AccountStore()
    let container = AppDatabase.makeContainer(inMemory: true)
    let calendar = Calendar.current
    for daysAgo in 0..<10 {
        let wakeDay = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)) ?? .now
        let wake = calendar.date(bySettingHour: 7, minute: daysAgo * 5 % 50, second: 0, of: wakeDay) ?? .now
        let bed = wake.addingTimeInterval(-Double(6 + daysAgo % 3) * 3600 - 1800)
        container.mainContext.insert(SleepEntry(member: .owner, bedtime: bed, wakeTime: wake, quality: 1 + daysAgo % 5, note: ""))
    }
    return SleepRootView()
        .modelContainer(container)
        .environment(account)
        .environment(SyncCoordinator(container: container, models: [], account: account))
}
