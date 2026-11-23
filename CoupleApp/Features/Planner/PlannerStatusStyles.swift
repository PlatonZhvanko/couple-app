import SwiftData
import SwiftUI

/// Вид записи при статусе: свой цвет и эмодзи. Область: «all» (все дела) или «type:<тип дела>».
/// Статус: «none» (без отметки), «done», «notDone», «moved».
@Model
final class PlannerStatusStyle: SyncableModel {
    struct Payload: Codable {
        var scope: String
        var status: String
        var color: String
        var emoji: String
        var hideEmoji: Bool
    }

    static let recordKind = "planner.statusStyle"

    var syncID: UUID = UUID()
    var scope: String = "all"
    var status: String = "none"
    var colorHex: String = ""
    var emoji: String = ""
    var hideEmoji: Bool = false
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(scope: String, status: String) {
        self.syncID = Self.makeID(scope: scope, status: status)
        self.scope = scope
        self.status = status
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(scope: scope, status: status, color: colorHex, emoji: emoji, hideEmoji: hideEmoji)
    }

    func apply(_ payload: Payload) {
        scope = payload.scope
        status = payload.status
        colorHex = payload.color
        emoji = payload.emoji
        hideEmoji = payload.hideEmoji
    }

    static func makeID(scope: String, status: String) -> UUID {
        PlannerDeterministicID.make("statusstyle|\(scope.lowercased())|\(status)")
    }

    /// Совместные дела: у каждого свой вид в своём планере.
    static func sharedScope(_ member: String) -> String { "shared:\(member)" }

    static func typeScope(_ name: String) -> String { "type:\(name.lowercased())" }

    static func statusKey(_ status: PlannerErrandStatus?) -> String {
        switch status {
        case .done: "done"
        case .notDone: "notDone"
        case .moved: "moved"
        case nil: "none"
        }
    }

    var isCustom: Bool { !colorHex.isEmpty || !emoji.isEmpty || hideEmoji }
}

/// Итоговый вид с учётом типа дела и общих настроек.
struct PlannerResolvedStatusStyle {
    var colorHex = ""
    var emoji = ""
    var hideEmoji = false
}

enum PlannerStatusStyleStore {
    /// Сначала настройки типа дела, потом общие для всех дел; пустое поле берётся из общих.
    static func resolve(_ styles: [PlannerStatusStyle], errandType: String, status: PlannerErrandStatus?, sharedMember: String? = nil) -> PlannerResolvedStatusStyle {
        let key = PlannerStatusStyle.statusKey(status)
        let general = styles.first { $0.scope == "all" && $0.status == key }
        let typed = errandType.isEmpty ? nil : styles.first {
            $0.scope == PlannerStatusStyle.typeScope(errandType) && $0.status == key
        }
        let shared = sharedMember.flatMap { member in
            styles.first { $0.scope == PlannerStatusStyle.sharedScope(member) && $0.status == key }
        }
        var result = PlannerResolvedStatusStyle()
        for style in [general, typed, shared].compactMap({ $0 }) {
            if !style.colorHex.isEmpty { result.colorHex = style.colorHex }
            if !style.emoji.isEmpty { result.emoji = style.emoji; result.hideEmoji = false }
            if style.hideEmoji { result.hideEmoji = true; result.emoji = "" }
        }
        return result
    }

    @MainActor
    static func style(_ context: ModelContext, scope: String, status: String) -> PlannerStatusStyle {
        let id = PlannerStatusStyle.makeID(scope: scope, status: status)
        if let found = (try? context.fetch(FetchDescriptor<PlannerStatusStyle>(predicate: #Predicate { $0.syncID == id })))?.first {
            if found.deletedAt != nil { found.deletedAt = nil }
            return found
        }
        let item = PlannerStatusStyle(scope: scope, status: status)
        context.insert(item)
        return item
    }
}

/// Вкладка «Настройка статусов»: цвет и эмодзи записи при каждом статусе, для всех дел или для типа.
struct PlannerStatusSettingsView: View {
    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<PlannerErrandKind> { $0.deletedAt == nil }, sort: \PlannerErrandKind.name)
    private var kinds: [PlannerErrandKind]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PlannerStatusScopeView(scope: "all", title: "Все дела")
                    } label: {
                        Label("Все дела", systemImage: "square.stack")
                    }
                } footer: {
                    Text("Общие настройки: цвет и эмодзи записи, когда у неё нет отметки, «Сделано», «Не сделано» или «Перенесено». Если ничего не менять, остаются привычные.")
                }
                Section {
                    NavigationLink {
                        PlannerStatusScopeView(scope: PlannerStatusStyle.sharedScope(account.current.rawValue), title: "Совместные дела")
                    } label: {
                        Label("Совместные дела 💞", systemImage: "heart")
                    }
                } header: {
                    Text("Совместные")
                } footer: {
                    Text("Это только для вашего планера: совместные дела будут светиться так, как вам нравится. У второго человека свои настройки.")
                }
                Section("По типам дел") {
                    let mine = kinds.visible(to: account.current)
                    if mine.isEmpty { Text("Типов дел пока нет").foregroundStyle(.secondary) }
                    ForEach(mine) { kind in
                        NavigationLink {
                            PlannerStatusScopeView(scope: PlannerStatusStyle.typeScope(kind.name), title: kind.name)
                        } label: {
                            Text("\(kind.displayEmoji) \(kind.name)")
                        }
                    }
                }
            }
            .navigationTitle("Настройка статусов")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PlannerStatusScopeView: View {
    let scope: String
    let title: String

    private let statuses: [(key: String, title: String, defaultEmoji: String)] = [
        ("none", "Без отметки", ""),
        ("done", "Сделано", "✅"),
        ("notDone", "Не сделано", "❌"),
        ("moved", "Перенесено", "↪️"),
    ]

    var body: some View {
        List {
            ForEach(statuses, id: \.key) { item in
                PlannerStatusStyleRow(scope: scope, status: item.key, title: item.title, defaultEmoji: item.defaultEmoji)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlannerStatusStyleRow: View {
    let scope: String
    let status: String
    let title: String
    let defaultEmoji: String

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @State private var useColor = false
    @State private var color: Color = .blue
    @State private var emoji = ""
    @State private var hideEmoji = false
    @State private var loaded = false

    var body: some View {
        Section(title) {
            Toggle("🎨 Свой цвет", isOn: $useColor)
            if useColor {
                ColorPicker("Цвет", selection: $color, supportsOpacity: false)
            }
            HStack {
                Text("Эмодзи")
                Spacer()
                TextField(defaultEmoji.isEmpty ? "нет" : defaultEmoji, text: $emoji)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(hideEmoji)
            }
            Toggle("Без эмодзи", isOn: $hideEmoji)
            Button("Вернуть по умолчанию", role: .destructive, action: reset)
                .font(.footnote)
        }
        .onAppear(perform: load)
        .onChange(of: useColor) { _, _ in save() }
        .onChange(of: emoji) { _, _ in save() }
        .onChange(of: hideEmoji) { _, _ in save() }
        .onDisappear(perform: save)
    }

    private func load() {
        guard !loaded else { return }
        let style = PlannerStatusStyleStore.style(context, scope: scope, status: status)
        if let saved = Color(hex: style.colorHex), !style.colorHex.isEmpty {
            useColor = true
            color = saved
        }
        emoji = style.emoji
        hideEmoji = style.hideEmoji
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let style = PlannerStatusStyleStore.style(context, scope: scope, status: status)
        let hex = useColor ? color.hexString : ""
        let clean = emoji.trimmingCharacters(in: .whitespaces)
        guard hex != style.colorHex || clean != style.emoji || hideEmoji != style.hideEmoji else { return }
        style.colorHex = hex
        style.emoji = clean
        style.hideEmoji = hideEmoji
        style.markChanged()
        try? context.save()
        sync.requestSync()
    }

    private func reset() {
        useColor = false
        emoji = ""
        hideEmoji = false
        save()
    }
}

enum PlannerStatusSettingsFeature {
    static let feature = Feature(
        id: "plannerStatusSettings",
        title: "Настройка статусов",
        systemImage: "paintbrush.fill"
    ) {
        PlannerStatusSettingsView()
    }
}
