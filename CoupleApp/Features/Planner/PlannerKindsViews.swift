import SwiftData
import SwiftUI

/// Типы прибыли или трат Платони: поиск, «+» для нового, удаление с подтверждением.
struct PlannerMoneyKindsView: View {
    let profit: Bool

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Query(filter: #Predicate<PlannerMoneyKind> { $0.deletedAt == nil }, sort: \PlannerMoneyKind.name)
    private var kinds: [PlannerMoneyKind]

    @State private var query = ""
    @State private var pendingDelete: PlannerMoneyKind?
    @State private var showConfirm = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var mine: [PlannerMoneyKind] { kinds.filter { $0.isProfit == profit } }
    private var shown: [PlannerMoneyKind] {
        trimmed.isEmpty ? mine : mine.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
    private var exists: Bool {
        mine.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Поиск или новый тип", text: $query)
                        .onSubmit(add)
                    if !trimmed.isEmpty && !exists {
                        Button(action: add) {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Section {
                if shown.isEmpty { Text("Ничего нет").foregroundStyle(.secondary) }
                ForEach(shown) { kind in
                    NavigationLink {
                        PlannerMoneyKindDetail(kind: kind)
                    } label: {
                        Text(kind.title)
                    }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = kind
                                showConfirm = true
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
            } footer: {
                Text("Потяни запись влево, чтобы удалить тип из базы.")
            }
        }
        .navigationTitle(profit ? "Типы прибыли" : "Типы трат")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Удалить тип из базы?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                pendingDelete?.markDeleted()
                pendingDelete = nil
                try? context.save()
                sync.requestSync()
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        _ = PlannerMoneyKindStore.ensure(context, name: trimmed, isProfit: profit)
        query = ""
        sync.requestSync()
    }
}

/// Типы регулярных дел того, кто вошёл: поиск, «+» и удаление с подтверждением.
struct PlannerErrandKindsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<PlannerErrandKind> { $0.deletedAt == nil }, sort: \PlannerErrandKind.name)
    private var kinds: [PlannerErrandKind]

    @State private var query = ""
    @State private var pendingDelete: PlannerErrandKind?
    @State private var showConfirm = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var mine: [PlannerErrandKind] { kinds.visible(to: account.current) }
    private var shown: [PlannerErrandKind] {
        trimmed.isEmpty ? mine : mine.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
    private var exists: Bool {
        mine.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Поиск или новый тип", text: $query)
                        .onSubmit(add)
                    if !trimmed.isEmpty && !exists {
                        Button(action: add) {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Section {
                if shown.isEmpty { Text("Ничего нет").foregroundStyle(.secondary) }
                ForEach(shown) { kind in
                    NavigationLink {
                        PlannerErrandKindDetail(kind: kind)
                    } label: {
                        Text("\(kind.displayEmoji) \(kind.name)")
                    }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = kind
                                showConfirm = true
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
            } footer: {
                Text("Потяни запись влево, чтобы удалить тип из базы. Старые записи в журнале останутся.")
            }
        }
        .navigationTitle("Типы дел")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Удалить тип из базы?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                pendingDelete?.markDeleted()
                pendingDelete = nil
                try? context.save()
                sync.requestSync()
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        PlannerErrandKindStore.ensure(context, name: trimmed, owner: account.current)
        query = ""
        sync.requestSync()
    }
}

/// Один тип дела: эмодзи, цвет, сколько дел, удаление.
struct PlannerErrandKindDetail: View {
    let kind: PlannerErrandKind

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var events: [PlannerEvent]

    @State private var emoji = ""
    @State private var colorHex = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    private var related: [PlannerEvent] {
        events.filter { $0.errandType.caseInsensitiveCompare(kind.name) == .orderedSame }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        Form {
            Section("Внешний вид") {
                HStack {
                    Text("Эмодзи")
                    Spacer()
                    TextField("💼", text: $emoji)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                PlannerColorField(title: "Свой цвет типа", hex: $colorHex, defaultColor: .accentColor)
            }
            Section("Дела этого типа: \(related.count)") {
                if related.isEmpty { Text("Пока нет").foregroundStyle(.secondary) }
                ForEach(related.prefix(20)) { event in
                    HStack {
                        Text(event.title)
                        Spacer()
                        Text(StatisticsFormat.day(event.start)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Удалить тип из базы", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Старые записи в журнале останутся.")
            }
        }
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            emoji = kind.emoji
            colorHex = kind.colorHex
        }
        .onDisappear(perform: save)
        .confirmationDialog("Удалить тип из базы?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                loaded = false
                kind.markDeleted()
                try? context.save()
                sync.requestSync()
                dismiss()
            }
        }
    }

    private func save() {
        guard loaded, kind.deletedAt == nil else { return }
        let clean = emoji.trimmingCharacters(in: .whitespaces)
        guard clean != kind.emoji || colorHex != kind.colorHex else { return }
        kind.emoji = clean
        kind.colorHex = colorHex
        kind.markChanged()
        try? context.save()
        sync.requestSync()
    }
}

/// Один тип прибыли или траты: эмодзи, сколько операций, удаление.
struct PlannerMoneyKindDetail: View {
    let kind: PlannerMoneyKind

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<PlannerMoneyOp> { $0.deletedAt == nil })
    private var ops: [PlannerMoneyOp]

    @State private var emoji = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    private var related: [PlannerMoneyOp] {
        ops.filter { $0.typeName == kind.name }.sorted { $0.date > $1.date }
    }

    var body: some View {
        Form {
            Section("Внешний вид") {
                HStack {
                    Text("Эмодзи")
                    Spacer()
                    TextField("🙂", text: $emoji)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
            Section("Операции этого типа: \(related.count)") {
                if related.isEmpty { Text("Пока нет").foregroundStyle(.secondary) }
                ForEach(related.prefix(20)) { op in
                    HStack {
                        Text(StatisticsFormat.day(op.date))
                        Spacer()
                        Text(PlannerPricing.format(op.amount)).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Удалить тип из базы", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            emoji = kind.emoji
        }
        .onDisappear(perform: save)
        .confirmationDialog("Удалить тип из базы?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                loaded = false
                kind.markDeleted()
                try? context.save()
                sync.requestSync()
                dismiss()
            }
        }
    }

    private func save() {
        guard loaded, kind.deletedAt == nil else { return }
        let clean = emoji.trimmingCharacters(in: .whitespaces)
        guard clean != kind.emoji else { return }
        kind.emoji = clean
        kind.markChanged()
        try? context.save()
        sync.requestSync()
    }
}
