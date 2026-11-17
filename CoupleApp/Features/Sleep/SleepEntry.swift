import Foundation
import SwiftData

/// Одна ночь сна одного человека.
/// Синхронизируется между телефонами: партнёр видит ваш сон, вы — его.
@Model
final class SleepEntry: SyncableModel {
    struct Payload: Codable {
        var member: String
        var bedtime: Date
        var wakeTime: Date
        var quality: Int
        var note: String
        var source: String
    }

    static let recordKind = "sleep.entry"

    var syncID: UUID = UUID()
    /// Чей это сон: `CoupleMember.rawValue`.
    var member: String = CoupleMember.owner.rawValue
    /// Когда лёг(ла).
    var bedtime: Date = Date.now
    /// Когда встал(а).
    var wakeTime: Date = Date.now
    /// Как спалось: 1 (плохо) … 5 (отлично).
    var quality: Int = 3
    var note: String = ""
    /// Откуда запись: "manual" (вручную). Позже появится "health" (Apple Здоровье).
    var source: String = "manual"
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(member: CoupleMember, bedtime: Date, wakeTime: Date, quality: Int, note: String) {
        self.member = member.rawValue
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.quality = quality
        self.note = note
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(member: member, bedtime: bedtime, wakeTime: wakeTime, quality: quality, note: note, source: source)
    }

    func apply(_ payload: Payload) {
        member = payload.member
        bedtime = payload.bedtime
        wakeTime = payload.wakeTime
        quality = payload.quality
        note = payload.note
        source = payload.source
    }

    /// Длительность сна в секундах.
    var duration: TimeInterval { max(0, wakeTime.timeIntervalSince(bedtime)) }

    /// День, к которому относится ночь (день пробуждения).
    var nightDay: Date { Calendar.current.startOfDay(for: wakeTime) }
}
