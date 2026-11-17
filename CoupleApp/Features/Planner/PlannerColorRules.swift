import SwiftData
import SwiftUI

/// Свой цвет для группы, дела или клиента (настройки цветов).
/// Ключ: `group:<название>`, `errand:<название>` или `client:<id клиента>`.
@Model
final class PlannerColorRule: SyncableModel {
    struct Payload: Codable {
        var key: String
        var hex: String
    }

    static let recordKind = "planner.colorRule"

    var syncID: UUID = UUID()
    var key: String = ""
    var hex: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(key: String, hex: String) {
        self.syncID = Self.makeID(key: key)
        self.key = key
        self.hex = hex
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(key: key, hex: hex) }

    func apply(_ payload: Payload) {
        key = payload.key
        hex = payload.hex
    }

    static func makeID(key: String) -> UUID {
        PlannerDeterministicID.make("color|" + key)
    }

    static func groupKey(_ name: String) -> String {
        "group:" + name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func errandKey(_ name: String) -> String {
        "errand:" + name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func clientKey(_ id: UUID) -> String { "client:" + id.uuidString }
}

enum PlannerColorStore {
    /// Какого цвета рисовать запись: свой цвет записи, затем цвет клиента, группы или дела, затем цвет вида.
    static func color(for event: PlannerEvent, rules: [PlannerColorRule]) -> Color {
        if let own = Color(hex: event.colorHex) { return own }
        func rule(_ key: String) -> Color? {
            rules.first { $0.key == key && $0.deletedAt == nil }.flatMap { Color(hex: $0.hex) }
        }
        switch event.categoryValue {
        case .personal:
            if let id = event.participantIDs.first, let color = rule(PlannerColorRule.clientKey(id)) { return color }
        case .group, .school:
            if let color = rule(PlannerColorRule.groupKey(event.title)) { return color }
        case .errand:
            if let color = rule(PlannerColorRule.errandKey(event.title)) { return color }
        default:
            break
        }
        return event.categoryValue.color
    }

    @MainActor
    static func set(_ context: ModelContext, key: String, hex: String?) {
        let id = PlannerColorRule.makeID(key: key)
        let found = try? context.fetch(FetchDescriptor<PlannerColorRule>(predicate: #Predicate { $0.syncID == id }))
        if let hex {
            if let rule = found?.first {
                rule.hex = hex
                rule.deletedAt = nil
                rule.markChanged()
            } else {
                let rule = PlannerColorRule(key: key, hex: hex)
                context.insert(rule)
                rule.markChanged()
            }
        } else if let rule = found?.first {
            rule.markDeleted()
        }
        try? context.save()
    }
}

/// Настройки цветов: для каждой группы, дела и (по желанию) клиента.
struct PlannerColorSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PlannerGroupKind> { $0.deletedAt == nil }, sort: \PlannerGroupKind.name)
    private var groups: [PlannerGroupKind]
    @Query(filter: #Predicate<PlannerErrandKind> { $0.deletedAt == nil }, sort: \PlannerErrandKind.name)
    private var errands: [PlannerErrandKind]
    @Query(filter: #Predicate<PlannerColorRule> { $0.deletedAt == nil })
    private var rules: [PlannerColorRule]

    @State private var clients: [PlannerClientDirectory.Entry] = []
    @State private var query = ""

    private var matchingClients: [PlannerClientDirectory.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(clients.filter { hasRule(PlannerColorRule.clientKey($0.id)) }) }
        return Array(clients.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(8))
    }

    private func hasRule(_ key: String) -> Bool { rules.contains { $0.key == key } }

    var body: some View {
        List {
            Section("👧👦 Группы") {
                if groups.isEmpty { Text("Групп пока нет").foregroundStyle(.secondary) }
                ForEach(groups) { group in
                    row(title: group.name, key: PlannerColorRule.groupKey(group.name), fallback: group.categoryValue.color)
                }
            }
            Section("🧳 Дела") {
                if errands.isEmpty { Text("Регулярных дел пока нет").foregroundStyle(.secondary) }
                ForEach(errands) { errand in
                    row(title: errand.name, key: PlannerColorRule.errandKey(errand.name), fallback: PlannerCategory.errand.color)
                }
            }
            Section {
                TextField("🔍 Найти клиента", text: $query).autocorrectionDisabled()
                ForEach(matchingClients) { client in
                    row(title: client.name, key: PlannerColorRule.clientKey(client.id), fallback: PlannerCategory.personal.color)
                }
            } header: {
                Text("🙋 Клиенты (по желанию)")
            } footer: {
                Text("Свой цвет у клиента красит его персональные тренировки. Цвет самой записи можно поменять в её форме.")
            }
        }
        .onAppear { clients = PlannerClientDirectory.all(context) }
    }

    private func row(title: String, key: String, fallback: Color) -> some View {
        let current = rules.first { $0.key == key }.flatMap { Color(hex: $0.hex) }
        return HStack {
            Circle().fill(current ?? fallback).frame(width: 14, height: 14)
            Text(title)
            Spacer()
            if current != nil {
                Button("Сбросить") {
                    PlannerColorStore.set(context, key: key, hex: nil)
                    sync.requestSync()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            ColorPicker("", selection: Binding(
                get: { current ?? fallback },
                set: {
                    PlannerColorStore.set(context, key: key, hex: $0.hexString)
                    sync.requestSync()
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}

/// Строка «Свой цвет» для группы или клиента: пишет в настройки цветов.
struct PlannerRuleColorRow: View {
    let key: String
    let fallback: Color

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Query(filter: #Predicate<PlannerColorRule> { $0.deletedAt == nil })
    private var rules: [PlannerColorRule]

    var body: some View {
        let current = rules.first { $0.key == key }.flatMap { Color(hex: $0.hex) }
        HStack {
            Text("🎨 Цвет")
            Spacer()
            if current != nil {
                Button("Сбросить") {
                    PlannerColorStore.set(context, key: key, hex: nil)
                    sync.requestSync()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            ColorPicker("", selection: Binding(
                get: { current ?? fallback },
                set: {
                    PlannerColorStore.set(context, key: key, hex: $0.hexString)
                    sync.requestSync()
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}
