import SwiftData
import SwiftUI

/// Списки дел с галочками: общие, мои и партнёра.
struct PlannerTasksView: View {
    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<PlannerTask> { $0.deletedAt == nil }, sort: \PlannerTask.createdAt)
    private var tasks: [PlannerTask]

    @State private var draft = ""
    @State private var draftShared = true
    @AppStorage("planner.showDone") private var showDone = false
    @State private var editing: PlannerTask?
    @FocusState private var draftFocused: Bool

    private var groups: [PlannerScope] {
        [.shared, .personal(account.current), .personal(account.current.other)]
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Новое дело", text: $draft)
                        .focused($draftFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Menu {
                        Picker("Для кого", selection: $draftShared) {
                            Label("Общее", systemImage: "person.2").tag(true)
                            Label("Только моё", systemImage: "person").tag(false)
                        }
                    } label: {
                        Image(systemName: draftShared ? "person.2" : "person")
                    }
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .buttonStyle(.borderless)
            } footer: {
                Text(draftShared ? "Добавится в общий список." : "Добавится в ваш личный список, \(account.partnerName) увидит его, но не сможет менять.")
            }

            ForEach(groups) { scope in
                let open = sorted(tasks.filter { $0.scopeValue == scope && !$0.isDone })
                if !open.isEmpty {
                    Section(sectionTitle(scope)) {
                        ForEach(open) { task in
                            row(task)
                        }
                    }
                }
            }

            let done = tasks.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
            if !done.isEmpty {
                Section {
                    Button {
                        withAnimation { showDone.toggle() }
                    } label: {
                        HStack {
                            Text("Сделано (\(done.count))")
                            Spacer()
                            Image(systemName: showDone ? "chevron.up" : "chevron.down")
                        }
                        .foregroundStyle(.secondary)
                    }
                    if showDone {
                        ForEach(done) { task in
                            row(task)
                        }
                    }
                }
            }

            if tasks.isEmpty {
                Section {
                    Text("Пока нет дел. Например, добавьте общий список покупок.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable { await sync.syncNow() }
        .sheet(item: $editing) { task in
            PlannerTaskEditor(task: task)
        }
    }

    private func row(_ task: PlannerTask) -> some View {
        PlannerTaskRow(task: task, showsDue: true)
            .contentShape(Rectangle())
            .onTapGesture { editing = task }
            .swipeActions {
                if task.scopeValue.canEdit(by: account.current) {
                    Button("Удалить", role: .destructive) {
                        task.markDeleted()
                        try? context.save()
                        sync.requestSync()
                    }
                }
            }
    }

    private func sectionTitle(_ scope: PlannerScope) -> String {
        switch scope {
        case .shared: "Общие"
        default: scope.member == account.current ? "Мои" : account.name(of: scope.member ?? .owner)
        }
    }

    /// Сначала со сроком (ближайшие выше), потом без срока по порядку добавления.
    private func sorted(_ list: [PlannerTask]) -> [PlannerTask] {
        list.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): l < r
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): lhs.createdAt < rhs.createdAt
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let task = PlannerTask()
        task.title = text
        task.scope = (draftShared ? PlannerScope.shared : .personal(account.current)).rawValue
        task.createdBy = account.current.rawValue
        task.createdAt = .now
        task.markChanged()
        context.insert(task)
        try? context.save()
        sync.requestSync()
        draft = ""
        draftFocused = true
    }
}

/// Строка дела с галочкой. Используется и в списке дел, и в календаре.
struct PlannerTaskRow: View {
    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context

    let task: PlannerTask
    let showsDue: Bool

    private var canEdit: Bool { task.scopeValue.canEdit(by: account.current) }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : (canEdit ? Color.accentColor : Color.secondary))
            }
            .buttonStyle(.borderless)
            .disabled(!canEdit)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if showsDue, let due = task.dueDate, !task.isDone {
                    Text(dueText(due))
                        .font(.caption)
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                }
                if !showsDue && task.scopeValue != .shared {
                    Text(task.scopeValue.title(account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !canEdit {
                Image(systemName: "lock").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func dueText(_ due: Date) -> String {
        let cal = PlannerCalendar.calendar
        if cal.isDateInToday(due) { return "Сегодня" }
        if cal.isDateInTomorrow(due) { return "Завтра" }
        if cal.isDateInYesterday(due) { return "Вчера" }
        return PlannerCalendar.format(due, "dMMMM")
    }

    private func toggle() {
        guard canEdit else { return }
        withAnimation {
            task.isDone.toggle()
            task.doneAt = task.isDone ? .now : nil
            task.markChanged()
        }
        try? context.save()
        sync.requestSync()
    }
}

/// Правка дела: название, срок, для кого, заметка.
struct PlannerTaskEditor: View {
    let task: PlannerTask

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var title: String
    @State private var notes: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var isShared: Bool

    init(task: PlannerTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _hasDue = State(initialValue: task.dueDate != nil)
        _due = State(initialValue: task.dueDate ?? PlannerCalendar.calendar.startOfDay(for: .now))
        _isShared = State(initialValue: task.scopeValue == .shared)
    }

    private var canEdit: Bool { task.scopeValue.canEdit(by: account.current) }

    var body: some View {
        NavigationStack {
            Form {
                if !canEdit {
                    Section {
                        Label("Это личное дело: \(account.name(of: task.scopeValue.member ?? .owner)).", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Название", text: $title)
                    Picker("Для кого", selection: $isShared) {
                        Text("Общее").tag(true)
                        Text("Только моё").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Срок", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Дата", selection: $due, displayedComponents: [.date])
                    }
                } footer: {
                    Text("Дело со сроком видно в календаре в этот день.")
                }
                Section("Заметка") {
                    TextField("Подробности", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if canEdit {
                    Section {
                        Button("Удалить дело", role: .destructive) {
                            task.markDeleted()
                            try? context.save()
                            sync.requestSync()
                            dismiss()
                        }
                    }
                }
            }
            .disabled(!canEdit)
            .navigationTitle(canEdit ? "Дело" : "Просмотр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить", action: save)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
            }
        }
        .environment(\.locale, PlannerCalendar.locale)
    }

    private func save() {
        task.title = title.trimmingCharacters(in: .whitespaces)
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.dueDate = hasDue ? PlannerCalendar.calendar.startOfDay(for: due) : nil
        task.scope = (isShared ? PlannerScope.shared : .personal(account.current)).rawValue
        task.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
