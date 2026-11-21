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
                    Text(kind.title)
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
                    Text(kind.name)
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
