import SwiftData
import SwiftUI

/// Экран новой отметки настроения или правки существующей.
struct MoodEntryEditor: View {
    /// Существующая отметка для правки или `nil` для новой.
    let entry: MoodEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var level: MoodLevel
    @State private var tags: Set<String>
    @State private var note: String
    @State private var isNotePrivate: Bool
    @State private var createdAt: Date
    @State private var confirmDelete = false

    init(entry: MoodEntry? = nil, initialLevel: MoodLevel = .okay) {
        self.entry = entry
        _level = State(initialValue: entry?.moodLevel ?? initialLevel)
        _tags = State(initialValue: Set(entry?.tags ?? []))
        _note = State(initialValue: entry?.note ?? "")
        _isNotePrivate = State(initialValue: entry?.isNotePrivate ?? false)
        _createdAt = State(initialValue: entry?.createdAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Как ты?") {
                    MoodLevelPicker(selection: $level)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                    Text(level.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }

                Section("Что чувствуешь") {
                    MoodTagCloud(selection: $tags)
                }

                Section {
                    TextField("Заметка (необязательно)", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                    Toggle("Только для меня", isOn: $isNotePrivate)
                } footer: {
                    Text(isNotePrivate
                         ? "Заметка останется только на этом телефоне. \(account.partnerName) увидит настроение и метки, но не текст."
                         : "\(account.partnerName) увидит и заметку.")
                }

                Section {
                    DatePicker("Когда", selection: $createdAt, in: ...Date.now)
                }

                if entry != nil {
                    Section {
                        Button("Удалить отметку", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Новая отметка" : "Отметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                }
            }
            .confirmationDialog("Удалить отметку?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
            }
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedTags = MoodTags.all.filter { tags.contains($0) }
        if let entry {
            entry.level = level.rawValue
            entry.tags = sortedTags
            entry.note = trimmed
            entry.isNotePrivate = isNotePrivate
            entry.createdAt = createdAt
            entry.markChanged()
        } else {
            context.insert(MoodEntry(
                member: account.current,
                level: level,
                tags: sortedTags,
                note: trimmed,
                isNotePrivate: isNotePrivate,
                createdAt: createdAt
            ))
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

// MARK: - Элементы

/// Ряд из пяти эмодзи для выбора настроения.
struct MoodLevelPicker: View {
    @Binding var selection: MoodLevel
    /// false — кнопки без подсветки (быстрая отметка на главном экране).
    var showsSelection: Bool = true

    private func isHighlighted(_ item: MoodLevel) -> Bool {
        showsSelection && item == selection
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MoodLevel.allCases) { item in
                Button {
                    selection = item
                } label: {
                    Text(item.emoji)
                        .font(.system(size: 36))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isHighlighted(item) ? item.color.opacity(0.35) : Color.clear)
                        )
                        .scaleEffect(isHighlighted(item) ? 1.1 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .animation(.snappy, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Метки-кнопки, которые можно включать и выключать.
struct MoodTagCloud: View {
    @Binding var selection: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(MoodTags.all, id: \.self) { tag in
                let isOn = selection.contains(tag)
                Button {
                    if isOn { selection.remove(tag) } else { selection.insert(tag) }
                } label: {
                    Text(tag)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
