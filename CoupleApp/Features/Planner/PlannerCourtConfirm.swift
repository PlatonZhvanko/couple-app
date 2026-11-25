import SwiftData
import SwiftUI

// Подтверждение корта в YClients (планер Насти).
//
// Занятие с галочкой «Запрос на подтверждение корта» горит белым. Когда в YClients (записи с
// источником «yclients») появляется такая же запись, они сливаются в один блок оранжевого цвета.
// Совпадение: тот же день, начало и конец в пределах 5 минут, клиент YClients — тот же, что у
// занятия, или тот, кого Настя указала как «клиента в YClients» для группы или клиента.
// Статистика и деньги идут по занятию планера, а дубль YClients в них не считается.

/// Состояние занятия по подтверждению корта.
enum PlannerCourtState {
    case none
    /// Ждём подтверждения: белая запись.
    case request
    /// В YClients нашлась такая же запись: оранжевая.
    case confirmed
}

// MARK: - Синоним клиента в YClients

/// Настройка «бронируется в YClients на другого клиента» для группы/школы или клиента.
/// Ключ: «group:<название в нижнем регистре>» или «client:<id клиента>».
@Model
final class PlannerCourtAlias: SyncableModel {
    struct Payload: Codable {
        var key: String
        var enabled: Bool
        var aliasClientID: UUID?
        var aliasName: String
    }

    static let recordKind = "planner.court_alias"

    var syncID: UUID = UUID()
    var key: String = ""
    var enabled: Bool = false
    var aliasClientID: UUID? = nil
    var aliasName: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(key: String) {
        self.syncID = Self.makeID(key: key)
        self.key = key
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload { Payload(key: key, enabled: enabled, aliasClientID: aliasClientID, aliasName: aliasName) }

    func apply(_ payload: Payload) {
        key = payload.key
        enabled = payload.enabled
        aliasClientID = payload.aliasClientID
        aliasName = payload.aliasName
    }

    static func makeID(key: String) -> UUID { PlannerDeterministicID.make("courtalias|" + key) }

    static func groupKey(_ name: String) -> String {
        "group:" + name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func clientKey(_ id: UUID) -> String { "client:" + id.uuidString.uppercased() }
}

// MARK: - Сверка

/// Сверяет занятия с запросом и записи YClients. Строится один раз за перерисовку,
/// результат по дню запоминается: ничего тяжёлого в теле экрана.
final class PlannerCourtMatcher {
    private struct DayResult {
        /// id занятия с запросом → id записи YClients.
        var confirmed: [UUID: UUID] = [:]
        var superseded: Set<UUID> = []
    }

    /// Допуск по началу и концу.
    static let tolerance: TimeInterval = 5 * 60

    static let empty = PlannerCourtMatcher(events: [], aliases: [])

    private let requests: [PlannerEvent]
    private let requestIDs: Set<UUID>
    private let yclientsByDay: [Date: [PlannerEvent]]
    private let aliases: [String: [PlannerCourtAlias]]
    private var cache: [Date: DayResult] = [:]

    var isActive: Bool { !requests.isEmpty }

    init(events: [PlannerEvent], aliases: [PlannerCourtAlias]) {
        let cal = PlannerCalendar.calendar
        let enabled = Dictionary(
            grouping: aliases.filter { $0.deletedAt == nil && $0.enabled },
            by: \.key
        )
        var requests: [PlannerEvent] = []
        var byDay: [Date: [PlannerEvent]] = [:]
        for event in events where event.deletedAt == nil && !event.isAllDay {
            if event.isFromYClients {
                byDay[cal.startOfDay(for: event.start), default: []].append(event)
            } else if event.categoryValue != .errand {
                // Запросом считается только запись планера с включённой галочкой.
                let isRequest = event.courtAsk
                if isRequest { requests.append(event) }
            }
        }
        self.requestIDs = Set(requests.map(\.syncID))
        self.requests = requests
        // Без запросов сверять нечего: записи YClients не нужны.
        self.yclientsByDay = requests.isEmpty ? [:] : byDay
        self.aliases = enabled
    }

    func state(of event: PlannerEvent, on day: Date) -> PlannerCourtState {
        guard isActive, requestIDs.contains(event.syncID) else { return .none }
        return result(on: day).confirmed[event.syncID] != nil ? .confirmed : .request
    }

    /// Запись YClients слилась с занятием планера и отдельно не показывается.
    func isSuperseded(_ event: PlannerEvent, on day: Date) -> Bool {
        guard isActive, event.isFromYClients else { return false }
        return result(on: day).superseded.contains(event.syncID)
    }

    /// Запись YClients, с которой слилось занятие (корт в `notes`, клиент в `title`).
    func linkedRecord(of event: PlannerEvent, on rawDay: Date) -> PlannerEvent? {
        guard isActive, let id = result(on: rawDay).confirmed[event.syncID] else { return nil }
        let day = PlannerCalendar.calendar.startOfDay(for: rawDay)
        return yclientsByDay[day]?.first { $0.syncID == id }
    }

    /// Все записи YClients, слитые с занятиями (для статистики).
    func allSupersededIDs() -> Set<UUID> {
        guard isActive else { return [] }
        var all: Set<UUID> = []
        for day in yclientsByDay.keys { all.formUnion(result(on: day).superseded) }
        return all
    }

    // MARK: -

    private func result(on rawDay: Date) -> DayResult {
        let cal = PlannerCalendar.calendar
        let day = cal.startOfDay(for: rawDay)
        if let cached = cache[day] { return cached }
        var result = DayResult()
        let candidates = yclientsByDay[day] ?? []
        if !candidates.isEmpty {
            var used: Set<UUID> = []
            let todays = requests
                .filter { $0.startsOn(day) && !$0.isCancelled(on: day) }
                .sorted { PlannerCalendar.combine(day: day, time: $0.start) < PlannerCalendar.combine(day: day, time: $1.start) }
            for request in todays {
                let start = PlannerCalendar.combine(day: day, time: request.start)
                let end = start.addingTimeInterval(request.end.timeIntervalSince(request.start))
                let who = synonyms(of: request)
                let found = candidates.first { record in
                    !used.contains(record.syncID)
                        && !record.isCancelled(on: day)
                        && abs(record.start.timeIntervalSince(start)) <= Self.tolerance
                        && abs(record.end.timeIntervalSince(end)) <= Self.tolerance
                        && Self.sameClient(record, who)
                }
                if let found {
                    used.insert(found.syncID)
                    result.confirmed[request.syncID] = found.syncID
                    result.superseded.insert(found.syncID)
                }
            }
        }
        cache[day] = result
        return result
    }

    private struct Synonyms {
        var ids: Set<UUID> = []
        var names: Set<String> = []
    }

    private func synonyms(of request: PlannerEvent) -> Synonyms {
        var who = Synonyms()
        who.names.insert(Self.norm(request.title))
        if request.categoryValue == .personal { who.ids.formUnion(request.participantIDs) }
        var keys: [String] = request.participantIDs.map { PlannerCourtAlias.clientKey($0) }
        if request.categoryValue != .personal { keys.append(PlannerCourtAlias.groupKey(request.title)) }
        for key in keys {
            for alias in aliases[key] ?? [] {
                if let id = alias.aliasClientID { who.ids.insert(id) }
                if !alias.aliasName.isEmpty { who.names.insert(Self.norm(alias.aliasName)) }
            }
        }
        return who
    }

    private static func sameClient(_ record: PlannerEvent, _ who: Synonyms) -> Bool {
        if let id = record.participantIDs.first, who.ids.contains(id) { return true }
        return who.names.contains(norm(record.title))
    }

    /// Имя без регистра и порядка слов: «Дерипаска Сергей» = «сергей дерипаска».
    static func norm(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { $0.isWhitespace })
            .sorted()
            .joined(separator: " ")
    }
}

// MARK: - Настройка клиента YClients

extension PlannerClientDirectory {
    /// Клиенты, пришедшие из YClients.
    @MainActor
    static func iclientsClients(_ context: ModelContext) -> [Entry] {
        let descriptor = FetchDescriptor<ClientsClient>(predicate: #Predicate { $0.deletedAt == nil && $0.source == "iclients" })
        let clients = (try? context.fetch(descriptor)) ?? []
        return clients
            .map { Entry(id: $0.syncID, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Блок настроек: «Бронируется в YClients на другого клиента» и выбор клиента из YClients (поиском).
struct PlannerCourtAliasSection: View {
    let key: String
    let subject: String

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @State private var enabled = false
    @State private var aliasID: UUID?
    @State private var aliasName = ""
    @State private var query = ""
    @State private var pool: [PlannerClientDirectory.Entry] = []
    @State private var loaded = false

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var suggestions: [PlannerClientDirectory.Entry] {
        guard !trimmedQuery.isEmpty else { return Array(pool.prefix(2)) }
        let q = trimmedQuery.lowercased()
        return Array(pool.lazy.filter { $0.matches(q) }.prefix(6))
    }

    var body: some View {
        Section {
            Toggle("Бронируется в YClients на другого клиента", isOn: $enabled)
            if enabled {
                if aliasName.isEmpty {
                    TextField("Найти клиента YClients", text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    ForEach(suggestions) { client in
                        Button {
                            aliasID = client.id
                            aliasName = client.name
                            query = ""
                            save()
                        } label: {
                            Label(client.name, systemImage: "person")
                        }
                    }
                    if pool.isEmpty {
                        Text("Клиентов из YClients пока нет: они появятся после синхронизации.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Label(aliasName, systemImage: "person.crop.circle.badge.checkmark")
                        Spacer()
                        Button {
                            aliasID = nil
                            aliasName = ""
                            save()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("📋 YClients")
        } footer: {
            Text("Если «\(subject)» в YClients записывают на другого клиента, выбери его. Тогда запись планера и запись YClients с таким клиентом сольются в одну, когда корт подтвердится.")
        }
        .onAppear(perform: load)
        .onChange(of: enabled) { _, _ in save() }
    }

    private func load() {
        guard !loaded else { return }
        let id = PlannerCourtAlias.makeID(key: key)
        if let found = (try? context.fetch(FetchDescriptor<PlannerCourtAlias>(predicate: #Predicate { $0.syncID == id })))?.first,
           found.deletedAt == nil {
            enabled = found.enabled
            aliasID = found.aliasClientID
            aliasName = found.aliasName
        }
        loaded = true
        if enabled && aliasName.isEmpty { loadPool() }
    }

    /// Список клиентов YClients читаем только когда он нужен (включено и клиент ещё не выбран).
    private func loadPool() {
        guard pool.isEmpty else { return }
        pool = PlannerClientDirectory.iclientsClients(context)
    }

    private func save() {
        guard loaded else { return }
        if enabled && aliasName.isEmpty { loadPool() }
        let id = PlannerCourtAlias.makeID(key: key)
        let item: PlannerCourtAlias
        if let found = (try? context.fetch(FetchDescriptor<PlannerCourtAlias>(predicate: #Predicate { $0.syncID == id })))?.first {
            item = found
            item.deletedAt = nil
        } else {
            guard enabled else { return }
            item = PlannerCourtAlias(key: key)
            context.insert(item)
        }
        guard item.enabled != enabled || item.aliasClientID != aliasID || item.aliasName != aliasName else { return }
        item.enabled = enabled
        item.aliasClientID = aliasID
        item.aliasName = aliasName
        item.markChanged()
        try? context.save()
        sync.requestSync()
    }
}
