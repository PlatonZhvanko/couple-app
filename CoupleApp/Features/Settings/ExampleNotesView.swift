import SwiftData
import SwiftUI

/// Проверка синхронизации: добавьте заметку на одном телефоне,
/// и через несколько секунд она появится на втором.
struct ExampleNotesView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<ExampleNote> { $0.deletedAt == nil }, sort: \ExampleNote.createdAt, order: .reverse)
    private var notes: [ExampleNote]
    @State private var draft = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Новая заметка", text: $draft)
                        .onSubmit(add)
                    Button("Добавить", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Добавьте заметку здесь, а потом откройте этот же экран на втором телефоне.")
            }

            Section {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.text)
                        Text("\(note.author.isEmpty ? "Без имени" : note.author) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Проверка синхронизации")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sync.syncNow() }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        context.insert(ExampleNote(text: text, author: account.myName))
        try? context.save()
        draft = ""
        sync.requestSync()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { notes[index].markDeleted() }
        try? context.save()
        sync.requestSync()
    }
}
