import Foundation
import SwiftData
import SwiftUI

// MARK: - Шкала

/// Оценка настроения от 1 (очень плохо) до 5 (отлично).
enum MoodLevel: Int, CaseIterable, Identifiable {
    case awful = 1, bad, okay, good, great

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .awful: "😣"
        case .bad: "😕"
        case .okay: "😐"
        case .good: "🙂"
        case .great: "😄"
        }
    }

    var title: String {
        switch self {
        case .awful: "Очень плохо"
        case .bad: "Плохо"
        case .okay: "Нормально"
        case .good: "Хорошо"
        case .great: "Отлично"
        }
    }

    var color: Color {
        MoodLevel.color(for: Double(rawValue))
    }

    /// Ближайшая оценка к среднему значению (например, 3.6 → хорошо).
    static func nearest(to value: Double) -> MoodLevel {
        let rounded = Int(value.rounded())
        return MoodLevel(rawValue: min(max(rounded, 1), 5)) ?? .okay
    }

    /// Цвет для среднего значения: от красного (1) через жёлтый (3) к зелёному (5).
    static func color(for value: Double) -> Color {
        let clamped = min(max(value, 1), 5)
        // Оттенок: 0.0 — красный, 0.33 — зелёный.
        let hue = (clamped - 1) / 4 * 0.33
        return Color(hue: hue, saturation: 0.65, brightness: 0.9)
    }
}

/// Готовые метки, которые можно добавить к отметке.
enum MoodTags {
    static let all: [String] = [
        "радостно", "спокойно", "благодарность", "влюблённость", "энергия",
        "устал", "тревожно", "грустно", "раздражение", "стресс",
        "болею", "скучаю",
    ]
}

/// Реакции поддержки, которые можно отправить партнёру.
enum MoodSupport {
    static let emojis: [String] = ["❤️", "🤗", "☕️", "🍫", "🌷", "💪", "😘", "🫶", "🌙", "🐱", "🎧", "🛁"]

    static func title(for emoji: String) -> String {
        switch emoji {
        case "❤️": "Люблю"
        case "🤗": "Обнимаю"
        case "☕️": "Сделаю чай"
        case "🍫": "Принесу вкусняшку"
        case "🌷": "Ты чудесная"
        case "💪": "Ты справишься"
        case "😘": "Целую"
        case "🫶": "Я рядом"
        case "🌙": "Сладких снов"
        case "🐱": "Коты скучают"
        case "🎧": "Включу твоё кино"
        case "🛁": "Устрою спа-вечер"
        default: emoji
        }
    }
}

// MARK: - Отметка настроения

/// Одна отметка настроения. Видна обоим, кроме приватной заметки.
@Model
final class MoodEntry: SyncableModel {
    struct Payload: Codable {
        var member: String
        var level: Int
        var tags: [String]
        /// Пустая, если заметка приватная.
        var note: String
        var createdAt: Date
    }

    static let recordKind = "mood.entry"

    var syncID: UUID = UUID()
    /// Чья отметка: `CoupleMember.rawValue`.
    var member: String = CoupleMember.owner.rawValue
    var level: Int = 3
    var tags: [String] = []
    var note: String = ""
    /// true — заметка только на этом телефоне и на сервер не уходит.
    var isNotePrivate: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember, level: MoodLevel, tags: [String] = [], note: String = "", isNotePrivate: Bool = false, createdAt: Date = .now) {
        self.member = member.rawValue
        self.level = level.rawValue
        self.tags = tags
        self.note = note
        self.isNotePrivate = isNotePrivate
        self.createdAt = createdAt
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(member: member, level: level, tags: tags, note: isNotePrivate ? "" : note, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        level = payload.level
        tags = payload.tags
        // Свою приватную заметку не затираем пустой строкой с сервера.
        if !isNotePrivate { note = payload.note }
        createdAt = payload.createdAt
    }

    var moodLevel: MoodLevel { MoodLevel(rawValue: level) ?? .okay }
    var coupleMember: CoupleMember { CoupleMember(rawValue: member) ?? .owner }
}

// MARK: - Поддержка

/// Реакция поддержки: «❤️ от неё тебе».
@Model
final class MoodReaction: SyncableModel {
    struct Payload: Codable {
        var from: String
        var to: String
        var emoji: String
        var createdAt: Date
        var seenAt: Date?
        /// Своё слово от отправителя. Необязательно.
        var comment: String?
    }

    static let recordKind = "mood.reaction"

    var syncID: UUID = UUID()
    /// Кто отправил: `CoupleMember.rawValue`.
    var sender: String = CoupleMember.owner.rawValue
    /// Кому: `CoupleMember.rawValue`.
    var recipient: String = CoupleMember.partner.rawValue
    var emoji: String = "❤️"
    var createdAt: Date = Date.now
    /// Когда получатель увидел реакцию. `nil` — ещё не видел.
    var seenAt: Date? = nil
    /// Своё слово вместе с реакцией; пустая строка, если не писали.
    var comment: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(from: CoupleMember, to: CoupleMember, emoji: String, comment: String = "") {
        self.sender = from.rawValue
        self.recipient = to.rawValue
        self.emoji = emoji
        self.comment = comment
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(from: sender, to: recipient, emoji: emoji, createdAt: createdAt, seenAt: seenAt, comment: comment.isEmpty ? nil : comment)
    }

    func apply(_ payload: Payload) {
        sender = payload.from
        recipient = payload.to
        emoji = payload.emoji
        createdAt = payload.createdAt
        seenAt = payload.seenAt
        comment = payload.comment ?? ""
    }
}

// MARK: - Подсчёты

enum MoodStats {
    /// Среднее настроение по отметкам или `nil`, если отметок нет.
    static func average(_ entries: [MoodEntry]) -> Double? {
        guard !entries.isEmpty else { return nil }
        return Double(entries.reduce(0) { $0 + $1.level }) / Double(entries.count)
    }

    /// Отметки, сгруппированные по началу дня.
    static func byDay(_ entries: [MoodEntry], calendar: Calendar = .current) -> [Date: [MoodEntry]] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
    }
}
