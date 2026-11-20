import SwiftData
import SwiftUI

/// Добавить или изменить ночь сна.
struct SleepEntryEditor: View {
    /// nil — новая запись.
    let entry: SleepEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var bedtime: Date
    @State private var wakeTime: Date
    @State private var quality: Int
    @State private var note: String

    init(entry: SleepEntry?) {
        self.entry = entry
        if let entry {
            _bedtime = State(initialValue: entry.bedtime)
            _wakeTime = State(initialValue: entry.wakeTime)
            _quality = State(initialValue: entry.quality)
            _note = State(initialValue: entry.note)
        } else {
            // По умолчанию: вчера в 23:00 → сегодня в 07:00.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let wake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today) ?? .now
            let bed = calendar.date(byAdding: .hour, value: -8, to: wake) ?? .now
            _bedtime = State(initialValue: bed)
            _wakeTime = State(initialValue: wake)
            _quality = State(initialValue: 3)
            _note = State(initialValue: "")
        }
    }

    private var duration: TimeInterval { wakeTime.timeIntervalSince(bedtime) }

    private var problem: String? {
        if duration <= 0 { return "Время пробуждения должно быть позже, чем время отхода ко сну." }
        if duration > 20 * 3600 { return "Больше 20 часов сна — проверьте даты." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SleepTimeFields(bedtime: $bedtime, wakeTime: $wakeTime)
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else {
                        Text("Сон: \(SleepFormat.duration(duration))")
                    }
                }

                Section("Как спалось") {
                    HStack {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                quality = value
                            } label: {
                                Text(SleepFormat.emoji(for: value))
                                    .font(.largeTitle)
                                    .opacity(quality == value ? 1 : 0.35)
                                    .scaleEffect(quality == value ? 1.15 : 1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(SleepFormat.title(for: value))
                        }
                    }
                    Text(SleepFormat.title(for: quality))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }

                Section("Заметка") {
                    TextField("Например: кофе вечером, просыпался ночью", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if entry != nil {
                    Section {
                        Button("Удалить запись", role: .destructive, action: delete)
                    }
                }
            }
            .navigationTitle(entry == nil ? "Новая ночь" : "Ночь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .disabled(problem != nil)
                }
            }
        }
    }

    private func save() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            entry.bedtime = bedtime
            entry.wakeTime = wakeTime
            entry.quality = quality
            entry.note = text
            entry.markChanged()
        } else {
            context.insert(SleepEntry(member: account.current, bedtime: bedtime, wakeTime: wakeTime, quality: quality, note: text))
        }
        try? context.save()
        sync.requestSync()
        dismiss()
    }

    private func delete() {
        entry?.markDeleted()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
