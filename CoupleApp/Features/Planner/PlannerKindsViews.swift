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
                if let target = pendingDelete { PlannerMoneyKindStore.delete(context, kind: target) }
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
                if let target = pendingDelete { PlannerErrandKindStore.delete(context, kind: target) }
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

    @State private var name = ""
    @State private var money: PlannerMoneyDirection = .none
    @State private var emoji = ""
    @State private var useColor = false
    @State private var color: Color = .blue
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var total = 0
    @State private var recent: [(title: String, start: Date)] = []

    var body: some View {
        Form {
            Section("Название") {
                TextField("Название типа", text: $name)
                    .onSubmit(save)
            }
            Section {
                Picker("Деньги", selection: $money) {
                    ForEach(PlannerMoneyDirection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Деньги типа")
            } footer: {
                Text("Прибыль или трата: тип сам появится в типах прибыли или трат, второй тип создавать не нужно.")
            }
            Section("Внешний вид") {
                PlannerEmojiStrip(selection: $emoji)
                Toggle("🎨 Свой цвет типа", isOn: $useColor)
                if useColor {
                    ColorPicker("Цвет", selection: $color, supportsOpacity: false)
                }
            }
            Section("Дела этого типа: \(total)") {
                if recent.isEmpty { Text("Пока нет").foregroundStyle(.secondary) }
                ForEach(Array(recent.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(StatisticsFormat.day(row.start)).font(.caption).foregroundStyle(.secondary)
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
        .onAppear(perform: load)
        .onChange(of: emoji) { _, _ in save() }
        .onChange(of: useColor) { _, _ in save() }
        .onChange(of: money) { _, _ in save() }
        .onDisappear(perform: save)
        .confirmationDialog("Удалить тип из базы?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                loaded = false
                PlannerErrandKindStore.delete(context, kind: kind)
                try? context.save()
                sync.requestSync()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func load() {
        guard !loaded else { return }
        let kindName = kind.name
        var descriptor = FetchDescriptor<PlannerEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.errandType == kindName },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        total = (try? context.fetchCount(descriptor)) ?? 0
        descriptor.fetchLimit = 20
        let rows = (try? context.fetch(descriptor)) ?? []
        recent = rows.map { (title: $0.title, start: $0.start) }
        emoji = kind.emoji
        name = kind.name
        money = kind.moneyDirection
        if let saved = Color(hex: kind.colorHex), !kind.colorHex.isEmpty {
            useColor = true
            color = saved
        }
        loaded = true
    }

    private func save() {
        guard loaded, kind.deletedAt == nil else { return }
        let newEmoji = emoji.trimmingCharacters(in: .whitespaces)
        let newHex = useColor ? color.hexString : ""
        let newName = name.trimmingCharacters(in: .whitespaces)
        let renamed = !newName.isEmpty && newName != kind.name
        let moneyChanged = money != kind.moneyDirection
        guard renamed || moneyChanged || newEmoji != kind.emoji || newHex != kind.colorHex else { return }
        if renamed { PlannerErrandKindStore.rename(context, kind: kind, to: newName) }
        if moneyChanged { PlannerErrandKindStore.setMoney(context, kind: kind, direction: money) }
        kind.emoji = newEmoji
        kind.colorHex = newHex
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

    @State private var name = ""
    @State private var emoji = ""
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var total = 0
    @State private var recent: [(amount: Double, date: Date)] = []
    @State private var pending = 0

    var body: some View {
        Form {
            Section("Название") {
                TextField("Название типа", text: $name)
                    .onSubmit(save)
            }
            Section("Внешний вид") {
                PlannerEmojiStrip(selection: $emoji)
            }
            Section {
                if pending > 0 {
                    Text("Дел с этим типом ждут отметки «Сделано»: \(pending). Деньги попадут в статистику после отметки.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Операции этого типа: \(total)") {
                if recent.isEmpty { Text("Пока нет").foregroundStyle(.secondary) }
                ForEach(Array(recent.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(StatisticsFormat.day(row.date))
                        Spacer()
                        Text(PlannerPricing.format(row.amount)).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Удалить тип из базы", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .onChange(of: emoji) { _, _ in save() }
        .confirmationDialog("Удалить тип из базы?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                loaded = false
                PlannerMoneyKindStore.delete(context, kind: kind)
                try? context.save()
                sync.requestSync()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func load() {
        guard !loaded else { return }
        let kindName = kind.name
        var descriptor = FetchDescriptor<PlannerMoneyOp>(
            predicate: #Predicate { $0.deletedAt == nil && $0.typeName == kindName },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let opCount = (try? context.fetchCount(descriptor)) ?? 0
        descriptor.fetchLimit = 20
        let ops = (try? context.fetch(descriptor)) ?? []
        // Деньги дел с этим типом: идут в статистику, когда в записи отмечено «Сделано».
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.moneyType == kindName }
        ))) ?? []
        let matching = events.filter { ($0.moneyDirection == .profit) == kind.isProfit && $0.moneyDirection != .none }
        let done = PlannerLedger.entries(events: matching, shifts: [], ops: [])
        pending = matching.filter { event in !event.statuses.values.contains { $0 == .done } }.count
        var rows = ops.map { (amount: $0.amount, date: $0.date) }
        rows += done.map { (amount: abs($0.amount), date: $0.day) }
        rows.sort { $0.date > $1.date }
        total = opCount + done.count
        recent = Array(rows.prefix(20))
        emoji = kind.emoji
        name = kind.name
        loaded = true
    }

    private func save() {
        guard loaded, kind.deletedAt == nil else { return }
        let clean = emoji.trimmingCharacters(in: .whitespaces)
        let newName = name.trimmingCharacters(in: .whitespaces)
        let renamed = !newName.isEmpty && newName != kind.name
        guard renamed || clean != kind.emoji else { return }
        if renamed { PlannerMoneyKindStore.rename(context, kind: kind, to: newName) }
        kind.emoji = clean
        kind.markChanged()
        try? context.save()
        sync.requestSync()
    }
}

/// Отдельный раздел «Типы дел» (вкладка Насти, рядом с клиентами и группами).
enum PlannerErrandKindsFeature {
    static let feature = Feature(
        id: "plannerErrandKinds",
        title: "Типы дел",
        systemImage: "tag.fill",
        availableFor: [.partner]
    ) {
        NavigationStack {
            PlannerErrandKindsView()
        }
    }
}
