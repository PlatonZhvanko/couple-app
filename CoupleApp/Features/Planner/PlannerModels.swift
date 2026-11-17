import Foundation
import SwiftData
import SwiftUI

// MARK: - Для кого запись

/// Чья запись: общая или одного из двоих.
enum PlannerScope: String, CaseIterable, Identifiable, Codable {
    case shared
    case owner
    case partner

    var id: String { rawValue }

    static func personal(_ member: CoupleMember) -> PlannerScope {
        member == .owner ? .owner : .partner
    }

    var member: CoupleMember? {
        switch self {
        case .shared: nil
        case .owner: .owner
        case .partner: .partner
        }
    }

    /// Общее меняют оба, личное только хозяин.
    func canEdit(by me: CoupleMember) -> Bool {
        guard let member else { return true }
        return member == me
    }

    /// Получает ли этот человек напоминания.
    func concerns(_ me: CoupleMember) -> Bool {
        guard let member else { return true }
        return member == me
    }

    @MainActor
    func title(_ account: AccountStore) -> String {
        guard let member else { return "Общее" }
        return member == account.current ? "Моё" : account.name(of: member)
    }
}

// MARK: - Категория

enum PlannerCategory: String, CaseIterable, Identifiable {
    case general, together, work, health, home, travel, celebration
    /// Тренировки и дела тренера (профиль Настеньки).
    case personal, group, school, errand

    var id: String { rawValue }

    /// Обычные категории событий.
    static let regular: [PlannerCategory] = [.general, .together, .work, .health, .home, .travel, .celebration]

    /// Эмодзи для журнала. `nil` у обычных категорий.
    var emoji: String? {
        switch self {
        case .personal: "🐱🎾"
        case .group: "👧👦🎾"
        case .school: "🏫🎾"
        case .errand: "🧳"
        default: nil
        }
    }

    var title: String {
        switch self {
        case .general: "Разное"
        case .together: "Вместе"
        case .work: "Работа"
        case .health: "Здоровье"
        case .home: "Дом"
        case .travel: "Поездки"
        case .celebration: "Праздники"
        case .personal: "Персоналка"
        case .group: "Группа"
        case .school: "Школа"
        case .errand: "Дело"
        }
    }

    var color: Color {
        switch self {
        case .general: .blue
        case .together: .pink
        case .work: .indigo
        case .health: .green
        case .home: .orange
        case .travel: .teal
        case .celebration: .purple
        case .personal: .green
        case .group: .yellow
        case .school: .orange
        case .errand: .pink
        }
    }

    var systemImage: String {
        switch self {
        case .general: "circle.fill"
        case .together: "heart.fill"
        case .work: "briefcase.fill"
        case .health: "cross.case.fill"
        case .home: "house.fill"
        case .travel: "airplane"
        case .celebration: "gift.fill"
        case .personal, .group, .school: "figure.tennis"
        case .errand: "briefcase.fill"
        }
    }
}

// MARK: - Повтор

enum PlannerRepeat: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Не повторять"
        case .daily: "Каждый день"
        case .weekly: "Каждую неделю"
        case .monthly: "Каждый месяц"
        case .yearly: "Каждый год"
        }
    }
}

// MARK: - Напоминание

struct PlannerReminderOption: Identifiable, Hashable {
    let minutes: Int
    let title: String
    var id: Int { minutes }

    static let none = -1

    static let timed: [PlannerReminderOption] = [
        .init(minutes: none, title: "Нет"),
        .init(minutes: 0, title: "В момент начала"),
        .init(minutes: 10, title: "За 10 минут"),
        .init(minutes: 30, title: "За 30 минут"),
        .init(minutes: 60, title: "За час"),
        .init(minutes: 120, title: "За 2 часа"),
        .init(minutes: 1440, title: "За день"),
    ]

    static let allDay: [PlannerReminderOption] = [
        .init(minutes: none, title: "Нет"),
        .init(minutes: 0, title: "В день события, 9:00"),
        .init(minutes: 1440, title: "За день, 9:00"),
        .init(minutes: 10080, title: "За неделю, 9:00"),
    ]

    static func options(allDay: Bool) -> [PlannerReminderOption] {
        allDay ? Self.allDay : timed
    }
}

// MARK: - Событие

/// Событие календаря. Синхронизируется между телефонами.
@Model
final class PlannerEvent: SyncableModel {
    struct Payload: Codable {
        var title: String
        var notes: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var scope: String
        var category: String
        var repeatRule: String
        var reminderMinutes: Int
        var createdBy: String
        var createdAt: Date
        /// Клиенты тренировки (id из раздела «Клиенты»). Нет в старых записях.
        var participantIDs: [UUID]?
        /// Дни повторяющегося события, которые перенесены в другое время.
        var skippedDays: [Date]?
    }

    static let recordKind = "planner.event"

    var syncID: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    /// Для событий на весь день: начало первого дня.
    var start: Date = Date.now
    /// Для событий на весь день: начало последнего дня (включительно).
    var end: Date = Date.now
    var isAllDay: Bool = false
    var scope: String = PlannerScope.shared.rawValue
    var category: String = PlannerCategory.general.rawValue
    var repeatRule: String = PlannerRepeat.none.rawValue
    /// Минут до начала; -1 — без напоминания.
    var reminderMinutes: Int = -1
    var createdBy: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    /// Клиенты тренировки (id из раздела «Клиенты»).
    var participantIDs: [UUID] = []
    /// Дни повторяющегося события, которые перенесены в другое время.
    var skippedDays: [Date] = []
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init() {}

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(
            title: title, notes: notes, start: start, end: end, isAllDay: isAllDay,
            scope: scope, category: category, repeatRule: repeatRule,
            reminderMinutes: reminderMinutes, createdBy: createdBy, createdAt: createdAt,
            participantIDs: participantIDs, skippedDays: skippedDays
        )
    }

    func apply(_ payload: Payload) {
        title = payload.title
        notes = payload.notes
        start = payload.start
        end = payload.end
        isAllDay = payload.isAllDay
        scope = payload.scope
        category = payload.category
        repeatRule = payload.repeatRule
        reminderMinutes = payload.reminderMinutes
        createdBy = payload.createdBy
        createdAt = payload.createdAt
        participantIDs = payload.participantIDs ?? []
        skippedDays = payload.skippedDays ?? []
    }

    var scopeValue: PlannerScope { PlannerScope(rawValue: scope) ?? .shared }
    var categoryValue: PlannerCategory { PlannerCategory(rawValue: category) ?? .general }
    var repeatValue: PlannerRepeat { PlannerRepeat(rawValue: repeatRule) ?? .none }
}

// MARK: - Дело

/// Дело из списка с галочками. Синхронизируется между телефонами.
@Model
final class PlannerTask: SyncableModel {
    struct Payload: Codable {
        var title: String
        var notes: String
        var dueDate: Date?
        var isDone: Bool
        var doneAt: Date?
        var scope: String
        var createdBy: String
        var createdAt: Date
    }

    static let recordKind = "planner.task"

    var syncID: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    /// Срок (день). Если задан, дело видно в календаре.
    var dueDate: Date? = nil
    var isDone: Bool = false
    var doneAt: Date? = nil
    var scope: String = PlannerScope.shared.rawValue
    var createdBy: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init() {}

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(
            title: title, notes: notes, dueDate: dueDate, isDone: isDone, doneAt: doneAt,
            scope: scope, createdBy: createdBy, createdAt: createdAt
        )
    }

    func apply(_ payload: Payload) {
        title = payload.title
        notes = payload.notes
        dueDate = payload.dueDate
        isDone = payload.isDone
        doneAt = payload.doneAt
        scope = payload.scope
        createdBy = payload.createdBy
        createdAt = payload.createdAt
    }

    var scopeValue: PlannerScope { PlannerScope(rawValue: scope) ?? .shared }

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < PlannerCalendar.calendar.startOfDay(for: .now)
    }
}

extension PlannerEvent {
    /// Название с эмодзи тренировки, если оно есть.
    var displayTitle: String {
        let name = title.isEmpty ? "Без названия" : title
        guard let emoji = categoryValue.emoji else { return name }
        return "\(emoji) \(name)"
    }
}
