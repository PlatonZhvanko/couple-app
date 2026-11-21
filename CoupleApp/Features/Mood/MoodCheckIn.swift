import SwiftData
import SwiftUI

// MARK: - Параметры вечернего опроса

/// Параметры, по которым Мироня спрашивает про день. Оценка каждого: 1…5.
enum MoodParameter: String, CaseIterable, Identifiable {
    case energy, calm, body, warmth, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy: "Энергия"
        case .calm: "Спокойствие"
        case .body: "Самочувствие"
        case .warmth: "Коммуникация"
        case .focus: "Дела и работа"
        }
    }

    var emoji: String {
        switch self {
        case .energy: "⚡️"
        case .calm: "🌿"
        case .body: "🫶"
        case .warmth: "💬"
        case .focus: "🎯"
        }
    }

    var hint: String {
        switch self {
        case .energy: "сколько было сил"
        case .calm: "насколько было спокойно"
        case .body: "как чувствовало себя тело"
        case .warmth: "как общались с близкими"
        case .focus: "как шли дела"
        }
    }
}

/// Ключ дня вида «2026-11-20» (такой же, как в других разделах).
enum MoodDayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String {
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

// MARK: - Модель

/// Вечерний итог дня одного человека: общая оценка и оценки по параметрам.
/// Видна обоим. По одной записи на человека в день.
@Model
final class MoodDayCheckIn: SyncableModel {
    struct Payload: Codable {
        var member: String
        var dayKey: String
        var day: Date
        var overall: Int
        var energy: Int
        var calm: Int
        var health: Int
        var warmth: Int
        var focus: Int
        var note: String
        var entryID: UUID?
        var createdAt: Date
    }

    static let recordKind = "mood.checkin"

    var syncID: UUID = UUID()
    var member: String = CoupleMember.owner.rawValue
    var dayKey: String = ""
    /// Начало дня, к которому относится итог.
    var day: Date = Date.now
    var overall: Int = 3
    var energy: Int = 3
    var calm: Int = 3
    var health: Int = 3
    var warmth: Int = 3
    var focus: Int = 3
    var note: String = ""
    /// Отметка в истории настроения, созданная вместе с итогом.
    var entryID: UUID? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember, date: Date = .now) {
        self.member = member.rawValue
        self.dayKey = MoodDayKey.key(for: date)
        self.day = Calendar.current.startOfDay(for: date)
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(member: member, dayKey: dayKey, day: day, overall: overall, energy: energy, calm: calm,
                health: health, warmth: warmth, focus: focus, note: note, entryID: entryID, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        dayKey = payload.dayKey
        day = payload.day
        overall = payload.overall
        energy = payload.energy
        calm = payload.calm
        health = payload.health
        warmth = payload.warmth
        focus = payload.focus
        note = payload.note
        entryID = payload.entryID
        createdAt = payload.createdAt
    }

    var level: MoodLevel { MoodLevel(rawValue: overall) ?? .okay }
    var coupleMember: CoupleMember { CoupleMember(rawValue: member) ?? .owner }

    func value(_ parameter: MoodParameter) -> Int {
        switch parameter {
        case .energy: energy
        case .calm: calm
        case .body: health
        case .warmth: warmth
        case .focus: focus
        }
    }

    func set(_ value: Int, for parameter: MoodParameter) {
        switch parameter {
        case .energy: energy = value
        case .calm: calm = value
        case .body: health = value
        case .warmth: warmth = value
        case .focus: focus = value
        }
    }
}

// MARK: - Календарь

enum MoodCalendar {
    /// Итоги дня для общего календаря «Планера».
    @MainActor
    static func items(context: ModelContext, interval: DateInterval) -> [CalendarItem] {
        let from = interval.start.addingTimeInterval(-86_400)
        let to = interval.end
        let descriptor = FetchDescriptor<MoodDayCheckIn>(
            predicate: #Predicate { $0.deletedAt == nil && $0.day >= from && $0.day < to }
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        let calendar = Calendar.current
        return rows.compactMap { row in
            guard let start = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: row.day),
                  let end = calendar.date(byAdding: .minute, value: 30, to: start),
                  end > interval.start, start < interval.end else { return nil }
            return CalendarItem(
                id: "mood.checkin.\(row.syncID.uuidString)",
                title: "\(row.level.emoji) Настроение \(row.overall)/5",
                start: start,
                end: end,
                member: row.coupleMember,
                color: row.level.color,
                systemImage: "face.smiling"
            )
        }
    }
}

// MARK: - Экран вечернего опроса

/// «Мироня спрашивает»: вечерний итог дня.
struct MoodCheckInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    let existing: MoodDayCheckIn?

    @State private var overall: MoodLevel = .good
    @State private var values: [MoodParameter: Int] = [:]
    @State private var note = ""
    @State private var logSleep = true
    @State private var bedtime = MoodCheckInView.defaultBedtime()
    @State private var wakeTime = MoodCheckInView.defaultWake()
    @State private var sleepQuality = 3
    @State private var sleepEntry: SleepEntry?
    @State private var weightText = ""

    /// По умолчанию: лёг вчера в 23:00, встал сегодня в 07:00.
    private static func defaultWake() -> Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    }

    private static func defaultBedtime() -> Date {
        Calendar.current.date(byAdding: .hour, value: -8, to: defaultWake()) ?? .now
    }

    private var sleepDuration: TimeInterval { wakeTime.timeIntervalSince(bedtime) }
    private var sleepProblem: Bool { sleepDuration <= 0 || sleepDuration > 20 * 3600 }

    init(existing: MoodDayCheckIn? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoodMironSpeech(text: MoodMiron.question(for: .now)) { EmptyView() }
                        .listRowBackground(Color.clear)
                }

                Section("Как прошёл день в целом") {
                    MoodLevelPicker(selection: $overall)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section("По чуть-чуть") {
                    ForEach(MoodParameter.allCases) { parameter in
                        MoodScaleRow(parameter: parameter, value: Binding(
                            get: { values[parameter] ?? 3 },
                            set: { values[parameter] = $0 }
                        ))
                    }
                }

                Section {
                    Toggle("Записать, как спалось", isOn: $logSleep)
                    if logSleep {
                        SleepTimeFields(bedtime: $bedtime, wakeTime: $wakeTime)
                        LabeledContent("Сон") {
                            Text(sleepProblem ? "проверьте время" : SleepFormat.duration(sleepDuration))
                                .foregroundStyle(sleepProblem ? .red : .primary)
                        }
                        MoodMironSpeech(text: "Как спалось?") {
                            HStack {
                                ForEach(1...5, id: \.self) { value in
                                    Button {
                                        sleepQuality = value
                                    } label: {
                                        Text(SleepFormat.emoji(for: value))
                                            .font(.title2)
                                            .opacity(sleepQuality == value ? 1 : 0.35)
                                            .scaleEffect(sleepQuality == value ? 1.15 : 1)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(SleepFormat.title(for: value))
                                }
                            }
                            .frame(maxWidth: 230)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Сон прошлой ночью")
                }

                Section {
                    TextField("Вес сегодня, кг", text: $weightText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Вес (необязательно)")
                } footer: {
                    Text("Можно пропустить или записать в любой день в разделе «Здоровье».")
                }

                Section("Пара слов (необязательно)") {
                    TextField("Что запомнилось за день", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Итог дня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Позже") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled((logSleep && sleepProblem) || (!weightText.isEmpty && MoodWeightStore.parse(weightText) == nil))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        // Сон, который уже записан на сегодня (проснулись сегодня).
        let today = Calendar.current.startOfDay(for: .now)
        let who = account.current.rawValue
        let todayKey = MoodDayKey.key(for: .now)
        if let weight = ((try? context.fetch(FetchDescriptor<MoodWeightEntry>())) ?? [])
            .first(where: { $0.deletedAt == nil && $0.member == who && $0.dayKey == todayKey }) {
            weightText = MoodWeightStore.format(weight.kg)
        }
        let rows = ((try? context.fetch(FetchDescriptor<SleepEntry>())) ?? [])
            .filter { $0.deletedAt == nil && $0.member == who && $0.nightDay == today }
        if let main = rows.max(by: { $0.duration < $1.duration }) {
            sleepEntry = main
            bedtime = main.bedtime
            wakeTime = main.wakeTime
            sleepQuality = main.quality
        }
        guard let existing else { return }
        overall = existing.level
        note = existing.note
        for parameter in MoodParameter.allCases {
            values[parameter] = existing.value(parameter)
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let item: MoodDayCheckIn
        if let existing {
            item = existing
        } else {
            item = MoodDayCheckIn(member: account.current)
            context.insert(item)
        }
        item.overall = overall.rawValue
        for parameter in MoodParameter.allCases {
            item.set(values[parameter] ?? 3, for: parameter)
        }
        item.note = trimmed

        // Отметка в истории настроения, чтобы итог попал в календарь-сетку.
        var entry: MoodEntry?
        if let id = item.entryID {
            entry = (try? context.fetch(FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.syncID == id })))?.first
        }
        if let entry, entry.deletedAt == nil {
            entry.level = overall.rawValue
            entry.markChanged()
        } else {
            let created = MoodEntry(member: account.current, level: overall, tags: ["итог дня"])
            context.insert(created)
            item.entryID = created.syncID
        }
        item.markChanged()

        if logSleep, !sleepProblem {
            if let sleepEntry {
                sleepEntry.bedtime = bedtime
                sleepEntry.wakeTime = wakeTime
                sleepEntry.quality = sleepQuality
                sleepEntry.markChanged()
            } else {
                context.insert(SleepEntry(member: account.current, bedtime: bedtime, wakeTime: wakeTime, quality: sleepQuality, note: ""))
            }
        }
        try? context.save()
        sync.requestSync()
        if let kg = MoodWeightStore.parse(weightText) {
            MoodWeightStore.save(kg: kg, member: account.current, context: context, sync: sync)
        }
        MoodReminder.skipToday()
        dismiss()
    }
}

/// Строка оценки параметра: пять кружков.
struct MoodScaleRow: View {
    let parameter: MoodParameter
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(parameter.emoji) \(parameter.title)")
                Spacer()
                Text(parameter.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        value = step
                    } label: {
                        Circle()
                            .fill(step <= value ? MoodLevel.color(for: Double(value)) : Color.secondary.opacity(0.18))
                            .frame(height: 28)
                            .overlay(Text("\(step)").font(.caption2.bold()).foregroundStyle(step <= value ? .white : .secondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: value)
        }
        .padding(.vertical, 4)
    }
}
