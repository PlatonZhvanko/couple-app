import Foundation
import SwiftData

/// Расписание кортов «Олимпик» за один день. Копия журнала YClients, только для просмотра:
/// заполняется синхронизацией на сервере, в приложении не меняется.
@Model
final class PlannerOlimpicDay: SyncableModel {
    struct Court: Codable, Hashable {
        var id: Int
        var name: String
        /// «padel» или «tennis» (определяет сервер).
        var kind: String?
    }

    struct Booking: Codable, Hashable, Identifiable {
        var id: Int
        var court: Int
        var client: String
        /// Начало, ISO 8601.
        var start: String
        /// Длительность в секундах.
        var length: Int
        /// confirmed, arrived, pending или noshow.
        var status: String
        var service: String?
        /// Ресурс «Новик Анастасия» (её тренировки).
        var nastya: Bool?
    }

    struct Payload: Codable {
        var day: String
        var courts: [Court]
        var bookings: [Booking]
    }

    static let recordKind = "planner.olimpic_day"

    var syncID: UUID = UUID()
    /// День в виде «2026-11-24» (московский).
    var day: String = ""
    var courtsJSON: String = "[]"
    var bookingsJSON: String = "[]"
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = false

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var courts: [Court] { Self.decode(courtsJSON) }
    var bookings: [Booking] { Self.decode(bookingsJSON) }

    var payload: Payload { Payload(day: day, courts: courts, bookings: bookings) }

    func apply(_ payload: Payload) {
        day = payload.day
        courtsJSON = Self.encode(payload.courts)
        bookingsJSON = Self.encode(payload.bookings)
    }

    private static func decode<T: Decodable>(_ text: String) -> [T] {
        (try? JSONDecoder().decode([T].self, from: Data(text.utf8))) ?? []
    }

    private static func encode<T: Encodable>(_ items: [T]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
